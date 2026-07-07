import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:meshagent/meshagent.dart';
import 'package:test/test.dart';

class _ProtocolPair {
  _ProtocolPair() {
    serverProtocol = Protocol(
      channel: StreamProtocolChannel(input: _clientToServer.stream, output: _serverToClient.sink),
    );
  }

  final _clientToServer = StreamController<Uint8List>();
  final _serverToClient = StreamController<Uint8List>();
  Protocol? _clientProtocol;
  late final Protocol serverProtocol;

  Protocol clientProtocolFactory() {
    if (_clientProtocol != null) {
      throw ProtocolReconnectUnsupportedException('protocolFactory was not configured for reconnecting this protocol');
    }
    final protocol = Protocol(
      channel: StreamProtocolChannel(input: _serverToClient.stream, output: _clientToServer.sink),
    );
    _clientProtocol = protocol;
    return protocol;
  }

  Future<void> dispose() async {
    final clientProtocol = _clientProtocol;
    if (clientProtocol != null) {
      try {
        clientProtocol.dispose();
      } catch (_) {}
    }
    try {
      serverProtocol.dispose();
    } catch (_) {}
    await _clientToServer.close();
    if (!_serverToClient.isClosed) {
      await _serverToClient.close();
    }
  }
}

class _RecordedRequest {
  _RecordedRequest({required this.tool, required this.input});

  final String tool;
  final Map<String, dynamic> input;
}

Future<void> _sendRoomReady(Protocol protocol) async {
  await protocol.send(
    'room_ready',
    packMessage({'room_name': 'test-room', 'room_url': 'ws://example/rooms/test-room', 'session_id': 'session-1'}),
  );
  await protocol.send(
    'connected',
    packMessage({
      'type': 'init',
      'participantId': 'self',
      'attributes': {'name': 'self'},
    }),
  );
}

ArrowSchema _testArrowSchema() {
  return const ArrowSchema([
    ArrowField(name: 'id', type: ArrowIntType(bitWidth: 64, signed: true)),
    ArrowField(name: 'label', type: ArrowUtf8Type()),
  ]);
}

ArrowRecordBatch _testArrowBatch({int id = 1, String label = 'alpha'}) {
  final schema = _testArrowSchema();
  return ArrowRecordBatch.fromColumns(
    schema: schema,
    columns: [
      ArrowValueArray(field: schema.fields[0], values: [BigInt.from(id)]),
      ArrowValueArray(field: schema.fields[1], values: [label]),
    ],
  );
}

ArrowRecordBatch _mixedArrowBatch() {
  const schema = ArrowSchema([
    ArrowField(name: 'id', type: ArrowIntType(bitWidth: 64, signed: true)),
    ArrowField(name: 'score', type: ArrowFloatingPointType(ArrowFloatingPointPrecision.doublePrecision)),
    ArrowField(name: 'payload', type: ArrowBinaryType()),
  ]);
  return ArrowRecordBatch.fromColumns(
    schema: schema,
    columns: [
      ArrowValueArray(field: schema.fields[0], values: [BigInt.one, BigInt.two]),
      ArrowValueArray(field: schema.fields[1], values: [1.5, null]),
      ArrowValueArray(
        field: schema.fields[2],
        values: [
          Uint8List.fromList([1, 2, 3]),
          null,
        ],
      ),
    ],
  );
}

class _SqliteHarness {
  _SqliteHarness({required this.pair, required this.room, required this.server});

  final _ProtocolPair pair;
  final RoomClient room;
  final _FakeSqliteServer server;

  Future<void> dispose() async {
    await Future<void>.delayed(Duration.zero);
    room.dispose();
    await pair.dispose();
  }
}

class _FakeSqliteServer {
  final requests = <_RecordedRequest>[];
  final writeStarts = <String, List<Map<String, dynamic>>>{'create_table': [], 'insert': []};
  final writeStartData = <String, List<Uint8List>>{'create_table': [], 'insert': []};
  final writeChunks = <String, List<Map<String, dynamic>>>{'create_table': [], 'insert': []};
  final readStarts = <String, List<Map<String, dynamic>>>{'search': [], 'read_sql_query': []};
  final readPulls = <String, List<Map<String, dynamic>>>{'search': [], 'read_sql_query': []};
  final malformedResponses = <String, Content>{};
  final streamChunks = <String, List<Content>>{};
  final _toolCallTools = <String, String>{};
  late Uint8List searchBatchBytes = _testArrowBatch(id: 1, label: 'search').ipcBytes;
  late Uint8List sqlBatchBytes = _testArrowBatch(id: 2, label: 'sql').ipcBytes;

  Future<void> handleMessage(Protocol protocol, int messageId, String type, Uint8List data) async {
    final message = unpackMessage(data);
    final request = message.header;
    if (type == 'room.invoke_tool') {
      if (request['toolkit'] != 'sqlite') {
        return;
      }
      final tool = request['tool'] as String;
      final input = _decodeInput(message: message, request: request);
      final malformed = malformedResponses[tool];
      if (malformed != null) {
        await protocol.send('__response__', malformed.pack(), id: messageId);
        return;
      }
      if (input is ControlContent) {
        final toolCallId = request['tool_call_id'] as String;
        _toolCallTools[toolCallId] = tool;
        await protocol.send('__response__', ControlContent(method: 'open').pack(), id: messageId);
        return;
      }
      if (tool == 'open_sql_query' || tool == 'execute_sql') {
        if (input is! BinaryContent) {
          throw StateError('sqlite.$tool expected BinaryContent input');
        }
        requests.add(_RecordedRequest(tool: tool, input: Map<String, dynamic>.from(input.headers)));
        await protocol.send(
          '__response__',
          BinaryContent(
            data: ArrowIpcSchema.fromSchema(_testArrowSchema()).bytes,
            headers: const {'kind': 'query', 'query_id': 'sql-query-1'},
          ).pack(),
          id: messageId,
        );
        return;
      }
      if (tool == 'execute_sql_statement') {
        if (input is! BinaryContent) {
          throw StateError('sqlite.$tool expected BinaryContent input');
        }
        requests.add(_RecordedRequest(tool: tool, input: Map<String, dynamic>.from(input.headers)));
        await protocol.send('__response__', JsonContent(json: const {'rows_affected': 3}).pack(), id: messageId);
        return;
      }
      if (tool == 'add_columns') {
        if (input is! BinaryContent) {
          throw StateError('sqlite.add_columns expected BinaryContent input');
        }
        requests.add(_RecordedRequest(tool: tool, input: Map<String, dynamic>.from(input.headers)));
        await protocol.send('__response__', EmptyContent().pack(), id: messageId);
        return;
      }
      if (tool == 'inspect') {
        final jsonInput = _jsonInput(input, tool);
        requests.add(_RecordedRequest(tool: tool, input: jsonInput));
        await protocol.send('__response__', BinaryContent(data: ArrowIpcSchema.fromSchema(_testArrowSchema()).bytes).pack(), id: messageId);
        return;
      }
      final jsonInput = _jsonInput(input, tool);
      requests.add(_RecordedRequest(tool: tool, input: jsonInput));
      switch (tool) {
        case 'list_databases':
          await protocol.send(
            '__response__',
            JsonContent(
              json: const {
                'databases': ['app'],
              },
            ).pack(),
            id: messageId,
          );
          return;
        case 'inspect_database':
          await protocol.send(
            '__response__',
            JsonContent(
              json: const {
                'name': 'app',
                'namespace': ['team'],
                'tables': 2,
                'size_bytes': 4096,
              },
            ).pack(),
            id: messageId,
          );
          return;
        case 'list_tables':
          await protocol.send(
            '__response__',
            JsonContent(
              json: const {
                'tables': ['records'],
              },
            ).pack(),
            id: messageId,
          );
          return;
        case 'update':
        case 'delete':
          await protocol.send('__response__', JsonContent(json: const {'rows_affected': 3}).pack(), id: messageId);
          return;
        case 'count':
          await protocol.send('__response__', JsonContent(json: const {'count': 3}).pack(), id: messageId);
          return;
        case 'cancel_sql_query':
          await protocol.send('__response__', JsonContent(json: const {'status': 'not_cancellable'}).pack(), id: messageId);
          return;
        default:
          await protocol.send('__response__', EmptyContent().pack(), id: messageId);
          return;
      }
    }
    if (type == 'room.tool_call_request_chunk') {
      final toolCallId = request['tool_call_id'] as String;
      final tool = _toolCallTools[toolCallId];
      if (tool == null) {
        throw StateError('unknown tool call: $toolCallId');
      }
      final chunk = _decodeChunk(message: message, request: request);
      await protocol.send('__response__', EmptyContent().pack(), id: messageId);
      if (chunk is ControlContent) {
        if (chunk.method != 'close') {
          throw StateError('unsupported control chunk for sqlite.$tool');
        }
        if (tool == 'create_table' || tool == 'insert') {
          await _sendResponseChunk(protocol, toolCallId, ControlContent(method: 'close'));
        }
        return;
      }
      if (tool == 'create_table' || tool == 'insert') {
        if (chunk is! BinaryContent) {
          throw StateError('sqlite.$tool expected BinaryContent chunk');
        }
        if (chunk.headers['kind'] == 'start') {
          writeStarts[tool]!.add(Map<String, dynamic>.from(chunk.headers));
          writeStartData[tool]!.add(chunk.data);
          final override = _takeStreamChunk(tool);
          await _sendResponseChunk(protocol, toolCallId, override ?? BinaryContent(data: Uint8List(0), headers: const {'kind': 'pull'}));
          return;
        }
        writeChunks[tool]!.add({'headers': Map<String, dynamic>.from(chunk.headers), 'data': chunk.data});
        await _sendResponseChunk(protocol, toolCallId, BinaryContent(data: Uint8List(0), headers: const {'kind': 'pull'}));
        return;
      }
      if (tool == 'search' || tool == 'read_sql_query') {
        if (chunk is! BinaryContent) {
          throw StateError('sqlite.$tool expected BinaryContent chunk');
        }
        if (chunk.headers['kind'] == 'start') {
          readStarts[tool]!.add(Map<String, dynamic>.from(chunk.headers));
          return;
        }
        readPulls[tool]!.add(Map<String, dynamic>.from(chunk.headers));
        final override = _takeStreamChunk(tool);
        if (override != null) {
          await _sendResponseChunk(protocol, toolCallId, override);
          return;
        }
        if (readPulls[tool]!.length == 1) {
          await _sendResponseChunk(
            protocol,
            toolCallId,
            BinaryContent(data: tool == 'search' ? searchBatchBytes : sqlBatchBytes, headers: const {'kind': 'data'}),
          );
          return;
        }
        await _sendResponseChunk(protocol, toolCallId, ControlContent(method: 'close'));
        return;
      }
    }
  }

  Content? _takeStreamChunk(String tool) {
    final chunks = streamChunks[tool];
    if (chunks == null || chunks.isEmpty) {
      return null;
    }
    return chunks.removeAt(0);
  }

  Map<String, dynamic> _jsonInput(Content input, String tool) {
    if (input is! JsonContent) {
      throw StateError('sqlite.$tool expected JsonContent input');
    }
    return Map<String, dynamic>.from(input.json);
  }

  Content _decodeInput({required Message message, required Map<String, dynamic> request}) {
    final arguments = Map<String, dynamic>.from(request['arguments'] as Map);
    return unpackContent(packMessage(arguments, message.payload.isEmpty ? null : message.payload));
  }

  Content _decodeChunk({required Message message, required Map<String, dynamic> request}) {
    final chunk = Map<String, dynamic>.from(request['chunk'] as Map);
    return unpackContent(packMessage(chunk, message.payload.isEmpty ? null : message.payload));
  }

  Future<void> _sendResponseChunk(Protocol protocol, String toolCallId, Content chunk) async {
    await protocol.send(
      'room.tool_call_response_chunk',
      packMessage({
        'tool_call_id': toolCallId,
        'chunk': jsonDecode(splitMessageHeader(chunk.pack())) as Map<String, dynamic>,
      }, splitMessagePayload(chunk.pack()).isEmpty ? null : splitMessagePayload(chunk.pack())),
    );
  }
}

Future<_SqliteHarness> _startSqliteHarness() async {
  final pair = _ProtocolPair();
  final server = _FakeSqliteServer();
  pair.serverProtocol.start(onMessage: server.handleMessage);

  final room = RoomClient(protocolFactory: pair.clientProtocolFactory);
  final startFuture = room.start();
  await _sendRoomReady(pair.serverProtocol);
  await startFuture;

  return _SqliteHarness(pair: pair, room: room, server: server);
}

void main() {
  test('sqlite client forwards lifecycle, table, mutation, and SQL calls', () async {
    final harness = await _startSqliteHarness();
    final batch = _testArrowBatch(id: 42, label: 'forty-two');
    final table = ArrowTable(schema: batch.schema, batches: [batch]);
    final db = harness.room.sqlite.database('app', namespace: ['team']);

    expect(await harness.room.sqlite.listDatabases(namespace: ['team']), ['app']);
    await harness.room.sqlite.createDatabase(name: 'app', namespace: ['team'], mode: SqliteCreateMode.createIfNotExists);
    final details = await harness.room.sqlite.inspectDatabase(name: 'app', namespace: ['team']);
    expect(details.tables, 2);
    await db.createDatabase(mode: SqliteCreateMode.createIfNotExists);
    expect((await db.inspectDatabase()).tables, 2);
    await db.dropDatabase(ignoreMissing: true);
    await db.createTableFromArrowTable(name: 'records', table: table);
    await db.insertTable(table: 'records', records: table);
    expect(await db.listTables(), ['records']);
    expect((await db.inspect('records')).fields.map((field) => field.name), ['id', 'label']);
    expect(
      (await db.searchTable(
        table: 'records',
        where: {
          'label': DatasetJson({'kind': 'demo'}),
        },
      )).toRows(),
      [
        {'id': BigInt.one, 'label': 'search'},
      ],
    );
    expect((await db.sqlTable(query: 'SELECT * FROM records WHERE id = ?', params: [1])).toRows(), [
      {'id': BigInt.from(2), 'label': 'sql'},
    ]);
    expect(await db.update(table: 'records', where: 'id = ?', params: [1], values: {'label': 'updated'}), 3);
    expect(await db.delete(table: 'records', where: 'id = ?', params: [1]), 3);
    expect(await db.count(table: 'records', where: {'label': 'updated'}), 3);
    await db.addColumnsWithSchema(
      table: 'records',
      schema: const ArrowSchema([ArrowField(name: 'email', type: ArrowUtf8Type())]),
    );
    await db.dropColumns(table: 'records', columns: ['email']);
    await db.renameTable(name: 'records', newName: 'renamed_records');
    expect(await db.executeSqlStatement(query: 'DELETE FROM records WHERE id = ?', params: [1]), 3);
    final cancelResult = await harness.room.sqlite.cancelSqlQuery(queryId: 'sql-query-1');
    expect(cancelResult.status, SqliteSqlCancelStatus.notCancellable);

    expect(harness.server.writeStarts['create_table']!.single, {
      'kind': 'start',
      'database': 'app',
      'name': 'records',
      'mode': 'create',
      'namespace': ['team'],
    });
    expect(harness.server.writeStarts['insert']!.single, {
      'kind': 'start',
      'database': 'app',
      'table': 'records',
      'namespace': ['team'],
    });
    expect(harness.server.readStarts['search']!.single, {
      'kind': 'start',
      'database': 'app',
      'table': 'records',
      'where': {
        'label': {
          'json': {'kind': 'demo'},
        },
      },
      'params': null,
      'offset': null,
      'limit': null,
      'select': null,
      'namespace': ['team'],
    });
    expect(harness.server.requests.firstWhere((request) => request.tool == 'execute_sql').input, {
      'database': 'app',
      'query': 'SELECT * FROM records WHERE id = ?',
      'params': [1],
      'namespace': ['team'],
    });
    expect(harness.server.requests.firstWhere((request) => request.tool == 'update').input, {
      'database': 'app',
      'table': 'records',
      'where': 'id = ?',
      'values': [
        {'column': 'label', 'value_json': '"updated"'},
      ],
      'params': [1],
      'namespace': ['team'],
    });
    expect(harness.server.requests.firstWhere((request) => request.tool == 'drop_columns').input, {
      'database': 'app',
      'table': 'records',
      'columns': ['email'],
      'namespace': ['team'],
    });

    await harness.dispose();
  });

  test('sqlite client rejects malformed responses', () async {
    final harness = await _startSqliteHarness();
    final client = harness.room.sqlite;

    harness.server.malformedResponses['list_databases'] = EmptyContent();
    expect(() => client.listDatabases(), throwsA(isA<RoomServerException>()));

    harness.server.malformedResponses['list_databases'] = JsonContent(
      json: const {
        'databases': ['app', 3],
      },
    );
    expect(() => client.listDatabases(), throwsA(isA<RoomServerException>()));

    harness.server.malformedResponses['list_tables'] = JsonContent(
      json: const {
        'tables': ['records', 3],
      },
    );
    expect(() => client.listTables(database: 'app'), throwsA(isA<RoomServerException>()));

    harness.server.malformedResponses['count'] = JsonContent(json: const {'count': '3'});
    expect(() => client.count(database: 'app', table: 'records'), throwsA(isA<RoomServerException>()));

    harness.server.malformedResponses['open_sql_query'] = BinaryContent(
      data: ArrowIpcSchema.fromSchema(_testArrowSchema()).bytes,
      headers: const {'kind': 'query'},
    );
    expect(() => client.openSqlQuery(database: 'app', query: 'SELECT * FROM records'), throwsA(isA<RoomServerException>()));

    harness.server.malformedResponses['execute_sql'] = JsonContent(json: const {'kind': 'statement', 'rows_affected': '3'});
    expect(() => client.executeSql(database: 'app', query: 'DELETE FROM records'), throwsA(isA<RoomServerException>()));

    harness.server.malformedResponses['execute_sql_statement'] = JsonContent(json: const {'rows_affected': '3'});
    expect(() => client.executeSqlStatement(database: 'app', query: 'DELETE FROM records'), throwsA(isA<RoomServerException>()));

    harness.server.malformedResponses['cancel_sql_query'] = JsonContent(json: const {'status': 'done'});
    expect(() => client.cancelSqlQuery(queryId: 'sql-query-1'), throwsA(isA<RoomServerException>()));

    await harness.dispose();
  });

  test('sqlite client propagates stream errors and rejects malformed stream chunks', () async {
    final batch = _testArrowBatch();
    final table = ArrowTable(schema: batch.schema, batches: [batch]);

    var harness = await _startSqliteHarness();
    harness.server.streamChunks['create_table'] = [
      JsonContent(json: const {'kind': 'pull'}),
    ];
    expect(
      () => harness.room.sqlite.createTableFromArrowTable(database: 'app', name: 'records', table: table),
      throwsA(isA<RoomServerException>()),
    );
    await harness.dispose();

    harness = await _startSqliteHarness();
    harness.server.streamChunks['create_table'] = [ErrorContent(text: 'create failed', code: 400)];
    await expectLater(
      () => harness.room.sqlite.createTableFromArrowTable(database: 'app', name: 'records', table: table),
      throwsA(isA<RoomServerException>().having((error) => error.message, 'message', contains('create failed'))),
    );
    await harness.dispose();

    harness = await _startSqliteHarness();
    harness.server.streamChunks['search'] = [
      BinaryContent(data: Uint8List(0), headers: const {'kind': 'pull'}),
    ];
    expect(() => harness.room.sqlite.searchTable(database: 'app', table: 'records'), throwsA(isA<RoomServerException>()));
    await harness.dispose();

    harness = await _startSqliteHarness();
    harness.server.streamChunks['search'] = [ErrorContent(text: 'search failed', code: 400)];
    await expectLater(
      () => harness.room.sqlite.searchTable(database: 'app', table: 'records'),
      throwsA(isA<RoomServerException>().having((error) => error.message, 'message', contains('search failed'))),
    );
    await harness.dispose();

    harness = await _startSqliteHarness();
    harness.server.streamChunks['read_sql_query'] = [
      BinaryContent(data: Uint8List(0), headers: const {'kind': 'pull'}),
    ];
    expect(() => harness.room.sqlite.readSqlQuery(queryId: 'sql-query-1').toList(), throwsA(isA<RoomServerException>()));
    await harness.dispose();

    harness = await _startSqliteHarness();
    harness.server.streamChunks['read_sql_query'] = [ErrorContent(text: 'read failed', code: 400)];
    await expectLater(
      () => harness.room.sqlite.readSqlQuery(queryId: 'sql-query-1').toList(),
      throwsA(isA<RoomServerException>().having((error) => error.message, 'message', contains('read failed'))),
    );
    await harness.dispose();
  });

  test('sqlite client decodes float, binary, and null Arrow values', () async {
    final harness = await _startSqliteHarness();
    final mixed = _mixedArrowBatch();
    harness.server.searchBatchBytes = mixed.ipcBytes;
    harness.server.sqlBatchBytes = mixed.ipcBytes;

    final searchRows = (await harness.room.sqlite.searchTable(database: 'app', table: 'metrics')).toRows();
    expect(searchRows, [
      {
        'id': BigInt.one,
        'score': 1.5,
        'payload': Uint8List.fromList([1, 2, 3]),
      },
      {'id': BigInt.two, 'score': null, 'payload': null},
    ]);

    final sqlRows = (await harness.room.sqlite.sqlTable(database: 'app', query: 'SELECT id, score, payload FROM metrics')).toRows();
    expect(sqlRows, searchRows);

    await harness.dispose();
  });
}

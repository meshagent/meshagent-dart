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

  Protocol get clientProtocol {
    final protocol = _clientProtocol;
    if (protocol == null) {
      throw StateError('client protocol has not been created');
    }
    return protocol;
  }

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

class _RecordedRequest {
  _RecordedRequest({required this.tool, required this.input});

  final String tool;
  final Map<String, dynamic> input;
}

Object? _encodedDatasetValue(Object? value) {
  if (value == null || value is bool || value is num || value is String) {
    return value;
  }
  if (value is Uint8List) {
    return {'binary': base64Encode(value)};
  }
  if (value is UuidValue) {
    return {'uuid': value.toFormattedString(validate: true)};
  }
  if (value is DatasetExpression) {
    return {'expression': value.expression};
  }
  if (value is DatasetDate) {
    return {'date': value.toString()};
  }
  if (value is DateTime) {
    final normalized = value.isUtc ? value : value.toUtc();
    return {'timestamp': normalized.toIso8601String().replaceFirst("+00:00", "Z")};
  }
  if (value is DatasetStruct) {
    return {'struct': value.toJson()};
  }
  if (value is DatasetJson) {
    return {'json': value.toJson()};
  }
  if (value is List) {
    return {'list': value.map(_encodedDatasetValue).toList(growable: false)};
  }
  if (value is Map<String, Object?>) {
    return {
      'struct': {for (final entry in value.entries) entry.key: _encodedDatasetValue(entry.value)},
    };
  }
  throw StateError('unsupported typed value ${value.runtimeType}');
}

Map<String, dynamic> _rowsChunk(List<Map<String, dynamic>> rows) {
  return {
    'kind': 'rows',
    'rows': rows
        .map(
          (row) => {
            'columns': row.entries
                .map((entry) {
                  return {'name': entry.key, 'value': _encodedDatasetValue(entry.value)};
                })
                .toList(growable: false),
          },
        )
        .toList(growable: false),
  };
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

class _DatasetsHarness {
  _DatasetsHarness({required this.pair, required this.room, required this.server});

  final _ProtocolPair pair;
  final RoomClient room;
  final _FakeDatasetsServer server;

  Future<void> dispose() async {
    await Future<void>.delayed(Duration.zero);
    room.dispose();
    await pair.dispose();
  }
}

class _FakeDatasetsServer {
  final requests = <_RecordedRequest>[];
  final writeStarts = <String, List<Map<String, dynamic>>>{'create_table': [], 'insert': [], 'merge': []};
  final writeStartData = <String, List<Uint8List>>{'create_table': [], 'insert': [], 'merge': []};
  final writeChunks = <String, List<Map<String, dynamic>>>{'create_table': [], 'insert': [], 'merge': []};
  final readStarts = <String, List<Map<String, dynamic>>>{'search': [], 'read_sql_query': []};
  final readPulls = <String, List<Map<String, dynamic>>>{'search': [], 'read_sql_query': []};
  final _toolCallTools = <String, String>{};
  var inspectFields = <Map<String, dynamic>>[
    {
      'name': 'annotations',
      'data_type': {
        'type': 'list',
        'nullable': null,
        'metadata': null,
        'element_type': {
          'type': 'struct',
          'nullable': null,
          'metadata': null,
          'fields': [
            {
              'name': 'key',
              'data_type': {'type': 'text', 'nullable': null, 'metadata': null},
            },
            {
              'name': 'value',
              'data_type': {'type': 'text', 'nullable': null, 'metadata': null},
            },
          ],
        },
      },
    },
  ];
  var searchRows = <Map<String, dynamic>>[
    {'payload': Uint8List.fromList('hello'.codeUnits)},
  ];
  var sqlRows = <Map<String, dynamic>>[
    {'id': 1, 'payload': Uint8List.fromList('sql-result'.codeUnits)},
  ];
  late final inspectSchema = ArrowSchema(
    [
      ArrowField(
        name: 'annotations',
        metadata: {'field': 'annotations'},
        type: ArrowListType(
          ArrowField(
            name: 'item',
            type: ArrowStructType([
              ArrowField(name: 'key', type: ArrowUtf8Type(), nullable: false, metadata: {'role': 'key'}),
              ArrowField(name: 'value', type: ArrowUtf8Type(large: true), metadata: {'role': 'value'}),
            ]),
          ),
        ),
      ),
    ],
    metadata: {'schema': 'inspect'},
  );
  late final inspectSchemaBytes = ArrowIpcSchema.fromSchema(inspectSchema).bytes;
  late Uint8List searchBatchBytes = _testArrowBatch(id: 1, label: 'search').ipcBytes;
  late Uint8List sqlBatchBytes = _testArrowBatch(id: 2, label: 'sql').ipcBytes;

  Future<void> handleMessage(Protocol protocol, int messageId, String type, Uint8List data) async {
    final message = unpackMessage(data);
    final request = message.header;
    if (type == 'room.invoke_tool') {
      if (request['toolkit'] != 'dataset') {
        return;
      }

      final tool = request['tool'] as String;
      final input = _decodeInput(message: message, request: request);
      if (input is ControlContent) {
        final toolCallId = request['tool_call_id'] as String;
        _toolCallTools[toolCallId] = tool;
        await protocol.send('__response__', ControlContent(method: 'open').pack(), id: messageId);
        return;
      }
      if (tool == 'open_sql_query' || tool == 'execute_sql') {
        if (input is! BinaryContent) {
          throw StateError('datasets.$tool expected BinaryContent input');
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
          throw StateError('datasets.$tool expected BinaryContent input');
        }
        requests.add(_RecordedRequest(tool: tool, input: Map<String, dynamic>.from(input.headers)));
        await protocol.send('__response__', JsonContent(json: const {'rows_affected': 3}).pack(), id: messageId);
        return;
      }

      if (input is! JsonContent) {
        throw StateError('datasets.$tool expected JsonContent input');
      }

      requests.add(_RecordedRequest(tool: tool, input: Map<String, dynamic>.from(input.json)));

      switch (tool) {
        case 'list_tables':
          await protocol.send(
            '__response__',
            JsonContent(
              json: {
                'tables': ['records'],
              },
            ).pack(),
            id: messageId,
          );
          return;
        case 'inspect':
          await protocol.send('__response__', BinaryContent(data: inspectSchemaBytes).pack(), id: messageId);
          return;
        case 'count':
          await protocol.send('__response__', JsonContent(json: {'count': 1}).pack(), id: messageId);
          return;
        case 'close_sql_query':
          await protocol.send('__response__', EmptyContent().pack(), id: messageId);
          return;
        case 'cancel_sql_query':
          await protocol.send('__response__', JsonContent(json: {'status': 'cancelling'}).pack(), id: messageId);
          return;
        case 'list_versions':
          await protocol.send(
            '__response__',
            JsonContent(
              json: {
                'versions': [
                  {
                    'version': 1,
                    'timestamp': '2025-01-01T00:00:00Z',
                    'metadata_json': jsonEncode({'kind': 'demo'}),
                  },
                ],
              },
            ).pack(),
            id: messageId,
          );
          return;
        case 'list_branches':
          await protocol.send(
            '__response__',
            JsonContent(
              json: {
                'branches': [
                  {'name': 'main', 'parent_branch': null, 'parent_version': null, 'created_at': '2025-01-01T00:00:00Z', 'manifest_size': 1},
                ],
              },
            ).pack(),
            id: messageId,
          );
          return;
        case 'list_indexes':
          await protocol.send(
            '__response__',
            JsonContent(
              json: {
                'indexes': [
                  {
                    'name': 'idx_records_id',
                    'columns': ['id'],
                    'type': 'btree',
                  },
                ],
              },
            ).pack(),
            id: messageId,
          );
          return;
        case 'optimize':
          await protocol.send(
            '__response__',
            JsonContent(
              json: {
                'compaction': {'fragments_removed': 0, 'fragments_added': 0, 'files_removed': 0, 'files_added': 0},
                'optimized_indices': true,
                'cleanup': {'bytes_removed': 0},
              },
            ).pack(),
            id: messageId,
          );
          return;
        case 'stats':
          await protocol.send(
            '__response__',
            JsonContent(
              json: {
                'dataset': {'num_fragments': 1},
                'data': {'fields': []},
              },
            ).pack(),
            id: messageId,
          );
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
          throw StateError('unsupported control chunk for datasets.$tool');
        }
        if (tool == 'create_table' || tool == 'insert' || tool == 'merge') {
          await _sendResponseChunk(protocol, toolCallId, ControlContent(method: 'close'));
        }
        return;
      }

      if (tool == 'create_table' || tool == 'insert' || tool == 'merge') {
        if (chunk is BinaryContent) {
          if (chunk.headers['kind'] == 'start') {
            writeStarts[tool]!.add(Map<String, dynamic>.from(chunk.headers));
            writeStartData[tool]!.add(chunk.data);
            await _sendResponseChunk(protocol, toolCallId, BinaryContent(data: Uint8List(0), headers: const {'kind': 'pull'}));
            return;
          }
          writeChunks[tool]!.add({'headers': Map<String, dynamic>.from(chunk.headers), 'data': chunk.data});
          await _sendResponseChunk(protocol, toolCallId, BinaryContent(data: Uint8List(0), headers: const {'kind': 'pull'}));
          return;
        }
        if (chunk is! JsonContent) {
          throw StateError('datasets.$tool expected JsonContent or BinaryContent chunk');
        }
        if (chunk.json['kind'] == 'start') {
          writeStarts[tool]!.add(Map<String, dynamic>.from(chunk.json));
          await _sendResponseChunk(protocol, toolCallId, JsonContent(json: const {'kind': 'pull'}));
          return;
        }
        writeChunks[tool]!.add(Map<String, dynamic>.from(chunk.json));
        await _sendResponseChunk(protocol, toolCallId, JsonContent(json: const {'kind': 'pull'}));
        return;
      }

      if (tool == 'search' || tool == 'read_sql_query') {
        if (chunk is! BinaryContent) {
          throw StateError('datasets.$tool expected BinaryContent chunk');
        }
        if (chunk.headers['kind'] == 'start') {
          readStarts[tool]!.add(Map<String, dynamic>.from(chunk.headers));
          return;
        }
        readPulls[tool]!.add(Map<String, dynamic>.from(chunk.headers));
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

      throw StateError('unsupported streamed datasets operation: $tool');
    }
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

Future<_DatasetsHarness> _startDatasetsHarness() async {
  final pair = _ProtocolPair();
  final server = _FakeDatasetsServer();
  pair.serverProtocol.start(onMessage: server.handleMessage);

  final room = RoomClient(protocolFactory: pair.clientProtocolFactory);
  final startFuture = room.start();
  await _sendRoomReady(pair.serverProtocol);
  await startFuture;

  return _DatasetsHarness(pair: pair, room: room, server: server);
}

void main() {
  final tableSchema = ArrowSchema([ArrowField(name: 'id', type: ArrowIntType(bitWidth: 64, signed: true))]);

  test('datasets client streams structured row chunks', () async {
    final harness = await _startDatasetsHarness();

    await harness.room.datasets.createTableWithSchema(name: 'records', schema: tableSchema, branch: 'exp', metadata: {'kind': 'demo'});
    await harness.room.datasets.createTableFromData(
      name: 'records-from-data',
      data: [
        {'created_at': DateTime.utc(2025, 5, 21, 18, 32, 56)},
      ],
    );
    await harness.room.datasets.insert(
      table: 'records',
      namespace: ['team'],
      branch: 'exp',
      records: ArrowRecordBatch(Uint8List.fromList('inserted'.codeUnits)),
    );
    await harness.room.datasets.merge(
      table: 'records',
      namespace: ['team'],
      branch: 'exp',
      on: 'id',
      records: ArrowRecordBatch(Uint8List.fromList('merged'.codeUnits)),
    );

    final createStart = harness.server.writeStarts['create_table']!.first;
    expect(createStart['kind'], 'start');
    expect(createStart['name'], 'records');
    expect(createStart['metadata'], [
      {'key': 'kind', 'value': 'demo'},
    ]);
    expect(createStart['branch'], 'exp');
    expect(ArrowIpcSchema(harness.server.writeStartData['create_table']!.first).schema.fields.single.name, 'id');
    expect(harness.server.writeChunks['create_table'], [
      _rowsChunk([
        {'created_at': DateTime.utc(2025, 5, 21, 18, 32, 56)},
      ]),
    ]);
    expect(harness.server.writeStarts['insert']!.single, {
      'kind': 'start',
      'table': 'records',
      'namespace': ['team'],
      'branch': 'exp',
    });
    expect(harness.server.writeChunks['insert'], [
      {
        'headers': {'kind': 'data', 'content_type': 'application/vnd.apache.arrow.stream'},
        'data': Uint8List.fromList('inserted'.codeUnits),
      },
    ]);
    expect(harness.server.writeStarts['merge']!.single, {
      'kind': 'start',
      'table': 'records',
      'on': 'id',
      'namespace': ['team'],
      'branch': 'exp',
    });
    expect(harness.server.writeChunks['merge'], [
      {
        'headers': {'kind': 'data', 'content_type': 'application/vnd.apache.arrow.stream'},
        'data': Uint8List.fromList('merged'.codeUnits),
      },
    ]);

    await harness.dispose();
  });

  test('datasets client exposes native Arrow table helpers', () async {
    final harness = await _startDatasetsHarness();
    final batch = _testArrowBatch(id: 42, label: 'forty-two');
    final table = ArrowTable(schema: batch.schema, batches: [batch]);

    await harness.room.datasets.createTableFromArrowTable(
      name: 'native_records',
      table: table,
      mode: CreateMode.overwrite,
      namespace: ['team'],
      branch: 'exp',
      metadata: {'kind': 'arrow'},
    );
    await harness.room.datasets.insertTable(table: 'native_records', records: table, namespace: ['team'], branch: 'exp');
    await harness.room.datasets.mergeTable(table: 'native_records', on: 'id', records: table, namespace: ['team'], branch: 'exp');

    final searchTable = await harness.room.datasets.searchTable(table: 'native_records', branch: 'exp');
    final sqlTable = await harness.room.datasets.sqlTable(
      query: 'SELECT * FROM native_records',
      tables: [TableRef(name: 'native_records', branch: 'exp')],
    );

    expect(harness.server.writeStarts['create_table']!.single, {
      'kind': 'start',
      'name': 'native_records',
      'mode': 'overwrite',
      'namespace': ['team'],
      'branch': 'exp',
      'metadata': [
        {'key': 'kind', 'value': 'arrow'},
      ],
    });
    expect(ArrowIpcSchema(harness.server.writeStartData['create_table']!.single).schema.fields.map((field) => field.name), ['id', 'label']);
    expect(harness.server.writeChunks['create_table']!.single, {
      'headers': {'kind': 'data', 'content_type': 'application/vnd.apache.arrow.stream'},
      'data': batch.ipcBytes,
    });
    expect(harness.server.writeChunks['insert']!.single, {
      'headers': {'kind': 'data', 'content_type': 'application/vnd.apache.arrow.stream'},
      'data': batch.ipcBytes,
    });
    expect(harness.server.writeChunks['merge']!.single, {
      'headers': {'kind': 'data', 'content_type': 'application/vnd.apache.arrow.stream'},
      'data': batch.ipcBytes,
    });

    expect(searchTable.schema.fields.map((field) => field.name), ['id', 'label']);
    expect(searchTable.toRows(), [
      {'id': BigInt.one, 'label': 'search'},
    ]);
    expect(sqlTable.schema.fields.map((field) => field.name), ['id', 'label']);
    expect(sqlTable.toRows(), [
      {'id': BigInt.from(2), 'label': 'sql'},
    ]);

    await harness.dispose();
  });

  test('datasets inspect, search, and sql decode streamed row chunks', () async {
    final harness = await _startDatasetsHarness();

    final inspectedSchema = await harness.room.datasets.inspect('records', branch: 'exp', version: 7);
    expect(inspectedSchema.fields.single.name, 'annotations');
    expect(inspectedSchema.metadata, {'schema': 'inspect'});
    expect(inspectedSchema.fields.single.metadata, {'field': 'annotations'});
    final annotationsType = inspectedSchema.fields.single.type as ArrowListType;
    final itemType = annotationsType.valueField.type as ArrowStructType;
    expect(itemType.fields[0].nullable, isFalse);
    expect(itemType.fields[0].metadata, {'role': 'key'});
    final valueType = itemType.fields[1].type as ArrowUtf8Type;
    expect(valueType.large, isTrue);

    final rows = await harness.room.datasets.search(table: 'records', branch: 'exp', version: 7);
    expect(rows, hasLength(1));
    expect(rows.single.ipcBytes, harness.server.searchBatchBytes);

    final sqlRows = await harness.room.datasets.sql(
      query: 'SELECT * FROM records',
      tables: [TableRef(name: 'records', branch: 'exp', version: 7)],
    );
    expect(sqlRows, hasLength(1));
    expect(sqlRows.single.ipcBytes, harness.server.sqlBatchBytes);

    final versions = await harness.room.datasets.listVersions('records', branch: 'exp');
    expect(versions, hasLength(1));
    expect(versions.single.version, 1);
    expect(versions.single.metadata, {'kind': 'demo'});

    final branches = await harness.room.datasets.listBranches(namespace: ['team']);
    expect(branches, hasLength(1));
    expect(branches.single.name, 'main');
    expect(branches.single.parentBranch, isNull);
    expect(branches.single.parentVersion, isNull);
    expect(branches.single.createdAt, DateTime.parse('2025-01-01T00:00:00Z'));
    expect(branches.single.manifestSize, 1);

    await harness.room.datasets.createBranch(branch: 'exp', fromBranch: 'main', namespace: ['team']);
    await harness.room.datasets.createIndex(
      table: 'records',
      config: const DatasetIndexConfig(column: 'embedding', indexType: 'IVF_PQ', numPartitions: 32, numSubVectors: 8),
      namespace: ['team'],
      branch: 'exp',
    );
    await harness.room.datasets.restore(table: 'records', version: 2, namespace: ['team'], branch: 'exp');
    await harness.room.datasets.dropIndex(table: 'records', name: 'idx_records_id', namespace: ['team'], branch: 'exp');
    await harness.room.datasets.updateColumnMetadata(
      table: 'records',
      column: 'image',
      metadata: {'content-type': 'image/*'},
      namespace: ['team'],
      branch: 'exp',
    );
    final optimizeResult = await harness.room.datasets.optimize(table: 'records', namespace: ['team'], branch: 'exp');
    expect(optimizeResult.optimizedIndices, isTrue);
    final stats = await harness.room.datasets.stats('records', namespace: ['team'], branch: 'exp', version: 7);
    expect(stats.dataset['num_fragments'], 1);
    final indexes = await harness.room.datasets.listIndexes('records', namespace: ['team'], branch: 'exp', version: 7);
    expect(indexes, hasLength(1));
    expect(indexes.single.name, 'idx_records_id');
    await harness.room.datasets.deleteBranch(branch: 'exp', namespace: ['team']);

    expect(harness.server.readStarts['search']!.single, {
      'kind': 'start',
      'table': 'records',
      'text': null,
      'vector': null,
      'text_columns': null,
      'where': null,
      'offset': null,
      'limit': null,
      'select': null,
      'namespace': null,
      'branch': 'exp',
      'version': 7,
    });
    expect(harness.server.readPulls['search'], [
      {'kind': 'pull'},
      {'kind': 'pull'},
    ]);
    expect(harness.server.readStarts['read_sql_query']!.single, {'kind': 'start', 'query_id': 'sql-query-1'});
    expect(harness.server.requests.firstWhere((request) => request.tool == 'execute_sql').input, {
      'query': 'SELECT * FROM records',
      'tables': [
        {'name': 'records', 'namespace': null, 'alias': null, 'branch': 'exp', 'version': 7},
      ],
      'namespace': null,
      'branch': null,
    });
    expect(harness.server.readPulls['read_sql_query'], [
      {'kind': 'pull'},
      {'kind': 'pull'},
    ]);
    expect(harness.server.requests.firstWhere((request) => request.tool == 'close_sql_query').input, {'query_id': 'sql-query-1'});

    final cancelResult = await harness.room.datasets.cancelSqlQuery(queryId: 'sql-query-1');
    expect(cancelResult.status, DatasetSqlCancelStatus.cancelling);
    expect(harness.server.requests.firstWhere((request) => request.tool == 'cancel_sql_query').input, {'query_id': 'sql-query-1'});

    final rowsAffected = await harness.room.datasets.executeSqlStatement(
      query: 'DELETE FROM records WHERE id = \$id',
      tables: [TableRef(name: 'records')],
      params: ArrowTable(
        schema: _testArrowSchema(),
        batches: [_testArrowBatch(id: 1, label: 'delete')],
      ),
    );
    expect(rowsAffected, 3);
    expect(harness.server.requests.firstWhere((request) => request.tool == 'execute_sql_statement').input, {
      'query': 'DELETE FROM records WHERE id = \$id',
      'tables': [
        {'name': 'records', 'namespace': null, 'alias': null, 'branch': null, 'version': null},
      ],
      'namespace': null,
      'branch': null,
    });

    expect(harness.server.requests.firstWhere((request) => request.tool == 'inspect').input, {
      'table': 'records',
      'namespace': null,
      'branch': 'exp',
      'version': 7,
    });
    expect(harness.server.requests.firstWhere((request) => request.tool == 'list_versions').input, {
      'table': 'records',
      'namespace': null,
      'branch': 'exp',
    });
    expect(harness.server.requests.firstWhere((request) => request.tool == 'create_branch').input, {
      'branch': 'exp',
      'from_branch': 'main',
      'namespace': ['team'],
    });
    expect(harness.server.requests.firstWhere((request) => request.tool == 'restore').input, {
      'table': 'records',
      'version': 2,
      'namespace': ['team'],
      'branch': 'exp',
    });
    expect(harness.server.requests.firstWhere((request) => request.tool == 'create_index').input, {
      'table': 'records',
      'config': {'column': 'embedding', 'index_type': 'IVF_PQ', 'num_partitions': 32, 'num_sub_vectors': 8},
      'namespace': ['team'],
      'branch': 'exp',
    });
    expect(harness.server.requests.firstWhere((request) => request.tool == 'list_indexes').input, {
      'table': 'records',
      'namespace': ['team'],
      'branch': 'exp',
      'version': 7,
    });
    expect(harness.server.requests.firstWhere((request) => request.tool == 'update_column_metadata').input, {
      'table': 'records',
      'column': 'image',
      'metadata': [
        {'key': 'content-type', 'value': 'image/*'},
      ],
      'namespace': ['team'],
      'branch': 'exp',
    });
    expect(harness.server.requests.firstWhere((request) => request.tool == 'optimize').input, {
      'table': 'records',
      'namespace': ['team'],
      'branch': 'exp',
      'config': null,
    });
    expect(harness.server.requests.firstWhere((request) => request.tool == 'stats').input, {
      'table': 'records',
      'namespace': ['team'],
      'branch': 'exp',
      'version': 7,
      'max_rows_per_group': null,
    });
    expect(harness.server.requests.firstWhere((request) => request.tool == 'delete_branch').input, {
      'branch': 'exp',
      'namespace': ['team'],
    });

    await harness.dispose();
  });

  test('datasets where maps use json semantics', () async {
    final harness = await _startDatasetsHarness();

    await harness.room.datasets.search(table: 'records', where: {'id': 1, 'active': true, 'name': "O'Reilly"});

    expect(harness.server.readStarts['search']!.single['where'], 'id = 1 AND active = true AND name = "O\'Reilly"');

    await harness.dispose();
  });

  test('datasets client supports uuid schemas, values, and where filters', () async {
    final harness = await _startDatasetsHarness();
    final id = UuidValue.withValidation('123e4567-e89b-12d3-a456-426614174000');

    harness.server.inspectFields = [
      {
        'name': 'id',
        'data_type': {'type': 'uuid', 'nullable': null, 'metadata': null},
      },
    ];
    harness.server.searchRows = [
      {'id': id},
    ];

    await harness.room.datasets.createTableWithSchema(name: 'uuid_records', schema: tableSchema);
    await harness.room.datasets.insert(table: 'uuid_records', records: ArrowRecordBatch(Uint8List.fromList([10, 11, 12])));

    final inspectedSchema = await harness.room.datasets.inspect('uuid_records');
    expect(inspectedSchema.fields.single.name, 'annotations');

    final rows = await harness.room.datasets.search(table: 'uuid_records', where: {'id': id});
    expect(rows, hasLength(1));
    expect(rows.single.ipcBytes, harness.server.searchBatchBytes);

    await harness.room.datasets.count(table: 'uuid_records', where: {'id': id});

    expect(harness.server.writeStarts['create_table']!.single, {
      'kind': 'start',
      'name': 'uuid_records',
      'mode': 'create',
      'namespace': null,
      'branch': null,
      'metadata': null,
    });
    expect(ArrowIpcSchema(harness.server.writeStartData['create_table']!.single).schema.fields.single.name, 'id');
    expect(harness.server.writeStarts['insert']!.single, {'kind': 'start', 'table': 'uuid_records', 'namespace': null, 'branch': null});
    expect(harness.server.writeChunks['insert'], [
      {
        'headers': {'kind': 'data', 'content_type': 'application/vnd.apache.arrow.stream'},
        'data': Uint8List.fromList([10, 11, 12]),
      },
    ]);
    expect(harness.server.readStarts['search']!.single['where'], "id = X'123e4567e89b12d3a456426614174000'");
    expect(harness.server.requests.firstWhere((request) => request.tool == 'count').input, {
      'table': 'uuid_records',
      'text': null,
      'vector': null,
      'text_columns': null,
      'where': "id = X'123e4567e89b12d3a456426614174000'",
      'namespace': null,
      'branch': null,
      'version': null,
    });

    await harness.dispose();
  });

  test('datasets client supports json schemas and values', () async {
    final harness = await _startDatasetsHarness();
    final payload = DatasetJson({
      'kind': 'demo',
      'count': 3,
      'tags': ['a', 'b'],
    });

    harness.server.inspectFields = [
      {
        'name': 'payload',
        'data_type': {'type': 'json', 'nullable': null, 'metadata': null},
      },
    ];
    harness.server.searchRows = [
      {'payload': payload},
    ];

    await harness.room.datasets.createTableWithSchema(name: 'json_records', schema: tableSchema);
    await harness.room.datasets.insert(table: 'json_records', records: ArrowRecordBatch(Uint8List.fromList([13, 14, 15])));

    final inspectedSchema = await harness.room.datasets.inspect('json_records');
    expect(inspectedSchema.fields.single.name, 'annotations');

    final rows = await harness.room.datasets.search(table: 'json_records');
    expect(rows, hasLength(1));
    expect(rows.single.ipcBytes, harness.server.searchBatchBytes);

    expect(harness.server.writeStarts['create_table']!.single, {
      'kind': 'start',
      'name': 'json_records',
      'mode': 'create',
      'namespace': null,
      'branch': null,
      'metadata': null,
    });
    expect(ArrowIpcSchema(harness.server.writeStartData['create_table']!.single).schema.fields.single.name, 'id');
    expect(harness.server.writeChunks['insert'], [
      {
        'headers': {'kind': 'data', 'content_type': 'application/vnd.apache.arrow.stream'},
        'data': Uint8List.fromList([13, 14, 15]),
      },
    ]);

    await harness.dispose();
  });

  test('datasets client encodes expressions for streamed writes and updates', () async {
    final harness = await _startDatasetsHarness();

    await harness.room.datasets.insert(
      table: 'records',
      namespace: ['team'],
      branch: 'exp',
      records: ArrowRecordBatch(Uint8List.fromList([16, 17, 18])),
    );

    await harness.room.datasets.update(
      table: 'records',
      where: 'true',
      namespace: ['team'],
      branch: 'exp',
      values: {'id': DatasetExpression('uuid()'), 'upper_name': DatasetExpression('upper(name)')},
    );

    expect(harness.server.writeStarts['insert']!.single, {
      'kind': 'start',
      'table': 'records',
      'namespace': ['team'],
      'branch': 'exp',
    });
    expect(harness.server.writeChunks['insert'], [
      {
        'headers': {'kind': 'data', 'content_type': 'application/vnd.apache.arrow.stream'},
        'data': Uint8List.fromList([16, 17, 18]),
      },
    ]);
    expect(harness.server.requests.firstWhere((request) => request.tool == 'update').input, {
      'table': 'records',
      'where': 'true',
      'values': [
        {'column': 'id', 'value_json': '{"expression":"uuid()"}'},
        {'column': 'upper_name', 'value_json': '{"expression":"upper(name)"}'},
      ],
      'namespace': ['team'],
      'branch': 'exp',
    });

    await harness.dispose();
  });

  test('datasets client decodes typed date and timestamp row values', () async {
    final harness = await _startDatasetsHarness();
    harness.server.searchRows = [
      {'event_date': DatasetDate('2026-04-09'), 'created_at': DateTime.parse('2026-04-09T12:30:45Z')},
    ];
    harness.server.sqlRows = [
      {'event_date': DatasetDate('2026-04-09'), 'created_at': DateTime.parse('2026-04-09T12:30:45Z')},
    ];

    final searchRows = await harness.room.datasets.search(table: 'records');
    final sqlRows = await harness.room.datasets.sql(
      query: 'SELECT * FROM records',
      tables: [TableRef(name: 'records')],
    );

    expect(searchRows.single.ipcBytes, harness.server.searchBatchBytes);
    expect(sqlRows.single.ipcBytes, harness.server.sqlBatchBytes);

    await harness.dispose();
  });
}

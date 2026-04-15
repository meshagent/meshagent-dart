import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:meshagent/meshagent.dart';
import 'package:meshagent/database_client.dart';
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

Object? _encodedDatabaseValue(Object? value) {
  if (value == null || value is bool || value is num || value is String) {
    return value;
  }
  if (value is Uint8List) {
    return {'binary': base64Encode(value)};
  }
  if (value is UuidValue) {
    return {'uuid': value.toFormattedString(validate: true)};
  }
  if (value is DatabaseExpression) {
    return {'expression': value.expression};
  }
  if (value is DatabaseDate) {
    return {'date': value.toString()};
  }
  if (value is DateTime) {
    final normalized = value.isUtc ? value : value.toUtc();
    return {'timestamp': normalized.toIso8601String().replaceFirst("+00:00", "Z")};
  }
  if (value is DatabaseStruct) {
    return {'struct': value.toJson()};
  }
  if (value is DatabaseJson) {
    return {'json': value.toJson()};
  }
  if (value is List) {
    return {'list': value.map(_encodedDatabaseValue).toList(growable: false)};
  }
  if (value is Map<String, Object?>) {
    return {
      'struct': {for (final entry in value.entries) entry.key: _encodedDatabaseValue(entry.value)},
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
                  return {'name': entry.key, 'value': _encodedDatabaseValue(entry.value)};
                })
                .toList(growable: false),
          },
        )
        .toList(growable: false),
  };
}

class _DatabaseHarness {
  _DatabaseHarness({required this.pair, required this.room, required this.server});

  final _ProtocolPair pair;
  final RoomClient room;
  final _FakeDatabaseServer server;

  Future<void> dispose() async {
    room.dispose();
    await pair.dispose();
  }
}

class _FakeDatabaseServer {
  final requests = <_RecordedRequest>[];
  final writeStarts = <String, List<Map<String, dynamic>>>{'create_table': [], 'insert': [], 'merge': []};
  final writeChunks = <String, List<Map<String, dynamic>>>{'create_table': [], 'insert': [], 'merge': []};
  final readStarts = <String, List<Map<String, dynamic>>>{'search': [], 'sql': []};
  final readPulls = <String, List<Map<String, dynamic>>>{'search': [], 'sql': []};
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

  Future<void> handleMessage(Protocol protocol, int messageId, String type, Uint8List data) async {
    final message = unpackMessage(data);
    final request = message.header;
    if (type == 'room.invoke_tool') {
      if (request['toolkit'] != 'database') {
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
      if (input is! JsonContent) {
        throw StateError('database.$tool expected JsonContent input');
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
          await protocol.send('__response__', JsonContent(json: {'fields': inspectFields, 'metadata': null}).pack(), id: messageId);
          return;
        case 'count':
          await protocol.send('__response__', JsonContent(json: {'count': 1}).pack(), id: messageId);
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
          throw StateError('unsupported control chunk for database.$tool');
        }
        if (tool == 'create_table' || tool == 'insert' || tool == 'merge') {
          await _sendResponseChunk(protocol, toolCallId, ControlContent(method: 'close'));
        }
        return;
      }

      if (chunk is! JsonContent) {
        throw StateError('database.$tool expected JsonContent chunk');
      }

      if (tool == 'create_table' || tool == 'insert' || tool == 'merge') {
        if (chunk.json['kind'] == 'start') {
          writeStarts[tool]!.add(Map<String, dynamic>.from(chunk.json));
          await _sendResponseChunk(protocol, toolCallId, JsonContent(json: const {'kind': 'pull'}));
          return;
        }
        writeChunks[tool]!.add(Map<String, dynamic>.from(chunk.json));
        await _sendResponseChunk(protocol, toolCallId, JsonContent(json: const {'kind': 'pull'}));
        return;
      }

      if (tool == 'search' || tool == 'sql') {
        if (chunk.json['kind'] == 'start') {
          readStarts[tool]!.add(Map<String, dynamic>.from(chunk.json));
          return;
        }
        readPulls[tool]!.add(Map<String, dynamic>.from(chunk.json));
        if (readPulls[tool]!.length == 1) {
          if (tool == 'search') {
            await _sendResponseChunk(protocol, toolCallId, JsonContent(json: _rowsChunk(searchRows)));
          } else {
            await _sendResponseChunk(protocol, toolCallId, JsonContent(json: _rowsChunk(sqlRows)));
          }
          return;
        }
        await _sendResponseChunk(protocol, toolCallId, ControlContent(method: 'close'));
        return;
      }

      throw StateError('unsupported streamed database operation: $tool');
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

Future<_DatabaseHarness> _startDatabaseHarness() async {
  final pair = _ProtocolPair();
  final server = _FakeDatabaseServer();
  pair.serverProtocol.start(onMessage: server.handleMessage);

  final room = RoomClient(protocolFactory: pair.clientProtocolFactory);
  final startFuture = room.start();
  await _sendRoomReady(pair.serverProtocol);
  await startFuture;

  return _DatabaseHarness(pair: pair, room: room, server: server);
}

void main() {
  test('database client streams structured row chunks', () async {
    final harness = await _startDatabaseHarness();

    await harness.room.database.createTableWithSchema(
      name: 'records',
      schema: {
        'annotations': ListDataType(elementType: StructDataType(fields: {'key': TextDataType(), 'value': TextDataType()})),
      },
      branch: 'exp',
      metadata: {'kind': 'demo'},
    );
    await harness.room.database.createTableFromData(
      name: 'records-from-data',
      data: [
        {'created_at': DateTime.utc(2025, 5, 21, 18, 32, 56)},
      ],
    );
    await harness.room.database.insert(
      table: 'records',
      namespace: ['team'],
      branch: 'exp',
      records: [
        {'payload': Uint8List.fromList('inserted'.codeUnits)},
      ],
    );
    await harness.room.database.merge(
      table: 'records',
      namespace: ['team'],
      branch: 'exp',
      on: 'id',
      records: [
        {'id': 1, 'payload': Uint8List.fromList('merged'.codeUnits)},
      ],
    );

    final createStart = harness.server.writeStarts['create_table']!.first;
    expect(createStart['fields'], isA<List>());
    final fields = createStart['fields'] as List<dynamic>;
    expect(fields.single['name'], 'annotations');
    expect(fields.single['data_type']['type'], 'list');
    expect(fields.single['data_type']['element_type']['type'], 'struct');
    expect(fields.single['data_type']['element_type']['fields'], [
      {
        'name': 'key',
        'data_type': {'type': 'text', 'nullable': null, 'metadata': null},
      },
      {
        'name': 'value',
        'data_type': {'type': 'text', 'nullable': null, 'metadata': null},
      },
    ]);
    expect(createStart['metadata'], [
      {'key': 'kind', 'value': 'demo'},
    ]);
    expect(createStart['branch'], 'exp');
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
      _rowsChunk([
        {'payload': Uint8List.fromList('inserted'.codeUnits)},
      ]),
    ]);
    expect(harness.server.writeStarts['merge']!.single, {
      'kind': 'start',
      'table': 'records',
      'on': 'id',
      'namespace': ['team'],
      'branch': 'exp',
    });
    expect(harness.server.writeChunks['merge'], [
      _rowsChunk([
        {'id': 1, 'payload': Uint8List.fromList('merged'.codeUnits)},
      ]),
    ]);

    await harness.dispose();
  });

  test('database inspect, search, and sql decode streamed row chunks', () async {
    final harness = await _startDatabaseHarness();

    final schema = await harness.room.database.inspect('records', branch: 'exp', version: 7);
    expect(schema['annotations'], isA<ListDataType>());
    final annotations = schema['annotations'] as ListDataType;
    expect(annotations.elementType, isA<StructDataType>());
    final struct = annotations.elementType as StructDataType;
    expect(struct.fields['key'], isA<TextDataType>());
    expect(struct.fields['value'], isA<TextDataType>());

    final rows = await harness.room.database.search(table: 'records', branch: 'exp', version: 7);
    expect(rows, hasLength(1));
    expect(rows.single['payload'], isA<Uint8List>());
    expect(utf8.decode(rows.single['payload'] as Uint8List), 'hello');

    final sqlRows = await harness.room.database.sql(
      query: 'SELECT * FROM records',
      tables: [TableRef(name: 'records', branch: 'exp', version: 7)],
    );
    expect(sqlRows, hasLength(1));
    expect(sqlRows.single['id'], 1);
    expect(utf8.decode(sqlRows.single['payload'] as Uint8List), 'sql-result');

    final versions = await harness.room.database.listVersions('records', branch: 'exp');
    expect(versions, hasLength(1));
    expect(versions.single.version, 1);
    expect(versions.single.metadata, {'kind': 'demo'});

    final branches = await harness.room.database.listBranches(namespace: ['team']);
    expect(branches, hasLength(1));
    expect(branches.single.name, 'main');
    expect(branches.single.parentBranch, isNull);
    expect(branches.single.parentVersion, isNull);
    expect(branches.single.createdAt, DateTime.parse('2025-01-01T00:00:00Z'));
    expect(branches.single.manifestSize, 1);

    await harness.room.database.createBranch(branch: 'exp', fromBranch: 'main', namespace: ['team']);
    await harness.room.database.restore(table: 'records', version: 2, namespace: ['team'], branch: 'exp');
    await harness.room.database.dropIndex(table: 'records', name: 'idx_records_id', namespace: ['team'], branch: 'exp');
    await harness.room.database.optimize(table: 'records', namespace: ['team'], branch: 'exp');
    final indexes = await harness.room.database.listIndexes('records', namespace: ['team'], branch: 'exp', version: 7);
    expect(indexes, hasLength(1));
    expect(indexes.single.name, 'idx_records_id');
    await harness.room.database.deleteBranch(branch: 'exp', namespace: ['team']);

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
    expect(harness.server.readStarts['sql']!.single, {
      'kind': 'start',
      'query': 'SELECT * FROM records',
      'tables': [
        {'name': 'records', 'namespace': null, 'alias': null, 'branch': 'exp', 'version': 7},
      ],
      'params_json': null,
    });
    expect(harness.server.readPulls['sql'], [
      {'kind': 'pull'},
      {'kind': 'pull'},
    ]);

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
    expect(harness.server.requests.firstWhere((request) => request.tool == 'list_indexes').input, {
      'table': 'records',
      'namespace': ['team'],
      'branch': 'exp',
      'version': 7,
    });
    expect(harness.server.requests.firstWhere((request) => request.tool == 'delete_branch').input, {
      'branch': 'exp',
      'namespace': ['team'],
    });

    await harness.dispose();
  });

  test('database where maps use json semantics', () async {
    final harness = await _startDatabaseHarness();

    await harness.room.database.search(table: 'records', where: {'id': 1, 'active': true, 'name': "O'Reilly"});

    expect(harness.server.readStarts['search']!.single['where'], 'id = 1 AND active = true AND name = "O\'Reilly"');

    await harness.dispose();
  });

  test('database client supports uuid schemas, values, and where filters', () async {
    final harness = await _startDatabaseHarness();
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

    await harness.room.database.createTableWithSchema(name: 'uuid_records', schema: {'id': UuidDataType()});
    await harness.room.database.insert(
      table: 'uuid_records',
      records: [
        {'id': id},
      ],
    );

    final schema = await harness.room.database.inspect('uuid_records');
    expect(schema['id'], isA<UuidDataType>());

    final rows = await harness.room.database.search(table: 'uuid_records', where: {'id': id});
    expect(rows, hasLength(1));
    expect(rows.single['id'], equals(id));

    await harness.room.database.count(table: 'uuid_records', where: {'id': id});

    expect(harness.server.writeStarts['create_table']!.single, {
      'kind': 'start',
      'name': 'uuid_records',
      'fields': [
        {
          'name': 'id',
          'data_type': {'type': 'uuid', 'nullable': null, 'metadata': null},
        },
      ],
      'mode': 'create',
      'namespace': null,
      'branch': null,
      'metadata': null,
    });
    expect(harness.server.writeStarts['insert']!.single, {'kind': 'start', 'table': 'uuid_records', 'namespace': null, 'branch': null});
    expect(harness.server.writeChunks['insert'], [
      _rowsChunk([
        {'id': id},
      ]),
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

  test('database client supports json schemas and values', () async {
    final harness = await _startDatabaseHarness();
    final payload = DatabaseJson({
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

    await harness.room.database.createTableWithSchema(name: 'json_records', schema: {'payload': JsonDataType()});
    await harness.room.database.insert(
      table: 'json_records',
      records: [
        {'payload': payload},
      ],
    );

    final schema = await harness.room.database.inspect('json_records');
    expect(schema['payload'], isA<JsonDataType>());

    final rows = await harness.room.database.search(table: 'json_records');
    expect(rows, hasLength(1));
    expect(rows.single['payload'], isA<DatabaseJson>());
    expect((rows.single['payload'] as DatabaseJson).toJson(), payload.toJson());

    expect(harness.server.writeStarts['create_table']!.single, {
      'kind': 'start',
      'name': 'json_records',
      'fields': [
        {
          'name': 'payload',
          'data_type': {'type': 'json', 'nullable': null, 'metadata': null},
        },
      ],
      'mode': 'create',
      'namespace': null,
      'branch': null,
      'metadata': null,
    });
    expect(harness.server.writeChunks['insert'], [
      _rowsChunk([
        {'payload': payload},
      ]),
    ]);

    await harness.dispose();
  });

  test('database client encodes expressions for streamed writes and updates', () async {
    final harness = await _startDatabaseHarness();

    await harness.room.database.insert(
      table: 'records',
      namespace: ['team'],
      branch: 'exp',
      records: [
        {'id': DatabaseExpression('uuid()'), 'upper_name': DatabaseExpression('upper(name)')},
      ],
    );

    await harness.room.database.update(
      table: 'records',
      where: 'true',
      namespace: ['team'],
      branch: 'exp',
      values: {'id': DatabaseExpression('uuid()'), 'upper_name': DatabaseExpression('upper(name)')},
    );

    expect(harness.server.writeStarts['insert']!.single, {
      'kind': 'start',
      'table': 'records',
      'namespace': ['team'],
      'branch': 'exp',
    });
    expect(harness.server.writeChunks['insert'], [
      _rowsChunk([
        {'id': DatabaseExpression('uuid()'), 'upper_name': DatabaseExpression('upper(name)')},
      ]),
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

  test('database client decodes typed date and timestamp row values', () async {
    final harness = await _startDatabaseHarness();
    harness.server.searchRows = [
      {'event_date': DatabaseDate('2026-04-09'), 'created_at': DateTime.parse('2026-04-09T12:30:45Z')},
    ];
    harness.server.sqlRows = [
      {'event_date': DatabaseDate('2026-04-09'), 'created_at': DateTime.parse('2026-04-09T12:30:45Z')},
    ];

    final searchRows = await harness.room.database.search(table: 'records');
    final sqlRows = await harness.room.database.sql(
      query: 'SELECT * FROM records',
      tables: [TableRef(name: 'records')],
    );

    expect(searchRows.single['event_date'], isA<DatabaseDate>());
    expect(searchRows.single['event_date'].toString(), '2026-04-09');
    expect(searchRows.single['created_at'], isA<DateTime>());
    expect((searchRows.single['created_at'] as DateTime).toUtc().toIso8601String(), '2026-04-09T12:30:45.000Z');

    expect(sqlRows.single['event_date'], isA<DatabaseDate>());
    expect(sqlRows.single['event_date'].toString(), '2026-04-09');
    expect(sqlRows.single['created_at'], isA<DateTime>());
    expect((sqlRows.single['created_at'] as DateTime).toUtc().toIso8601String(), '2026-04-09T12:30:45.000Z');

    await harness.dispose();
  });
}

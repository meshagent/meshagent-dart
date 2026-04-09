import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:meshagent/meshagent.dart';
import 'package:meshagent/database_client.dart';
import 'package:test/test.dart';

class _ProtocolPair {
  _ProtocolPair() {
    clientProtocol = Protocol(
      channel: StreamProtocolChannel(input: _serverToClient.stream, output: _clientToServer.sink),
    );
    serverProtocol = Protocol(
      channel: StreamProtocolChannel(input: _clientToServer.stream, output: _serverToClient.sink),
    );
  }

  final _clientToServer = StreamController<Uint8List>();
  final _serverToClient = StreamController<Uint8List>();
  late final Protocol clientProtocol;
  late final Protocol serverProtocol;

  Future<void> dispose() async {
    try {
      clientProtocol.dispose();
    } catch (_) {}
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
}

class _RecordedRequest {
  _RecordedRequest({required this.tool, required this.input});

  final String tool;
  final Map<String, dynamic> input;
}

Map<String, dynamic> _rowsChunk(List<Map<String, dynamic>> rows) {
  return {
    'kind': 'rows',
    'rows': rows
        .map(
          (row) => {
            'columns': row.entries
                .map((entry) {
                  final value = entry.value;
                  if (value is Uint8List) {
                    return {
                      'name': entry.key,
                      'value': {'type': 'binary', 'data': base64Encode(value)},
                    };
                  }
                  if (value is DateTime) {
                    final normalized = value.isUtc ? value : value.toUtc();
                    return {
                      'name': entry.key,
                      'value': {'type': 'timestamp', 'value': normalized.toIso8601String().replaceFirst("+00:00", "Z")},
                    };
                  }
                  if (value is int) {
                    return {
                      'name': entry.key,
                      'value': {'type': 'int', 'value': value},
                    };
                  }
                  return {
                    'name': entry.key,
                    'value': {'type': 'text', 'value': value},
                  };
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
          await protocol.send(
            '__response__',
            JsonContent(
              json: {
                'fields': [
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
                ],
                'metadata': null,
              },
            ).pack(),
            id: messageId,
          );
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
            await _sendResponseChunk(
              protocol,
              toolCallId,
              JsonContent(
                json: _rowsChunk([
                  {'payload': Uint8List.fromList('hello'.codeUnits)},
                ]),
              ),
            );
          } else {
            await _sendResponseChunk(
              protocol,
              toolCallId,
              JsonContent(
                json: _rowsChunk([
                  {'id': 1, 'payload': Uint8List.fromList('sql-result'.codeUnits)},
                ]),
              ),
            );
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

  final room = RoomClient(protocol: pair.clientProtocol);
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
}

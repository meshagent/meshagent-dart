import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:meshagent/meshagent.dart';
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

Map<String, dynamic> _typedValue(dynamic value) {
  if (value == null) {
    return {'type': 'null'};
  }
  if (value is bool) {
    return {'type': 'bool', 'value': value};
  }
  if (value is int) {
    return {'type': 'int', 'value': value};
  }
  if (value is num) {
    return {'type': 'float', 'value': value.toDouble()};
  }
  if (value is String) {
    return {'type': 'text', 'value': value};
  }
  if (value is Uint8List) {
    return {'type': 'binary', 'data': base64Encode(value)};
  }
  if (value is List) {
    return {'type': 'list', 'items': value.map(_typedValue).toList(growable: false)};
  }
  if (value is Map<String, dynamic>) {
    return {
      'type': 'struct',
      'fields': value.entries.map((entry) => {'name': entry.key, 'value': _typedValue(entry.value)}).toList(growable: false),
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
            'columns': row.entries.map((entry) => {'name': entry.key, 'value': _typedValue(entry.value)}).toList(growable: false),
          },
        )
        .toList(growable: false),
  };
}

class _MemoryHarness {
  _MemoryHarness({required this.pair, required this.room, required this.server});

  final _ProtocolPair pair;
  final RoomClient room;
  final _FakeMemoryServer server;

  Future<void> dispose() async {
    room.dispose();
    await pair.dispose();
  }
}

class _FakeMemoryServer {
  final requests = <_RecordedRequest>[];

  Future<void> handleMessage(Protocol protocol, int messageId, String type, Uint8List data) async {
    if (type != 'room.invoke_tool') {
      return;
    }

    final message = unpackMessage(data);
    final request = message.header;
    if (request['toolkit'] != 'memory') {
      return;
    }

    final tool = request['tool'] as String;
    final input = _decodeInput(message: message, request: request);
    if (input is! JsonContent) {
      throw StateError('memory.$tool expected JsonContent input');
    }

    requests.add(_RecordedRequest(tool: tool, input: Map<String, dynamic>.from(input.json)));

    switch (tool) {
      case 'list':
        await protocol.send(
          '__response__',
          JsonContent(
            json: {
              'memories': ['alpha', 'beta'],
            },
          ).pack(),
          id: messageId,
        );
        return;
      case 'create':
      case 'drop':
        await protocol.send('__response__', EmptyContent().pack(), id: messageId);
        return;
      case 'inspect':
        await protocol.send(
          '__response__',
          JsonContent(
            json: {
              'name': 'graph',
              'namespace': ['demo'],
              'path': '/memory/demo/graph',
              'datasets': [
                {
                  'name': 'Entity',
                  'rows': 2,
                  'columns': ['entity_id', 'name'],
                },
              ],
            },
          ).pack(),
          id: messageId,
        );
        return;
      case 'query':
        await protocol.send(
          '__response__',
          JsonContent(
            json: _rowsChunk([
              {
                'entity_id': 'acme',
                'name': 'ACME',
                'confidence': 0.9,
                'count': 2,
                'tags': ['customer', 'renewal'],
                'info': {'owner': 'sales'},
              },
            ]),
          ).pack(),
          id: messageId,
        );
        return;
      case 'upsert_table':
      case 'upsert_nodes':
      case 'upsert_relationships':
        await protocol.send('__response__', JsonContent(json: {'rows_written': 1}).pack(), id: messageId);
        return;
      case 'ingest_text':
      case 'ingest_image':
      case 'ingest_file':
      case 'ingest_from_table':
      case 'ingest_from_storage':
        await protocol.send(
          '__response__',
          JsonContent(
            json: {
              'name': 'graph',
              'stats': {'entities': 2, 'relationships': 1, 'sources': 1},
              'entity_ids': ['acme', 'renewal'],
            },
          ).pack(),
          id: messageId,
        );
        return;
      case 'recall':
        await protocol.send(
          '__response__',
          JsonContent(
            json: {
              'name': 'graph',
              'query': 'renewal',
              'items': [
                {
                  'entity_id': 'acme',
                  'name': 'ACME',
                  'entity_type': 'company',
                  'context': 'Enterprise customer',
                  'confidence': 0.95,
                  'created_at': '2025-01-01T00:00:00Z',
                  'valid_at': null,
                  'score': 0.88,
                  'relationships': [
                    {
                      'source_entity_id': 'acme',
                      'target_entity_id': 'renewal-q3',
                      'relationship_type': 'HAS_MILESTONE',
                      'description': 'Renewal target quarter',
                    },
                  ],
                },
              ],
            },
          ).pack(),
          id: messageId,
        );
        return;
      case 'delete_entities':
        await protocol.send(
          '__response__',
          JsonContent(json: {'name': 'graph', 'deleted_entities': 1, 'deleted_relationships': 2}).pack(),
          id: messageId,
        );
        return;
      case 'delete_relationships':
        await protocol.send('__response__', JsonContent(json: {'name': 'graph', 'deleted_relationships': 1}).pack(), id: messageId);
        return;
      case 'optimize':
        await protocol.send(
          '__response__',
          JsonContent(
            json: {
              'name': 'graph',
              'datasets': [
                {
                  'dataset': 'Entity',
                  'fragments_added': 1,
                  'fragments_removed': 1,
                  'files_added': 1,
                  'files_removed': 1,
                  'old_versions_removed': 1,
                  'bytes_removed': 512,
                },
              ],
            },
          ).pack(),
          id: messageId,
        );
        return;
      default:
        throw StateError('unsupported memory operation: $tool');
    }
  }

  Content _decodeInput({required Message message, required Map<String, dynamic> request}) {
    final arguments = Map<String, dynamic>.from(request['arguments'] as Map);
    return unpackContent(packMessage(arguments, message.payload.isEmpty ? null : message.payload));
  }
}

Future<_MemoryHarness> _startMemoryHarness() async {
  final pair = _ProtocolPair();
  final server = _FakeMemoryServer();
  pair.serverProtocol.start(onMessage: server.handleMessage);

  final room = RoomClient(protocol: pair.clientProtocol);
  final startFuture = room.start();
  await _sendRoomReady(pair.serverProtocol);
  await startFuture;

  return _MemoryHarness(pair: pair, room: room, server: server);
}

void main() {
  test('memory client uses toolkit-backed methods and parses typed responses', () async {
    final harness = await _startMemoryHarness();

    final memories = await harness.room.memory.list(namespace: ['demo']);
    await harness.room.memory.create(name: 'graph', namespace: ['demo'], overwrite: true, ignoreExists: true);
    await harness.room.memory.drop(name: 'graph', namespace: ['demo'], ignoreMissing: true);
    final details = await harness.room.memory.inspect(name: 'graph', namespace: ['demo']);
    final rows = await harness.room.memory.query(name: 'graph', namespace: ['demo'], statement: 'MATCH (e) RETURN e.name as name');
    await harness.room.memory.upsertTable(
      name: 'graph',
      namespace: ['demo'],
      table: 'facts',
      records: [
        {'entity_id': 'acme', 'note': 'Renewal in Q3', 'seen_at': DateTime.utc(2025, 1, 1)},
      ],
    );
    await harness.room.memory.upsertNodes(
      name: 'graph',
      namespace: ['demo'],
      records: [MemoryEntityRecord(entityId: 'acme', name: 'ACME', entityType: 'company', confidence: 0.8)],
    );
    await harness.room.memory.upsertRelationships(
      name: 'graph',
      namespace: ['demo'],
      records: [MemoryRelationshipRecord(sourceEntityId: 'acme', targetEntityId: 'renewal-q3', relationshipType: 'HAS_MILESTONE')],
    );
    final ingestResult = await harness.room.memory.ingestText(
      name: 'graph',
      namespace: ['demo'],
      text: 'ACME has a Q3 renewal.',
      strategy: MemoryIngestStrategy.llm,
      llmModel: 'gpt-4o-mini',
      llmTemperature: 0.2,
    );
    final recall = await harness.room.memory.recall(
      name: 'graph',
      namespace: ['demo'],
      query: 'renewal',
      limit: 10,
      includeRelationships: true,
    );
    final deleteEntities = await harness.room.memory.deleteEntities(name: 'graph', namespace: ['demo'], entityIds: ['acme']);
    final deleteRelationships = await harness.room.memory.deleteRelationships(
      name: 'graph',
      namespace: ['demo'],
      relationships: [MemoryRelationshipSelector(sourceEntityId: 'acme', targetEntityId: 'renewal-q3', relationshipType: 'HAS_MILESTONE')],
    );
    final optimize = await harness.room.memory.optimize(name: 'graph', namespace: ['demo']);

    expect(memories, ['alpha', 'beta']);
    expect(details.name, 'graph');
    expect(details.namespace, ['demo']);
    expect(details.path, '/memory/demo/graph');
    expect(details.datasets.single.name, 'Entity');
    expect(details.datasets.single.rows, 2);
    expect(details.datasets.single.columns, ['entity_id', 'name']);
    expect(rows, [
      {
        'entity_id': 'acme',
        'name': 'ACME',
        'confidence': 0.9,
        'count': 2,
        'tags': ['customer', 'renewal'],
        'info': {'owner': 'sales'},
      },
    ]);
    expect(ingestResult.name, 'graph');
    expect(ingestResult.stats.entities, 2);
    expect(ingestResult.stats.relationships, 1);
    expect(ingestResult.stats.sources, 1);
    expect(ingestResult.entityIds, ['acme', 'renewal']);
    expect(recall.name, 'graph');
    expect(recall.query, 'renewal');
    expect(recall.items, hasLength(1));
    expect(recall.items.single.entityId, 'acme');
    expect(recall.items.single.relationships, hasLength(1));
    expect(recall.items.single.relationships.single.relationshipType, 'HAS_MILESTONE');
    expect(deleteEntities.deletedEntities, 1);
    expect(deleteEntities.deletedRelationships, 2);
    expect(deleteRelationships.deletedRelationships, 1);
    expect(optimize.name, 'graph');
    expect(optimize.datasets, hasLength(1));
    expect(optimize.datasets.single.dataset, 'Entity');
    expect(optimize.datasets.single.bytesRemoved, 512);

    expect(harness.server.requests.map((entry) => entry.tool), [
      'list',
      'create',
      'drop',
      'inspect',
      'query',
      'upsert_table',
      'upsert_nodes',
      'upsert_relationships',
      'ingest_text',
      'recall',
      'delete_entities',
      'delete_relationships',
      'optimize',
    ]);
    expect(harness.server.requests[0].input, {
      'namespace': ['demo'],
    });
    expect(harness.server.requests[1].input, {
      'name': 'graph',
      'namespace': ['demo'],
      'overwrite': true,
      'ignore_exists': true,
    });
    expect(harness.server.requests[2].input, {
      'name': 'graph',
      'namespace': ['demo'],
      'ignore_missing': true,
    });
    expect(harness.server.requests[3].input, {
      'name': 'graph',
      'namespace': ['demo'],
    });
    expect(harness.server.requests[4].input, {
      'name': 'graph',
      'namespace': ['demo'],
      'statement': 'MATCH (e) RETURN e.name as name',
    });
    expect(jsonDecode(harness.server.requests[5].input['records_json'] as String), [
      {'entity_id': 'acme', 'note': 'Renewal in Q3', 'seen_at': '2025-01-01T00:00:00.000Z'},
    ]);
    expect(jsonDecode(harness.server.requests[6].input['records_json'] as String), [
      {
        'entity_id': 'acme',
        'name': 'ACME',
        'entity_type': 'company',
        'context': null,
        'confidence': 0.8,
        'created_at': null,
        'valid_at': null,
        'metadata': null,
      },
    ]);
    expect(jsonDecode(harness.server.requests[7].input['records_json'] as String), [
      {
        'source_entity_id': 'acme',
        'target_entity_id': 'renewal-q3',
        'relationship_type': 'HAS_MILESTONE',
        'description': null,
        'confidence': null,
        'created_at': null,
        'valid_at': null,
        'expired_at': null,
        'invalid_at': null,
        'source_entity_name': null,
        'target_entity_name': null,
        'metadata': null,
      },
    ]);
    expect(harness.server.requests[8].input, {
      'name': 'graph',
      'namespace': ['demo'],
      'text': 'ACME has a Q3 renewal.',
      'strategy': 'llm',
      'llm_model': 'gpt-4o-mini',
      'llm_temperature': 0.2,
    });
    expect(harness.server.requests[9].input, {
      'name': 'graph',
      'namespace': ['demo'],
      'query': 'renewal',
      'limit': 10,
      'include_relationships': true,
    });
    expect(harness.server.requests[10].input, {
      'name': 'graph',
      'namespace': ['demo'],
      'entity_ids': ['acme'],
    });
    expect(harness.server.requests[11].input, {
      'name': 'graph',
      'namespace': ['demo'],
      'relationships': [
        {'source_entity_id': 'acme', 'target_entity_id': 'renewal-q3', 'relationship_type': 'HAS_MILESTONE'},
      ],
    });
    expect(harness.server.requests[12].input, {
      'name': 'graph',
      'namespace': ['demo'],
      'compact': true,
      'cleanup': true,
    });

    await harness.dispose();
  });

  test('memory client encodes image and storage-based ingest inputs', () async {
    final harness = await _startMemoryHarness();

    await harness.room.memory.ingestImage(
      name: 'graph',
      namespace: ['demo'],
      caption: 'whiteboard',
      data: Uint8List.fromList([1, 2, 3]),
      mimeType: 'image/png',
      source: 'whiteboard.png',
      annotations: {'scene': 'planning'},
    );
    await harness.room.memory.ingestFile(name: 'graph', namespace: ['demo'], text: 'inline text', mimeType: 'text/plain');
    await harness.room.memory.ingestFromTable(
      name: 'graph',
      namespace: ['demo'],
      table: 'facts',
      textColumns: ['summary'],
      tableNamespace: ['tables'],
      limit: 5,
    );
    await harness.room.memory.ingestFromStorage(name: 'graph', namespace: ['demo'], paths: ['notes.txt']);

    expect(harness.server.requests[0].input, {
      'name': 'graph',
      'namespace': ['demo'],
      'caption': 'whiteboard',
      'data_base64': base64Encode(Uint8List.fromList([1, 2, 3])),
      'mime_type': 'image/png',
      'source': 'whiteboard.png',
      'annotations_json': jsonEncode({'scene': 'planning'}),
      'strategy': 'heuristic',
      'llm_model': null,
      'llm_temperature': null,
    });
    expect(harness.server.requests[1].input, {
      'name': 'graph',
      'namespace': ['demo'],
      'path': null,
      'text': 'inline text',
      'mime_type': 'text/plain',
      'strategy': 'heuristic',
      'llm_model': null,
      'llm_temperature': null,
    });
    expect(harness.server.requests[2].input, {
      'name': 'graph',
      'namespace': ['demo'],
      'table': 'facts',
      'table_namespace': ['tables'],
      'text_columns': ['summary'],
      'limit': 5,
      'strategy': 'heuristic',
      'llm_model': null,
      'llm_temperature': null,
    });
    expect(harness.server.requests[3].input, {
      'name': 'graph',
      'namespace': ['demo'],
      'paths': ['notes.txt'],
      'strategy': 'heuristic',
      'llm_model': null,
      'llm_temperature': null,
    });

    await harness.dispose();
  });
}

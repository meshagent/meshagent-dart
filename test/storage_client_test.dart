import 'dart:async';
import 'dart:math' as math;
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

class _StorageHarness {
  _StorageHarness({required this.pair, required this.room, required this.server});

  final _ProtocolPair pair;
  final RoomClient room;
  final _InMemoryStorageServer server;

  Future<void> dispose() async {
    room.dispose();
    await pair.dispose();
  }
}

class _InMemoryStorageServer {
  final Map<String, Uint8List> _files = {};
  final Map<String, BytesBuilder> _streamingUploads = {};
  final Map<String, String> _uploadPaths = {};
  final Map<String, int?> _uploadExpectedSizes = {};
  final Map<String, String> _downloadPaths = {};
  final Map<String, int> _downloadOffsets = {};
  final Map<String, int> _downloadChunkSizes = {};

  String? invalidOperation;
  Content? invalidResponse;

  Future<void> handleMessage(Protocol protocol, int messageId, String type, Uint8List data) async {
    if (type == 'room.tool_call_request_chunk') {
      await _handleRequestChunk(protocol, messageId, data);
      return;
    }

    if (type != 'room.invoke_tool') {
      return;
    }

    final message = unpackMessage(data);
    final request = message.header;
    final toolkit = request['toolkit'];
    if (toolkit != 'storage') {
      return;
    }

    final operation = request['tool'] as String;
    if (invalidOperation == operation) {
      await protocol.send('__response__', (invalidResponse ?? EmptyContent()).pack(), id: messageId);
      return;
    }

    final input = _decodeInput(message: message, request: request);
    switch (operation) {
      case 'exists':
        final path = _jsonPath(input);
        await protocol.send('__response__', JsonContent(json: {'exists': _files.containsKey(path)}).pack(), id: messageId);
        return;
      case 'stat':
        final path = _jsonPath(input);
        if (_files.containsKey(path)) {
          await protocol.send(
            '__response__',
            JsonContent(
              json: {
                'exists': true,
                'name': path.split('/').last,
                'is_folder': false,
                'size': _files[path]!.length,
                'created_at': null,
                'updated_at': null,
              },
            ).pack(),
            id: messageId,
          );
        } else {
          await protocol.send('__response__', JsonContent(json: {'exists': false}).pack(), id: messageId);
        }
        return;
      case 'upload':
        final toolCallId = request['tool_call_id'] as String;
        _streamingUploads[toolCallId] = BytesBuilder(copy: false);
        await protocol.send('__response__', ControlContent(method: 'open').pack(), id: messageId);
        return;
      case 'download':
        final toolCallId = request['tool_call_id'] as String;
        _streamingUploads.remove(toolCallId);
        _uploadPaths.remove(toolCallId);
        _uploadExpectedSizes.remove(toolCallId);
        _downloadPaths[toolCallId] = '';
        _downloadOffsets[toolCallId] = 0;
        _downloadChunkSizes[toolCallId] = 64 * 1024;
        await protocol.send('__response__', ControlContent(method: 'open').pack(), id: messageId);
        return;
      case 'download_url':
        final path = _jsonPath(input);
        await protocol.send('__response__', JsonContent(json: {'url': 'https://example.test/download/$path'}).pack(), id: messageId);
        return;
      case 'list':
        final path = _jsonPath(input);
        await protocol.send('__response__', JsonContent(json: {'files': _listEntries(path)}).pack(), id: messageId);
        return;
      case 'delete':
        final path = _jsonPath(input);
        _files.remove(path);
        await protocol.send('__response__', EmptyContent().pack(), id: messageId);
        await protocol.send('storage.file.deleted', packMessage({'path': path, 'participant_id': 'participant-1'}));
        return;
      default:
        throw StateError('unsupported storage operation: $operation');
    }
  }

  Content _decodeInput({required Message message, required Map<String, dynamic> request}) {
    final arguments = Map<String, dynamic>.from(request['arguments'] as Map);
    return unpackContent(packMessage(arguments, message.payload.isEmpty ? null : message.payload));
  }

  Future<void> _handleRequestChunk(Protocol protocol, int messageId, Uint8List data) async {
    final message = unpackMessage(data);
    final request = message.header;
    final toolCallId = request['tool_call_id'] as String;
    final chunkHeader = Map<String, dynamic>.from(request['chunk'] as Map);
    final chunk = unpackContent(packMessage(chunkHeader, message.payload.isEmpty ? null : message.payload));

    if (_streamingUploads.containsKey(toolCallId)) {
      await protocol.send('__response__', EmptyContent().pack(), id: messageId);

      if (chunk is ControlContent && chunk.method == 'close') {
        final path = _uploadPaths.remove(toolCallId);
        if (path == null) {
          throw StateError('storage.upload missing start chunk for $toolCallId');
        }
        final bytes = _streamingUploads.remove(toolCallId)?.takeBytes() ?? Uint8List(0);
        final expectedSize = _uploadExpectedSizes.remove(toolCallId);
        if (expectedSize != null && expectedSize != bytes.length) {
          throw StateError('storage.upload size mismatch for $toolCallId');
        }
        _files[path] = Uint8List.fromList(bytes);
        await _sendToolCallChunk(
          protocol,
          toolCallId: toolCallId,
          chunk: ControlContent(method: 'close'),
        );
        await protocol.send('storage.file.updated', packMessage({'path': path, 'participant_id': 'participant-1'}));
      } else if (chunk is BinaryContent && chunk.headers['kind'] == 'start') {
        final path = chunk.headers['path'];
        if (path is! String) {
          throw StateError('storage.upload missing path header');
        }
        _uploadPaths[toolCallId] = path;
        final expectedSize = chunk.headers['size'];
        if (expectedSize is int) {
          _uploadExpectedSizes[toolCallId] = expectedSize;
        } else {
          _uploadExpectedSizes[toolCallId] = null;
        }
        await _sendToolCallChunk(
          protocol,
          toolCallId: toolCallId,
          chunk: BinaryContent(data: Uint8List(0), headers: {'kind': 'pull'}),
        );
      } else if (chunk is BinaryContent && chunk.headers['kind'] == 'data') {
        _streamingUploads[toolCallId]!.add(chunk.data);
        await _sendToolCallChunk(
          protocol,
          toolCallId: toolCallId,
          chunk: BinaryContent(data: Uint8List(0), headers: {'kind': 'pull'}),
        );
      } else {
        throw StateError('storage.upload expected BinaryContent chunks');
      }
      return;
    }

    if (_downloadPaths.containsKey(toolCallId)) {
      await protocol.send('__response__', EmptyContent().pack(), id: messageId);

      if (chunk is BinaryContent && chunk.headers['kind'] == 'start') {
        final path = chunk.headers['path'] as String;
        final bytes = _files[path];
        if (bytes == null) {
          throw StateError('unknown storage path: $path');
        }
        _downloadPaths[toolCallId] = path;
        _downloadOffsets[toolCallId] = 0;
        _downloadChunkSizes[toolCallId] = chunk.headers['chunk_size'] as int? ?? 64 * 1024;
        await _sendToolCallChunk(
          protocol,
          toolCallId: toolCallId,
          chunk: BinaryContent(
            data: Uint8List(0),
            headers: {'kind': 'start', 'name': path.split('/').last, 'mime_type': 'application/octet-stream', 'size': bytes.length},
          ),
        );
      } else if (chunk is BinaryContent && chunk.headers['kind'] == 'pull') {
        final path = _downloadPaths[toolCallId]!;
        final bytes = _files[path];
        if (bytes == null) {
          throw StateError('unknown storage path: $path');
        }
        final offset = _downloadOffsets[toolCallId]!;
        final end = math.min(offset + _downloadChunkSizes[toolCallId]!, bytes.length);
        if (offset >= bytes.length) {
          await _sendToolCallChunk(
            protocol,
            toolCallId: toolCallId,
            chunk: ControlContent(method: 'close'),
          );
        } else {
          _downloadOffsets[toolCallId] = end;
          final payload = Uint8List.sublistView(bytes, offset, end);
          await _sendToolCallChunk(
            protocol,
            toolCallId: toolCallId,
            chunk: BinaryContent(data: payload, headers: {'kind': 'data'}),
          );
          if (end >= bytes.length) {
            await _sendToolCallChunk(
              protocol,
              toolCallId: toolCallId,
              chunk: ControlContent(method: 'close'),
            );
          }
        }
      }
      return;
    }

    throw StateError('unexpected tool_call_id: $toolCallId');
  }

  Map<String, dynamic> _jsonPayload(Content input) {
    if (input is! JsonContent) {
      throw StateError('expected JsonContent input');
    }
    return input.json;
  }

  String _jsonPath(Content input) {
    return _jsonPayload(input)['path'] as String;
  }

  List<Map<String, dynamic>> _listEntries(String path) {
    final prefix = path.isEmpty ? '' : '$path/';
    final entries = <String, bool>{};
    for (final filePath in _files.keys) {
      if (!filePath.startsWith(prefix)) {
        continue;
      }

      final remainder = filePath.substring(prefix.length);
      if (remainder.isEmpty) {
        continue;
      }

      final slashIndex = remainder.indexOf('/');
      if (slashIndex == -1) {
        entries[remainder] = false;
      } else {
        entries[remainder.substring(0, slashIndex)] = true;
      }
    }

    final names = entries.keys.toList()..sort();
    return names.map((name) {
      final fullPath = prefix.isEmpty ? name : '$prefix$name';
      final bytes = _files[fullPath];
      return {'name': name, 'is_folder': entries[name], 'size': bytes?.length, 'created_at': null, 'updated_at': null};
    }).toList();
  }

  Future<void> _sendToolCallChunk(Protocol protocol, {required String toolCallId, required Content chunk}) async {
    final packed = unpackMessage(chunk.pack());
    await protocol.send(
      'room.tool_call_response_chunk',
      packMessage({'tool_call_id': toolCallId, 'chunk': packed.header}, packed.payload.isEmpty ? null : packed.payload),
    );
  }
}

Future<_StorageHarness> _startStorageHarness() async {
  final pair = _ProtocolPair();
  final server = _InMemoryStorageServer();
  pair.serverProtocol.start(onMessage: server.handleMessage);

  final room = RoomClient(protocol: pair.clientProtocol);
  final startFuture = room.start();
  await _sendRoomReady(pair.serverProtocol);
  await startFuture;

  return _StorageHarness(pair: pair, room: room, server: server);
}

void main() {
  test('storage exists returns false when file is absent', () async {
    final harness = await _startStorageHarness();

    final exists = await harness.room.storage.exists('missing.txt');
    expect(exists, isFalse);

    await harness.dispose();
  });

  test('storage uploadStream and download uses room.invoke', () async {
    final harness = await _startStorageHarness();

    final bytes = Uint8List.fromList('hello storage'.codeUnits);
    await harness.room.storage.uploadStream('docs/example.txt', Stream.value(bytes), size: bytes.length);

    expect(await harness.room.storage.exists('docs/example.txt'), isTrue);

    final downloaded = await harness.room.storage.download('docs/example.txt');
    expect(downloaded.data, orderedEquals(bytes));

    await harness.dispose();
  });

  test('storage writeStream and downloadStream use chunked binary content', () async {
    final harness = await _startStorageHarness();

    await harness.room.storage.uploadStream(
      'docs/streamed.txt',
      Stream.fromIterable([
        Uint8List.fromList(List<int>.filled(64 * 1024, 1)),
        Uint8List.fromList([2, 3, 4]),
      ]),
      size: (64 * 1024) + 3,
    );

    final chunks = await (await harness.room.storage.downloadStream('docs/streamed.txt')).toList();
    expect(chunks.length, greaterThanOrEqualTo(3));
    expect(chunks.first.headers, {
      'kind': 'start',
      'name': 'streamed.txt',
      'mime_type': 'application/octet-stream',
      'size': (64 * 1024) + 3,
    });
    expect(chunks.skip(1).expand((chunk) => chunk.data).toList(), [...List<int>.filled(64 * 1024, 1), 2, 3, 4]);

    await harness.dispose();
  });

  test('storage downloadUrl returns URL string', () async {
    final harness = await _startStorageHarness();

    await harness.room.storage.uploadStream('downloads/report.bin', Stream.value(Uint8List.fromList([1, 2, 3])), size: 3);

    final url = await harness.room.storage.downloadUrl('downloads/report.bin');
    expect(url, 'https://example.test/download/downloads/report.bin');

    await harness.dispose();
  });

  test('storage list and delete reflect stored files', () async {
    final harness = await _startStorageHarness();

    await harness.room.storage.uploadStream('folder/a.txt', Stream.value(Uint8List.fromList([1])), size: 1);

    await harness.room.storage.uploadStream('folder/b.txt', Stream.value(Uint8List.fromList([2])), size: 1);

    final listing = await harness.room.storage.list('folder');
    expect(listing.map((entry) => entry.name).toList(), ['a.txt', 'b.txt']);

    await harness.room.storage.delete('folder/a.txt');
    expect(await harness.room.storage.exists('folder/a.txt'), isFalse);
    expect(await harness.room.storage.exists('folder/b.txt'), isTrue);

    await harness.dispose();
  });

  test('storage emits file updated and deleted events', () async {
    final harness = await _startStorageHarness();
    final updated = Completer<FileUpdatedEvent>();
    final deleted = Completer<FileDeletedEvent>();

    final subscription = harness.room.listen((event) {
      if (event is FileUpdatedEvent && !updated.isCompleted) {
        updated.complete(event);
      }
      if (event is FileDeletedEvent && !deleted.isCompleted) {
        deleted.complete(event);
      }
    });

    final bytes = Uint8List.fromList('event'.codeUnits);
    await harness.room.storage.uploadStream('events/file.txt', Stream.value(bytes), size: bytes.length);

    final updatedEvent = await updated.future.timeout(const Duration(seconds: 1));
    expect(updatedEvent.path, 'events/file.txt');
    expect(updatedEvent.participantId, 'participant-1');

    await harness.room.storage.delete('events/file.txt');
    final deletedEvent = await deleted.future.timeout(const Duration(seconds: 1));
    expect(deletedEvent.path, 'events/file.txt');
    expect(deletedEvent.participantId, 'participant-1');

    await subscription.cancel();
    await harness.dispose();
  });

  test('storage throws on unexpected response type', () async {
    final harness = await _startStorageHarness();
    harness.server.invalidOperation = 'exists';
    harness.server.invalidResponse = EmptyContent();

    await expectLater(
      harness.room.storage.exists('bad.txt'),
      throwsA(
        isA<RoomServerException>().having((error) => error.message, 'message', contains('unexpected return type from storage.exists')),
      ),
    );

    await harness.dispose();
  });
}

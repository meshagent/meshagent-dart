import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:meshagent/meshagent.dart';
import 'package:meshagent/runtime.dart';
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
    unawaited(_clientToServer.close());
    if (!_serverToClient.isClosed) {
      unawaited(_serverToClient.close());
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

Future<void> _sendToolCallResponseChunk({required Protocol protocol, required String toolCallId, required Content chunk}) async {
  final packed = unpackMessage(chunk.pack());
  await protocol.send(
    'room.tool_call_response_chunk',
    packMessage({'tool_call_id': toolCallId, 'chunk': packed.header}, packed.payload.isEmpty ? null : packed.payload),
  );
}

class _FakeDocumentRuntime extends DocumentRuntime {
  _FakeDocumentRuntime() : super.base();

  @override
  void applyBackendChanges({required String documentId, required String base64}) {}

  @override
  void registerDocument(RuntimeDocument document) {}

  @override
  String getState({required String documentId, String? vectorBase64}) {
    return '';
  }

  @override
  String getStateVector({required String documentId}) {
    return '';
  }

  @override
  void unregisterDocument(RuntimeDocument document) {}

  @override
  void sendChanges(Map<String, dynamic> message) {}
}

void main() {
  test('sync client streams open, sync, and close through sync.open', () async {
    final pair = _ProtocolPair();
    final schema = MeshSchema(
      rootTagName: 'thread',
      elements: [ElementType(tagName: 'thread', description: '', properties: [])],
    );

    String? toolCallId;
    final requestChunks = <Content>[];

    pair.serverProtocol.start(
      onMessage: (protocol, messageId, type, data) async {
        if (type == 'room.invoke_tool') {
          final request = unpackMessage(data).header;
          expect(request['toolkit'], 'sync');
          expect(request['tool'], 'open');
          toolCallId = request['tool_call_id'] as String;
          final arguments = Map<String, dynamic>.from(request['arguments'] as Map);
          expect(arguments['type'], 'control');
          expect(arguments['method'], 'open');
          await protocol.send('__response__', ControlContent(method: 'open').pack(), id: messageId);
          return;
        }

        if (type != 'room.tool_call_request_chunk') {
          return;
        }

        final message = unpackMessage(data);
        final header = message.header;
        final chunkHeader = Map<String, dynamic>.from(header['chunk'] as Map);
        final packedChunk = packMessage(chunkHeader, message.payload.isEmpty ? null : message.payload);
        final chunk = unpackContent(packedChunk);
        requestChunks.add(chunk);
        await protocol.send('__response__', EmptyContent().pack(), id: messageId);

        if (toolCallId == null) {
          return;
        }

        if (chunk is BinaryContent && chunk.headers['kind'] == 'start') {
          await _sendToolCallResponseChunk(
            protocol: protocol,
            toolCallId: toolCallId!,
            chunk: BinaryContent(data: Uint8List(0), headers: {'kind': 'state', 'path': 'thread.thread', 'schema': schema.toJson()}),
          );
          return;
        }

        if (chunk is ControlContent && chunk.method == 'close') {
          await _sendToolCallResponseChunk(
            protocol: protocol,
            toolCallId: toolCallId!,
            chunk: ControlContent(method: 'close'),
          );
        }
      },
    );

    final room = RoomClient(protocolFactory: pair.clientProtocolFactory);
    final startFuture = room.start();
    await _sendRoomReady(pair.serverProtocol);
    await startFuture;

    try {
      DocumentRuntime.instance = _FakeDocumentRuntime();

      final doc = await room.sync.open('/thread.thread').timeout(const Duration(seconds: 1));
      expect(await doc.synchronized.timeout(const Duration(seconds: 1)), isTrue);

      await room.sync.sync('/thread.thread', Uint8List.fromList(utf8.encode('YQ==')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await room.sync.close('/thread.thread');

      expect(requestChunks.length, greaterThanOrEqualTo(3));

      expect(requestChunks.first, isA<BinaryContent>());
      final startChunk = requestChunks.first as BinaryContent;
      expect(startChunk.headers['kind'], 'start');
      expect(startChunk.headers['path'], 'thread.thread');
      expect(startChunk.headers['create'], isTrue);

      expect(requestChunks[1], isA<BinaryContent>());
      final syncChunk = requestChunks[1] as BinaryContent;
      expect(syncChunk.headers, {'kind': 'sync'});
      expect(syncChunk.data, Uint8List.fromList(utf8.encode('YQ==')));

      expect(requestChunks.last, isA<ControlContent>());
      final closeChunk = requestChunks.last as ControlContent;
      expect(closeChunk.method, 'close');
    } finally {
      room.dispose();
      await pair.dispose();
    }
  });

  test('sync client waits for close to finish before reopening the same document', () async {
    final pair = _ProtocolPair();
    final schema = MeshSchema(
      rootTagName: 'thread',
      elements: [ElementType(tagName: 'thread', description: '', properties: [])],
    );

    var openRequestCount = 0;
    var reopenedBeforeFirstCloseCompleted = false;
    var firstCloseCompleted = false;
    final closeRequested = Completer<void>();
    final allowClose = Completer<void>();

    pair.serverProtocol.start(
      onMessage: (protocol, messageId, type, data) async {
        if (type == 'room.invoke_tool') {
          final request = unpackMessage(data).header;
          expect(request['toolkit'], 'sync');
          expect(request['tool'], 'open');
          openRequestCount++;
          if (openRequestCount > 1 && !firstCloseCompleted) {
            reopenedBeforeFirstCloseCompleted = true;
          }
          await protocol.send('__response__', ControlContent(method: 'open').pack(), id: messageId);
          return;
        }

        if (type != 'room.tool_call_request_chunk') {
          return;
        }

        final message = unpackMessage(data);
        final header = message.header;
        final toolCallId = header['tool_call_id'] as String;
        final chunkHeader = Map<String, dynamic>.from(header['chunk'] as Map);
        final packedChunk = packMessage(chunkHeader, message.payload.isEmpty ? null : message.payload);
        final chunk = unpackContent(packedChunk);
        await protocol.send('__response__', EmptyContent().pack(), id: messageId);

        if (chunk is BinaryContent && chunk.headers['kind'] == 'start') {
          await _sendToolCallResponseChunk(
            protocol: protocol,
            toolCallId: toolCallId,
            chunk: BinaryContent(data: Uint8List(0), headers: {'kind': 'state', 'path': 'thread.thread', 'schema': schema.toJson()}),
          );
          return;
        }

        if (chunk is ControlContent && chunk.method == 'close') {
          if (!closeRequested.isCompleted) {
            closeRequested.complete();
          }
          unawaited(() async {
            await allowClose.future;
            firstCloseCompleted = true;
            await _sendToolCallResponseChunk(
              protocol: protocol,
              toolCallId: toolCallId,
              chunk: ControlContent(method: 'close'),
            );
          }());
        }
      },
    );

    final room = RoomClient(protocolFactory: pair.clientProtocolFactory);
    final startFuture = room.start();
    await _sendRoomReady(pair.serverProtocol);
    await startFuture;

    try {
      DocumentRuntime.instance = _FakeDocumentRuntime();

      final firstDoc = await room.sync.open('/thread.thread').timeout(const Duration(seconds: 1));
      expect(await firstDoc.synchronized.timeout(const Duration(seconds: 1)), isTrue);

      final closeFuture = room.sync.close('/thread.thread');
      await closeRequested.future.timeout(const Duration(seconds: 1));

      final reopenFuture = room.sync.open('/thread.thread');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(openRequestCount, 1);
      expect(reopenedBeforeFirstCloseCompleted, isFalse);

      allowClose.complete();

      final reopenedDoc = await reopenFuture.timeout(const Duration(seconds: 1));
      expect(await reopenedDoc.synchronized.timeout(const Duration(seconds: 1)), isTrue);
      await closeFuture.timeout(const Duration(seconds: 1));

      expect(openRequestCount, 2);
      expect(reopenedBeforeFirstCloseCompleted, isFalse);
    } finally {
      room.dispose();
      await pair.dispose();
    }
  });
}

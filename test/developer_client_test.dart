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

class _DeveloperHarness {
  _DeveloperHarness({required this.pair, required this.room, required this.server});

  final _ProtocolPair pair;
  final RoomClient room;
  final _FakeDeveloperServer server;

  Future<void> dispose() async {
    room.dispose();
    await pair.dispose();
  }
}

class _FakeDeveloperServer {
  String? _toolCallId;

  bool get hasOpenLogStream => _toolCallId != null;

  Future<void> handleMessage(Protocol protocol, int messageId, String type, Uint8List data) async {
    if (type == 'room.invoke_tool') {
      final message = unpackMessage(data);
      final request = message.header;
      if (request['toolkit'] != 'developer' || request['tool'] != 'logs') {
        return;
      }

      _toolCallId = request['tool_call_id'] as String;
      await protocol.send('__response__', ControlContent(method: 'open').pack(), id: messageId);
      return;
    }

    if (type == 'room.tool_call_request_chunk') {
      await protocol.send('__response__', EmptyContent().pack(), id: messageId);
    }
  }

  Future<void> sendLog(Protocol protocol, {required String type, required Map<String, dynamic> data}) async {
    final toolCallId = _toolCallId;
    if (toolCallId == null) {
      throw StateError('developer.logs tool call has not been opened');
    }

    await _sendToolCallChunk(
      protocol,
      toolCallId: toolCallId,
      chunk: BinaryContent(data: Uint8List.fromList(utf8.encode(jsonEncode(data))), headers: {'type': type}),
    );
  }

  Future<void> close(Protocol protocol) async {
    final toolCallId = _toolCallId;
    if (toolCallId == null) {
      return;
    }
    await _sendToolCallChunk(
      protocol,
      toolCallId: toolCallId,
      chunk: ControlContent(method: 'close'),
    );
  }

  Future<void> _sendToolCallChunk(Protocol protocol, {required String toolCallId, required Content chunk}) async {
    final packed = unpackMessage(chunk.pack());
    await protocol.send(
      'room.tool_call_response_chunk',
      packMessage({'tool_call_id': toolCallId, 'chunk': packed.header}, packed.payload.isEmpty ? null : packed.payload),
    );
  }
}

Future<_DeveloperHarness> _startDeveloperHarness() async {
  final pair = _ProtocolPair();
  final server = _FakeDeveloperServer();
  pair.serverProtocol.start(onMessage: server.handleMessage);

  final room = RoomClient(protocolFactory: pair.clientProtocolFactory);
  final startFuture = room.start();
  await _sendRoomReady(pair.serverProtocol);
  await startFuture;

  return _DeveloperHarness(pair: pair, room: room, server: server);
}

Future<void> _waitUntil(bool Function() condition, {Duration timeout = const Duration(seconds: 1)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition was not met before timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  test('developer logs stream does not mirror events onto room.events', () async {
    final harness = await _startDeveloperHarness();
    final roomLogEvents = <RoomLogEvent>[];
    final roomSub = harness.room.events.where((event) => event is RoomLogEvent).cast<RoomLogEvent>().listen(roomLogEvents.add);
    final streamEvents = <RoomLogEvent>[];
    final streamSub = harness.room.developer.logs().listen(streamEvents.add);

    await _waitUntil(() => harness.server.hasOpenLogStream);
    await harness.server.sendLog(harness.pair.serverProtocol, type: 'otel.log', data: {'message': 'hello'});
    await _waitUntil(() => streamEvents.length == 1);

    expect(streamEvents.single.type, 'otel.log');
    expect(streamEvents.single.data, {'message': 'hello'});

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(roomLogEvents, isEmpty);

    await harness.server.close(harness.pair.serverProtocol);
    await streamSub.cancel();
    await roomSub.cancel();
    await harness.dispose();
  });
}

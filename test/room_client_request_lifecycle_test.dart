import 'dart:async';
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

  Future<void> closeServerToClient() async {
    await _serverToClient.close();
  }

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
    "room_ready",
    packMessage({"room_name": "test-room", "room_url": "ws://example/rooms/test-room", "session_id": "session-1"}),
  );
}

void main() {
  test('sendRequest fails when room client is disposed before response', () async {
    final pair = _ProtocolPair();
    final requestReceived = Completer<void>();
    pair.serverProtocol.start(
      onMessage: (protocol, messageId, type, data) async {
        if (type == "test.hang" && !requestReceived.isCompleted) {
          requestReceived.complete();
        }
      },
    );

    final room = RoomClient(protocol: pair.clientProtocol);
    final startFuture = room.start();
    await _sendRoomReady(pair.serverProtocol);
    await startFuture;

    final requestFuture = room.sendRequest("test.hang", {"a": 1});
    await requestReceived.future;

    room.dispose();

    await expectLater(requestFuture, throwsA(isA<RoomServerException>()));
    await pair.dispose();
  });

  test('sendRequest fails when protocol closes before response', () async {
    final pair = _ProtocolPair();
    final requestReceived = Completer<void>();
    pair.serverProtocol.start(
      onMessage: (protocol, messageId, type, data) async {
        if (type == "test.hang" && !requestReceived.isCompleted) {
          requestReceived.complete();
        }
      },
    );

    final room = RoomClient(protocol: pair.clientProtocol);
    final startFuture = room.start();
    await _sendRoomReady(pair.serverProtocol);
    await startFuture;

    final requestFuture = room.sendRequest("test.hang", {"a": 1});
    await requestReceived.future;

    await pair.closeServerToClient();

    await expectLater(requestFuture, throwsA(isA<RoomServerException>()));
    await pair.dispose();
  });

  test('sendRequest succeeds when message id exceeds 16-bit range', () async {
    final pair = _ProtocolPair();
    pair.serverProtocol.start(
      onMessage: (protocol, messageId, type, data) async {
        if (type != "test.echo") {
          return;
        }
        await protocol.send("__response__", JsonContent(json: {"message_id": messageId}).pack(), id: messageId);
      },
    );

    final room = RoomClient(protocol: pair.clientProtocol);
    final startFuture = room.start();
    await _sendRoomReady(pair.serverProtocol);
    await startFuture;

    for (var i = 0; i < 65536; i++) {
      pair.clientProtocol.getNextMessageId();
    }

    final result = await room.sendRequest("test.echo", {"a": 1}).timeout(const Duration(seconds: 1));
    expect(result, isA<JsonContent>());
    expect((result as JsonContent).json["message_id"], 65536);

    await pair.dispose();
  });

  test('sendRequest propagates ErrorContent.code on RoomServerException', () async {
    final pair = _ProtocolPair();
    pair.serverProtocol.start(
      onMessage: (protocol, messageId, type, data) async {
        if (type != "test.error") {
          return;
        }
        await protocol.send("__response__", ErrorContent(text: "invalid request", code: 1002).pack(), id: messageId);
      },
    );

    final room = RoomClient(protocol: pair.clientProtocol);
    final startFuture = room.start();
    await _sendRoomReady(pair.serverProtocol);
    await startFuture;

    try {
      await room.sendRequest("test.error", {"a": 1});
      fail("expected RoomServerException");
    } on RoomServerException catch (ex) {
      expect(ex.message, contains("invalid request"));
      expect(ex.code, 1002);
    }

    await pair.dispose();
  });
}

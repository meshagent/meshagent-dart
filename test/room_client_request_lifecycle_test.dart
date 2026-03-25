import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meshagent/meshagent.dart';
import 'package:test/test.dart';

const _retryableCloseStatusCode = 1013;

class _CloseWithStatusProtocolChannel extends ProtocolChannel {
  _CloseWithStatusProtocolChannel({required this.closeCode, this.reason});

  final int closeCode;
  final String? reason;
  bool _started = false;

  @override
  void start(void Function(Uint8List data) onDataReceived, {void Function()? onDone, void Function(Object? error)? onError}) {
    if (_started) {
      throw Exception('Already started');
    }
    _started = true;
    scheduleMicrotask(() {
      onError?.call(ProtocolCloseException(closeCode: closeCode, reason: reason));
    });
  }

  @override
  void dispose() {
    _started = false;
  }

  @override
  Future<void> sendData(Uint8List data) async {}
}

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

Future<void> _sendWebSocketProtocolMessage(
  WebSocket websocket, {
  required int messageId,
  required String type,
  required Uint8List data,
}) async {
  final packets = (data.length / 1024).ceil();

  final header = ByteData(16);
  header.setUint32(0, messageId >> 32, Endian.big);
  header.setUint32(4, messageId & 0xffffffff, Endian.big);
  header.setInt32(8, 0, Endian.big);
  header.setInt32(12, packets, Endian.big);

  final packet = BytesBuilder();
  packet.add(Uint8List.view(header.buffer));
  packet.add(utf8.encode(type));
  websocket.add(packet.toBytes());

  for (var i = 0; i < packets; i++) {
    final packetHeader = ByteData(12);
    packetHeader.setUint32(0, messageId >> 32, Endian.big);
    packetHeader.setUint32(4, messageId & 0xffffffff, Endian.big);
    packetHeader.setInt32(8, i + 1, Endian.big);

    final chunk = BytesBuilder();
    chunk.add(Uint8List.view(packetHeader.buffer));
    chunk.add(Uint8List.sublistView(data, i * 1024, math.min((i + 1) * 1024, data.length).toInt()));
    websocket.add(chunk.toBytes());
  }
}

void main() {
  test('start surfaces retryable websocket close status', () async {
    final room = RoomClient(
      protocol: Protocol(
        // dart:io server-side WebSocket.close() rejects 1013 as reserved,
        // so simulate the websocket close surfaced by the protocol layer.
        channel: _CloseWithStatusProtocolChannel(closeCode: _retryableCloseStatusCode, reason: 'try_again_later'),
      ),
    );

    await expectLater(
      room.start(),
      throwsA(
        isA<RoomServerException>()
            .having((error) => error.statusCode, 'statusCode', 1013)
            .having((error) => error.retryable, 'retryable', true)
            .having((error) => error.message, 'message', 'try_again_later'),
      ),
    );
  });

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

  test('websocket room_ready message can be delivered over a raw socket', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

    final serverTask = () async {
      final request = await server.first;
      final websocket = await WebSocketTransformer.upgrade(request);
      await _sendWebSocketProtocolMessage(
        websocket,
        messageId: 0,
        type: 'room_ready',
        data: packMessage({'room_name': 'test-room', 'room_url': 'ws://example/rooms/test-room', 'session_id': 'session-1'}),
      );
    }();

    final room = RoomClient(
      protocol: Protocol(
        channel: WebSocketProtocolChannel(url: Uri.parse('ws://127.0.0.1:${server.port}/rooms/test-room'), jwt: 'token'),
      ),
    );

    await room.start();
    expect(room.ready, completes);

    room.dispose();
    await serverTask;
    await server.close(force: true);
  });
}

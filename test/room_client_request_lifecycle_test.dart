import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meshagent/meshagent.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

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

class _HandshakeStatus {
  const _HandshakeStatus({required this.statusCode, required this.statusText});

  final int statusCode;
  final String statusText;
}

class _HandshakeStatusProtocolChannel extends ProtocolChannel {
  _HandshakeStatusProtocolChannel({required this.statusCode, required this.statusText});

  final int statusCode;
  final String statusText;
  bool _started = false;

  @override
  void start(void Function(Uint8List data) onDataReceived, {void Function()? onDone, void Function(Object? error)? onError}) {
    if (_started) {
      throw Exception('Already started');
    }
    _started = true;
    scheduleMicrotask(() {
      onError?.call(
        WebSocketChannelException.from(WebSocketException('websocket connect failed with status $statusCode: $statusText', statusCode)),
      );
    });
  }

  @override
  void dispose() {
    _started = false;
  }

  @override
  Future<void> sendData(Uint8List data) async {}
}

class _StartupExceptionProtocolChannel extends ProtocolChannel {
  _StartupExceptionProtocolChannel({required this.message});

  final String message;
  bool _started = false;

  @override
  void start(void Function(Uint8List data) onDataReceived, {void Function()? onDone, void Function(Object? error)? onError}) {
    if (_started) {
      throw Exception('Already started');
    }
    _started = true;
    scheduleMicrotask(() {
      onError?.call(RoomServerException(message));
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

  Future<void> closeServerToClient() async {
    await _serverToClient.close();
  }

  Future<void> disconnectClientWithError([Object? error]) async {
    _serverToClient.addError(error ?? StateError('socket disconnected'));
    await _serverToClient.close();
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
    "room_ready",
    packMessage({"room_name": "test-room", "room_url": "ws://example/rooms/test-room", "session_id": "session-1"}),
  );
  await protocol.send(
    "connected",
    packMessage({
      "type": "init",
      "participantId": "self",
      "attributes": {"name": "self"},
    }),
  );
}

Future<void> _waitUntil(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 1));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition was not met before timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _IdleProtocolChannel extends ProtocolChannel {
  @override
  void dispose() {}

  @override
  Future<void> sendData(Uint8List data) async {}

  @override
  void start(void Function(Uint8List data) onDataReceived, {void Function()? onDone, void Function(Object? error)? onError}) {}
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
  test('start surfaces retryable websocket close status when automatic reconnect is disabled', () async {
    final room = RoomClient(
      protocolFactory: Protocol.createFactory(
        // dart:io server-side WebSocket.close() rejects 1013 as reserved,
        // so simulate the websocket close surfaced by the protocol layer.
        channel: _CloseWithStatusProtocolChannel(closeCode: _retryableCloseStatusCode, reason: 'try_again_later'),
      ),
      reconnectTimeout: Duration.zero,
    );

    await expectLater(
      room.start(),
      throwsA(
        isA<RoomServerException>().having(
          (error) => error.message,
          'message',
          'room connection unexpectedly closed before the room became ready: try_again_later',
        ),
      ),
    );
  });

  test('start retries transient startup exceptions', () async {
    final pair = _ProtocolPair();
    var protocolFactoryCalls = 0;
    final room = RoomClient(
      protocolFactory: () {
        protocolFactoryCalls++;
        if (protocolFactoryCalls == 1) {
          return Protocol(channel: _StartupExceptionProtocolChannel(message: 'transient startup error'));
        }
        return pair.clientProtocolFactory();
      },
      reconnectTimeout: const Duration(milliseconds: 500),
    );

    try {
      pair.serverProtocol.start(onMessage: (protocol, messageId, type, data) async {});

      final startFuture = room.start();
      await _sendRoomReady(pair.serverProtocol);
      await startFuture;

      expect(protocolFactoryCalls, 2);
      expect(room.isConnected, isTrue);
    } finally {
      room.dispose();
      await pair.dispose();
    }
  });

  test('start retries retryable websocket close status', () async {
    final pair = _ProtocolPair();
    var protocolFactoryCalls = 0;
    final room = RoomClient(
      protocolFactory: () {
        protocolFactoryCalls++;
        if (protocolFactoryCalls == 1) {
          return Protocol(
            channel: _CloseWithStatusProtocolChannel(closeCode: _retryableCloseStatusCode, reason: 'try_again_later'),
          );
        }
        return pair.clientProtocolFactory();
      },
      reconnectTimeout: const Duration(milliseconds: 500),
    );

    try {
      pair.serverProtocol.start(onMessage: (protocol, messageId, type, data) async {});

      final startFuture = room.start();
      await _waitUntil(() => protocolFactoryCalls >= 2);
      await _sendRoomReady(pair.serverProtocol);
      await startFuture;

      expect(protocolFactoryCalls, 2);
      expect(room.isConnected, isTrue);
    } finally {
      room.dispose();
      await pair.dispose();
    }
  });

  test('start reconnect timeout closes room after startup failures', () async {
    var protocolFactoryCalls = 0;
    final room = RoomClient(
      protocolFactory: () {
        protocolFactoryCalls++;
        return Protocol(channel: _StartupExceptionProtocolChannel(message: 'transient startup error'));
      },
      reconnectTimeout: const Duration(milliseconds: 50),
    );

    await expectLater(
      room.start(),
      throwsA(
        isA<RoomServerException>().having(
          (error) => error.message,
          'message',
          'room connection unexpectedly closed before the room became ready: '
              'room reconnect timed out after 0.05s (transient startup error)',
        ),
      ),
    );

    expect(protocolFactoryCalls, greaterThan(1));
    expect(room.isConnected, isFalse);
    expect(room.isClosed, isTrue);
    expect(room.closeKind, ProtocolCloseKind.error);
    expect(room.closeReason, 'room reconnect timed out after 0.05s (transient startup error)');

    await expectLater(
      room.sendRequest('noop', {'a': 1}),
      throwsA(
        isA<RoomServerException>().having(
          (error) => error.message,
          'message',
          'room connection unexpectedly closed before request completed: '
              'room reconnect timed out after 0.05s (transient startup error)',
        ),
      ),
    );

    room.dispose();
  });

  for (final handshakeStatus in const [
    _HandshakeStatus(statusCode: 403, statusText: 'Forbidden'),
    _HandshakeStatus(statusCode: 404, statusText: 'Not Found'),
  ]) {
    test('start does not retry websocket handshake status ${handshakeStatus.statusCode}', () async {
      var protocolFactoryCalls = 0;
      final room = RoomClient(
        protocolFactory: () {
          protocolFactoryCalls++;
          return Protocol(
            channel: _HandshakeStatusProtocolChannel(statusCode: handshakeStatus.statusCode, statusText: handshakeStatus.statusText),
          );
        },
      );

      try {
        await expectLater(
          room.start(),
          throwsA(
            isA<RoomServerException>().having(
              (error) => error.message,
              'message',
              'room connection unexpectedly closed before the room became ready: '
                  'websocket connect failed with status ${handshakeStatus.statusCode}: ${handshakeStatus.statusText}',
            ),
          ),
        );
        expect(protocolFactoryCalls, 1);
        expect(room.isClosed, isTrue);
        expect(room.closeKind, ProtocolCloseKind.error);
        expect(room.closeReason, 'websocket connect failed with status ${handshakeStatus.statusCode}: ${handshakeStatus.statusText}');
        await room.waitForClose().timeout(const Duration(seconds: 1));
      } finally {
        room.dispose();
      }
    });

    test('reconnect does not retry websocket handshake status ${handshakeStatus.statusCode}', () async {
      final pair = _ProtocolPair();
      var protocolFactoryCalls = 0;
      final room = RoomClient(
        protocolFactory: () {
          protocolFactoryCalls++;
          if (protocolFactoryCalls == 1) {
            return pair.clientProtocolFactory();
          }
          return Protocol(
            channel: _HandshakeStatusProtocolChannel(statusCode: handshakeStatus.statusCode, statusText: handshakeStatus.statusText),
          );
        },
        reconnectTimeout: const Duration(milliseconds: 500),
      );

      try {
        pair.serverProtocol.start(onMessage: (protocol, messageId, type, data) async {});

        final startFuture = room.start();
        await _sendRoomReady(pair.serverProtocol);
        await startFuture;

        await pair.disconnectClientWithError(StateError('socket disconnected'));
        await room.waitForClose().timeout(const Duration(seconds: 1));

        expect(protocolFactoryCalls, 2);
        expect(room.isClosed, isTrue);
        expect(room.closeKind, ProtocolCloseKind.error);
        expect(room.closeReason, 'websocket connect failed with status ${handshakeStatus.statusCode}: ${handshakeStatus.statusText}');

        await expectLater(
          room.sendRequest('noop', {'a': 1}),
          throwsA(
            isA<RoomServerException>().having(
              (error) => error.message,
              'message',
              'room connection unexpectedly closed before request completed: '
                  'websocket connect failed with status ${handshakeStatus.statusCode}: ${handshakeStatus.statusText}',
            ),
          ),
        );
      } finally {
        room.dispose();
        await pair.dispose();
      }
    });
  }

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

    final room = RoomClient(protocolFactory: pair.clientProtocolFactory);
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

    final room = RoomClient(protocolFactory: pair.clientProtocolFactory);
    final startFuture = room.start();
    await _sendRoomReady(pair.serverProtocol);
    await startFuture;

    final requestFuture = room.sendRequest("test.hang", {"a": 1});
    await requestReceived.future;

    await pair.closeServerToClient();

    await expectLater(requestFuture, throwsA(isA<RoomServerException>()));
    await pair.dispose();
  });

  test('waitForClose stays pending during reconnect attempts and closes after reconnect timeout', () async {
    final pair = _ProtocolPair();
    var reconnectAttempts = 0;

    final room = RoomClient(
      protocolFactory: () {
        if (reconnectAttempts == 0) {
          reconnectAttempts++;
          return pair.clientProtocolFactory();
        }
        reconnectAttempts++;
        return Protocol(channel: _IdleProtocolChannel());
      },
      reconnectTimeout: const Duration(milliseconds: 50),
    );

    final events = <RoomStatusEvent>[];
    room.listen((event) {
      if (event is RoomStatusEvent) {
        events.add(event);
      }
    });

    pair.serverProtocol.start(onMessage: (protocol, messageId, type, data) async {});

    final startFuture = room.start();
    await _sendRoomReady(pair.serverProtocol);
    await startFuture;

    final waitForClose = room.waitForClose().then((_) => 'closed');

    await pair.disconnectClientWithError();

    final earlyState = await Future.any<String>([waitForClose, Future<String>.delayed(const Duration(milliseconds: 10), () => 'waiting')]);
    expect(earlyState, 'waiting');

    expect(await waitForClose.timeout(const Duration(seconds: 1)), 'closed');
    expect(room.isClosed, isTrue);
    expect(room.closeKind, ProtocolCloseKind.error);
    expect(room.closeReason, contains('room reconnect timed out'));
    expect(events.map((event) => event.status), contains('disconnected'));
    expect(events.map((event) => event.status), isNot(contains('reconnected')));
    expect(reconnectAttempts, greaterThan(1));

    await pair.dispose();
  });

  test('server normal close attempts reconnect when client is not closing', () async {
    final firstPair = _ProtocolPair();
    final secondPair = _ProtocolPair();
    var protocolFactoryCalls = 0;

    final room = RoomClient(
      protocolFactory: () {
        protocolFactoryCalls++;
        if (protocolFactoryCalls == 1) {
          return firstPair.clientProtocolFactory();
        }
        return secondPair.clientProtocolFactory();
      },
      reconnectTimeout: const Duration(milliseconds: 500),
    );

    final events = <RoomStatusEvent>[];
    room.listen((event) {
      if (event is RoomStatusEvent) {
        events.add(event);
      }
    });

    try {
      firstPair.serverProtocol.start(onMessage: (protocol, messageId, type, data) async {});

      final startFuture = room.start();
      await _sendRoomReady(firstPair.serverProtocol);
      await startFuture;

      await firstPair.closeServerToClient();
      await _waitUntil(() => protocolFactoryCalls == 2);

      secondPair.serverProtocol.start(onMessage: (protocol, messageId, type, data) async {});
      await _sendRoomReady(secondPair.serverProtocol);

      await _waitUntil(() => events.map((event) => event.status).contains('reconnected'));

      expect(room.isConnected, isTrue);
      expect(room.isClosed, isFalse);
      expect(protocolFactoryCalls, 2);
    } finally {
      room.dispose();
      await firstPair.dispose();
      await secondPair.dispose();
    }
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

    final room = RoomClient(protocolFactory: pair.clientProtocolFactory);
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

    final room = RoomClient(protocolFactory: pair.clientProtocolFactory);
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

  test('stream invoke waits for open response before sending request chunks', () async {
    final pair = _ProtocolPair();
    var opened = false;
    var chunkBeforeOpen = false;
    var requestChunks = 0;
    pair.serverProtocol.start(
      onMessage: (protocol, messageId, type, data) async {
        if (type == 'room.invoke_tool') {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          opened = true;
          await protocol.send('__response__', ControlContent(method: 'open').pack(), id: messageId);
          return;
        }
        if (type == 'room.tool_call_request_chunk') {
          requestChunks++;
          if (!opened) {
            chunkBeforeOpen = true;
          }
          await protocol.send('__response__', EmptyContent().pack(), id: messageId);
        }
      },
    );

    final room = RoomClient(protocolFactory: pair.clientProtocolFactory);
    final startFuture = room.start();
    await _sendRoomReady(pair.serverProtocol);
    await startFuture;

    final output = await room.invoke(
      toolkit: 'test',
      tool: 'stream',
      input: ToolStreamInput(
        Stream<Content>.fromIterable([
          JsonContent(json: const {'step': 1}),
        ]),
      ),
    );
    expect(output, isA<ToolStreamOutput>());
    await (output as ToolStreamOutput).inputClosed;

    expect(chunkBeforeOpen, isFalse);
    expect(requestChunks, 2);

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
      await _sendWebSocketProtocolMessage(
        websocket,
        messageId: 1,
        type: 'connected',
        data: packMessage({
          'type': 'init',
          'participantId': 'self',
          'attributes': {'name': 'self'},
        }),
      );
    }();

    final room = RoomClient(
      protocolFactory: WebSocketClientProtocol.createFactory(
        url: Uri.parse('ws://127.0.0.1:${server.port}/rooms/test-room'),
        token: 'token',
      ),
    );

    await room.start();
    expect(room.ready, completes);

    room.dispose();
    await serverTask;
    await server.close(force: true);
  });
}

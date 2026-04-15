import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:meshagent/version.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:web_socket_channel/web_socket_channel.dart';

class ProtocolMessage {
  ProtocolMessage({required this.id, required this.data, required this.type}) : sent = Completer<void>();

  final int id;
  final Uint8List data;
  final String type;
  final Completer<void> sent;
}

enum ProtocolCloseKind { client, server, error }

class ProtocolReconnectUnsupportedException implements Exception {
  ProtocolReconnectUnsupportedException(this.message);

  final String message;

  @override
  String toString() {
    return message;
  }
}

class ProtocolCloseException implements Exception {
  ProtocolCloseException({required this.closeCode, this.reason});

  final int closeCode;
  final String? reason;

  @override
  String toString() {
    if (reason == null || reason == '') {
      return 'connection closed with status $closeCode';
    }
    return reason!;
  }
}

abstract class ProtocolChannel {
  ProtocolChannel();

  void start(void Function(Uint8List data) onDataReceived, {void Function()? onDone, void Function(Object? error)? onError});

  void dispose();

  Future<void> sendData(Uint8List data);
}

class StreamProtocolChannel extends ProtocolChannel {
  StreamProtocolChannel({required this.input, required this.output});

  final Stream<Uint8List> input;
  final StreamSink<Uint8List> output;

  StreamSubscription<Uint8List>? subscription;

  @override
  void start(void Function(Uint8List data) onDataReceived, {void Function()? onDone, void Function(Object? error)? onError}) {
    if (subscription != null) {
      throw StateError('Already started');
    }

    subscription = input.listen(onDataReceived, onError: onError, onDone: onDone, cancelOnError: true);
  }

  @override
  void dispose() {
    final current = subscription;
    subscription = null;
    current?.cancel();
  }

  @override
  Future<void> sendData(Uint8List data) async {
    output.add(data);
  }
}

class WebSocketProtocolChannel extends ProtocolChannel {
  WebSocketProtocolChannel({required this.url, required this.jwt});

  final String jwt;
  final Uri url;

  WebSocketChannel? webSocket;
  StreamSubscription<dynamic>? sub;
  void Function(Uint8List data)? onDataReceived;

  @override
  void start(void Function(Uint8List data) onDataReceived, {void Function()? onDone, void Function(Object? error)? onError}) {
    this.onDataReceived = onDataReceived;

    webSocket = WebSocketChannel.connect(url.replace(queryParameters: {'token': jwt, 'v': version}));
    sub = webSocket!.stream.listen(
      _onData,
      onDone: () {
        final closeCode = webSocket?.closeCode;
        if (closeCode != null && closeCode != status.normalClosure) {
          onError?.call(ProtocolCloseException(closeCode: closeCode, reason: webSocket?.closeReason));
          return;
        }
        onDone?.call();
      },
      onError: onError,
    );
  }

  void _onData(dynamic data) {
    onDataReceived?.call(data as Uint8List);
  }

  @override
  void dispose() {
    webSocket?.sink.close(status.normalClosure);
    unawaited(sub?.cancel());
    sub = null;
    webSocket = null;
  }

  @override
  Future<void> sendData(Uint8List data) async {
    webSocket?.sink.add(data);
  }
}

typedef ProtocolMessageHandler = Future<void> Function(Protocol protocol, int messageId, String type, Uint8List data);
typedef ProtocolFactory = Protocol Function();

class Protocol<T extends ProtocolChannel> {
  Protocol({required this.channel});

  final T channel;
  final Map<String, ProtocolMessageHandler> handlers = <String, ProtocolMessageHandler>{};
  final StreamController<ProtocolMessage> _send = StreamController<ProtocolMessage>();
  final Completer<Object?> _done = Completer<Object?>();

  Object? _sendError;
  Future<void>? _sendLoop;
  int _id = 0;
  bool _open = false;
  bool _closed = false;
  ProtocolCloseKind? _closeKind;
  String? _closeReason;

  int recvPacketId = 0;
  String recvState = 'ready';
  int recvPacketTotal = 0;
  int recvMessageId = -1;
  String recvType = '';
  BytesBuilder recvPackets = BytesBuilder();

  Uri? get url {
    return null;
  }

  String? get token {
    return null;
  }

  bool get isOpen {
    return _open;
  }

  ProtocolCloseKind? get closeKind {
    return _closeKind;
  }

  String? get closeReason {
    return _closeReason;
  }

  Future<Object?> get done {
    return _done.future;
  }

  Future<void> waitForClose() async {
    await done;
  }

  static ProtocolFactory createFactory<T extends ProtocolChannel>({required T channel}) {
    var used = false;
    return () {
      if (used) {
        throw ProtocolReconnectUnsupportedException('protocolFactory was not configured for reconnecting this protocol');
      }
      used = true;
      return Protocol<T>(channel: channel);
    };
  }

  void _setCloseState({required ProtocolCloseKind kind, String? reason}) {
    _closeKind ??= kind;
    if (reason != null && reason.isNotEmpty && _closeReason == null) {
      _closeReason = reason;
    }
  }

  void addHandler(String type, ProtocolMessageHandler handler) {
    if (handlers.containsKey(type)) {
      throw StateError('already registered handler for $type');
    }
    handlers[type] = handler;
  }

  void removeHandler(String type, ProtocolMessageHandler handler) {
    final current = handlers[type];
    if (!identical(current, handler)) {
      throw StateError('handler mismatch for $type');
    }
    handlers.remove(type);
  }

  ProtocolMessageHandler? getHandler(String type) {
    return handlers[type];
  }

  Future<void> handleMessage(int messageId, String type, Uint8List data) async {
    final handler = handlers[type] ?? handlers['*'];
    if (handler == null) {
      throw StateError('No handler registered for $type');
    }
    await handler(this, messageId, type, data);
  }

  int getNextMessageId() {
    return _id++;
  }

  int sendNowait(String type, Uint8List data, {int? id}) {
    if (_sendError != null) {
      throw _sendError!;
    }
    if (_closed) {
      throw StateError('protocol is closed');
    }
    final msg = ProtocolMessage(id: id ?? getNextMessageId(), type: type, data: data);
    _send.add(msg);
    return msg.id;
  }

  Future<void> send(String type, Uint8List data, {int? id}) async {
    final msg = ProtocolMessage(id: id ?? getNextMessageId(), type: type, data: data);
    if (_sendError != null) {
      throw _sendError!;
    }
    if (_closed) {
      throw StateError('protocol is closed');
    }
    _send.add(msg);
    await msg.sent.future;
  }

  Future<void> sendJson(Object object) async {
    await send('application/json', Uint8List.fromList(utf8.encode(jsonEncode(object))));
  }

  void start({ProtocolMessageHandler? onMessage, void Function()? onDone, void Function(Object? error)? onError}) {
    if (_sendLoop != null) {
      throw StateError('protocol already started');
    }
    if (onMessage != null) {
      addHandler('*', onMessage);
    }
    _open = true;
    channel.start(
      onDataReceived,
      onDone: () {
        _setCloseState(kind: ProtocolCloseKind.server);
        _shutdown();
        if (!_done.isCompleted) {
          _done.complete(null);
        }
        onDone?.call();
      },
      onError: (Object? error) {
        _setCloseState(kind: ProtocolCloseKind.error, reason: error?.toString());
        _shutdown();
        if (!_done.isCompleted) {
          _done.complete(error);
        }
        onError?.call(error);
      },
    );
    _sendLoop = _runSendLoop();
  }

  void close() {
    _setCloseState(kind: ProtocolCloseKind.client);
    _shutdown();
    channel.dispose();
    if (!_done.isCompleted) {
      _done.complete(null);
    }
  }

  void dispose() {
    close();
  }

  void _shutdown() {
    if (_closed) {
      return;
    }
    _closed = true;
    _open = false;
    if (!_send.isClosed) {
      unawaited(_send.close());
    }
  }

  Future<void> _runSendLoop() async {
    await for (final message in _send.stream) {
      try {
        final packets = (message.data.length / 1024).ceil();

        final packet = BytesBuilder();
        packet.add(
          Uint8List(16)
            ..buffer.asByteData().setUint32(0, message.id >> 32, Endian.big)
            ..buffer.asByteData().setUint32(4, message.id & 0xffffffff, Endian.big)
            ..buffer.asByteData().setInt32(8, 0, Endian.big)
            ..buffer.asByteData().setInt32(12, packets, Endian.big),
        );
        packet.add(utf8.encode(message.type));
        await channel.sendData(packet.toBytes());

        for (var i = 0; i < packets; i++) {
          final packetBuilder = BytesBuilder();
          final header = Uint8List(12).buffer.asByteData();

          header.setUint32(0, message.id >> 32, Endian.big);
          header.setUint32(4, message.id & 0xffffffff, Endian.big);
          header.setInt32(8, i + 1, Endian.big);

          packetBuilder.add(Uint8List.view(header.buffer));
          packetBuilder.add(Uint8List.sublistView(message.data, i * 1024, min((i + 1) * 1024, message.data.length)));

          await channel.sendData(packetBuilder.toBytes());
        }
        if (!message.sent.isCompleted) {
          message.sent.complete();
        }
      } catch (error, stackTrace) {
        _sendError = error;
        _setCloseState(kind: ProtocolCloseKind.error, reason: error.toString());
        if (!message.sent.isCompleted) {
          message.sent.completeError(error, stackTrace);
        }
        _shutdown();
        if (!_done.isCompleted) {
          _done.complete(error);
        }
        return;
      }
    }
  }

  void onDataReceived(Uint8List dataPacket) {
    final data = dataPacket.buffer.asByteData();

    final messageId = data.getUint32(4).toInt() + (data.getUint32(0).toInt() << 32);
    final packet = data.getInt32(8);

    if (packet != recvPacketId) {
      recvState = 'error';
    }

    if (packet == 0) {
      if (recvState == 'ready' || recvState == 'error') {
        recvPacketTotal = data.getInt32(12);
        recvMessageId = messageId;
        recvType = utf8.decode(dataPacket.sublist(16));

        if (recvPacketTotal == 0) {
          final payload = recvPackets.takeBytes();
          _dispatchMessage(messageId: messageId, type: recvType, data: payload);
          recvState = 'ready';
          recvPacketId = 0;
          recvType = '';
          recvMessageId = -1;
        } else {
          recvPacketId += 1;
          recvState = 'processing';
        }
      } else {
        recvState = 'error';
        recvPacketId = 0;
      }
      return;
    }

    if (recvState != 'processing') {
      recvState = 'error';
      recvPacketId = 0;
      return;
    }

    if (messageId != recvMessageId) {
      recvState = 'error';
      recvPacketId = 0;
    }

    recvPackets.add(dataPacket.sublist(12));

    if (recvPacketTotal == recvPacketId) {
      final payload = recvPackets.takeBytes();
      _dispatchMessage(messageId: messageId, type: recvType, data: payload);
      recvState = 'ready';
      recvPacketId = 0;
      recvType = '';
      recvMessageId = -1;
      return;
    }

    recvPacketId += 1;
  }

  void _dispatchMessage({required int messageId, required String type, required Uint8List data}) {
    unawaited(
      handleMessage(messageId, type, data).catchError((Object error, StackTrace stackTrace) {
        Zone.current.handleUncaughtError(error, stackTrace);
      }),
    );
  }
}

class WebSocketClientProtocol extends Protocol<WebSocketProtocolChannel> {
  WebSocketClientProtocol({required Uri url, required String token})
    : _url = url,
      _token = token,
      super(
        channel: WebSocketProtocolChannel(url: url, jwt: token),
      );

  final Uri _url;
  final String _token;

  @override
  Uri get url {
    return _url;
  }

  @override
  String get token {
    return _token;
  }

  static ProtocolFactory createFactory({required Uri url, required String token}) {
    return () => WebSocketClientProtocol(url: url, token: token);
  }
}

import "dart:typed_data";
import "dart:async";
import "dart:math";
import "dart:convert";
import "package:flutter/material.dart";

import "package:web_socket_channel/web_socket_channel.dart";
import 'package:web_socket_channel/status.dart' as status;

class ProtocolMessage {
  ProtocolMessage({required this.id, required this.data, required this.type}) : sent = Completer();

  final int id;
  final Uint8List data;
  final String type;

  final Completer sent;
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
      throw Exception("Already started");
    }

    subscription = input.listen(onDataReceived, onError: onError, onDone: onDone, cancelOnError: true);
  }

  @override
  void dispose() {
    if (subscription == null) {
      throw Exception("Already stopped");
    }
    subscription?.cancel();
    subscription = null;
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

  StreamSubscription? sub;

  void Function(Uint8List data)? onDataReceived;

  @override
  void start(void Function(Uint8List data) onDataReceived, {void Function()? onDone, void Function(Object? error)? onError}) {
    this.onDataReceived = onDataReceived;

    final s = url.replace(queryParameters: {"token": jwt}).toString();

    print("jkkkk connecting to $s");

    webSocket = WebSocketChannel.connect(url.replace(queryParameters: {"token": jwt}));
    sub = webSocket!.stream.listen(onData, onDone: onDone, onError: onError);
  }

  void onData(dynamic data) {
    onDataReceived!(data as Uint8List);
  }

  @override
  void dispose() {
    webSocket?.sink.close(status.normalClosure);
    sub?.cancel();
  }

  @override
  Future<void> sendData(Uint8List data) async {
    webSocket?.sink.add(data);
  }
}

typedef ProtocolMessageHandler = Future<void> Function(Protocol, int messageId, String type, Uint8List data);

class Protocol<T extends ProtocolChannel> {
  Protocol({required this.channel});

  Map<String, ProtocolMessageHandler> handlers = {};

  void addHandler(String type, ProtocolMessageHandler handler) {
    handlers[type] = handler;
  }

  void removeHandler(String type, ProtocolMessageHandler handler) {
    handlers.remove(type);
  }

  Future<void> handleMessage(int messageId, String type, Uint8List data) async {
    //await onMessage!(this, messageId, type, data);

    final handler = handlers[type] ?? handlers["*"];
    if (handler == null) {
      throw Exception("No handler registered for $type");
    }
    await handler(this, messageId, type, data);
  }

  final _send = StreamController<ProtocolMessage>();

  int _id = 0;

  int getNextMessageId() {
    return _id++;
  }

  Future<void> send(String type, Uint8List data, {int? id}) async {
    final msg = ProtocolMessage(id: id ?? getNextMessageId(), type: type, data: data);
    _send.add(msg);
    await msg.sent.future;
  }

  Future<void> sendJson(Object object) async {
    return await send("application/json", utf8.encode(jsonEncode(object)));
  }

  final T channel;

  void start({ProtocolMessageHandler? onMessage, void Function()? onDone, void Function(Object? error)? onError}) {
    if (onMessage != null) {
      addHandler("*", onMessage);
    }
    channel.start(onDataReceived, onDone: onDone, onError: onError);

    () async {
      await for (final message in _send.stream) {
        debugPrint("message recv on protocol ${message.id} ${message.type}");

        final packets = (message.data.length / 1024).ceil();

        final packet = BytesBuilder();
        packet.add(
          Uint8List(16)
            ..buffer.asByteData().setUint32(0, message.id >> 32, Endian.big)
            ..buffer.asByteData().setUint32(4, message.id & 0xffff, Endian.big)
            ..buffer.asByteData().setInt32(8, 0, Endian.big)
            ..buffer.asByteData().setInt32(12, packets, Endian.big),
        );
        packet.add(utf8.encode(message.type));
        await channel.sendData(packet.toBytes());

        for (var i = 0; i < packets; i++) {
          final packetBuilder = BytesBuilder();
          final header = Uint8List(12).buffer.asByteData();

          header.setUint32(0, message.id >> 32, Endian.big);
          header.setUint32(4, message.id & 0xffff, Endian.big);
          header.setInt32(8, i + 1, Endian.big);

          packetBuilder.add(Uint8List.view(header.buffer));
          packetBuilder.add(Uint8List.sublistView(message.data, i * 1024, min((i + 1) * 1024, message.data.length)));

          await channel.sendData(packetBuilder.toBytes());
        }
        message.sent.complete();

        debugPrint("message sent on protocol ${message.id} ${message.type}");
      }
      debugPrint("protocol done");
    }();
  }

  void dispose() {
    channel.dispose();
    // TODO: close stream?
  }

  int recvPacketId = 0;
  String recvState = "ready";
  int recvPacketTotal = 0;
  int recvMessageId = -1;
  String recvType = "";
  BytesBuilder recvPackets = BytesBuilder();

  void onDataReceived(Uint8List dataPacket) {
    final data = dataPacket.buffer.asByteData();

    final messageId = data.getUint32(4).toInt() + (data.getUint32(0).toInt() << 32);
    final packet = data.getInt32(8);

    if (packet != recvPacketId) {
      recvState = "error";
      debugPrint("received out of order packet got $packet expected $recvPacketId, total $recvPacketTotal message ID: $messageId");
    }

    if (packet == 0) {
      if (recvState == "ready" || recvState == "error") {
        recvPacketTotal = data.getInt32(12);
        recvMessageId = messageId;
        recvType = utf8.decode(dataPacket.sublist(16));
        debugPrint("received packet $recvType");

        if (recvPacketTotal == 0) {
          try {
            handleMessage(messageId, recvType, recvPackets.takeBytes());
          } finally {
            debugPrint("expecting packet reset to 0");
            recvState = "ready";
            recvPacketId = 0;
            recvType = "";
            recvMessageId = -1;
          }
        } else {
          recvPacketId += 1;
          debugPrint("expecting packet $recvPacketId");
          recvState = "processing";
        }
      } else {
        recvState = "error";
        recvPacketId = 0;
        debugPrint("received packet 0 in invalid state");
      }
    } else if (recvState != "processing") {
      recvState = "error";
      recvPacketId = 0;
      debugPrint("received datapacket in invalid state");
    } else {
      if (messageId != recvMessageId) {
        recvState = "error";
        recvPacketId = 0;
        debugPrint("received packet from incorrect message");
      }

      recvPackets.add(dataPacket.sublist(12));

      if (recvPacketTotal == recvPacketId) {
        try {
          handleMessage(messageId, recvType, recvPackets.takeBytes());
        } finally {
          recvState = "ready";
          recvPacketId = 0;
          recvType = "";
          recvMessageId = -1;
        }
      } else {
        recvPacketId += 1;
      }
    }
  }
}

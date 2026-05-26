import 'dart:io';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

WebSocketChannel connectWebSocketChannel(Uri url, {required String? token}) {
  return IOWebSocketChannel(
    WebSocket.connect(
      url.toString(),
      compression: CompressionOptions.compressionDefault,
      headers: token == null ? null : {'Authorization': 'Bearer $token'},
    ),
  );
}

import 'dart:io';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

WebSocketChannel connectWebSocketChannel(Uri url) {
  return IOWebSocketChannel(WebSocket.connect(url.toString(), compression: CompressionOptions.compressionDefault));
}

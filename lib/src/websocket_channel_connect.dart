import 'package:web_socket_channel/web_socket_channel.dart';

WebSocketChannel connectWebSocketChannel(Uri url) {
  return WebSocketChannel.connect(url);
}

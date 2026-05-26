import 'package:web_socket_channel/web_socket_channel.dart';

WebSocketChannel connectWebSocketChannel(Uri url, {required String? token}) {
  return WebSocketChannel.connect(url, protocols: token == null ? null : ['meshagent-room.$token']);
}

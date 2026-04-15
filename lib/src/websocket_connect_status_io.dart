import 'dart:io';

import 'package:web_socket_channel/web_socket_channel.dart';

int? websocketConnectStatusCode(Object? error) {
  if (error is WebSocketException) {
    return error.httpStatusCode;
  }
  if (error is WebSocketChannelException) {
    final inner = error.inner;
    if (inner is WebSocketException) {
      return inner.httpStatusCode;
    }
  }
  return null;
}

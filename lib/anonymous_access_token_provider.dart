import 'dart:convert';

import 'package:http/http.dart' as http;

import 'client.dart';
import 'protocol.dart' show ProtocolHandshakeException;

/// Retains an anonymous session while obtaining a fresh token for each connection.
class AnonymousAccessTokenProvider implements AccessTokenProvider {
  AnonymousAccessTokenProvider({required String resource, Uri? authorizationUrl, http.Client? client})
    : authorizationUrl = Uri.base.resolveUri(authorizationUrl ?? Uri.parse('/.well-known/meshagent/authorize')),
      _client = client {
    if (resource != 'room' && resource != 'agent') {
      throw ArgumentError.value(resource, 'resource', 'must be room or agent');
    }
    if (!['http', 'https'].contains(this.authorizationUrl.scheme)) {
      throw ArgumentError('anonymous authorization requires an HTTP(S) URL');
    }
    connectUrl = this.authorizationUrl.resolve('/.well-known/meshagent/$resource/connect');
  }

  final Uri authorizationUrl;
  late final Uri connectUrl;
  final http.Client? _client;
  DateTime? expiresAt;
  String? _cookie;
  Future<String>? _pending;

  @override
  Future<String> getToken() => _pending ??= _exchange().whenComplete(() => _pending = null);

  Future<String> _exchange() async {
    final issuedAt = DateTime.now().toUtc();
    final client = _client ?? http.Client();
    try {
      final request = http.Request('POST', authorizationUrl)..followRedirects = false;
      if (_cookie != null) request.headers['Cookie'] = _cookie!;
      final response = await http.Response.fromStream(await client.send(request));
      if (response.statusCode != 200) {
        final detail = response.body.trim();
        // Reverse proxies may return HTML error pages; never expose their markup.
        final message = detail.isNotEmpty && !detail.startsWith('<')
            ? detail.substring(0, detail.length > 2048 ? 2048 : detail.length)
            : response.reasonPhrase;
        throw ProtocolHandshakeException(
          statusCode: response.statusCode,
          statusText: message == null || message.isEmpty ? 'Anonymous authorization failed' : message,
          errorCode: [401, 403].contains(response.statusCode) ? 'anonymous_access_denied' : 'anonymous_authorization_failed',
        );
      }
      final dynamic body;
      try {
        body = jsonDecode(response.body);
      } on FormatException {
        throw ProtocolHandshakeException(
          statusCode: 400,
          statusText: 'Invalid anonymous authorization response: expected JSON',
          errorCode: 'invalid_anonymous_authorization_response',
        );
      }
      if (body is! Map<String, dynamic> ||
          body['jwt'] is! String ||
          (body['jwt'] as String).isEmpty ||
          body['connect_path'] != connectUrl.path ||
          body['expires_in'] is! num ||
          !(body['expires_in'] as num).isFinite ||
          (body['expires_in'] as num) <= 0) {
        throw ProtocolHandshakeException(
          statusCode: 400,
          statusText: 'Invalid anonymous authorization response',
          errorCode: 'invalid_anonymous_authorization_response',
        );
      }
      // The browser retains HttpOnly cookies; native HTTP clients need this jar.
      final cookie = RegExp(r'(?:^|,\s*)__meshagent_anonymous=([^; ,]+)').firstMatch(response.headers['set-cookie'] ?? '');
      if (cookie != null) _cookie = '__meshagent_anonymous=${cookie.group(1)}';
      expiresAt = issuedAt.add(Duration(milliseconds: ((body['expires_in'] as num) * 1000).floor()));
      return body['jwt'] as String;
    } finally {
      if (_client == null) client.close();
    }
  }
}

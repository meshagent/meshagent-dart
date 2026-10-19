import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meshagent/meshagent.dart';
import 'package:test/test.dart';

class _PendingToken implements AccessTokenProvider {
  final result = Completer<String>();
  @override
  Future<String> getToken() => result.future;
}

void main() {
  test('exchanges share a session, expose expiry, and reject revoked access', () async {
    var requests = 0;
    final provider = AnonymousAccessTokenProvider(
      resource: 'room',
      authorizationUrl: Uri.parse('https://example.test/.well-known/meshagent/authorize'),
      client: MockClient((request) async {
        requests++;
        if (requests > 1) {
          expect(request.headers['cookie'], '__meshagent_anonymous=visitor-one');
          return http.Response('revoked', 401);
        }
        return http.Response(
          jsonEncode({'jwt': 'first', 'connect_path': '/.well-known/meshagent/room/connect', 'expires_in': 300}),
          200,
          headers: {'set-cookie': '__meshagent_anonymous=visitor-one; HttpOnly; Path=/'},
        );
      }),
    );
    expect(await Future.wait([provider.getToken(), provider.getToken()]), ['first', 'first']);
    expect(requests, 1);
    expect(provider.expiresAt!.isAfter(DateTime.now()), isTrue);
    await expectLater(
      provider.getToken(),
      throwsA(
        isA<ProtocolHandshakeException>()
            .having((error) => error.statusCode, 'statusCode', 401)
            .having((error) => error.statusText, 'message', 'revoked'),
      ),
    );
  });

  test('room stops retrying when anonymous access is denied', () async {
    var requests = 0;
    final provider = AnonymousAccessTokenProvider(
      resource: 'room',
      authorizationUrl: Uri.parse('https://example.test/.well-known/meshagent/authorize'),
      client: MockClient((request) async {
        requests++;
        return http.Response('denied', 401);
      }),
    );
    final room = RoomClient(
      protocolFactory: WebSocketClientProtocol.createFactory(url: Uri.parse('ws://127.0.0.1:1'), tokenProvider: provider),
    );
    try {
      await expectLater(
        room.start().timeout(const Duration(seconds: 2)),
        throwsA(
          isA<RoomServerException>()
              .having((error) => error.message, 'message', contains('denied'))
              .having((error) => error.statusCode, 'statusCode', 401)
              .having((error) => error.errorCode, 'errorCode', 'anonymous_access_denied'),
        ),
      );
      expect(requests, 1);
    } finally {
      room.dispose();
    }
  });

  for (final (body, status, message, code) in [
    ('<html>proxy failure</html>', 503, 'Anonymous authorization failed', 'anonymous_authorization_failed'),
    ('not json', 200, 'expected JSON', 'invalid_anonymous_authorization_response'),
    ('{}', 200, 'Invalid anonymous authorization response', 'invalid_anonymous_authorization_response'),
  ]) {
    test('reports a useful error for $body', () async {
      final provider = AnonymousAccessTokenProvider(
        resource: 'room',
        authorizationUrl: Uri.parse('https://example.test'),
        client: MockClient((_) async => http.Response(body, status)),
      );
      await expectLater(
        provider.getToken(),
        throwsA(
          isA<ProtocolHandshakeException>()
              .having((error) => error.toString(), 'message', contains(message))
              .having((error) => error.errorCode, 'errorCode', code),
        ),
      );
    });
  }

  test('disposal during authorization cannot open a room socket', () async {
    final provider = _PendingToken();
    final channel = WebSocketProtocolChannel(url: Uri.parse('ws://127.0.0.1:1'), jwt: null, tokenProvider: provider);
    channel.start((Uint8List _) {}, onError: (error) => fail('disposed channel reported $error'));
    channel.dispose();
    provider.result.complete('late');
    await Future<void>.delayed(Duration.zero);
    expect(channel.webSocket, isNull);
  });
}

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meshagent/meshagent.dart';
import 'package:test/test.dart';

void main() {
  test('getUserProfile throws ForbiddenException on 403', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), 'http://example.test/accounts/profiles/me');
      return http.Response(jsonEncode({'error': 'forbidden'}), 403);
    });

    final meshagent = Meshagent(baseUrl: 'http://example.test', token: 'test-token', client: client);

    await expectLater(meshagent.getUserProfile('me'), throwsA(isA<ForbiddenException>()));
  });
}

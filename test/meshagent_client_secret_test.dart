import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meshagent/meshagent.dart';
import 'package:test/test.dart';

class _RecordedRequest {
  _RecordedRequest({required this.method, required this.uri, this.body});

  final String method;
  final Uri uri;
  final Map<String, dynamic>? body;
}

void main() {
  test('createProjectSecret sends a base64 payload', () async {
    final requests = <_RecordedRequest>[];
    final client = MockClient((request) async {
      requests.add(
        _RecordedRequest(
          method: request.method,
          uri: request.url,
          body: request.body.isEmpty ? null : jsonDecode(request.body) as Map<String, dynamic>,
        ),
      );
      return http.Response(jsonEncode({'id': 'secret-1'}), 200);
    });
    final meshagent = Meshagent(baseUrl: 'http://example.test', token: 'test-token', client: client);

    final secretId = await meshagent.createProjectSecret(
      projectId: 'proj_123',
      name: 'registry',
      type: 'docker',
      data: Uint8List.fromList(utf8.encode('{"server":"registry.example.com"}')),
    );

    expect(secretId, 'secret-1');
    expect(requests, hasLength(1));
    expect(requests.single.method, 'POST');
    expect(requests.single.uri.toString(), 'http://example.test/accounts/projects/proj_123/secrets');
    expect(requests.single.body, {'name': 'registry', 'type': 'docker', 'data_base64': 'eyJzZXJ2ZXIiOiJyZWdpc3RyeS5leGFtcGxlLmNvbSJ9'});
  });

  test('listSecrets compatibility wrapper fetches managed secret payloads', () async {
    final requests = <_RecordedRequest>[];
    final client = MockClient((request) async {
      requests.add(
        _RecordedRequest(
          method: request.method,
          uri: request.url,
          body: request.body.isEmpty ? null : jsonDecode(request.body) as Map<String, dynamic>,
        ),
      );

      if (request.url.path == '/accounts/projects/proj_123/secrets') {
        return http.Response(
          jsonEncode({
            'secrets': [
              {'id': 'secret-1', 'name': 'registry', 'type': 'docker', 'delegated_to': null},
            ],
          }),
          200,
        );
      }

      if (request.url.path == '/accounts/projects/proj_123/secrets/secret-1') {
        return http.Response(
          jsonEncode({
            'id': 'secret-1',
            'name': 'registry',
            'type': 'docker',
            'data_base64':
                'eyJzZXJ2ZXIiOiJyZWdpc3RyeS5leGFtcGxlLmNvbSIsInVzZXJuYW1lIjoiYWxpY2UiLCJwYXNzd29yZCI6InNlY3JldCIsImVtYWlsIjoibm9uZUBleGFtcGxlLmNvbSJ9',
          }),
          200,
        );
      }

      throw StateError('unexpected request: ${request.method} ${request.url}');
    });
    final meshagent = Meshagent(baseUrl: 'http://example.test', token: 'test-token', client: client);

    final secrets = await meshagent.listSecrets('proj_123');

    expect(secrets, hasLength(1));
    expect(secrets.single, {
      'id': 'secret-1',
      'name': 'registry',
      'type': 'docker',
      'data': {'server': 'registry.example.com', 'username': 'alice', 'password': 'secret', 'email': 'none@example.com'},
    });
    expect(requests.map((request) => '${request.method} ${request.uri}'), [
      'GET http://example.test/accounts/projects/proj_123/secrets',
      'GET http://example.test/accounts/projects/proj_123/secrets/secret-1',
    ]);
  });

  test('room secret and external oauth methods pass query parameters', () async {
    final requests = <_RecordedRequest>[];
    final client = MockClient((request) async {
      requests.add(
        _RecordedRequest(
          method: request.method,
          uri: request.url,
          body: request.body.isEmpty ? null : jsonDecode(request.body) as Map<String, dynamic>,
        ),
      );

      if (request.url.toString() ==
          'http://example.test/accounts/projects/proj_123/rooms/room-a/secrets/secret-1?delegated_to=agent&for_identity=agent') {
        return http.Response(
          jsonEncode({
            'id': 'secret-1',
            'name': 'api-key',
            'type': 'application/octet-stream',
            'delegated_to': 'agent',
            'data_base64': 'c2VjcmV0',
          }),
          200,
        );
      }

      if (request.url.toString() == 'http://example.test/accounts/projects/proj_123/rooms/room-a/external-oauth?delegated_to=agent') {
        return http.Response(
          jsonEncode({
            'registrations': [
              {
                'id': 'registration-1',
                'delegated_to': 'agent',
                'connector': null,
                'oauth': {
                  'authorization_endpoint': 'https://auth.example.com/authorize',
                  'token_endpoint': 'https://auth.example.com/token',
                  'client_id': 'client-id',
                  'client_secret': null,
                  'scopes': ['openid'],
                },
                'client_id': 'client-id',
                'client_secret': 'client-secret',
              },
            ],
          }),
          200,
        );
      }

      if (request.url.toString() ==
          'http://example.test/accounts/projects/proj_123/rooms/room-a/external-oauth/registration-1?delegated_to=agent') {
        return http.Response(jsonEncode({}), 200);
      }

      throw StateError('unexpected request: ${request.method} ${request.url}');
    });
    final meshagent = Meshagent(baseUrl: 'http://example.test', token: 'test-token', client: client);

    final secret = await meshagent.getRoomSecret(
      projectId: 'proj_123',
      roomName: 'room-a',
      secretId: 'secret-1',
      delegatedTo: 'agent',
      forIdentity: 'agent',
    );
    final registrations = await meshagent.listRoomExternalOAuthRegistrations(
      projectId: 'proj_123',
      roomName: 'room-a',
      delegatedTo: 'agent',
    );
    await meshagent.deleteRoomExternalOAuthRegistration(
      projectId: 'proj_123',
      roomName: 'room-a',
      registrationId: 'registration-1',
      delegatedTo: 'agent',
    );

    expect(utf8.decode(secret.data), 'secret');
    expect(registrations.single.id, 'registration-1');
    expect(requests.map((request) => '${request.method} ${request.uri}'), [
      'GET http://example.test/accounts/projects/proj_123/rooms/room-a/secrets/secret-1?delegated_to=agent&for_identity=agent',
      'GET http://example.test/accounts/projects/proj_123/rooms/room-a/external-oauth?delegated_to=agent',
      'DELETE http://example.test/accounts/projects/proj_123/rooms/room-a/external-oauth/registration-1?delegated_to=agent',
    ]);
  });

  test('createProjectExternalOAuthRegistration serializes connector payloads', () async {
    final requests = <_RecordedRequest>[];
    final client = MockClient((request) async {
      requests.add(
        _RecordedRequest(
          method: request.method,
          uri: request.url,
          body: request.body.isEmpty ? null : jsonDecode(request.body) as Map<String, dynamic>,
        ),
      );
      return http.Response(jsonEncode({'id': 'registration-1'}), 200);
    });
    final meshagent = Meshagent(baseUrl: 'http://example.test', token: 'test-token', client: client);

    final registrationId = await meshagent.createProjectExternalOAuthRegistration(
      projectId: 'proj_123',
      oauth: OAuthClientConfig(
        authorizationEndpoint: 'https://auth.example.com/authorize',
        tokenEndpoint: 'https://auth.example.com/token',
        clientId: 'configured-client-id',
        scopes: ['openid'],
      ),
      clientId: 'client-id',
      clientSecret: 'client-secret',
      delegatedTo: 'agent',
      connector: ConnectorRef(openaiConnectorId: 'connector-1', serverUrl: 'https://connector.example.com', clientSecretId: 'secret-1'),
    );

    expect(registrationId, 'registration-1');
    expect(requests, hasLength(1));
    expect(requests.single.method, 'POST');
    expect(requests.single.uri.toString(), 'http://example.test/accounts/projects/proj_123/external-oauth');
    expect(requests.single.body, {
      'oauth': {
        'client_id': 'configured-client-id',
        'authorization_endpoint': 'https://auth.example.com/authorize',
        'token_endpoint': 'https://auth.example.com/token',
        'scopes': ['openid'],
      },
      'client_id': 'client-id',
      'client_secret': 'client-secret',
      'delegated_to': 'agent',
      'connector': {'openai_connector_id': 'connector-1', 'server_url': 'https://connector.example.com', 'client_secret_id': 'secret-1'},
    });
  });
}

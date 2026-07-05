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
  test('uses user and service account secret endpoints', () async {
    final requests = <_RecordedRequest>[];
    final secret = {
      'id': 'secret-1',
      'project_id': 'proj_123',
      'owner_user_id': 'user-1',
      'type': 'oauth',
      'name': 'github',
      'http_only': true,
      'metadata': {'service': 'github'},
      'annotations': {'meshagent.io/secret.service': 'github'},
      'current_version_id': 'version-1',
      'value_base64': 'dmFsdWU=',
      'created_at': '2026-06-01T00:00:00Z',
      'updated_at': '2026-06-01T00:00:00Z',
    };
    final version = {
      'id': 'version-1',
      'secret_id': 'secret-1',
      'version': 1,
      'value_sha256': 'BQ==',
      'created_at': '2026-06-01T00:00:00Z',
    };
    final client = MockClient((request) async {
      requests.add(
        _RecordedRequest(
          method: request.method,
          uri: request.url,
          body: request.body.isEmpty ? null : jsonDecode(request.body) as Map<String, dynamic>,
        ),
      );

      if (request.url.path.endsWith(':access')) {
        return http.Response(jsonEncode({'secret_id': 'secret-1', 'version_id': 'version-1', 'value_base64': 'dmFsdWU='}), 200);
      }
      if (request.url.path.endsWith('/versions')) {
        return http.Response(
          jsonEncode(
            request.method == 'POST'
                ? version
                : {
                    'versions': [version],
                  },
          ),
          200,
        );
      }
      if (request.url.path.endsWith('/access')) {
        return http.Response(
          jsonEncode({
            'access_grants': [
              {
                'subject': {'type': 'service_account', 'id': 'sa-1'},
                'roles': ['use_proxy'],
              },
            ],
          }),
          200,
        );
      }
      if (request.url.path.endsWith('/pull-secrets')) {
        return http.Response(
          jsonEncode({
            'secrets': [secret],
            'continuation_token': null,
          }),
          200,
        );
      }
      if (request.method == 'PUT' || request.method == 'DELETE') {
        return http.Response('', 204);
      }
      if (request.url.path.endsWith('/secrets') && request.method == 'GET') {
        return http.Response(
          jsonEncode({
            'secrets': [secret],
            'continuation_token': 'next',
          }),
          200,
        );
      }
      return http.Response(jsonEncode(secret), 200);
    });
    final meshagent = Meshagent(baseUrl: 'http://example.test', token: 'test-token', client: client);

    await meshagent.createUserSecret(
      projectId: 'proj_123',
      name: 'github',
      type: 'oauth',
      httpOnly: true,
      metadata: {'service': 'github'},
      annotations: {'meshagent.io/secret.service': 'github'},
    );
    await meshagent.listUserSecrets(pageSize: 10, continuationToken: 'cursor', filter: 'github');
    await meshagent.searchUserSecrets(name: 'github', httpOnly: true, pageSize: 5);
    await meshagent.createUserSecretVersion('secret-1', value: Uint8List.fromList([1, 2, 3]), setCurrent: false);
    final userVersionValue = await meshagent.accessUserSecretVersion('secret-1', 'version-1');
    await meshagent.deleteUserSecretVersion('secret-1', 'version-1');
    final fetchedUserSecret = await meshagent.getUserSecret('secret-1', includeValue: true);
    await meshagent.listUserSecretProxyAccess('secret-1');
    await meshagent.grantUserSecretProxyAccess('secret-1', 'sa-1');
    await meshagent.revokeUserSecretProxyAccess('secret-1', 'sa-1');
    await meshagent.createServiceAccountSecret('proj_123', 'sa-1', name: 'pull', type: 'opaque');
    final fetchedServiceAccountSecret = await meshagent.getServiceAccountSecret('proj_123', 'sa-1', 'secret-1', includeValue: true);
    final serviceAccountVersionValue = await meshagent.accessServiceAccountSecretVersion('proj_123', 'sa-1', 'secret-1', 'version-1');
    await meshagent.deleteServiceAccountSecretVersion('proj_123', 'sa-1', 'secret-1', 'version-1');
    await meshagent.listServiceAccountPullSecrets('proj_123', 'sa-1');
    await meshagent.addServiceAccountPullSecret('proj_123', 'sa-1', 'secret-1');
    await meshagent.removeServiceAccountPullSecret('proj_123', 'sa-1', 'secret-1');

    expect(requests[0].method, 'POST');
    expect(requests[0].uri.toString(), 'http://example.test/accounts/users/me/secrets');
    expect(requests[0].body, containsPair('project_id', 'proj_123'));
    expect(requests[0].body, containsPair('http_only', true));
    expect(
      requests[1].uri.toString(),
      'http://example.test/accounts/users/me/secrets?page_size=10&continuation_token=cursor&filter=github',
    );
    expect(requests[2].uri.toString(), 'http://example.test/accounts/users/me/secrets:search');
    expect(requests[2].body, {'page_size': 5, 'name': 'github', 'http_only': true});
    expect(requests[3].body, {'value_base64': 'AQID', 'set_current': false});
    expect(userVersionValue, orderedEquals(utf8.encode('value')));
    expect(requests[4].method, 'GET');
    expect(requests[4].uri.toString(), 'http://example.test/accounts/users/me/secrets/secret-1/versions/version-1:access');
    expect(requests[5].method, 'DELETE');
    expect(requests[5].uri.toString(), 'http://example.test/accounts/users/me/secrets/secret-1/versions/version-1');
    expect(fetchedUserSecret.valueBase64, 'dmFsdWU=');
    expect(requests[6].uri.toString(), 'http://example.test/accounts/users/me/secrets/secret-1?include_value=true');
    expect(requests[8].body, {
      'subject': {'type': 'service_account', 'id': 'sa-1'},
    });
    expect(requests[10].uri.toString(), 'http://example.test/accounts/projects/proj_123/service-accounts/sa-1/secrets');
    expect(fetchedServiceAccountSecret.valueBase64, 'dmFsdWU=');
    expect(
      requests[11].uri.toString(),
      'http://example.test/accounts/projects/proj_123/service-accounts/sa-1/secrets/secret-1?include_value=true',
    );
    expect(serviceAccountVersionValue, orderedEquals(utf8.encode('value')));
    expect(requests[12].method, 'GET');
    expect(
      requests[12].uri.toString(),
      'http://example.test/accounts/projects/proj_123/service-accounts/sa-1/secrets/secret-1/versions/version-1:access',
    );
    expect(requests[13].method, 'DELETE');
    expect(
      requests[13].uri.toString(),
      'http://example.test/accounts/projects/proj_123/service-accounts/sa-1/secrets/secret-1/versions/version-1',
    );
    expect(requests[14].uri.toString(), 'http://example.test/accounts/projects/proj_123/service-accounts/sa-1/pull-secrets');
    expect(requests[15].method, 'PUT');
    expect(requests[15].uri.toString(), 'http://example.test/accounts/projects/proj_123/service-accounts/sa-1/pull-secrets/secret-1');
    expect(requests[16].method, 'DELETE');
    expect(requests[16].uri.toString(), 'http://example.test/accounts/projects/proj_123/service-accounts/sa-1/pull-secrets/secret-1');
  });

  test('external oauth registration methods are removed from the client', () {
    final dynamic meshagent = Meshagent(
      baseUrl: 'http://example.test',
      token: 'test-token',
      client: MockClient((_) async => http.Response('{}', 200)),
    );

    expect(() => meshagent.createProjectExternalOAuthRegistration(projectId: 'proj_123'), throwsA(isA<NoSuchMethodError>()));
    expect(() => meshagent.updateProjectExternalOAuthRegistration(projectId: 'proj_123'), throwsA(isA<NoSuchMethodError>()));
    expect(() => meshagent.listProjectExternalOAuthRegistrations(projectId: 'proj_123'), throwsA(isA<NoSuchMethodError>()));
    expect(() => meshagent.deleteProjectExternalOAuthRegistration(projectId: 'proj_123'), throwsA(isA<NoSuchMethodError>()));
    expect(() => meshagent.createRoomExternalOAuthRegistration(projectId: 'proj_123'), throwsA(isA<NoSuchMethodError>()));
    expect(() => meshagent.updateRoomExternalOAuthRegistration(projectId: 'proj_123'), throwsA(isA<NoSuchMethodError>()));
    expect(() => meshagent.listRoomExternalOAuthRegistrations(projectId: 'proj_123'), throwsA(isA<NoSuchMethodError>()));
    expect(() => meshagent.deleteRoomExternalOAuthRegistration(projectId: 'proj_123'), throwsA(isA<NoSuchMethodError>()));
  });
}

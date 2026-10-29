import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meshagent/meshagent.dart';
import 'package:test/test.dart';

void main() {
  test('room CRUD scopes requests and omits unchanged credentials', () async {
    final requests = <http.Request>[];
    final connection = {
      'id': 'connection-1',
      'room_id': 'room-1',
      'name': 'warehouse',
      'config': {'provider': 's3', 'bucket': 'test-bucket', 'region': 'us-east-1', 'prefix': 'datasets'},
      'revision': 1,
      'created_at': '2026-10-29T00:00:00Z',
      'updated_at': '2026-10-29T00:00:00Z',
    };
    final client = Meshagent(
      baseUrl: 'http://localhost',
      token: 'test-token',
      client: MockClient((request) async {
        requests.add(request);
        expect(request.url.pathSegments.take(6), ['accounts', 'projects', 'project-1', 'rooms', 'test room', 'storage-connections']);
        expect(request.headers['Authorization'], 'Bearer test-token');
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'connections': [connection],
            }),
            200,
          );
        }
        if (request.method == 'DELETE') return http.Response('', 204);
        return http.Response(jsonEncode(connection), 200);
      }),
    );
    addTearDown(client.close);
    final connections = await client.listRoomStorageConnections(projectId: 'project-1', roomName: 'test room');
    expect(connections.single.config, isA<S3StorageConfig>());
    expect(connections.single.config.location, 's3://test-bucket/datasets');
    const credentials = S3StorageCredentials(accessKeyId: 'access-id', secretAccessKey: 'secret');
    final created = await client.createRoomStorageConnection(
      projectId: 'project-1',
      roomName: 'test room',
      name: 'warehouse',
      config: connections.single.config,
      credentials: credentials,
    );
    await client.updateRoomStorageConnection(
      projectId: 'project-1',
      roomName: 'test room',
      connectionId: created.id,
      name: created.name,
      config: created.config,
    );
    await client.updateRoomStorageConnection(
      projectId: 'project-1',
      roomName: 'test room',
      connectionId: created.id,
      name: created.name,
      config: created.config,
      credentials: credentials,
    );
    await client.deleteRoomStorageConnection(projectId: 'project-1', roomName: 'test room', connectionId: created.id);
    expect(requests.map((request) => request.method), ['GET', 'POST', 'PUT', 'PUT', 'DELETE']);
    expect(jsonDecode(requests[1].body)['credentials']['secret_access_key'], 'secret');
    expect((jsonDecode(requests[2].body) as Map).containsKey('credentials'), isFalse);
    expect(jsonDecode(requests[3].body)['credentials']['secret_access_key'], 'secret');
    expect(requests.last.url.pathSegments.last, created.id);
  });

  test('errors do not echo credential-bearing response bodies', () async {
    final client = Meshagent(
      baseUrl: 'http://localhost',
      token: 'test',
      client: MockClient((_) async => http.Response('secret-value', 400)),
    );
    addTearDown(client.close);
    await expectLater(
      client.createRoomStorageConnection(
        projectId: 'p',
        roomName: 'r',
        name: 'connection',
        config: const GCSStorageConfig(bucket: 'test-bucket'),
        credentials: const GCSStorageCredentials(serviceAccountJson: {'private_key': 'secret-value'}),
      ),
      throwsA(predicate((Object error) => error.toString().contains('400') && !error.toString().contains('secret-value'))),
    );
  });

  test('Azure auth variants and GCS JSON preserve wire format', () {
    expect(const AzureStorageCredentials.accountKey('key').toJson(), {'provider': 'azure', 'account_key': 'key', 'sas_token': null});
    expect(const AzureStorageCredentials.sasToken('sas').toJson(), {'provider': 'azure', 'account_key': null, 'sas_token': 'sas'});
    const config = AzureStorageConfig(account: 'account', container: 'container', prefix: 'prefix');
    expect(StorageConnectionConfig.fromJson(config.toJson()).toJson(), config.toJson());
    expect(const GCSStorageCredentials(serviceAccountJson: {'type': 'service_account'}).toJson()['service_account_json'], {
      'type': 'service_account',
    });
  });
}

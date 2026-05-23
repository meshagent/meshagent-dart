import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meshagent/meshagent.dart';
import 'package:test/test.dart';

void main() {
  test('getProjectByKey requests the project key endpoint', () async {
    final requests = <String>[];
    final client = MockClient((request) async {
      requests.add('${request.method} ${request.url}');
      return http.Response(jsonEncode({'id': 'proj_123', 'project_key': 'team/app'}), 200);
    });
    final meshagent = Meshagent(baseUrl: 'http://example.test', token: 'test-token', client: client);

    final project = await meshagent.getProjectByKey('team/app');

    expect(project, {'id': 'proj_123', 'project_key': 'team/app'});
    expect(requests, ['GET http://example.test/accounts/projects/by-key/team%2Fapp']);
  });

  test('createRoom serializes ApiScope permissions', () async {
    Map<String, dynamic>? body;
    final client = MockClient((request) async {
      body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(jsonEncode({'id': 'room-1', 'name': 'demo', 'metadata': {}, 'annotations': {}}), 200);
    });
    final meshagent = Meshagent(baseUrl: 'http://example.test', token: 'test-token', client: client);

    await meshagent.createRoom(projectId: 'proj_123', name: 'demo', permissions: {'user-1': ApiScope.full()});

    expect(body, containsPair('name', 'demo'));
    expect(body, containsPair('if_not_exists', false));
    expect(body?['permissions'], isA<Map<String, dynamic>>());
    expect((body?['permissions'] as Map<String, dynamic>)['user-1'], containsPair('admin', <String, dynamic>{}));
  });
}

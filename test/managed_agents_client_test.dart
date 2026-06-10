import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meshagent/meshagent.dart';
import 'package:test/test.dart';

void main() {
  test('createAgent omits null permissions', () async {
    Map<String, dynamic>? body;
    final client = MockClient((request) async {
      body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'id': 'agent-1',
          'name': 'chatbot',
          'configuration': {'name': 'chatbot'},
        }),
        200,
      );
    });
    final meshagent = Meshagent(baseUrl: 'http://example.test', token: 'test-token', client: client);

    await meshagent.createAgent(projectId: 'proj_123', configuration: {'name': 'chatbot'});

    expect(body, {
      'configuration': {'name': 'chatbot'},
      'if_not_exists': false,
    });
  });

  test('agent policy methods send IAM payloads', () async {
    final requests = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      requests.add({
        'method': request.method,
        'url': request.url.toString(),
        'body': request.body.isEmpty ? null : jsonDecode(request.body),
      });
      if (request.method == 'GET') {
        return http.Response(
          jsonEncode({
            'resource': {'type': 'agent', 'id': 'agent-1', 'name': 'planner'},
            'access_grants': [
              {
                'resource': {'type': 'agent', 'id': 'agent-1', 'name': 'planner'},
                'subject': {'type': 'user', 'id': 'user-1'},
                'direct_roles': ['operator', 'list'],
              },
            ],
            'continuation_token': 'next-token',
          }),
          200,
        );
      }
      return http.Response('{}', 200);
    });
    final meshagent = Meshagent(baseUrl: 'http://example.test', token: 'test-token', client: client);

    await meshagent.grantResourcePolicy(
      projectId: 'proj_123',
      resourceType: 'agent',
      resourceId: 'agent-1',
      subject: const AccessSubject(type: 'user', id: 'user-1'),
      roles: const ['operator', 'list'],
    );
    await meshagent.grantResourcePolicy(
      projectId: 'proj_123',
      resourceType: 'agent',
      resourceId: 'agent-1',
      subject: const AccessSubject(type: 'group', id: 'group-1'),
      roles: const ['viewer', 'list'],
    );
    final page = await meshagent.getResourcePolicyPage(
      projectId: 'proj_123',
      resourceType: 'agent',
      resourceId: 'agent-1',
      continuationToken: 'cursor-1',
    );
    await meshagent.revokeResourcePolicy(
      projectId: 'proj_123',
      resourceType: 'agent',
      resourceId: 'agent-1',
      subject: const AccessSubject(type: 'user', id: 'user-1'),
    );

    expect(page.continuationToken, 'next-token');
    expect(requests[0]['body'], {
      'subject': {'type': 'user', 'id': 'user-1'},
      'roles': ['operator', 'list'],
    });
    expect(requests[1]['body'], {
      'subject': {'type': 'group', 'id': 'group-1'},
      'roles': ['viewer', 'list'],
    });
    expect(
      requests[2]['url'],
      'http://example.test/accounts/projects/proj_123/iam/agent/agent-1/policy?page_size=50&continuation_token=cursor-1',
    );
    expect(requests[3]['url'], 'http://example.test/accounts/projects/proj_123/iam/agent/agent-1/policy:revoke');
    for (final request in requests.take(2)) {
      expect(request['body'], isNot(contains('permissions')));
      expect(request['body'], isNot(contains('user_id')));
    }
  });

  test('RoomSession omits null managed-agent fields', () {
    final session = RoomSession(
      id: 'session-1',
      roomId: 'room-1',
      roomName: 'general',
      createdAt: DateTime.parse('2026-05-15T12:00:00Z'),
      isActive: true,
      participants: null,
    );

    expect(session.toJson(), {
      'id': 'session-1',
      'room_id': 'room-1',
      'room_name': 'general',
      'started_at': '2026-05-15T12:00:00.000Z',
      'is_active': true,
      'kind': 'room',
    });
  });
}

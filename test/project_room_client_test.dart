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

  test('createRoom does not serialize permission grants', () async {
    Map<String, dynamic>? body;
    final client = MockClient((request) async {
      body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(jsonEncode({'id': 'room-1', 'name': 'demo', 'metadata': {}, 'annotations': {}}), 200);
    });
    final meshagent = Meshagent(baseUrl: 'http://example.test', token: 'test-token', client: client);

    await meshagent.createRoom(projectId: 'proj_123', name: 'demo');

    expect(body, containsPair('name', 'demo'));
    expect(body, containsPair('if_not_exists', false));
    expect(body, isNot(contains('permissions')));
  });

  test('listRooms sends view query when provided', () async {
    final requests = <String>[];
    final client = MockClient((request) async {
      requests.add('${request.method} ${request.url}');
      return http.Response(jsonEncode({'rooms': [], 'total': 0}), 200);
    });
    final meshagent = Meshagent(baseUrl: 'http://example.test', token: 'test-token', client: client);

    final rooms = await meshagent.listRooms(projectId: 'proj_123', view: 'all');

    expect(rooms, isEmpty);
    expect(requests, ['GET http://example.test/accounts/projects/proj_123/rooms?page_size=100&view=all']);
  });

  test('project members page returns typed OpenFGA member rows', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'users': [
            {
              'user': {'id': 'user-1', 'email': 'ada@example.test', 'first_name': 'Ada', 'last_name': 'Lovelace'},
              'direct_roles': ['member', 'admin', 'room_creator'],
            },
          ],
          'continuation_token': 'next-token',
        }),
        200,
      );
    });
    final meshagent = Meshagent(baseUrl: 'http://example.test', token: 'test-token', client: client);

    final page = await meshagent.getUsersInProjectPage('proj_123');
    final member = page.users.single;

    expect(page.continuationToken, 'next-token');
    expect(member.id, 'user-1');
    expect(member.email, 'ada@example.test');
    expect(member.firstName, 'Ada');
    expect(member.lastName, 'Lovelace');
    expect(member.directRoles, ['member', 'admin', 'room_creator']);
  });

  test('room policy methods send IAM payloads', () async {
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
            'resource': {'type': 'room', 'id': 'room-1', 'name': 'demo', 'metadata': {}, 'annotations': {}},
            'access_grants': [
              {
                'resource': {'type': 'room', 'id': 'room-1', 'name': 'demo', 'metadata': {}, 'annotations': {}},
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
      resourceType: 'room',
      resourceId: 'room-1',
      subject: const AccessSubject(type: 'user', id: 'user-1'),
      roles: const ['operator', 'list'],
    );
    await meshagent.grantResourcePolicy(
      projectId: 'proj_123',
      resourceType: 'room',
      resourceId: 'room-1',
      subject: const AccessSubject(type: 'group', id: 'group-1'),
      roles: const ['viewer', 'list'],
    );
    final page = await meshagent.getResourcePolicyPage(
      projectId: 'proj_123',
      resourceType: 'room',
      resourceId: 'room-1',
      continuationToken: 'cursor-1',
    );
    await meshagent.revokeResourcePolicy(
      projectId: 'proj_123',
      resourceType: 'room',
      resourceId: 'room-1',
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
      'http://example.test/accounts/projects/proj_123/iam/room/room-1/policy?page_size=50&continuation_token=cursor-1',
    );
    expect(requests[3]['url'], 'http://example.test/accounts/projects/proj_123/iam/room/room-1/policy:revoke');
    for (final request in requests.take(2)) {
      expect(request['body'], isNot(contains('permissions')));
      expect(request['body'], isNot(contains('user_id')));
    }
  });

  test('access evaluator methods post subject resource and relation payloads', () async {
    final requests = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      requests.add({
        'method': request.method,
        'url': request.url.toString(),
        'body': request.body.isEmpty ? null : jsonDecode(request.body),
      });
      if (request.url.path.endsWith('/access:test')) {
        return http.Response(jsonEncode({'allowed': true, 'relation': 'can_use'}), 200);
      }
      if (request.url.path.endsWith('/access:bindings')) {
        return http.Response(
          jsonEncode({
            'access_grants': [
              {
                'resource': {'type': 'room', 'id': 'room-1', 'name': 'demo'},
                'subject': {'type': 'user', 'id': 'user-1'},
                'direct_roles': ['operator'],
              },
              {
                'resource': {'type': 'agent', 'id': 'agent-1', 'name': 'planner'},
                'subject': {'type': 'user', 'id': 'user-1'},
                'direct_roles': ['viewer'],
              },
            ],
            'continuation_token': 'next-access',
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'resource': {'type': 'room', 'id': 'room-1', 'name': 'demo'},
          'subject': {'type': 'user', 'id': 'user-1'},
          'effective_roles': ['developer'],
          'capabilities': {'can_use': true, 'can_manage': false},
        }),
        200,
      );
    });
    final meshagent = Meshagent(baseUrl: 'http://example.test', token: 'test-token', client: client);

    final testResult = await meshagent.testAccess(
      projectId: 'proj_123',
      subject: const AccessSubject(type: 'user', id: 'user-1'),
      resource: const AccessResource(type: 'room', id: 'room-1'),
      relation: 'can_use',
    );
    final effective = await meshagent.getEffectiveAccess(
      projectId: 'proj_123',
      subject: const AccessSubject(type: 'user', id: 'user-1'),
      resource: const AccessResource(type: 'room', id: 'room-1'),
      relations: const ['can_use', 'can_manage'],
    );
    final bindings = await meshagent.listAccessBindingsPage(
      projectId: 'proj_123',
      subject: const AccessSubject(type: 'user', id: 'user-1'),
    );
    await meshagent.grantResourcePolicy(
      projectId: 'proj_123',
      resourceType: 'room',
      resourceId: 'room-1',
      subject: const AccessSubject(type: 'userset', id: 'proj_123', objectType: 'project', relation: 'member'),
      roles: const ['viewer', 'list'],
    );

    expect(testResult.allowed, isTrue);
    expect(effective.effectiveRoles, ['developer']);
    expect(effective.capabilities, {'can_use': true, 'can_manage': false});
    expect(bindings.continuationToken, 'next-access');
    expect(bindings.accessGrants.map((grant) => grant.resource.type).toList(), ['room', 'agent']);
    expect(bindings.accessGrants.first.directRoles, ['operator']);
    expect(requests[0]['url'], 'http://example.test/accounts/projects/proj_123/access:test');
    expect(requests[0]['body'], {
      'subject': {'type': 'user', 'id': 'user-1'},
      'resource': {'type': 'room', 'id': 'room-1'},
      'relation': 'can_use',
    });
    expect(requests[1]['url'], 'http://example.test/accounts/projects/proj_123/access:effective');
    expect(requests[2]['url'], 'http://example.test/accounts/projects/proj_123/access:bindings');
    expect(requests[2]['body'], {
      'subject': {'type': 'user', 'id': 'user-1'},
    });
    expect(requests[3]['body'], {
      'subject': {'type': 'userset', 'id': 'proj_123', 'object_type': 'project', 'relation': 'member'},
      'roles': ['viewer', 'list'],
    });
  });

  test('project role enum exposes typed relation values for generic access checks', () {
    expect(ProjectRole.billingManager.relation, ProjectRoles.billingManager);
    expect(ProjectRole.usageReporter.relation, ProjectRoles.usageReporter);
    expect(ProjectRole.llmProxyUser.relation, ProjectRoles.llmProxyUser);
    expect(ProjectRole.fromRelation('billing_manager'), ProjectRole.billingManager);
    expect(ProjectRole.fromRelation('not_a_role'), ProjectRole.none);
    expect(ProjectRole.assignable.map((role) => role.relation), containsAll(ProjectRoles.all));
  });

  test('group methods send group resources and subject payloads', () async {
    final requests = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      requests.add({
        'method': request.method,
        'url': request.url.toString(),
        'body': request.body.isEmpty ? null : jsonDecode(request.body),
      });
      if (request.method == 'GET' && request.url.path.endsWith('/groups/group-1/members')) {
        return http.Response(
          jsonEncode({
            'members': [
              {
                'subject': {'type': 'user', 'id': 'user-1', 'email': 'dev@example.com'},
                'direct_roles': ['member', 'manager'],
              },
              {
                'subject': {'type': 'agent', 'id': 'agent-1', 'name': 'planner'},
                'direct_roles': ['member'],
              },
              {
                'subject': {'type': 'group', 'id': 'group-child', 'name': 'child group'},
                'direct_roles': ['member'],
              },
            ],
            'continuation_token': 'next-member',
          }),
          200,
        );
      }
      if (request.method == 'GET' && request.url.path.endsWith('/groups')) {
        return http.Response(
          jsonEncode({
            'groups': [
              {'id': 'group-1', 'name': 'developers', 'metadata': {}, 'annotations': {}},
            ],
            'continuation_token': 'next-group',
          }),
          200,
        );
      }
      if (request.method == 'POST' && request.url.path.endsWith('/groups')) {
        return http.Response(jsonEncode({'id': 'group-1', 'name': 'developers', 'metadata': {}, 'annotations': {}}), 200);
      }
      return http.Response('{}', 200);
    });
    final meshagent = Meshagent(baseUrl: 'http://example.test', token: 'test-token', client: client);

    final group = await meshagent.createGroup(
      projectId: 'proj_123',
      name: 'developers',
      metadata: {'color': 'blue'},
      annotations: {'owner': 'platform'},
    );
    await meshagent.updateGroup(projectId: 'proj_123', groupId: 'group-1', name: 'operators');
    final page = await meshagent.listGroupsPage(projectId: 'proj_123', continuationToken: 'cursor-1');
    await meshagent.setGroupMember(
      projectId: 'proj_123',
      groupId: 'group-1',
      subject: const AccessSubject(type: 'group', id: 'group-child'),
      role: 'manager',
    );
    final members = await meshagent.listGroupMembersPage(projectId: 'proj_123', groupId: 'group-1', continuationToken: 'member-cursor');
    await meshagent.deleteGroupMember(projectId: 'proj_123', groupId: 'group-1', subjectType: 'agent', subjectId: 'agent-1');
    await meshagent.deleteGroup(projectId: 'proj_123', groupId: 'group-1');

    expect(group.id, 'group-1');
    expect(page.continuationToken, 'next-group');
    expect(members.continuationToken, 'next-member');
    expect(members.members[0].subject.email, 'dev@example.com');
    expect(members.members[0].directRoles, ['member', 'manager']);
    expect(members.members[1].subject.type, 'agent');
    expect(members.members[2].subject.type, 'group');
    expect(requests.map((request) => '${request['method']} ${request['url']}'), [
      'POST http://example.test/accounts/projects/proj_123/groups',
      'PUT http://example.test/accounts/projects/proj_123/groups/group-1',
      'GET http://example.test/accounts/projects/proj_123/groups?page_size=50&continuation_token=cursor-1',
      'POST http://example.test/accounts/projects/proj_123/groups/group-1/members',
      'GET http://example.test/accounts/projects/proj_123/groups/group-1/members?page_size=50&continuation_token=member-cursor',
      'DELETE http://example.test/accounts/projects/proj_123/groups/group-1/members/agent/agent-1',
      'DELETE http://example.test/accounts/projects/proj_123/groups/group-1',
    ]);
    expect(requests[0]['body'], {
      'name': 'developers',
      'metadata': {'color': 'blue'},
      'annotations': {'owner': 'platform'},
    });
    expect(requests[3]['body'], {
      'subject': {'type': 'group', 'id': 'group-child'},
      'role': 'manager',
    });
  });

  test('service account methods return typed rows and scope API keys', () async {
    final requests = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      requests.add({
        'method': request.method,
        'url': request.url.toString(),
        'body': request.body.isEmpty ? null : jsonDecode(request.body),
      });
      if (request.method == 'GET' && request.url.path.endsWith('/service-accounts')) {
        return http.Response(
          jsonEncode({
            'service_accounts': [
              {
                'id': 'service-account-1',
                'project_id': 'proj_123',
                'key': 'builder',
                'name': 'builder',
                'display_name': 'Builder',
                'email': 'builder@service.demo.example.test',
                'description': 'Build automation',
                'metadata': {'display_name': 'Builder Metadata', 'env': 'ci'},
                'annotations': {'owner': 'platform'},
                'created_at': '2026-01-01T00:00:00Z',
                'updated_at': '2026-01-02T00:00:00Z',
                'created_by_user_id': 'user-1',
              },
            ],
            'continuation_token': 'next-service-account',
          }),
          200,
        );
      }
      if (request.method == 'POST' && request.url.path.endsWith('/service-accounts')) {
        return http.Response(
          jsonEncode({
            'id': 'service-account-1',
            'project_id': 'proj_123',
            'key': 'builder',
            'name': 'builder',
            'display_name': 'Builder',
            'description': 'Build automation',
            'metadata': {},
            'annotations': {},
            'created_at': '2026-01-01T00:00:00Z',
            'updated_at': '2026-01-01T00:00:00Z',
          }),
          200,
        );
      }
      if (request.method == 'POST' && request.url.path.endsWith('/api-keys')) {
        return http.Response(
          jsonEncode({'id': 'key-1', 'name': 'ci', 'description': 'CI', 'value': 'secret', 'service_account_id': 'service-account-1'}),
          200,
        );
      }
      return http.Response('{}', 200);
    });
    final meshagent = Meshagent(baseUrl: 'http://example.test', token: 'test-token', client: client);

    final page = await meshagent.listServiceAccountsPage('proj_123', continuationToken: 'cursor-1', filter: 'build', view: 'all');
    final created = await meshagent.createServiceAccount(
      'proj_123',
      'builder',
      displayName: 'Builder',
      description: 'Build automation',
      metadata: {'env': 'ci'},
      annotations: {'owner': 'platform'},
    );
    await meshagent.updateServiceAccount('proj_123', 'service-account-1', name: 'builder-renamed');
    await meshagent.deleteServiceAccount('proj_123', 'service-account-1');
    final key = await meshagent.createApiKey('proj_123', 'service-account-1', 'ci', 'CI');

    expect(page.continuationToken, 'next-service-account');
    expect(page.serviceAccounts.single.id, 'service-account-1');
    expect(
      requests.first['url'],
      'http://example.test/accounts/projects/proj_123/service-accounts?page_size=100&continuation_token=cursor-1&filter=build&view=all',
    );
    expect(page.serviceAccounts.single.displayName, 'Builder Metadata');
    expect(page.serviceAccounts.single.email, 'builder@service.demo.example.test');
    expect(page.serviceAccounts.single.metadata, {'display_name': 'Builder Metadata', 'env': 'ci'});
    expect(created.name, 'builder');
    expect(key.serviceAccountId, 'service-account-1');
    expect(requests.map((request) => '${request['method']} ${request['url']}'), [
      'GET http://example.test/accounts/projects/proj_123/service-accounts?page_size=100&continuation_token=cursor-1&filter=build',
      'POST http://example.test/accounts/projects/proj_123/service-accounts',
      'PUT http://example.test/accounts/projects/proj_123/service-accounts/service-account-1',
      'DELETE http://example.test/accounts/projects/proj_123/service-accounts/service-account-1',
      'POST http://example.test/accounts/projects/proj_123/service-accounts/service-account-1/api-keys',
    ]);
    expect(requests[1]['body'], {
      'name': 'builder',
      'display_name': 'Builder',
      'description': 'Build automation',
      'metadata': {'env': 'ci'},
      'annotations': {'owner': 'platform'},
    });
    expect(requests[2]['body'], {'name': 'builder-renamed'});
  });

  test('resolve subject returns typed service account subjects', () async {
    final requests = <String>[];
    final client = MockClient((request) async {
      requests.add(request.url.toString());
      return http.Response(
        jsonEncode({'type': 'service_account', 'id': 'service-account-1', 'name': 'Builder', 'email': 'builder@service.demo.example.test'}),
        200,
      );
    });
    final meshagent = Meshagent(baseUrl: 'http://example.test', token: 'test-token', client: client);

    final subject = await meshagent.resolveSubject('proj_123', 'builder@service.demo.example.test');

    expect(subject.type, 'service_account');
    expect(subject.id, 'service-account-1');
    expect(subject.name, 'Builder');
    expect(subject.email, 'builder@service.demo.example.test');
    expect(requests.single, 'http://example.test/accounts/projects/proj_123/subjects:resolve?email=builder%40service.demo.example.test');
  });

  test('agent room policy uses room policy with agent subject', () async {
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
            'resource': {'type': 'room', 'id': 'room-1', 'name': 'demo', 'metadata': {}, 'annotations': {}},
            'access_grants': [
              {
                'resource': {'type': 'room', 'id': 'room-1', 'name': 'demo', 'metadata': {}, 'annotations': {}},
                'subject': {'type': 'agent', 'id': 'agent-1', 'name': 'planner'},
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
      resourceType: 'room',
      resourceId: 'room-1',
      subject: const AccessSubject(type: 'agent', id: 'agent-1'),
      roles: const ['operator', 'list'],
    );
    await meshagent.grantResourcePolicy(
      projectId: 'proj_123',
      resourceType: 'room',
      resourceId: 'room-1',
      subject: const AccessSubject(type: 'agent', id: 'agent-1'),
      roles: const ['admin', 'list'],
    );
    final page = await meshagent.getResourcePolicyPage(
      projectId: 'proj_123',
      resourceType: 'room',
      resourceId: 'room-1',
      continuationToken: 'cursor-1',
    );

    expect(page.continuationToken, 'next-token');
    expect(requests[0]['body'], {
      'subject': {'type': 'agent', 'id': 'agent-1'},
      'roles': ['operator', 'list'],
    });
    expect(requests[1]['body'], {
      'subject': {'type': 'agent', 'id': 'agent-1'},
      'roles': ['admin', 'list'],
    });
    expect(
      requests[2]['url'],
      'http://example.test/accounts/projects/proj_123/iam/room/room-1/policy?page_size=50&continuation_token=cursor-1',
    );
    for (final request in requests.take(2)) {
      expect(request['body'], isNot(contains('permissions')));
    }
  });

  test('setGroupMember exposes structured error details', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'error': {'code': 'group_self_membership', 'message': 'A group cannot be a member of itself.'},
        }),
        400,
      );
    });
    final meshagent = Meshagent(baseUrl: 'http://example.test', token: 'test-token', client: client);

    try {
      await meshagent.setGroupMember(
        projectId: 'proj_123',
        groupId: 'group-1',
        subject: const AccessSubject(type: 'group', id: 'group-1'),
      );
      fail('setGroupMember should throw');
    } on MeshagentException catch (error) {
      expect(error.statusCode, 400);
      expect(error.errorCode, 'group_self_membership');
      expect(error.errorMessage, 'A group cannot be a member of itself.');
      expect(error.displayMessage, 'A group cannot be a member of itself.');
    }
  });
}

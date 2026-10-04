import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meshagent/meshagent.dart';
import 'package:test/test.dart';

void main() {
  test('updateUserProfile preserves omitted fields and accepts editor context', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response(jsonEncode({'ok': true}), 200);
    });
    final meshagent = Meshagent(baseUrl: 'http://example.test', token: 'test-token', client: client);
    await meshagent.updateUserProfile('me', null, null, metadata: {});
    await meshagent.updateUserProfile(
      'user-2',
      'Grace',
      'Hopper',
      metadata: {
        'nested': {'active': true},
      },
      annotations: {'department': 'research'},
      projectId: 'project-1',
    );
    expect(jsonDecode(requests[0].body), {'metadata': {}});
    expect(requests[1].url.path, '/accounts/projects/project-1/users/user-2/profile');
    expect(requests[1].url.queryParameters, isEmpty);
    expect(jsonDecode(requests[1].body), {
      'first_name': 'Grace',
      'last_name': 'Hopper',
      'metadata': {
        'nested': {'active': true},
      },
      'annotations': {'department': 'research'},
    });
  });

  test('project member retains metadata, annotations and editor role', () {
    final member = ProjectMember.fromJson({
      'user': {
        'id': 'user-1',
        'email': 'ada@example.test',
        'metadata': {'active': true},
        'annotations': {'department': 'research'},
      },
      'direct_roles': ['member', 'user_profile_editor'],
    });
    expect(member.metadata, {'active': true});
    expect(member.annotations, {'department': 'research'});
    expect(ProjectMember.fromJson(member.toJson()).annotations, member.annotations);
    expect(ProjectRoles.all, contains('user_profile_editor'));
    expect(ProjectRole.fromRelation('user_profile_editor'), ProjectRole.userProfileEditor);
  });

  test('getUserProfile throws ForbiddenException on 403', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), 'http://example.test/accounts/profiles/me');
      return http.Response(jsonEncode({'error': 'forbidden'}), 403);
    });

    final meshagent = Meshagent(baseUrl: 'http://example.test', token: 'test-token', client: client);

    await expectLater(meshagent.getUserProfile('me'), throwsA(isA<ForbiddenException>()));
  });
  test('project views preserve absent and explicitly cleared names', () async {
    final requests = <http.Request>[];
    final meshagent = Meshagent(
      baseUrl: 'http://example.test',
      token: 'test-token',
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(jsonEncode({'id': 'user-1', 'email': 'a@example.test', 'first_name': null}), 200);
      }),
    );
    final profile = await meshagent.getUserProfile('user-1', projectId: 'project-1', view: UserProfileView.project);
    expect(profile.containsKey('last_name'), isFalse);
    expect(profile.containsKey('first_name'), isTrue);
    expect(profile['first_name'], isNull);
    expect(requests.single.url.path, '/accounts/projects/project-1/users/user-1/profile');
    expect(requests.single.url.queryParameters, {'view': 'project'});
    await meshagent.updateUserProfile(
      'user-1',
      null,
      null,
      projectId: 'project-1',
      inherit: [UserProfileField.firstName, UserProfileField.metadata],
    );
    expect(jsonDecode(requests.last.body), {
      'inherit': ['first_name', 'metadata'],
    });
  });

  test('sysadmin requests propagate access denials', () async {
    final meshagent = Meshagent(
      baseUrl: 'http://example.test',
      token: 'test-token',
      client: MockClient((request) async => http.Response('forbidden', 403)),
    );
    await expectLater(meshagent.searchSysadminUsers(), throwsA(isA<ForbiddenException>()));
    await expectLater(meshagent.getSysadminUserProfile('user-1'), throwsA(isA<ForbiddenException>()));
    await expectLater(meshagent.updateSysadminUserProfile('user-1', annotations: {}), throwsA(isA<ForbiddenException>()));
  });
}

import 'package:meshagent/meshagent.dart';
import 'package:test/test.dart';

void main() {
  test('fullOAuthScope matches the shared scope list', () {
    expect(fullOAuthScope, fullOAuthScopes.join(' '));
  });

  test('fullOAuthScopes are unique and non-empty', () {
    expect(fullOAuthScopes.toSet(), hasLength(fullOAuthScopes.length));
    expect(fullOAuthScopes.every((scope) => scope.trim() == scope && scope.isNotEmpty), isTrue);
  });

  test('fullOAuthScopes matches the official scope set', () {
    expect(fullOAuthScopes, <String>[
      'profile:read',
      'profile:write',
      'project/*',
      'room/*',
      'users:create',
      'users:read',
      'users:update',
      'users:delete',
      'projects:read',
      'projects:update',
      'projects:iam.read',
      'projects:iam.write',
      'projects:billing.read',
      'projects:billing.write',
      'rooms:create',
      'rooms:read',
      'rooms:connect',
      'rooms:update',
      'rooms:delete',
      'agents:create',
      'agents:read',
      'agents:update',
      'agents:delete',
      'agents:run',
      'agents:sessions.read',
      'mailboxes:create',
      'mailboxes:read',
      'mailboxes:update',
      'mailboxes:delete',
      'routes:create',
      'routes:read',
      'routes:update',
      'routes:delete',
      'scheduledTasks:create',
      'scheduledTasks:read',
      'scheduledTasks:update',
      'scheduledTasks:delete',
      'services:create',
      'services:read',
      'services:update',
      'services:delete',
      'repositories:create',
      'repositories:read',
      'repositories:update',
      'repositories:delete',
      'apiKeys:create',
      'apiKeys:read',
      'apiKeys:delete',
      'serviceAccounts:create',
      'serviceAccounts:read',
      'serviceAccounts:update',
      'serviceAccounts:delete',
      'oauthClients:create',
      'oauthClients:read',
      'oauthClients:update',
      'oauthClients:delete',
      'llm:invoke',
      'llm:usage.read',
      'llm:logs.read',
      'llm:logs.write',
      'secrets:read',
      'secrets:write',
      'secrets:delete',
      'secrets:grant',
      'secrets:proxy',
    ]);
  });

  for (final scope in fullOAuthScopes) {
    test('fullOAuthScope includes $scope', () {
      expect(fullOAuthScope.split(' '), contains(scope));
    });
  }
}

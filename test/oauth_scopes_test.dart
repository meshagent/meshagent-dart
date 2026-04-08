import 'package:meshagent/meshagent.dart';
import 'package:test/test.dart';

void main() {
  test('fullOAuthScope matches the shared scope list', () {
    expect(fullOAuthScope, fullOAuthScopes.join(' '));
  });

  test('fullOAuthScopes matches the official scope set', () {
    expect(fullOAuthScopes, <String>[
      'profile',
      'project/*',
      'room/*',
      'create_users',
      'create_rooms',
      'admin',
      'developer',
      'connect_room',
      'delete_room',
      'update_room',
    ]);
  });
}

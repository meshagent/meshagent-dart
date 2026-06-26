import 'package:meshagent/participant_token.dart';
import 'package:test/test.dart';

void main() {
  group('ApiScope defaults', () {
    test('exclude legacy room secrets grant', () {
      expect(ApiScope.agentDefault().secrets, isNull);
      expect(ApiScope.userDefault().secrets, isNull);
      expect(ApiScope.full().secrets, isNull);
    });

    test('include sqlite grant in standard scopes', () {
      expect(ApiScope.agentDefault().sqlite, isA<SqliteGrant>());
      expect(ApiScope.userDefault().sqlite, isA<SqliteGrant>());
      expect(ApiScope.full().sqlite, isA<SqliteGrant>());
    });

    test('sqlite grant supports database and table namespace matching', () {
      var grant = SqliteGrant();
      expect(grant.canCreateDatabase(), isTrue);
      expect(grant.canListDatabases(), isTrue);
      expect(grant.canRead('app', 'users'), isTrue);
      expect(grant.canWrite('app', 'users'), isTrue);

      grant = SqliteGrant(
        createDatabase: false,
        databases: [
          SqliteDatabaseGrant(
            name: 'app',
            namespace: ['analytics'],
            createTable: false,
            drop: false,
            inspect: true,
            listTables: true,
            execute: false,
            tables: [
              SqliteTableGrant(database: 'app', table: 'users', namespace: ['analytics'], read: true, write: false, alter: false),
            ],
          ),
        ],
      );

      expect(grant.canCreateDatabase(), isFalse);
      expect(grant.canInspectDatabase('app', namespace: ['analytics']), isTrue);
      expect(grant.canExecute('app', namespace: ['analytics']), isFalse);
      expect(grant.canRead('app', 'users', namespace: ['analytics']), isTrue);
      expect(grant.canWrite('app', 'users', namespace: ['analytics']), isFalse);
      expect(grant.canRead('app', 'users', namespace: ['other']), isFalse);
    });

    test('reject legacy oauth token request grant', () {
      expect(
        () => SecretsGrant.fromJson({
          'request_oauth_token': [
            {'endpoint': 'https://accounts.example/authorize', 'client_id': 'client-1'},
          ],
        }),
        throwsFormatException,
      );
    });
  });
}

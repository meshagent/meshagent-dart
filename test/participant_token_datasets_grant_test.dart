import 'package:meshagent/participant_token.dart';
import 'package:test/test.dart';

void main() {
  group('DatasetGrant', () {
    test('allows all operations when no table restrictions are configured', () {
      final grant = DatasetGrant();

      expect(grant.canRead('tbl'), isTrue);
      expect(grant.canWrite('tbl'), isTrue);
      expect(grant.canAlter('tbl'), isTrue);
      expect(grant.canAccess('tbl'), isTrue);
    });

    test('enforces table and namespace-scoped permissions', () {
      final grant = DatasetGrant(
        tables: [
          TableGrant(name: 'read_only', read: true, write: false, alter: false),
          TableGrant(name: 'write_only', namespace: ['analytics'], read: false, write: true, alter: false),
        ],
      );

      expect(grant.canRead('read_only'), isTrue);
      expect(grant.canWrite('read_only'), isFalse);

      expect(grant.canWrite('write_only', namespace: ['analytics']), isTrue);
      expect(grant.canWrite('write_only', namespace: ['default']), isFalse);
      expect(grant.canRead('write_only', namespace: ['analytics']), isFalse);
      expect(grant.canRead('unknown'), isFalse);
      expect(grant.canWrite('unknown'), isFalse);
      expect(grant.canAccess('unknown'), isFalse);
    });
  });
}

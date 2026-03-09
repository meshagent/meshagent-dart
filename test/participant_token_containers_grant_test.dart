import 'package:meshagent/participant_token.dart';
import 'package:test/test.dart';

void main() {
  group('ContainersGrant', () {
    test('allows all image operations when no restrictions are configured', () {
      final grant = ContainersGrant();

      expect(grant.canPull('repo/image'), isTrue);
      expect(grant.canRun('repo/image'), isTrue);
    });

    test('distinguishes exact matches from wildcard prefixes', () {
      final grant = ContainersGrant(pull: ['repo/image', 'lib/*'], run: ['runtime/app', 'tooling/*']);

      expect(grant.canPull('repo/image'), isTrue);
      expect(grant.canPull('repo/image-extra'), isFalse);
      expect(grant.canPull('lib/tool'), isTrue);
      expect(grant.canPull('other/tool'), isFalse);

      expect(grant.canRun('runtime/app'), isTrue);
      expect(grant.canRun('runtime/app-shell'), isFalse);
      expect(grant.canRun('tooling/bash'), isTrue);
      expect(grant.canRun('other/bash'), isFalse);
    });
  });
}

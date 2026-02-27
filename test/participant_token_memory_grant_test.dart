import 'package:meshagent/participant_token.dart';
import 'package:test/test.dart';

void main() {
  group('MemoryGrant', () {
    test('allows all memory operations when memories list is omitted', () {
      final grant = MemoryGrant();

      expect(grant.canCreate('profile'), isTrue);
      expect(grant.canQuery('profile'), isTrue);
      expect(grant.canRecall('profile'), isTrue);
      expect(grant.canOptimize('profile'), isTrue);
    });

    test('scopes access by memory name and namespace', () {
      final grant = MemoryGrant(
        list: true,
        memories: [
          MemoryEntryGrant(
            name: 'memories',
            namespace: ['agents', 'assistant'],
            permissions: const MemoryPermissions(
              create: true,
              drop: false,
              inspect: true,
              query: true,
              upsert: true,
              ingest: true,
              recall: true,
              optimize: false,
            ),
          ),
        ],
      );

      expect(grant.canCreate('memories', namespace: ['agents', 'assistant']), isTrue);
      expect(grant.canDrop('memories', namespace: ['agents', 'assistant']), isFalse);
      expect(grant.canOptimize('memories', namespace: ['agents', 'assistant']), isFalse);
      expect(grant.canQuery('memories', namespace: ['agents', 'other']), isFalse);
      expect(grant.canQuery('other', namespace: ['agents', 'assistant']), isFalse);
    });

    test('supports wildcard namespace when memory entry namespace is omitted', () {
      final grant = MemoryGrant(
        memories: [MemoryEntryGrant(name: 'memories', permissions: const MemoryPermissions(query: true))],
      );

      expect(grant.canQuery('memories', namespace: ['agents', 'assistant']), isTrue);
      expect(grant.canQuery('memories', namespace: ['agents', 'other']), isTrue);
      expect(grant.canQuery('other', namespace: ['agents', 'assistant']), isFalse);
    });
  });
}

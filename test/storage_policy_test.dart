import 'dart:convert';
import 'dart:io';

import 'package:meshagent/meshagent.dart';
import 'package:test/test.dart';

void main() {
  test('shared storage policy vectors round trip without expanding grants', () {
    final fixture = jsonDecode(File('../../testdata/files-permissions.json').readAsStringSync()) as Map<String, dynamic>;
    for (final (key, cases) in [('grant', 'cases'), ('legacy_grant', 'legacy_cases')]) {
      final grant = StorageGrant.fromJson((fixture[key] as Map).cast<String, dynamic>());
      var restored = StorageGrant.fromJson((jsonDecode(jsonEncode(grant.toJson())) as Map).cast<String, dynamic>());
      final participant = ParticipantToken(name: 'files-policy-test')..addApiGrant(ApiScope(storage: restored));
      const secret = 'files-policy-test-secret-at-least-32-bytes';
      restored = ParticipantToken.fromJwt(participant.toJwt(token: secret), token: secret).getApiGrant()!.storage!;
      for (final value in fixture[cases] as List) {
        final expected = (value as Map).cast<String, dynamic>();
        final path = expected['path'] as String;
        expect(
          {
            'read': restored.canRead(path),
            'write': restored.canWrite(path),
            'delete': restored.canDelete(path),
            'list': restored.canList(path),
            'list_directory': restored.canListDirectory(path),
            'presign': restored.canPresign(path),
            'read_tree': restored.canRead(path, subtree: true),
            'write_tree': restored.canWrite(path, subtree: true),
            'delete_tree': restored.canDelete(path, recursive: true),
          },
          Map.of(expected)..remove('path'),
          reason: '$key: $path',
        );
      }
    }
    expect(StorageGrant(files: FilesPolicy()).canRead('public/file'), isFalse);
    expect(StorageGrant(files: FilesPolicy()).canWrite('public/file'), isFalse);
    expect(StorageGrant().canPresign('file'), isFalse);
  });
}

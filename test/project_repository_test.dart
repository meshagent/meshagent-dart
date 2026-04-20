import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meshagent/meshagent.dart';
import 'package:test/test.dart';

void main() {
  test('listRepositoryTags requests the repository tags endpoint', () async {
    final requests = <String>[];
    final client = MockClient((request) async {
      requests.add('${request.method} ${request.url}');
      return http.Response(
        jsonEncode({
          'repository': {
            'id': 'repository-1',
            'project_id': 'project-1',
            'name': 'team/app',
            'description': '',
            'annotations': {},
            'created_at': '2026-04-19T00:00:00Z',
          },
          'tags': [
            {'tag': 'latest', 'digest': 'sha256:abc123', 'media_type': 'application/vnd.oci.image.manifest.v1+json', 'manifest_size': 702},
          ],
        }),
        200,
      );
    });

    final meshagent = Meshagent(baseUrl: 'http://example.test', token: 'test-token', client: client);

    final tags = await meshagent.listRepositoryTags(projectId: 'project-1', repositoryId: 'repository-1');

    expect(requests, ['GET http://example.test/accounts/projects/project-1/repositories/repository-1/tags']);
    expect(tags, hasLength(1));
    expect(tags.single.tag, 'latest');
    expect(tags.single.digest, 'sha256:abc123');
    expect(tags.single.mediaType, 'application/vnd.oci.image.manifest.v1+json');
    expect(tags.single.manifestSize, 702);
  });

  test('listRepositoryTags throws NotFoundException for missing repositories', () async {
    final client = MockClient((_) async => http.Response('missing', 404));

    final meshagent = Meshagent(baseUrl: 'http://example.test', token: 'test-token', client: client);

    expect(() => meshagent.listRepositoryTags(projectId: 'project-1', repositoryId: 'repository-1'), throwsA(isA<NotFoundException>()));
  });

  test('deleteRepositoryTag requests the repository tag delete endpoint', () async {
    final requests = <String>[];
    final client = MockClient((request) async {
      requests.add('${request.method} ${request.url}');
      return http.Response('{}', 202);
    });

    final meshagent = Meshagent(baseUrl: 'http://example.test', token: 'test-token', client: client);

    await meshagent.deleteRepositoryTag(projectId: 'project-1', repositoryId: 'repository-1', tag: 'latest');

    expect(requests, ['DELETE http://example.test/accounts/projects/project-1/repositories/repository-1/tags/latest']);
  });

  test('deleteRepositoryTag throws NotFoundException for missing tags', () async {
    final client = MockClient((_) async => http.Response('missing', 404));

    final meshagent = Meshagent(baseUrl: 'http://example.test', token: 'test-token', client: client);

    expect(
      () => meshagent.deleteRepositoryTag(projectId: 'project-1', repositoryId: 'repository-1', tag: 'latest'),
      throwsA(isA<NotFoundException>()),
    );
  });

  test('updateRepositoryImageTags requests the repository manifest tags endpoint', () async {
    final requests = <String>[];
    final bodies = <String>[];
    final client = MockClient((request) async {
      requests.add('${request.method} ${request.url}');
      bodies.add(request.body);
      return http.Response('{}', 200);
    });

    final meshagent = Meshagent(baseUrl: 'http://example.test', token: 'test-token', client: client);

    await meshagent.updateRepositoryImageTags(
      projectId: 'project-1',
      repositoryId: 'repository-1',
      digest: 'sha256:abc123',
      tags: const ['stable', 'release'],
    );

    expect(requests, ['PUT http://example.test/accounts/projects/project-1/repositories/repository-1/manifests/sha256%3Aabc123/tags']);
    expect(bodies, ['{"tags":["stable","release"]}']);
  });

  test('updateRepositoryImageTags throws NotFoundException for missing manifests', () async {
    final client = MockClient((_) async => http.Response('missing', 404));

    final meshagent = Meshagent(baseUrl: 'http://example.test', token: 'test-token', client: client);

    expect(
      () => meshagent.updateRepositoryImageTags(
        projectId: 'project-1',
        repositoryId: 'repository-1',
        digest: 'sha256:abc123',
        tags: const ['stable'],
      ),
      throwsA(isA<NotFoundException>()),
    );
  });

  test('deleteRepositoryManifest requests the repository manifest delete endpoint', () async {
    final requests = <String>[];
    final client = MockClient((request) async {
      requests.add('${request.method} ${request.url}');
      return http.Response('{}', 202);
    });

    final meshagent = Meshagent(baseUrl: 'http://example.test', token: 'test-token', client: client);

    await meshagent.deleteRepositoryManifest(projectId: 'project-1', repositoryId: 'repository-1', digest: 'sha256:abc123');

    expect(requests, ['DELETE http://example.test/accounts/projects/project-1/repositories/repository-1/manifests/sha256%3Aabc123']);
  });

  test('deleteRepositoryManifest throws NotFoundException for missing manifests', () async {
    final client = MockClient((_) async => http.Response('missing', 404));

    final meshagent = Meshagent(baseUrl: 'http://example.test', token: 'test-token', client: client);

    expect(
      () => meshagent.deleteRepositoryManifest(projectId: 'project-1', repositoryId: 'repository-1', digest: 'sha256:abc123'),
      throwsA(isA<NotFoundException>()),
    );
  });
}

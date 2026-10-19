import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meshagent/meshagent.dart';
import 'package:test/test.dart';

class RotatingTokenProvider implements AccessTokenProvider {
  String token = 'first';
  @override
  Future<String> getToken() async => token;
}

http.Response config([String? endpoint = 'https://files.test/base']) => http.Response(
  jsonEncode({
    'domains': {'files': endpoint},
  }),
  200,
);

void main() {
  test('permission snapshots distinguish a path from its entire subtree', () async {
    final api = Meshagent(
      baseUrl: 'https://api.test',
      token: '',
      client: MockClient((request) async {
        if (request.url.path == '/config') return config();
        expect(request.url.queryParameters, {'permissions': ''});
        expect(request.url.pathSegments.last, 'a +%');
        return http.Response('{"actions":["read","write"],"recursive_actions":["read"]}', 200);
      }),
    );
    final permissions = await api.files.forRoom(projectId: 'p', roomName: 'r').permissions('a +%');
    expect(permissions.actions, {FileAction.read, FileAction.write});
    expect(permissions.recursiveActions, {FileAction.read});
    api.close();
  });
  test('room and agent requests encode paths and use current credentials on the shared client', () async {
    final provider = RotatingTokenProvider();
    var discoveries = 0;
    final requests = <http.Request>[];
    final api = Meshagent.withTokenProvider(
      baseUrl: 'https://api.test/',
      token: '',
      tokenProvider: provider,
      client: MockClient((request) async {
        expect(request.followRedirects, isFalse);
        if (request.url.path == '/config') {
          discoveries++;
          return config();
        }
        requests.add(request);
        return http.Response('', 200, headers: {'content-length': '4', 'x-meshagent-is-folder': 'true', 'etag': 'v1'});
      }),
    );
    final room = api.files.forRoom(projectId: 'p +%', roomName: 'same');
    final agent = api.files.forAgent(projectId: 'p +%', agentName: 'same');
    await Future.wait([room.stat('résumé +%/a#?.bin'), agent.stat('a')]);
    expect(discoveries, 1);
    expect(requests.first.url.pathSegments, ['base', 'p +%', 'rooms', 'same', 'résumé +%', 'a#?.bin']);
    expect(requests.last.url.pathSegments, ['base', 'p +%', 'agents', 'same', 'a']);
    expect(requests.every((request) => request.headers['Authorization'] == 'Bearer first'), isTrue);
    provider.token = 'second';
    final metadata = await room.stat('a');
    expect(requests.last.headers['Authorization'], 'Bearer second');
    expect(metadata.isFolder, isTrue);
    expect(metadata.size, 4);
    expect(metadata.etag, 'v1');
    api.close();
  });

  test('listing follows opaque tokens, parses metadata and rejects repeated tokens', () async {
    var pages = 0;
    final api = Meshagent(
      baseUrl: 'https://api.test',
      token: '',
      client: MockClient((request) async {
        if (request.url.path == '/config') return config();
        expect(request.url.queryParameters['prefix'], 'a b');
        expect(request.url.queryParameters.containsKey('list'), isTrue);
        if (pages++ > 0) expect(request.url.queryParameters['continuation_token'], '+ /%');
        return http.Response(
          jsonEncode({
            'entries': [
              {'name': 'entry$pages', 'is_folder': false, 'size': 5, 'created_at': '2026-01-01T00:00:00Z'},
            ],
            'continuation_token': pages < 2 ? '+ /%' : null,
          }),
          200,
        );
      }),
    );
    final target = api.files.forRoom(projectId: 'p', roomName: 'r');
    final entries = await target.list(path: 'a b').toList();
    expect(entries.map((entry) => entry.name), ['entry1', 'entry2']);
    expect(entries.first.createdAt, DateTime.utc(2026));
    api.close();

    final repeated = Meshagent(
      baseUrl: 'https://api.test',
      token: '',
      client: MockClient(
        (request) async => request.url.path == '/config' ? config() : http.Response('{"entries":[],"continuation_token":"same"}', 200),
      ),
    );
    await expectLater(repeated.files.forAgent(projectId: 'p', agentName: 'a').list().drain<void>(), throwsA(isA<MeshagentException>()));
    repeated.close();
  });

  test('binary upload/download, copy/move/delete/mkdir and presign use typed REST payloads', () async {
    final requests = <http.Request>[];
    final api = Meshagent(
      baseUrl: 'https://api.test',
      token: 'secret',
      client: MockClient((request) async {
        if (request.url.path == '/config') return config();
        requests.add(request);
        if (request.url.path.endsWith('/v1/presign')) {
          expect(request.headers['content-type'], 'application/json');
          return http.Response(
            '{"url":"https://files.test/signed","method":"PUT","headers":{"x-test":"value"},"expires_at":"2026-01-01T00:00:00Z"}',
            200,
          );
        }
        if (request.method == 'GET') return http.Response.bytes([0, 255, 128], 200);
        return http.Response('', 204);
      }),
    );
    final room = api.files.forRoom(projectId: 'p1', roomName: 'room');
    final agent = api.files.forAgent(projectId: 'p2', agentName: 'agent');
    await agent.upload('binary', [0, 255, 128], overwrite: false, contentType: 'image/png');
    expect(requests.last.bodyBytes, [0, 255, 128]);
    expect(requests.last.headers['content-type'], 'image/png');
    expect(requests.last.url.queryParameters['overwrite'], 'false');
    expect(await agent.download('binary'), [0, 255, 128]);
    await agent.copy(room.location('source'), 'dest');
    expect(requests.last.headers['content-type'], 'application/json');
    expect(jsonDecode(requests.last.body), {
      'source': {
        'target': {'project_id': 'p1', 'kind': 'room', 'name': 'room'},
        'path': 'source',
      },
      'overwrite': false,
    });
    expect(requests.last.url.queryParameters['action'], 'copy');
    await agent.move(room.location('source'), 'dest', overwrite: true);
    expect(requests.last.url.queryParameters['action'], 'move');
    await agent.mkdir('directory');
    expect(requests.last.headers['content-type'], 'application/json');
    expect(requests.last.url.queryParameters['action'], 'mkdir');
    await agent.delete('directory', recursive: true);
    expect(requests.last.method, 'DELETE');
    expect(requests.last.url.queryParameters['recursive'], 'true');
    final signed = await agent.presign('binary', method: PresignedFileMethod.put, expiresIn: 60);
    expect(jsonDecode(requests.last.body), {
      'target': {'project_id': 'p2', 'kind': 'agent', 'name': 'agent'},
      'path': 'binary',
      'method': 'PUT',
      'expires_in': 60,
    });
    expect(signed.method, PresignedFileMethod.put);
    expect(signed.headers, {'x-test': 'value'});
    api.close();
  });

  test('only 404 means absent, redirects are errors and denied operations propagate', () async {
    var status = 404;
    final api = Meshagent(
      baseUrl: 'https://api.test',
      token: '',
      client: MockClient((request) async => request.url.path == '/config' ? config() : http.Response('', status)),
    );
    final files = api.files.forRoom(projectId: 'p', roomName: 'r');
    expect(await files.exists('missing'), isFalse);
    for (final code in [401, 403, 302, 503]) {
      status = code;
      await expectLater(files.exists('missing'), throwsA(isA<MeshagentException>().having((error) => error.statusCode, 'status', code)));
    }
    api.close();
  });

  test('failed discovery can retry, invalid config and paths fail before file access', () async {
    String? endpoint;
    var discoveries = 0;
    final api = Meshagent(
      baseUrl: 'https://api.test',
      token: '',
      client: MockClient((request) async {
        expect(request.url.path, '/config');
        discoveries++;
        return config(endpoint);
      }),
    );
    final files = api.files.forAgent(projectId: 'p', agentName: 'a');
    for (final value in [null, 'ftp://files.test', 'https://user:pass@files.test', 'https://files.test?x=y']) {
      endpoint = value;
      await expectLater(files.stat('valid'), throwsA(isA<MeshagentException>()));
    }
    expect(discoveries, 4);
    for (final path in [
      '/absolute',
      '../escape',
      'a//b',
      'a/./b',
      'a\\b',
      'a\u0085b',
      '.meshagent-directory',
      'a/.meshagent-upload-private',
    ]) {
      await expectLater(files.stat(path), throwsArgumentError);
    }
    expect(discoveries, 4);
    expect(() => FilesTarget(projectId: 'p/x', kind: FilesTargetKind.room, name: 'r'), throwsArgumentError);
    await expectLater(files.listPage(limit: 0), throwsArgumentError);
    await expectLater(files.presign('a', expiresIn: 0), throwsArgumentError);
    api.close();
  });

  test('file-only room grants do not advertise runtime permissions', () {
    final grant = ProjectRoomGrant.fromJson({
      'resource': {'type': 'room', 'id': 'r'},
      'subject': {'type': 'user', 'id': 'u'},
      'direct_roles': ['files_read'],
    });
    expect(grant.permissions.storage, isNull);
    expect(grant.permissions.developer, isNull);
    expect(grant.permissions.agents, isNull);
  });

  test('streaming upload is consumed incrementally with cancellation passed to transport', () async {
    final firstRead = Completer<void>();
    final release = Completer<void>();
    final abort = Completer<void>();
    Stream<List<int>> data() async* {
      yield [0, 255];
      await release.future;
      yield [128];
    }

    final api = Meshagent(
      baseUrl: 'https://api.test',
      token: '',
      client: MockClient.streaming((request, stream) async {
        if (request.url.path == '/config') {
          return http.StreamedResponse(Stream.value(utf8.encode('{"domains":{"files":"https://files.test"}}')), 200);
        }
        expect(request, isA<http.Abortable>());
        expect((request as http.Abortable).abortTrigger, same(abort.future));
        var chunks = 0;
        await for (final chunk in stream) {
          expect(chunk, chunks == 0 ? [0, 255] : [128]);
          chunks++;
          if (chunks == 1) firstRead.complete();
        }
        expect(chunks, 2);
        return http.StreamedResponse(const Stream.empty(), 204);
      }),
    );
    final upload = api.files.forRoom(projectId: 'p', roomName: 'r').uploadStream('a', data(), abortTrigger: abort.future);
    await firstRead.future.timeout(const Duration(seconds: 2));
    release.complete();
    await upload;
    api.close();
  });

  test('oversized control responses are bounded and their stream is cancelled', () async {
    var cancelled = false;
    final api = Meshagent(
      baseUrl: 'https://api.test',
      token: '',
      client: MockClient.streaming((request, stream) async {
        await stream.drain<void>();
        if (request.url.path == '/config') {
          return http.StreamedResponse(Stream.value(utf8.encode('{"domains":{"files":"https://files.test"}}')), 200);
        }
        final body = StreamController<List<int>>(
          onCancel: () {
            cancelled = true;
          },
        );
        body.add(List.filled(1024 * 1024 + 1, 0));
        return http.StreamedResponse(body.stream, 200);
      }),
    );
    await expectLater(api.files.forAgent(projectId: 'p', agentName: 'a').listPage(), throwsA(isA<MeshagentException>()));
    expect(cancelled, isTrue);
    api.close();
  });
}

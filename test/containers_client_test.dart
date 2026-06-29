import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:meshagent/meshagent.dart';
import 'package:test/test.dart';

class _ProtocolPair {
  _ProtocolPair() {
    serverProtocol = Protocol(
      channel: StreamProtocolChannel(input: _clientToServer.stream, output: _serverToClient.sink),
    );
  }

  final _clientToServer = StreamController<Uint8List>();
  final _serverToClient = StreamController<Uint8List>();
  Protocol? _clientProtocol;
  late final Protocol serverProtocol;

  Protocol get clientProtocol {
    final protocol = _clientProtocol;
    if (protocol == null) {
      throw StateError('client protocol has not been created');
    }
    return protocol;
  }

  Protocol clientProtocolFactory() {
    if (_clientProtocol != null) {
      throw ProtocolReconnectUnsupportedException('protocolFactory was not configured for reconnecting this protocol');
    }
    final protocol = Protocol(
      channel: StreamProtocolChannel(input: _serverToClient.stream, output: _clientToServer.sink),
    );
    _clientProtocol = protocol;
    return protocol;
  }

  Future<void> dispose() async {
    final clientProtocol = _clientProtocol;
    if (clientProtocol != null) {
      try {
        clientProtocol.dispose();
      } catch (_) {}
    }
    try {
      serverProtocol.dispose();
    } catch (_) {}
    unawaited(_clientToServer.close());
    if (!_serverToClient.isClosed) {
      unawaited(_serverToClient.close());
    }
  }
}

Future<void> _sendRoomReady(Protocol protocol) async {
  await protocol.send(
    'room_ready',
    packMessage({'room_name': 'test-room', 'room_url': 'ws://example/rooms/test-room', 'session_id': 'session-1'}),
  );
  await protocol.send(
    'connected',
    packMessage({
      'type': 'init',
      'participantId': 'self',
      'attributes': {'name': 'self'},
    }),
  );
}

class _RecordedRequest {
  _RecordedRequest({required this.tool, required this.input});

  final String tool;
  final Map<String, dynamic> input;
}

class _PendingBuildRequest {
  _PendingBuildRequest({required this.protocol, required this.messageId});

  final Protocol protocol;
  final int messageId;
}

class _ContainersHarness {
  _ContainersHarness({required this.pair, required this.room, required this.server});

  final _ProtocolPair pair;
  final RoomClient room;
  final _FakeContainersServer server;

  Future<void> dispose() async {
    room.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await pair.dispose();
  }
}

class _FakeContainersServer {
  final requests = <_RecordedRequest>[];
  final execChunks = <BinaryContent>[];
  final logChunks = <BinaryContent>[];
  final buildLogChunks = <BinaryContent>[];
  final buildChunks = <BinaryContent>[];
  final _streamTools = <String, String>{};
  final _logCloseCompleters = <String, Completer<void>>{};
  final _execCloseCompleters = <String, Completer<void>>{};
  final _logFollowByToolCall = <String, bool>{};
  final _pendingBuildRequests = <String, _PendingBuildRequest>{};

  Future<void> waitForLogsClose(String toolCallId) async {
    final completer = _logCloseCompleters[toolCallId];
    if (completer == null) {
      throw StateError('no logs stream recorded for $toolCallId');
    }
    await completer.future;
  }

  Future<void> waitForExecClose(String toolCallId) async {
    final completer = _execCloseCompleters[toolCallId];
    if (completer == null) {
      throw StateError('no exec stream recorded for $toolCallId');
    }
    await completer.future;
  }

  Future<void> handleMessage(Protocol protocol, int messageId, String type, Uint8List data) async {
    if (type == 'room.invoke_tool') {
      final message = unpackMessage(data);
      final request = message.header;
      if (request['toolkit'] != 'containers') {
        return;
      }

      final tool = request['tool'] as String;
      if (tool == 'exec' || tool == 'logs' || tool == 'get_build_logs' || tool == 'build') {
        final toolCallId = request['tool_call_id'] as String;
        _streamTools[toolCallId] = tool;
        if (tool == 'build') {
          _pendingBuildRequests[toolCallId] = _PendingBuildRequest(protocol: protocol, messageId: messageId);
          return;
        }
        if (tool == 'exec') {
          _execCloseCompleters[toolCallId] = Completer<void>();
        } else {
          _logCloseCompleters[toolCallId] = Completer<void>();
        }
        await protocol.send('__response__', ControlContent(method: 'open').pack(), id: messageId);
        return;
      }

      final input = _decodeInput(message: message, request: request);
      if (input is! JsonContent) {
        throw StateError('containers.$tool expected JsonContent input');
      }
      requests.add(_RecordedRequest(tool: tool, input: Map<String, dynamic>.from(input.json)));

      switch (tool) {
        case 'list_images':
          await protocol.send(
            '__response__',
            JsonContent(
              json: {
                'images': [
                  {
                    'id': 'img-1',
                    'preferred_ref': 'demo:latest',
                    'references': ['demo:latest'],
                    'labels': [
                      {'key': 'role', 'value': 'demo'},
                    ],
                    'created_at': '2026-01-01T00:00:00Z',
                    'updated_at': '2026-01-02T00:00:00Z',
                    'target_media_type': 'application/vnd.oci.image.manifest.v1+json',
                  },
                ],
              },
            ).pack(),
            id: messageId,
          );
          return;
        case 'inspect_image':
          await protocol.send(
            '__response__',
            JsonContent(
              json: {
                'image': {
                  'id': 'img-1',
                  'preferred_ref': 'demo:latest',
                  'references': ['demo:latest'],
                  'labels': [
                    {'key': 'role', 'value': 'demo'},
                  ],
                  'created_at': '2026-01-01T00:00:00Z',
                  'updated_at': '2026-01-02T00:00:00Z',
                  'target_media_type': 'application/vnd.oci.image.manifest.v1+json',
                },
                'target': {
                  'digest': 'sha256:target',
                  'media_type': 'application/vnd.oci.image.manifest.v1+json',
                  'size': 123,
                  'annotations': const [],
                },
                'selected_manifest': {
                  'digest': 'sha256:target',
                  'media_type': 'application/vnd.oci.image.manifest.v1+json',
                  'size': 123,
                  'annotations': const [],
                },
                'manifests': const [],
                'config': {
                  'digest': 'sha256:config',
                  'media_type': 'application/vnd.oci.image.config.v1+json',
                  'size': 45,
                  'annotations': const [],
                },
                'layers': [
                  {
                    'digest': 'sha256:layer-1',
                    'media_type': 'application/vnd.oci.image.layer.v1.tar+gzip',
                    'size': 67,
                    'annotations': const [],
                  },
                ],
                'content_size': 235,
              },
            ).pack(),
            id: messageId,
          );
          return;
        case 'run':
        case 'run_service':
        case 'push_image':
        case 'load_image':
        case 'save_image':
          await protocol.send('__response__', JsonContent(json: {'container_id': '$tool-ctr'}).pack(), id: messageId);
          return;
        case 'load':
          await protocol.send(
            '__response__',
            JsonContent(
              json: {
                'resolved_ref': 'registry.meshagent.com/images/example.tar:latest',
                'refs': ['registry.meshagent.com/images/example.tar:latest'],
              },
            ).pack(),
            id: messageId,
          );
          return;
        case 'pull_image':
        case 'delete_image':
        case 'cancel_build':
        case 'delete_build':
        case 'stop_container':
        case 'delete_container':
          await protocol.send('__response__', EmptyContent().pack(), id: messageId);
          return;
        case 'list_builds':
          await protocol.send(
            '__response__',
            JsonContent(
              json: {
                'builds': [
                  {'id': 'build-1', 'tag': 'demo:latest', 'status': 'succeeded', 'exit_code': 0},
                ],
              },
            ).pack(),
            id: messageId,
          );
          return;
        case 'list_containers':
          await protocol.send(
            '__response__',
            JsonContent(
              json: {
                'containers': [
                  {
                    'id': 'container-1',
                    'image': 'demo:latest',
                    'image_id': 'sha256:demo',
                    'name': 'demo',
                    'ports': [
                      {'container_port': 80, 'host_port': 8080},
                    ],
                    'started_by': {'id': 'p1', 'name': 'user'},
                    'state': 'RUNNING',
                    'private': false,
                    'service_id': null,
                    'stats': {
                      'cpu_usage_nano_cores': 125000000,
                      'memory_usage_bytes': 67108864,
                      'memory_working_set_bytes': 33554432,
                      'timestamp_ns': 1700000000,
                    },
                    'exit_status': {'exit_code': 0, 'reason': 'Completed', 'message': 'container exited', 'oom_killed': false},
                  },
                ],
              },
            ).pack(),
            id: messageId,
          );
          return;
        case 'wait_for_exit':
          await protocol.send(
            '__response__',
            JsonContent(json: {'exit_code': 0, 'reason': 'Completed', 'message': 'container exited', 'oom_killed': false}).pack(),
            id: messageId,
          );
          return;
        default:
          throw StateError('unsupported containers operation: $tool');
      }
    }

    if (type == 'room.tool_call_request_chunk') {
      final message = unpackMessage(data);
      final header = message.header;
      final toolCallId = header['tool_call_id'];
      if (toolCallId is! String) {
        await protocol.send('__response__', EmptyContent().pack(), id: messageId);
        return;
      }

      final chunkHeader = Map<String, dynamic>.from(header['chunk'] as Map);
      final chunk = unpackContent(packMessage(chunkHeader, message.payload.isEmpty ? null : message.payload));
      if (chunk is ControlContent) {
        final tool = _streamTools[toolCallId];
        if (tool == 'build') {
          final pending = _pendingBuildRequests.remove(toolCallId);
          if (pending == null) {
            throw StateError('no build request recorded for $toolCallId');
          }
          await pending.protocol.send('__response__', JsonContent(json: {'build_id': 'build-job'}).pack(), id: pending.messageId);
        }
        final execCloseCompleter = _execCloseCompleters[toolCallId];
        if (execCloseCompleter != null && !execCloseCompleter.isCompleted) {
          execCloseCompleter.complete();
        }
        final closeCompleter = _logCloseCompleters[toolCallId];
        if (closeCompleter != null && !closeCompleter.isCompleted) {
          closeCompleter.complete();
        }
        if (tool == 'logs' && _logFollowByToolCall[toolCallId] == true) {
          await _sendToolCallChunk(
            protocol,
            toolCallId: toolCallId,
            chunk: ControlContent(method: 'close'),
          );
        }
        await protocol.send('__response__', EmptyContent().pack(), id: messageId);
        return;
      }
      if (chunk is! BinaryContent) {
        throw StateError('containers expected BinaryContent stream chunks');
      }
      final tool = _streamTools[toolCallId];
      if (tool == 'exec') {
        execChunks.add(chunk);

        if (execChunks.length == 2) {
          await _sendToolCallChunk(
            protocol,
            toolCallId: toolCallId,
            chunk: BinaryContent(
              data: Uint8List.fromList('hello'.codeUnits),
              headers: {
                'request_id': execChunks.first.headers['request_id'],
                'container_id': execChunks.first.headers['container_id'],
                'channel': 1,
              },
            ),
          );
          await _sendToolCallChunk(
            protocol,
            toolCallId: toolCallId,
            chunk: BinaryContent(
              data: Uint8List.fromList('stderr'.codeUnits),
              headers: {
                'request_id': execChunks.first.headers['request_id'],
                'container_id': execChunks.first.headers['container_id'],
                'channel': 2,
              },
            ),
          );
          await _sendToolCallChunk(
            protocol,
            toolCallId: toolCallId,
            chunk: BinaryContent(
              data: Uint8List.fromList(utf8.encode('{"status": 0}')),
              headers: {
                'request_id': execChunks.first.headers['request_id'],
                'container_id': execChunks.first.headers['container_id'],
                'channel': 3,
              },
            ),
          );
          await _sendToolCallChunk(
            protocol,
            toolCallId: toolCallId,
            chunk: ControlContent(method: 'close'),
          );
        }
      } else if (tool == 'build') {
        buildChunks.add(chunk);
        if (chunk.headers['kind'] == 'start') {
          requests.add(_RecordedRequest(tool: 'build', input: Map<String, dynamic>.from(chunk.headers)));
        }
      } else if (tool == 'get_build_logs') {
        buildLogChunks.add(chunk);
        requests.add(_RecordedRequest(tool: 'get_build_logs', input: Map<String, dynamic>.from(chunk.headers)));
        await _sendToolCallChunk(
          protocol,
          toolCallId: toolCallId,
          chunk: BinaryContent(
            data: Uint8List.fromList('build line'.codeUnits),
            headers: {'request_id': chunk.headers['request_id'], 'build_id': chunk.headers['build_id'], 'channel': 1},
          ),
        );
        await _sendToolCallChunk(
          protocol,
          toolCallId: toolCallId,
          chunk: BinaryContent(
            data: Uint8List.fromList(utf8.encode('{"status": 0}')),
            headers: {'request_id': chunk.headers['request_id'], 'build_id': chunk.headers['build_id'], 'channel': 3},
          ),
        );
        await _sendToolCallChunk(
          protocol,
          toolCallId: toolCallId,
          chunk: ControlContent(method: 'close'),
        );
      } else if (tool == 'logs') {
        logChunks.add(chunk);
        requests.add(_RecordedRequest(tool: 'logs', input: Map<String, dynamic>.from(chunk.headers)));
        final follow = chunk.headers['follow'] as bool? ?? false;
        _logFollowByToolCall[toolCallId] = follow;
        await _sendToolCallChunk(
          protocol,
          toolCallId: toolCallId,
          chunk: BinaryContent(
            data: Uint8List.fromList('line 1'.codeUnits),
            headers: {'request_id': chunk.headers['request_id'], 'container_id': chunk.headers['container_id'], 'channel': 1},
          ),
        );
        if (!follow) {
          await _sendToolCallChunk(
            protocol,
            toolCallId: toolCallId,
            chunk: BinaryContent(
              data: Uint8List.fromList('line 2'.codeUnits),
              headers: {'request_id': chunk.headers['request_id'], 'container_id': chunk.headers['container_id'], 'channel': 1},
            ),
          );
          await _sendToolCallChunk(
            protocol,
            toolCallId: toolCallId,
            chunk: ControlContent(method: 'close'),
          );
        }
      }

      await protocol.send('__response__', EmptyContent().pack(), id: messageId);
    }
  }

  Future<void> _sendToolCallChunk(Protocol protocol, {required String toolCallId, required Content chunk}) async {
    final packed = unpackMessage(chunk.pack());
    await protocol.send(
      'room.tool_call_response_chunk',
      packMessage({'tool_call_id': toolCallId, 'chunk': packed.header}, packed.payload.isEmpty ? null : packed.payload),
    );
  }

  Content _decodeInput({required Message message, required Map<String, dynamic> request}) {
    final arguments = Map<String, dynamic>.from(request['arguments'] as Map);
    return unpackContent(packMessage(arguments, message.payload.isEmpty ? null : message.payload));
  }
}

Future<_ContainersHarness> _startContainersHarness() async {
  final pair = _ProtocolPair();
  final server = _FakeContainersServer();
  pair.serverProtocol.start(onMessage: server.handleMessage);

  final room = RoomClient(protocolFactory: pair.clientProtocolFactory);
  final startFuture = room.start();
  await _sendRoomReady(pair.serverProtocol);
  await startFuture;

  return _ContainersHarness(pair: pair, room: room, server: server);
}

void main() {
  test('containers client uses room.invoke and streams exec/logs', () async {
    final harness = await _startContainersHarness();

    await harness.room.containers.pullImage(
      tag: 'demo:latest',
      credentials: [DockerSecret(username: 'u', password: 'p', registry: 'https://example.com', email: 'u@example.com')],
    );
    expect(await harness.room.containers.run(image: 'demo:latest', env: {'KEY': 'VALUE'}, ports: {8080: 80}), 'run-ctr');
    expect(await harness.room.containers.runService(serviceId: 'svc-1', env: {'A': '1'}), 'run_service-ctr');
    final images = await harness.room.containers.listImages();
    expect(images.single.preferredRef, 'demo:latest');
    expect(images.single.references, ['demo:latest']);
    expect(images.single.labels, {'role': 'demo'});
    expect(images.single.createdAt, DateTime.parse('2026-01-01T00:00:00Z'));
    expect(images.single.targetMediaType, 'application/vnd.oci.image.manifest.v1+json');
    final inspection = await harness.room.containers.inspectImage(imageId: 'img-1');
    expect(inspection.image.preferredRef, 'demo:latest');
    expect(inspection.target.digest, 'sha256:target');
    expect(inspection.layers.single.digest, 'sha256:layer-1');
    expect(inspection.contentSize, 235);
    final containers = await harness.room.containers.list();
    expect(containers.single.id, 'container-1');
    expect(containers.single.imageId, 'sha256:demo');
    expect(containers.single.ports.single.containerPort, 80);
    expect(containers.single.ports.single.hostPort, 8080);
    expect(containers.single.stats?.cpuUsageNanoCores, 125000000);
    expect(containers.single.stats?.memoryUsageBytes, 67108864);
    expect(containers.single.stats?.memoryWorkingSetBytes, 33554432);
    expect(containers.single.stats?.timestampNs, 1700000000);
    expect(containers.single.exitStatus?.exitCode, 0);
    expect(containers.single.exitStatus?.reason, 'Completed');
    expect(await harness.room.containers.waitForExit(containerId: 'container-1'), 0);
    final exitStatus = await harness.room.containers.waitForExitStatus(containerId: 'container-1');
    expect(exitStatus.exitCode, 0);
    expect(exitStatus.reason, 'Completed');
    expect(exitStatus.message, 'container exited');
    expect(exitStatus.oomKilled, isFalse);

    final exec = harness.room.containers.exec(containerId: 'container-1', command: 'echo hi');
    await exec.write(Uint8List.fromList('ping'.codeUnits));
    expect(await exec.result.timeout(const Duration(seconds: 2), onTimeout: () => throw StateError('exec.result timed out')), 0);
    expect(utf8.decode(exec.previousOutput.single), 'hello');
    expect(utf8.decode(exec.previousError.single), 'stderr');
    final execToolCallId = harness.server._streamTools.entries.singleWhere((entry) => entry.value == 'exec').key;
    await harness.server
        .waitForExecClose(execToolCallId)
        .timeout(const Duration(seconds: 2), onTimeout: () => throw StateError('exec close timed out'));

    final logs = harness.room.containers.logs(containerId: 'container-1', follow: false);
    expect(await logs.stream.toList().timeout(const Duration(seconds: 2), onTimeout: () => throw StateError('logs stream timed out')), [
      'line 1',
      'line 2',
    ]);
    await logs.result.timeout(const Duration(seconds: 2), onTimeout: () => throw StateError('logs.result timed out'));
    final nonFollowLogsToolCallId = harness.server._streamTools.entries.singleWhere((entry) => entry.value == 'logs').key;
    await harness.server
        .waitForLogsClose(nonFollowLogsToolCallId)
        .timeout(const Duration(seconds: 2), onTimeout: () => throw StateError('non-follow logs close timed out'));

    expect(harness.server.requests.map((entry) => entry.tool).toList(), [
      'pull_image',
      'run',
      'run_service',
      'list_images',
      'inspect_image',
      'list_containers',
      'wait_for_exit',
      'wait_for_exit',
      'logs',
    ]);

    final runInput = harness.server.requests[1].input;
    expect(runInput['env'], [
      {'key': 'KEY', 'value': 'VALUE'},
    ]);
    expect(runInput['ports'], [
      {'container_port': 8080, 'host_port': 80},
    ]);

    final runServiceInput = harness.server.requests[2].input;
    expect(runServiceInput['env'], [
      {'key': 'A', 'value': '1'},
    ]);
    final logsInput = harness.server.requests[8].input;
    expect(logsInput['kind'], 'start');
    expect(logsInput['container_id'], 'container-1');
    expect(logsInput['follow'], false);

    expect(harness.server.execChunks, hasLength(2));
    expect(harness.server.execChunks.first.headers['kind'], 'start');
    expect(harness.server.execChunks.first.headers['container_id'], 'container-1');
    expect(harness.server.execChunks[1].headers['channel'], 1);
    expect(utf8.decode(harness.server.execChunks[1].data), 'ping');

    await harness.dispose().timeout(const Duration(seconds: 2), onTimeout: () => throw StateError('harness.dispose timed out'));
  });

  test('containers logs closes the request stream when the output stream is canceled early', () async {
    final harness = await _startContainersHarness();

    final logs = harness.room.containers.logs(containerId: 'container-1', follow: true);
    final firstLine = Completer<String>();
    late final StreamSubscription<String> subscription;
    subscription = logs.stream.listen((line) async {
      if (!firstLine.isCompleted) {
        firstLine.complete(line);
        await subscription.cancel();
      }
    });
    expect(await firstLine.future.timeout(const Duration(seconds: 2), onTimeout: () => throw StateError('first log timed out')), 'line 1');

    final logStartChunk = harness.server.logChunks.single;
    final toolCallId = harness.server._streamTools.entries.singleWhere((entry) => entry.value == 'logs').key;
    expect(logStartChunk.headers['follow'], true);
    await harness.server
        .waitForLogsClose(toolCallId)
        .timeout(const Duration(seconds: 2), onTimeout: () => throw StateError('logs close timed out'));
    await logs.result.timeout(const Duration(seconds: 2), onTimeout: () => throw StateError('logs.result timed out'));

    await harness.dispose().timeout(const Duration(seconds: 2), onTimeout: () => throw StateError('harness.dispose timed out'));
  });

  test('containers exec coalesces duplicate resize events', () async {
    final harness = await _startContainersHarness();

    final exec = harness.room.containers.exec(containerId: 'container-1', command: 'bash', tty: true);
    await exec.resize(width: 80, height: 24);
    await exec.resize(width: 80, height: 24);

    expect(await exec.result.timeout(const Duration(seconds: 2), onTimeout: () => throw StateError('exec.result timed out')), 0);
    expect(harness.server.execChunks, hasLength(2));
    expect(harness.server.execChunks[1].headers['channel'], 4);
    expect(harness.server.execChunks[1].headers['width'], 80);
    expect(harness.server.execChunks[1].headers['height'], 24);

    await harness.dispose().timeout(const Duration(seconds: 2), onTimeout: () => throw StateError('harness.dispose timed out'));
  });

  test('containers client supports build and image archive operations', () async {
    final harness = await _startContainersHarness();
    final mounts = <ContainerMountSpec>[
      ContainerMountSpec(
        room: [RoomStorageMountSpec(path: '/workspace', readOnly: false)],
        configs: const [ConfigMountSpec()],
      ),
    ];

    await harness.room.containers.deleteImage(image: 'demo:latest');
    expect(await harness.room.containers.pushImage(tag: 'demo:latest', private: true), 'push_image-ctr');

    final imported = await harness.room.containers.load(archivePath: '/images/example.tar');
    expect(imported.resolvedRef, 'registry.meshagent.com/images/example.tar:latest');
    expect(imported.refs, ['registry.meshagent.com/images/example.tar:latest']);

    expect(await harness.room.containers.loadImage(mounts: mounts, archivePath: '/workspace/example.tar', private: true), 'load_image-ctr');
    expect(
      await harness.room.containers.saveImage(tag: 'demo:latest', mounts: mounts, archivePath: '/workspace/example.tar', private: true),
      'save_image-ctr',
    );

    Stream<Uint8List> buildChunks() async* {
      yield Uint8List.fromList('hello '.codeUnits);
      yield Uint8List.fromList('world'.codeUnits);
    }

    expect(
      await harness.room.containers.build(
        tags: const ['example:latest'],
        mountPath: '/context',
        contextPath: '/workspace',
        chunks: buildChunks(),
        dockerfilePath: '/workspace/Dockerfile',
        optimizeImage: false,
        private: true,
        credentials: const [DockerSecret(username: 'u', password: 'p', registry: '', email: '')],
        builderName: 'builder-1',
        size: 11,
      ),
      'build-job',
    );

    final builds = await harness.room.containers.listBuilds();
    expect(builds, hasLength(1));
    expect(builds.single.id, 'build-1');
    expect(builds.single.tag, 'demo:latest');
    expect(builds.single.status, 'succeeded');
    expect(builds.single.exitCode, 0);

    await harness.room.containers.cancelBuild(buildId: 'build-1');
    await harness.room.containers.deleteBuild(buildId: 'build-1');

    final buildLogs = harness.room.containers.getBuildLogs(buildId: 'build-1', follow: true);
    expect(await buildLogs.stream.toList().timeout(const Duration(seconds: 2), onTimeout: () => throw StateError('build logs timed out')), [
      'build line',
    ]);
    expect(await buildLogs.result.timeout(const Duration(seconds: 2), onTimeout: () => throw StateError('build log result timed out')), 0);
    final buildLogsToolCallId = harness.server._streamTools.entries.singleWhere((entry) => entry.value == 'get_build_logs').key;
    await harness.server
        .waitForLogsClose(buildLogsToolCallId)
        .timeout(const Duration(seconds: 2), onTimeout: () => throw StateError('build logs close timed out'));

    await harness.room.containers.stop(containerId: 'container-1');

    expect(harness.server.requests.map((entry) => entry.tool).toList(), [
      'delete_image',
      'push_image',
      'load',
      'load_image',
      'save_image',
      'build',
      'list_builds',
      'cancel_build',
      'delete_build',
      'get_build_logs',
      'stop_container',
    ]);

    final loadImageInput = harness.server.requests[3].input;
    expect(loadImageInput['mounts'], [
      {
        'room': [
          {'path': '/workspace', 'read_only': false},
        ],
        'configs': [
          {'path': '/var/run/meshagent'},
        ],
      },
    ]);
    expect(loadImageInput['archive_path'], '/workspace/example.tar');
    expect(loadImageInput['private'], true);

    final buildRequest = harness.server.requests.firstWhere((entry) => entry.tool == 'build');
    final buildInput = buildRequest.input;
    expect(buildInput['tags'], ['example:latest']);
    expect(buildInput['mount_path'], '/context');
    expect(buildInput['context_path'], '/workspace');
    expect(buildInput['dockerfile_path'], '/workspace/Dockerfile');
    expect(buildInput['optimize_image'], false);
    expect(buildInput['private'], true);
    expect(buildInput['credentials'], [
      {'registry': '', 'username': 'u', 'password': 'p'},
    ]);
    expect(buildInput['builder_name'], 'builder-1');
    expect(buildInput['size'], 11);

    final buildLogsRequest = harness.server.requests.firstWhere((entry) => entry.tool == 'get_build_logs');
    final buildLogsInput = buildLogsRequest.input;
    expect(buildLogsInput['kind'], 'start');
    expect(buildLogsInput['build_id'], 'build-1');
    expect(buildLogsInput['follow'], true);

    final stopRequest = harness.server.requests.firstWhere((entry) => entry.tool == 'stop_container');
    final stopInput = stopRequest.input;
    expect(stopInput['force'], false);

    await harness.dispose().timeout(const Duration(seconds: 2), onTimeout: () => throw StateError('harness.dispose timed out'));
  });

  test('containers exec stop closes stdin without sending hard-stop control', () async {
    final harness = await _startContainersHarness();

    final exec = harness.room.containers.exec(containerId: 'container-1', command: 'bash', tty: true);
    unawaited(exec.result.catchError((Object _) => -1));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await exec.stop();

    final execToolCallId = harness.server._streamTools.entries.singleWhere((entry) => entry.value == 'exec').key;
    await harness.server
        .waitForExecClose(execToolCallId)
        .timeout(const Duration(seconds: 2), onTimeout: () => throw StateError('exec close timed out'));
    expect(harness.server.execChunks, hasLength(1));
    expect(harness.server.execChunks.single.headers['kind'], 'start');

    await harness.dispose().timeout(const Duration(seconds: 2), onTimeout: () => throw StateError('harness.dispose timed out'));
  });
}

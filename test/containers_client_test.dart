import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:meshagent/meshagent.dart';
import 'package:test/test.dart';

class _ProtocolPair {
  _ProtocolPair() {
    clientProtocol = Protocol(
      channel: StreamProtocolChannel(input: _serverToClient.stream, output: _clientToServer.sink),
    );
    serverProtocol = Protocol(
      channel: StreamProtocolChannel(input: _clientToServer.stream, output: _serverToClient.sink),
    );
  }

  final _clientToServer = StreamController<Uint8List>();
  final _serverToClient = StreamController<Uint8List>();
  late final Protocol clientProtocol;
  late final Protocol serverProtocol;

  Future<void> dispose() async {
    try {
      clientProtocol.dispose();
    } catch (_) {}
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
}

class _RecordedRequest {
  _RecordedRequest({required this.tool, required this.input});

  final String tool;
  final Map<String, dynamic> input;
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
  final _streamTools = <String, String>{};
  final _logCloseCompleters = <String, Completer<void>>{};
  final _execCloseCompleters = <String, Completer<void>>{};
  final _logFollowByToolCall = <String, bool>{};

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
      if (tool == 'exec' || tool == 'logs') {
        final toolCallId = request['tool_call_id'] as String;
        _streamTools[toolCallId] = tool;
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
                    'tags': ['demo:latest'],
                    'size': 1,
                    'labels': <String, dynamic>{},
                  },
                ],
              },
            ).pack(),
            id: messageId,
          );
          return;
        case 'run':
        case 'run_service':
          await protocol.send('__response__', JsonContent(json: {'container_id': '$tool-ctr'}).pack(), id: messageId);
          return;
        case 'pull_image':
        case 'stop_container':
        case 'delete_container':
          await protocol.send('__response__', EmptyContent().pack(), id: messageId);
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
                    'name': 'demo',
                    'started_by': {'id': 'p1', 'name': 'user'},
                    'state': 'RUNNING',
                    'private': false,
                    'service_id': null,
                  },
                ],
              },
            ).pack(),
            id: messageId,
          );
          return;
        case 'wait_for_exit':
          await protocol.send('__response__', JsonContent(json: {'exit_code': 0}).pack(), id: messageId);
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

  final room = RoomClient(protocol: pair.clientProtocol);
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
    expect(images.single.tags, ['demo:latest']);
    final containers = await harness.room.containers.list();
    expect(containers.single.id, 'container-1');
    expect(await harness.room.containers.waitForExit(containerId: 'container-1'), 0);

    final exec = harness.room.containers.exec(containerId: 'container-1', command: 'echo hi');
    await exec.write(Uint8List.fromList('ping'.codeUnits));
    expect(await exec.result.timeout(const Duration(seconds: 2), onTimeout: () => throw StateError('exec.result timed out')), 0);
    expect(utf8.decode(exec.previousOutput.single), 'hello');
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
      'list_containers',
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
    final logsInput = harness.server.requests[6].input;
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

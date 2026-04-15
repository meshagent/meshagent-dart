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
    await _clientToServer.close();
    if (!_serverToClient.isClosed) {
      await _serverToClient.close();
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

class _ServicesHarness {
  _ServicesHarness({required this.pair, required this.room, required this.server});

  final _ProtocolPair pair;
  final RoomClient room;
  final _FakeServicesServer server;

  Future<void> dispose() async {
    room.dispose();
    await pair.dispose();
  }
}

class _FakeServicesServer {
  final requests = <_RecordedRequest>[];

  Future<void> handleMessage(Protocol protocol, int messageId, String type, Uint8List data) async {
    if (type != 'room.invoke_tool') {
      return;
    }

    final message = unpackMessage(data);
    final request = message.header;
    if (request['toolkit'] != 'services') {
      return;
    }

    final tool = request['tool'] as String;
    final input = _decodeInput(message: message, request: request);
    if (input is! JsonContent) {
      throw StateError('services.$tool expected JsonContent input');
    }

    requests.add(_RecordedRequest(tool: tool, input: Map<String, dynamic>.from(input.json)));

    switch (tool) {
      case 'list':
        await protocol.send(
          '__response__',
          JsonContent(
            json: {
              'services_json': [
                jsonEncode({
                  'kind': 'Service',
                  'version': 'v1',
                  'id': 'svc-1',
                  'metadata': {'name': 'svc-1'},
                  'container': {'image': 'meshagent/cli:default'},
                  'ports': [],
                }),
              ],
              'service_states': [
                {
                  'service_id': 'svc-1',
                  'state': 'running',
                  'container_id': 'container-123',
                  'restart_scheduled_at': null,
                  'started_at': 123.0,
                  'restart_count': 2,
                  'last_exit_code': 137,
                  'last_exit_at': 122.0,
                },
              ],
            },
          ).pack(),
          id: messageId,
        );
        return;
      case 'restart':
        await protocol.send('__response__', EmptyContent().pack(), id: messageId);
        return;
      default:
        throw StateError('unsupported services operation: $tool');
    }
  }

  Content _decodeInput({required Message message, required Map<String, dynamic> request}) {
    final arguments = Map<String, dynamic>.from(request['arguments'] as Map);
    return unpackContent(packMessage(arguments, message.payload.isEmpty ? null : message.payload));
  }
}

Future<_ServicesHarness> _startServicesHarness() async {
  final pair = _ProtocolPair();
  final server = _FakeServicesServer();
  pair.serverProtocol.start(onMessage: server.handleMessage);

  final room = RoomClient(protocolFactory: pair.clientProtocolFactory);
  final startFuture = room.start();
  await _sendRoomReady(pair.serverProtocol);
  await startFuture;

  return _ServicesHarness(pair: pair, room: room, server: server);
}

void main() {
  test('services listWithState uses invoke and translates service state array', () async {
    final harness = await _startServicesHarness();

    final result = await harness.room.services.listWithState();

    expect(harness.server.requests, hasLength(1));
    expect(harness.server.requests.single.tool, 'list');
    expect(harness.server.requests.single.input, isEmpty);
    expect(result.services, hasLength(1));
    expect(result.services.single.id, 'svc-1');
    expect(result.serviceStates.keys, ['svc-1']);
    expect(result.serviceStates['svc-1']!.state, 'running');
    expect(result.serviceStates['svc-1']!.containerId, 'container-123');

    await harness.dispose();
  });

  test('services restart uses invoke', () async {
    final harness = await _startServicesHarness();

    await harness.room.services.restart(serviceId: 'svc-1');

    expect(harness.server.requests, hasLength(1));
    expect(harness.server.requests.single.tool, 'restart');
    expect(harness.server.requests.single.input, {'service_id': 'svc-1'});

    await harness.dispose();
  });
}

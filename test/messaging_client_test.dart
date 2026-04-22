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

class _MessagingHarness {
  _MessagingHarness({required this.pair, required this.room, required this.server});

  final _ProtocolPair pair;
  final RoomClient room;
  final _FakeMessagingServer server;

  Future<void> dispose() async {
    room.dispose();
    await pair.dispose();
  }
}

class _FakeMessagingServer {
  final requests = <_RecordedRequest>[];

  Future<void> handleMessage(Protocol protocol, int messageId, String type, Uint8List data) async {
    if (type != 'room.invoke_tool') {
      return;
    }

    final message = unpackMessage(data);
    final request = message.header;
    if (request['toolkit'] != 'messaging') {
      return;
    }

    final tool = request['tool'] as String;
    final input = _decodeInput(message: message, request: request);
    if (input is! JsonContent) {
      throw StateError('messaging.$tool expected JsonContent input');
    }

    requests.add(_RecordedRequest(tool: tool, input: Map<String, dynamic>.from(input.json)));

    switch (tool) {
      case 'enable':
        await protocol.send('__response__', EmptyContent().pack(), id: messageId);
        await protocol.send(
          'messaging.send',
          packMessage({
            'from_participant_id': 'local-participant',
            'type': 'messaging.enabled',
            'message': {
              'participants': [
                {
                  'id': 'remote-1',
                  'role': 'member',
                  'attributes': {'name': 'Remote'},
                },
              ],
            },
          }),
        );
        return;
      case 'send':
      case 'broadcast':
      case 'disable':
        await protocol.send('__response__', EmptyContent().pack(), id: messageId);
        return;
      default:
        throw StateError('unsupported messaging operation: $tool');
    }
  }

  Future<void> sendIncomingMessage(
    Protocol protocol, {
    required String type,
    required Map<String, dynamic> message,
    Uint8List? attachment,
  }) async {
    await protocol.send('messaging.send', packMessage({'from_participant_id': 'remote-1', 'type': type, 'message': message}, attachment));
  }

  Content _decodeInput({required Message message, required Map<String, dynamic> request}) {
    final arguments = Map<String, dynamic>.from(request['arguments'] as Map);
    return unpackContent(packMessage(arguments, message.payload.isEmpty ? null : message.payload));
  }
}

Future<_MessagingHarness> _startMessagingHarness() async {
  final pair = _ProtocolPair();
  final server = _FakeMessagingServer();
  pair.serverProtocol.start(onMessage: server.handleMessage);

  final room = RoomClient(protocolFactory: pair.clientProtocolFactory);
  final startFuture = room.start();
  await _sendRoomReady(pair.serverProtocol);
  await startFuture;

  return _MessagingHarness(pair: pair, room: room, server: server);
}

Future<void> _waitUntil(bool Function() condition, {Duration timeout = const Duration(seconds: 1)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition was not met before timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  test('messaging client uses room.invoke and encodes strict payloads', () async {
    final harness = await _startMessagingHarness();

    await harness.room.messaging.enable();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final remote = harness.room.messaging.remoteParticipants.single;
    expect(remote.id, 'remote-1');

    await harness.room.messaging.sendMessage(to: remote, type: 'direct', message: {'value': 1}, attachment: Uint8List.fromList([0, 1]));
    await harness.room.messaging.broadcastMessage(
      type: 'broadcast',
      message: {'hello': 'world'},
      attachment: Uint8List.fromList('bytes'.codeUnits),
    );
    await harness.room.messaging.disable();
    await _waitUntil(() => harness.server.requests.length == 4);

    expect(harness.server.requests.map((entry) => entry.tool).toList(), ['enable', 'send', 'broadcast', 'disable']);

    final sendInput = harness.server.requests[1].input;
    expect(sendInput['to_participant_id'], 'remote-1');
    expect(jsonDecode(sendInput['message_json'] as String), {'value': 1});
    expect(sendInput['attachment_base64'], base64Encode(Uint8List.fromList([0, 1])));

    final broadcastInput = harness.server.requests[2].input;
    expect(jsonDecode(broadcastInput['message_json'] as String), {'hello': 'world'});
    expect(broadcastInput['attachment_base64'], base64Encode(Uint8List.fromList('bytes'.codeUnits)));

    await harness.dispose();
  });

  test('messaging client still handles messaging.send pushes', () async {
    final harness = await _startMessagingHarness();

    await harness.room.messaging.enable();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final messageFuture = harness.room.events.firstWhere((event) {
      return event is RoomMessageEvent && event.message.type == 'chat';
    });

    await harness.server.sendIncomingMessage(
      harness.pair.serverProtocol,
      type: 'chat',
      message: {'text': 'hello'},
      attachment: Uint8List.fromList('hi'.codeUnits),
    );

    final event = await messageFuture.timeout(const Duration(seconds: 1));
    expect(event, isA<RoomMessageEvent>());
    final roomMessage = (event as RoomMessageEvent).message;
    expect(roomMessage.fromParticipantId, 'remote-1');
    expect(roomMessage.message, {'text': 'hello'});
    expect(utf8.decode(roomMessage.attachment!), 'hi');

    await harness.dispose();
  });

  test('messaging client resolves ad-hoc remote participants by id', () async {
    final harness = await _startMessagingHarness();

    await harness.room.messaging.enable();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    await harness.room.messaging.sendMessage(
      to: RemoteParticipant(client: harness.room, id: 'remote-1', role: 'member'),
      type: 'direct',
      message: {'value': 1},
    );

    expect(harness.server.requests.map((entry) => entry.tool).toList(), ['enable', 'send']);
    final sendInput = harness.server.requests[1].input;
    expect(sendInput['to_participant_id'], 'remote-1');
    expect(jsonDecode(sendInput['message_json'] as String), {'value': 1});

    await harness.dispose();
  });

  test('remote participants notify listeners when attributes or online state change', () async {
    final harness = await _startMessagingHarness();

    await harness.room.messaging.enable();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final remote = harness.room.messaging.remoteParticipants.single;
    var notifications = 0;
    remote.addListener(() {
      notifications++;
    });

    await harness.server.sendIncomingMessage(
      harness.pair.serverProtocol,
      type: 'participant.attributes',
      message: {
        'attributes': {'thread.status.text': 'Thinking'},
      },
    );

    await _waitUntil(() => notifications == 1);
    expect(remote.getAttribute('thread.status.text'), 'Thinking');

    await harness.server.sendIncomingMessage(harness.pair.serverProtocol, type: 'participant.disabled', message: {'id': 'remote-1'});

    await _waitUntil(() => notifications == 2);
    expect(remote.online, isFalse);

    await harness.dispose();
  });

  test('messaging client ignores offline remotes when ignoreOffline is true', () async {
    final harness = await _startMessagingHarness();

    await harness.room.messaging.enable();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final remote = harness.room.messaging.remoteParticipants.single;
    expect(remote.online, isTrue);

    await harness.server.sendIncomingMessage(harness.pair.serverProtocol, type: 'participant.disabled', message: {'id': 'remote-1'});
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(remote.online, isFalse);

    await harness.room.messaging.sendMessage(to: remote, type: 'direct', message: {'value': 1}, ignoreOffline: true);

    expect(harness.server.requests.map((entry) => entry.tool).toList(), ['enable']);

    await harness.dispose();
  });

  test('messaging client throws for offline remotes when ignoreOffline is false', () async {
    final harness = await _startMessagingHarness();

    await harness.room.messaging.enable();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final remote = harness.room.messaging.remoteParticipants.single;

    await harness.server.sendIncomingMessage(harness.pair.serverProtocol, type: 'participant.disabled', message: {'id': 'remote-1'});
    await Future<void>.delayed(const Duration(milliseconds: 10));

    await expectLater(
      harness.room.messaging.sendMessage(to: remote, type: 'direct', message: {'value': 1}),
      throwsA(isA<RoomServerException>().having((exception) => exception.message, 'message', 'the participant was not found')),
    );

    expect(harness.server.requests.map((entry) => entry.tool).toList(), ['enable']);

    await harness.dispose();
  });
}

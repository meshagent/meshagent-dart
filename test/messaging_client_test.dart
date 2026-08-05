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
  int clientProtocolFactoryCalls = 0;

  Protocol get clientProtocol {
    final protocol = _clientProtocol;
    if (protocol == null) {
      throw StateError('client protocol has not been created');
    }
    return protocol;
  }

  Protocol clientProtocolFactory() {
    clientProtocolFactoryCalls++;
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

Future<void> _sendToolCallResponseChunk({required Protocol protocol, required String toolCallId, required Content chunk}) async {
  final packed = unpackMessage(chunk.pack());
  await protocol.send(
    'room.tool_call_response_chunk',
    packMessage({'tool_call_id': toolCallId, 'chunk': packed.header}, packed.payload.isEmpty ? null : packed.payload),
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
  final List<(Protocol, int)> _pendingSendResponses = <(Protocol, int)>[];
  final streamMessages = <Map<String, dynamic>>[];
  int streamCloseCount = 0;
  bool holdSendResponses = false;
  bool failNextStreamMessage = false;
  String? _streamToolCallId;
  int _streamCount = 0;

  Future<void> handleMessage(Protocol protocol, int messageId, String type, Uint8List data) async {
    if (type == 'room.tool_call_request_chunk') {
      await _handleStreamChunk(protocol, messageId, data);
      return;
    }
    if (type != 'room.invoke_tool') {
      return;
    }

    final message = unpackMessage(data);
    final request = message.header;
    if (request['toolkit'] != 'messaging') {
      return;
    }

    final tool = request['tool'] as String;
    if (tool == 'stream') {
      _streamToolCallId = request['tool_call_id'] as String;
      _streamCount++;
      await protocol.send('__response__', ControlContent(method: 'open').pack(), id: messageId);
      return;
    }
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
        if (holdSendResponses) {
          _pendingSendResponses.add((protocol, messageId));
          return;
        }
        await protocol.send('__response__', EmptyContent().pack(), id: messageId);
        return;
      case 'broadcast':
      case 'disable':
        await protocol.send('__response__', EmptyContent().pack(), id: messageId);
        return;
      default:
        throw StateError('unsupported messaging operation: $tool');
    }
  }

  Future<void> _handleStreamChunk(Protocol protocol, int _, Uint8List data) async {
    final toolCallId = _streamToolCallId;
    if (toolCallId == null) {
      return;
    }
    final request = unpackMessage(data);
    final chunkHeader = Map<String, dynamic>.from(request.header['chunk'] as Map);
    final chunk = unpackContent(packMessage(chunkHeader, request.payload.isEmpty ? null : request.payload));
    if (chunk is ControlContent) {
      streamCloseCount++;
      return;
    }
    if (chunk is! JsonContent) {
      throw StateError('messaging.stream expected JsonContent chunks');
    }
    if (chunk.json.containsKey('to_participant_id')) {
      await _sendToolCallResponseChunk(
        protocol: protocol,
        toolCallId: toolCallId,
        chunk: JsonContent(json: {'kind': 'accepted', 'stream_id': 'stream-$_streamCount'}),
      );
      return;
    }

    streamMessages.add(Map<String, dynamic>.from(jsonDecode(chunk.json['message_json'] as String) as Map));
    if (failNextStreamMessage) {
      failNextStreamMessage = false;
      await _sendToolCallResponseChunk(
        protocol: protocol,
        toolCallId: toolCallId,
        chunk: ControlContent(method: 'close', statusCode: 1007, message: 'client disconnected'),
      );
      return;
    }
  }

  Future<void> disconnectStream(Protocol protocol) async {
    final toolCallId = _streamToolCallId;
    if (toolCallId == null) {
      throw StateError('messaging stream has not opened');
    }
    await _sendToolCallResponseChunk(
      protocol: protocol,
      toolCallId: toolCallId,
      chunk: JsonContent(json: const {'kind': 'client_disconnected', 'participant_id': 'remote-1'}),
    );
  }

  Future<void> sendDuplicateAcceptance(Protocol protocol) async {
    final toolCallId = _streamToolCallId;
    if (toolCallId == null) {
      throw StateError('messaging stream has not opened');
    }
    await _sendToolCallResponseChunk(
      protocol: protocol,
      toolCallId: toolCallId,
      chunk: JsonContent(json: const {'kind': 'accepted', 'stream_id': 'duplicate'}),
    );
  }

  Future<void> releaseSendResponses() async {
    for (final (protocol, messageId) in _pendingSendResponses) {
      await protocol.send('__response__', EmptyContent().pack(), id: messageId);
    }
    _pendingSendResponses.clear();
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

  test('dismiss message closes the room without reconnecting', () async {
    final harness = await _startMessagingHarness();
    final messageFuture = harness.room.events.firstWhere((event) {
      return event is RoomMessageEvent && event.message.type == 'dismiss';
    });

    await harness.server.sendIncomingMessage(harness.pair.serverProtocol, type: 'dismiss', message: const {});
    final event = await messageFuture.timeout(const Duration(seconds: 1));
    await harness.room.waitForClose().timeout(const Duration(seconds: 1));

    expect((event as RoomMessageEvent).message.fromParticipantId, 'remote-1');
    expect(harness.room.isClosed, isTrue);
    expect(harness.room.isConnected, isFalse);
    expect(harness.pair.clientProtocolFactoryCalls, 1);

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

  test('messaging client pipelines queued sends before their responses', () async {
    final harness = await _startMessagingHarness();

    await harness.room.messaging.enable();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final remote = harness.room.messaging.remoteParticipants.single;
    harness.server.holdSendResponses = true;

    await harness.room.messaging.sendMessage(to: remote, type: 'delta', message: {'index': 1}, ignoreOffline: true);
    await harness.room.messaging.sendMessage(to: remote, type: 'delta', message: {'index': 2}, ignoreOffline: true);

    await _waitUntil(() => harness.server.requests.where((request) => request.tool == 'send').length == 2);
    final sends = harness.server.requests.where((request) => request.tool == 'send').toList();
    expect(sends.map((request) => jsonDecode(request.input['message_json'] as String)['index']).toList(), [1, 2]);

    await harness.server.releaseSendResponses();
    await harness.dispose();
  });

  test('messaging stream latency does not wait for chunk responses', () async {
    final harness = await _startMessagingHarness();

    await harness.room.messaging.enable();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final remote = harness.room.messaging.remoteParticipants.single;
    final stream = await harness.room.messaging.stream(
      to: remote,
      type: 'meshagent.chat.thread.subscribe',
      message: {'type': 'thread.open', 'thread_id': 'thread-1'},
    );
    final first = stream.sendMessage(type: 'agent-message', message: {'index': 1});
    final second = stream.sendMessage(type: 'agent-message', message: {'index': 2});

    await _waitUntil(() => harness.server.streamMessages.length == 2);
    expect(harness.server.streamMessages, [
      {'index': 1},
      {'index': 2},
    ]);
    await Future.wait([first, second]);
    expect(harness.server.streamMessages, [
      {'index': 1},
      {'index': 2},
    ]);

    await stream.close();
    await _waitUntil(() => harness.server.streamCloseCount == 1);
    expect(stream.closed, isTrue);
    await harness.dispose();
  });

  test('messaging stream surfaces send failures and remote disconnects', () async {
    final harness = await _startMessagingHarness();

    await harness.room.messaging.enable();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final remote = harness.room.messaging.remoteParticipants.single;

    final failed = await harness.room.messaging.stream(to: remote, type: 'test', message: {'open': true});
    harness.server.failNextStreamMessage = true;
    final failureEvent = failed.events.first;
    await failed.sendMessage(type: 'test', message: {'index': 1});
    final failure = await failureEvent;
    expect(failure, isA<MessagingStreamClosed>().having((event) => event.message, 'message', contains('client disconnected')));
    await _waitUntil(() => failed.closed);
    await failed.close();

    final disconnected = await harness.room.messaging.stream(to: remote, type: 'test', message: {'open': true});
    final eventFuture = disconnected.events.first;
    await harness.server.disconnectStream(harness.pair.serverProtocol);
    final event = await eventFuture;
    expect(event, isA<MessagingStreamClientDisconnected>());
    await _waitUntil(() => disconnected.closed);
    await disconnected.close();
    await expectLater(
      disconnected.sendMessage(type: 'test', message: const {}),
      throwsA(isA<RoomServerException>().having((exception) => exception.message, 'message', contains('closed'))),
    );

    await harness.dispose();
  });

  test('messaging stream rejects duplicate acceptance and becomes terminal', () async {
    final harness = await _startMessagingHarness();

    await harness.room.messaging.enable();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final remote = harness.room.messaging.remoteParticipants.single;
    final stream = await harness.room.messaging.stream(to: remote, type: 'test', message: {'open': true});
    final eventFuture = stream.events.first;

    await harness.server.sendDuplicateAcceptance(harness.pair.serverProtocol);

    final event = await eventFuture;
    expect(event, isA<MessagingStreamClosed>().having((closed) => closed.message, 'message', contains('unexpected chunk')));
    await _waitUntil(() => stream.closed);
    await expectLater(
      stream.sendMessage(type: 'late', message: const {}),
      throwsA(isA<RoomServerException>().having((exception) => exception.message, 'message', contains('closed'))),
    );
    await stream.close();

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

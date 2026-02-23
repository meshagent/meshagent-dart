import 'dart:async';
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
    await _clientToServer.close();
    if (!_serverToClient.isClosed) {
      await _serverToClient.close();
    }
  }
}

Future<void> _sendRoomReady(Protocol protocol) async {
  await protocol.send(
    "room_ready",
    packMessage({"room_name": "test-room", "room_url": "ws://example/rooms/test-room", "session_id": "session-1"}),
  );
}

Matcher _roomServerErrorContaining(String expected) {
  return predicate((error) => error is RoomServerException && error.message.contains(expected));
}

void main() {
  test('room sendRequest resolves from __response__', () async {
    final pair = _ProtocolPair();
    pair.serverProtocol.start(
      onMessage: (protocol, messageId, type, data) async {
        if (type != "test.echo") {
          return;
        }
        await protocol.send("__response__", JsonContent(json: {"ok": true}).pack(), id: messageId);
      },
    );

    final room = RoomClient(protocol: pair.clientProtocol);
    final startFuture = room.start();
    await _sendRoomReady(pair.serverProtocol);
    await startFuture;

    final result = await room.sendRequest("test.echo", {"x": 1}).timeout(const Duration(seconds: 1));
    expect(result, isA<JsonContent>());
    expect((result as JsonContent).json["ok"], true);

    await pair.dispose();
  });

  test('invokeTool fails fast when server returns invoke response error', () async {
    final pair = _ProtocolPair();
    pair.serverProtocol.start(
      onMessage: (protocol, messageId, type, data) async {
        if (type != "agent.invoke_tool") {
          return;
        }
        await protocol.send("__response__", ErrorContent(text: "tool 'stream' requires streamed input").pack(), id: messageId);
      },
    );

    final room = RoomClient(protocol: pair.clientProtocol);
    final startFuture = room.start();
    await _sendRoomReady(pair.serverProtocol);
    await startFuture;

    final invokeFuture = room.agents.invokeTool(
      toolkit: "test-stream-toolkit",
      tool: "stream",
      input: ToolContentInput(JsonContent(json: {})),
    );

    await expectLater(invokeFuture.timeout(const Duration(seconds: 1)), throwsA(_roomServerErrorContaining("requires streamed input")));

    await pair.dispose();
  });

  test('invokeTool fails when error chunk arrives before invoke response', () async {
    final pair = _ProtocolPair();
    pair.serverProtocol.start(
      onMessage: (protocol, messageId, type, data) async {
        if (type != "agent.invoke_tool") {
          return;
        }

        final request = unpackMessage(data).header;
        final toolCallId = request["tool_call_id"] as String;
        await protocol.send(
          "agent.tool_call_response_chunk",
          packMessage({
            "tool_call_id": toolCallId,
            "toolkit": "test-stream-toolkit",
            "tool": "stream",
            "chunk": {"type": "error", "text": "tool 'stream' requires streamed input"},
          }),
        );
      },
    );

    final room = RoomClient(protocol: pair.clientProtocol);
    final startFuture = room.start();
    await _sendRoomReady(pair.serverProtocol);
    await startFuture;

    final invokeFuture = room.agents.invokeTool(
      toolkit: "test-stream-toolkit",
      tool: "stream",
      input: ToolContentInput(JsonContent(json: {})),
    );

    await expectLater(invokeFuture.timeout(const Duration(seconds: 1)), throwsA(_roomServerErrorContaining("requires streamed input")));

    await pair.dispose();
  });

  test('invokeTool forwards multiple request chunks before close', () async {
    final pair = _ProtocolPair();
    final received = <String>[];
    pair.serverProtocol.start(
      onMessage: (protocol, messageId, type, data) async {
        if (type == "agent.invoke_tool") {
          await protocol.send("__response__", ControlContent(method: "open").pack(), id: messageId);
          return;
        }
        if (type != "agent.tool_call_request_chunk") {
          return;
        }

        final message = unpackMessage(data).header;
        final chunk = message["chunk"] as Map<String, dynamic>;
        final chunkType = chunk["type"] as String;
        if (chunkType == "text") {
          received.add(chunk["text"] as String);
        } else if (chunkType == "control") {
          received.add("control:${chunk["method"]}");
        } else {
          received.add(chunkType);
        }

        await protocol.send("__response__", EmptyContent().pack(), id: messageId);
      },
    );

    final room = RoomClient(protocol: pair.clientProtocol);
    final startFuture = room.start();
    await _sendRoomReady(pair.serverProtocol);
    await startFuture;

    final input = StreamController<Content>();
    final response = await room.agents.invokeTool(toolkit: "test-stream-toolkit", tool: "stream", input: ToolStreamInput(input.stream));
    expect(response, isA<ToolStreamOutput>());

    input.add(TextContent(text: "first"));
    input.add(TextContent(text: "second"));
    await input.close();

    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(received, containsAllInOrder(["first", "second", "control:close"]));

    await pair.dispose();
  });
}

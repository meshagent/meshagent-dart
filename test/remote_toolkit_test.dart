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

  Future<void> disconnectClient() async {
    try {
      serverProtocol.dispose();
    } catch (_) {}
    if (!_serverToClient.isClosed) {
      await _serverToClient.close();
    }
  }

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

Content _decodeResponseChunk(Uint8List data) {
  final message = unpackMessage(data);
  final chunkHeader = message.header["chunk"] as Map<String, dynamic>;
  return unpackContent(packMessage(Map<String, dynamic>.from(chunkHeader), message.payload.isEmpty ? null : message.payload));
}

class _EchoTool extends FunctionTool {
  _EchoTool()
    : super(
        name: "echo",
        title: "Echo",
        description: "echo tool",
        inputSchema: const {"type": "object", "additionalProperties": false, "properties": {}},
      );

  @override
  Future<Content> execute(ToolContext context, Map<String, dynamic> arguments) async {
    return JsonContent(json: {"ok": true});
  }
}

class _RequiredValueTool extends FunctionTool {
  _RequiredValueTool()
    : super(
        name: "required_value",
        title: "RequiredValue",
        description: "requires value in input",
        inputSchema: const {
          "type": "object",
          "additionalProperties": false,
          "required": ["value"],
          "properties": {
            "value": {"type": "string"},
          },
        },
      );

  @override
  Future<Content> execute(ToolContext context, Map<String, dynamic> arguments) async {
    return JsonContent(json: {"ok": true});
  }
}

class _InvalidOutputTool extends FunctionTool {
  _InvalidOutputTool()
    : super(
        name: "invalid_output",
        title: "InvalidOutput",
        description: "returns output that does not match schema",
        inputSchema: const {"type": "object", "additionalProperties": false, "properties": {}},
        outputSpec: ToolContentSpec(
          types: [ToolContentType.json],
          stream: false,
          schema: {
            "type": "object",
            "required": ["ok"],
            "properties": {
              "ok": {"type": "boolean"},
            },
          },
        ),
      );

  @override
  Future<Content> execute(ToolContext context, Map<String, dynamic> arguments) async {
    return JsonContent(json: {"missing": true});
  }
}

class _CollectStreamTool extends ContentTool {
  _CollectStreamTool()
    : super(
        name: "collect",
        title: "Collect",
        description: "collect streamed text",
        inputSchema: const {"type": "object", "additionalProperties": false, "properties": {}},
        inputSpec: ToolContentSpec(types: [ToolContentType.text], stream: true),
      );

  @override
  Future<ToolOutput> execute(ToolContext context, ToolInput input) async {
    if (input is! ToolStreamInput) {
      throw Exception("collect requires streamed input");
    }
    final parts = <String>[];
    await for (final chunk in input.chunks) {
      if (chunk is TextContent) {
        parts.add(chunk.text);
      }
    }
    return ToolContentOutput(JsonContent(json: {"joined": parts.join(",")}));
  }
}

class _EchoContentInputTool extends ContentTool {
  _EchoContentInputTool()
    : super(
        name: "echo_content_input",
        title: "EchoContentInput",
        description: "echoes the first content input item",
        inputSchema: const {"type": "object", "additionalProperties": false, "properties": {}},
      );

  @override
  Future<ToolOutput> execute(ToolContext context, ToolInput input) async {
    if (input is! ToolContentInput) {
      throw Exception("echo_content_input requires single content input");
    }
    final content = input.content;
    dynamic first;
    if (content is JsonContent) {
      first = content.json;
    } else if (content is TextContent) {
      first = content.text;
    } else if (content is EmptyContent) {
      first = null;
    }
    return ToolContentOutput(JsonContent(json: {"count": 1, "first": first}));
  }
}

class _WaitForDisconnectTool extends ContentTool {
  _WaitForDisconnectTool()
    : super(
        name: "wait_for_disconnect",
        title: "WaitForDisconnect",
        description: "waits for request stream termination",
        inputSchema: const {"type": "object", "additionalProperties": false, "properties": {}},
        inputSpec: ToolContentSpec(types: [ToolContentType.text], stream: true),
      );

  final Completer<void> started = Completer<void>();
  final Completer<Object?> ended = Completer<Object?>();

  @override
  Future<ToolOutput> execute(ToolContext context, ToolInput input) async {
    if (input is! ToolStreamInput) {
      throw Exception("wait_for_disconnect requires streamed input");
    }
    if (!started.isCompleted) {
      started.complete();
    }
    return ToolStreamOutput(
      (() async* {
        try {
          await for (final _ in input.chunks) {}
          if (!ended.isCompleted) {
            ended.complete(null);
          }
          yield JsonContent(json: {"closed": true});
        } catch (error) {
          if (!ended.isCompleted) {
            ended.complete(error);
          }
          rethrow;
        }
      })(),
    );
  }
}

void main() {
  test('RemoteToolkit forwards streamed request input to ContentTool', () async {
    final pair = _ProtocolPair();
    final responses = <Content>[];
    final responseChunks = <Content>[];

    pair.serverProtocol.start(
      onMessage: (protocol, messageId, type, data) async {
        if (type == "agent.register_toolkit") {
          await protocol.send("__response__", JsonContent(json: {"id": "toolkit-registration"}).pack(), id: messageId);
          return;
        }
        if (type == "agent.unregister_toolkit") {
          await protocol.send("__response__", EmptyContent().pack(), id: messageId);
          return;
        }
        if (type == "agent.tool_call_response") {
          responses.add(unpackContent(data));
          return;
        }
        if (type == "agent.tool_call_response_chunk") {
          responseChunks.add(_decodeResponseChunk(data));
        }
      },
    );

    final room = RoomClient(protocol: pair.clientProtocol);
    final startFuture = room.start();
    await _sendRoomReady(pair.serverProtocol);
    await startFuture;

    final toolkit = RemoteToolkit(name: "test", room: room, tools: [_CollectStreamTool()]);
    await toolkit.start(public: true);

    await pair.serverProtocol.send(
      "agent.tool_call.test",
      packMessage({
        "name": "collect",
        "arguments": {"type": "control", "method": "open"},
        "tool_call_id": "call-1",
      }),
    );
    await pair.serverProtocol.send(
      "agent.tool_call_request_chunk.test",
      packMessage({
        "tool_call_id": "call-1",
        "chunk": {"type": "text", "text": "hello"},
      }),
    );
    await pair.serverProtocol.send(
      "agent.tool_call_request_chunk.test",
      packMessage({
        "tool_call_id": "call-1",
        "chunk": {"type": "text", "text": "world"},
      }),
    );
    await pair.serverProtocol.send(
      "agent.tool_call_request_chunk.test",
      packMessage({
        "tool_call_id": "call-1",
        "chunk": {"type": "control", "method": "close"},
      }),
    );

    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(responses.length, 1);
    expect(responses.first, isA<JsonContent>());
    expect((responses.first as JsonContent).json["joined"], "hello,world");
    expect(responseChunks, isEmpty);

    await toolkit.stop();
    await pair.dispose();
  });

  test('RemoteToolkit rejects streamed input for non-stream Tool', () async {
    final pair = _ProtocolPair();
    final responses = <Content>[];

    pair.serverProtocol.start(
      onMessage: (protocol, messageId, type, data) async {
        if (type == "agent.register_toolkit") {
          await protocol.send("__response__", JsonContent(json: {"id": "toolkit-registration"}).pack(), id: messageId);
          return;
        }
        if (type == "agent.unregister_toolkit") {
          await protocol.send("__response__", EmptyContent().pack(), id: messageId);
          return;
        }
        if (type == "agent.tool_call_response") {
          responses.add(unpackContent(data));
        }
      },
    );

    final room = RoomClient(protocol: pair.clientProtocol);
    final startFuture = room.start();
    await _sendRoomReady(pair.serverProtocol);
    await startFuture;

    final toolkit = RemoteToolkit(name: "test", room: room, tools: [_EchoTool()]);
    await toolkit.start(public: true);

    await pair.serverProtocol.send(
      "agent.tool_call.test",
      packMessage({
        "name": "echo",
        "arguments": {"type": "control", "method": "open"},
        "tool_call_id": "call-1",
      }),
    );

    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(responses.length, 1);
    expect(responses.first, isA<ErrorContent>());
    expect((responses.first as ErrorContent).text, contains("input_spec requires"));

    await toolkit.stop();
    await pair.dispose();
  });

  test('RemoteToolkit accepts non-stream input for ContentTool', () async {
    final pair = _ProtocolPair();
    final responses = <Content>[];

    pair.serverProtocol.start(
      onMessage: (protocol, messageId, type, data) async {
        if (type == "agent.register_toolkit") {
          await protocol.send("__response__", JsonContent(json: {"id": "toolkit-registration"}).pack(), id: messageId);
          return;
        }
        if (type == "agent.unregister_toolkit") {
          await protocol.send("__response__", EmptyContent().pack(), id: messageId);
          return;
        }
        if (type == "agent.tool_call_response") {
          responses.add(unpackContent(data));
        }
      },
    );

    final room = RoomClient(protocol: pair.clientProtocol);
    final startFuture = room.start();
    await _sendRoomReady(pair.serverProtocol);
    await startFuture;

    final toolkit = RemoteToolkit(name: "test", room: room, tools: [_EchoContentInputTool()]);
    await toolkit.start(public: true);

    await pair.serverProtocol.send(
      "agent.tool_call.test",
      packMessage({
        "name": "echo_content_input",
        "arguments": {
          "type": "json",
          "json": {"value": 1},
        },
        "tool_call_id": "call-1",
      }),
    );

    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(responses.length, 1);
    expect(responses.first, isA<JsonContent>());
    final response = responses.first as JsonContent;
    expect(response.json["count"], 1);
    expect(response.json["first"], {"value": 1});

    await toolkit.stop();
    await pair.dispose();
  });

  test('RemoteToolkit validates unary input against JSON schema', () async {
    final pair = _ProtocolPair();
    final responses = <Content>[];

    pair.serverProtocol.start(
      onMessage: (protocol, messageId, type, data) async {
        if (type == "agent.register_toolkit") {
          await protocol.send("__response__", JsonContent(json: {"id": "toolkit-registration"}).pack(), id: messageId);
          return;
        }
        if (type == "agent.unregister_toolkit") {
          await protocol.send("__response__", EmptyContent().pack(), id: messageId);
          return;
        }
        if (type == "agent.tool_call_response") {
          responses.add(unpackContent(data));
        }
      },
    );

    final room = RoomClient(protocol: pair.clientProtocol);
    final startFuture = room.start();
    await _sendRoomReady(pair.serverProtocol);
    await startFuture;

    final toolkit = RemoteToolkit(name: "test", room: room, tools: [_RequiredValueTool()]);
    await toolkit.start(public: true);

    await pair.serverProtocol.send(
      "agent.tool_call.test",
      packMessage({
        "name": "required_value",
        "arguments": {"type": "json", "json": {}},
        "tool_call_id": "call-1",
      }),
    );

    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(responses.length, 1);
    expect(responses.first, isA<ErrorContent>());
    expect((responses.first as ErrorContent).text, contains("input does not match input_schema"));

    await toolkit.stop();
    await pair.dispose();
  });

  test('RemoteToolkit validates unary output against JSON schema', () async {
    final pair = _ProtocolPair();
    final responses = <Content>[];

    pair.serverProtocol.start(
      onMessage: (protocol, messageId, type, data) async {
        if (type == "agent.register_toolkit") {
          await protocol.send("__response__", JsonContent(json: {"id": "toolkit-registration"}).pack(), id: messageId);
          return;
        }
        if (type == "agent.unregister_toolkit") {
          await protocol.send("__response__", EmptyContent().pack(), id: messageId);
          return;
        }
        if (type == "agent.tool_call_response") {
          responses.add(unpackContent(data));
        }
      },
    );

    final room = RoomClient(protocol: pair.clientProtocol);
    final startFuture = room.start();
    await _sendRoomReady(pair.serverProtocol);
    await startFuture;

    final toolkit = RemoteToolkit(name: "test", room: room, tools: [_InvalidOutputTool()]);
    await toolkit.start(public: true);

    await pair.serverProtocol.send(
      "agent.tool_call.test",
      packMessage({
        "name": "invalid_output",
        "arguments": {"type": "json", "json": {}},
        "tool_call_id": "call-1",
      }),
    );

    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(responses.length, 1);
    expect(responses.first, isA<ErrorContent>());
    expect((responses.first as ErrorContent).text, contains("output does not match output_schema"));

    await toolkit.stop();
    await pair.dispose();
  });

  test('RemoteToolkit closes request stream when room disconnects mid-call', () async {
    final pair = _ProtocolPair();
    final tool = _WaitForDisconnectTool();

    pair.serverProtocol.start(
      onMessage: (protocol, messageId, type, data) async {
        if (type == "agent.register_toolkit") {
          await protocol.send("__response__", JsonContent(json: {"id": "toolkit-registration"}).pack(), id: messageId);
          return;
        }
        if (type == "agent.unregister_toolkit") {
          await protocol.send("__response__", EmptyContent().pack(), id: messageId);
        }
      },
    );

    final room = RoomClient(protocol: pair.clientProtocol);
    final startFuture = room.start();
    await _sendRoomReady(pair.serverProtocol);
    await startFuture;

    final toolkit = RemoteToolkit(name: "test", room: room, tools: [tool]);
    await toolkit.start(public: true);

    await pair.serverProtocol.send(
      "agent.tool_call.test",
      packMessage({
        "name": "wait_for_disconnect",
        "arguments": {"type": "control", "method": "open"},
        "tool_call_id": "call-disconnect",
      }),
    );

    await tool.started.future.timeout(const Duration(seconds: 1));
    await pair.disconnectClient();

    await expectLater(tool.ended.future.timeout(const Duration(seconds: 1)), completes);

    await pair.dispose();
  });
}

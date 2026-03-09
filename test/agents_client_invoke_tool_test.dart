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
        if (type != "room.invoke_tool") {
          return;
        }
        await protocol.send("__response__", ErrorContent(text: "tool 'stream' requires streamed input", code: 1002).pack(), id: messageId);
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

    try {
      await invokeFuture.timeout(const Duration(seconds: 1));
      fail("expected RoomServerException");
    } on RoomServerException catch (ex) {
      expect(ex.message, contains("requires streamed input"));
      expect(ex.code, 1002);
    }

    await pair.dispose();
  });

  test('invokeTool fails when error chunk arrives before invoke response', () async {
    final pair = _ProtocolPair();
    pair.serverProtocol.start(
      onMessage: (protocol, messageId, type, data) async {
        if (type != "room.invoke_tool") {
          return;
        }

        final request = unpackMessage(data).header;
        final toolCallId = request["tool_call_id"] as String;
        await protocol.send(
          "room.tool_call_response_chunk",
          packMessage({
            "tool_call_id": toolCallId,
            "toolkit": "test-stream-toolkit",
            "tool": "stream",
            "chunk": {"type": "error", "text": "tool 'stream' requires streamed input", "code": 1002},
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

    try {
      await invokeFuture.timeout(const Duration(seconds: 1));
      fail("expected RoomServerException");
    } on RoomServerException catch (ex) {
      expect(ex.message, contains("requires streamed input"));
      expect(ex.code, 1002);
    }

    await pair.dispose();
  });

  test('invokeTool forwards multiple request chunks before close', () async {
    final pair = _ProtocolPair();
    final received = <String>[];
    pair.serverProtocol.start(
      onMessage: (protocol, messageId, type, data) async {
        if (type == "room.invoke_tool") {
          await protocol.send("__response__", ControlContent(method: "open").pack(), id: messageId);
          return;
        }
        if (type != "room.tool_call_request_chunk") {
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

  test('invokeTool stream emits error when request chunk send fails after open', () async {
    final pair = _ProtocolPair();
    var sawTextChunk = false;
    pair.serverProtocol.start(
      onMessage: (protocol, messageId, type, data) async {
        if (type == "room.invoke_tool") {
          await protocol.send("__response__", ControlContent(method: "open").pack(), id: messageId);
          return;
        }
        if (type != "room.tool_call_request_chunk") {
          return;
        }

        final message = unpackMessage(data).header;
        final chunk = Map<String, dynamic>.from(message["chunk"] as Map);
        final chunkType = chunk["type"] as String?;
        if (chunkType == "text") {
          sawTextChunk = true;
          await protocol.send("__response__", ErrorContent(text: "schema mismatch").pack(), id: messageId);
          return;
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

    final output = response as ToolStreamOutput;
    final streamDone = Completer<void>();
    Object? streamError;
    output.stream.listen(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        streamError = error;
        if (!streamDone.isCompleted) {
          streamDone.complete();
        }
      },
      onDone: () {
        if (!streamDone.isCompleted) {
          streamDone.complete();
        }
      },
      cancelOnError: false,
    );

    input.add(TextContent(text: "bad"));
    await input.close();

    await streamDone.future.timeout(const Duration(seconds: 1));
    expect(sawTextChunk, isTrue);
    expect(streamError, isA<RoomServerException>());
    expect((streamError as RoomServerException).message, contains("schema mismatch"));

    await pair.dispose();
  });

  test('invokeTool stream delivers ErrorContent chunk and then closes when server closes stream', () async {
    final pair = _ProtocolPair();
    String? toolCallId;
    var sentFailureChunks = false;
    pair.serverProtocol.start(
      onMessage: (protocol, messageId, type, data) async {
        if (type == "room.invoke_tool") {
          final request = unpackMessage(data).header;
          toolCallId = request["tool_call_id"] as String;
          await protocol.send("__response__", ControlContent(method: "open").pack(), id: messageId);
          return;
        }
        if (type != "room.tool_call_request_chunk") {
          return;
        }

        await protocol.send("__response__", EmptyContent().pack(), id: messageId);
        if (sentFailureChunks || toolCallId == null) {
          return;
        }
        sentFailureChunks = true;

        await protocol.send(
          "room.tool_call_response_chunk",
          packMessage({
            "tool_call_id": toolCallId,
            "toolkit": "test-stream-toolkit",
            "tool": "stream",
            "chunk": {"type": "error", "text": "schema mismatch"},
          }),
        );
        await protocol.send(
          "room.tool_call_response_chunk",
          packMessage({
            "tool_call_id": toolCallId,
            "toolkit": "test-stream-toolkit",
            "tool": "stream",
            "chunk": {"type": "control", "method": "close"},
          }),
        );
      },
    );

    final room = RoomClient(protocol: pair.clientProtocol);
    final startFuture = room.start();
    await _sendRoomReady(pair.serverProtocol);
    await startFuture;

    final input = StreamController<Content>();
    final response = await room.agents.invokeTool(toolkit: "test-stream-toolkit", tool: "stream", input: ToolStreamInput(input.stream));
    expect(response, isA<ToolStreamOutput>());
    final streamResponse = response as ToolStreamOutput;

    final received = <Content>[];
    Object? streamError;
    var done = false;
    final doneCompleter = Completer<void>();
    streamResponse.stream.listen(
      received.add,
      onError: (Object error, StackTrace stackTrace) {
        streamError = error;
        if (!doneCompleter.isCompleted) {
          doneCompleter.complete();
        }
      },
      onDone: () {
        done = true;
        if (!doneCompleter.isCompleted) {
          doneCompleter.complete();
        }
      },
      cancelOnError: false,
    );

    input.add(TextContent(text: "bad"));
    await input.close();

    await doneCompleter.future.timeout(const Duration(seconds: 1));
    expect(streamError, isNull);
    expect(done, isTrue);
    expect(received.length, 1);
    expect(received.first, isA<ErrorContent>());
    expect((received.first as ErrorContent).text, contains("schema mismatch"));

    await pair.dispose();
  });

  test('invokeTool stream raises when close control chunk is abnormal', () async {
    final pair = _ProtocolPair();
    String? toolCallId;
    var sentClose = false;
    pair.serverProtocol.start(
      onMessage: (protocol, messageId, type, data) async {
        if (type == "room.invoke_tool") {
          final request = unpackMessage(data).header;
          toolCallId = request["tool_call_id"] as String;
          await protocol.send("__response__", ControlContent(method: "open").pack(), id: messageId);
          return;
        }
        if (type != "room.tool_call_request_chunk") {
          return;
        }

        await protocol.send("__response__", EmptyContent().pack(), id: messageId);
        if (sentClose || toolCallId == null) {
          return;
        }
        sentClose = true;
        await protocol.send(
          "room.tool_call_response_chunk",
          packMessage({
            "tool_call_id": toolCallId,
            "toolkit": "test-stream-toolkit",
            "tool": "stream",
            "chunk": {
              "type": "control",
              "method": "close",
              "status_code": ControlCloseStatus.invalidData.code,
              "message": "schema mismatch",
            },
          }),
        );
      },
    );

    final room = RoomClient(protocol: pair.clientProtocol);
    final startFuture = room.start();
    await _sendRoomReady(pair.serverProtocol);
    await startFuture;

    final input = StreamController<Content>();
    final response = await room.agents.invokeTool(toolkit: "test-stream-toolkit", tool: "stream", input: ToolStreamInput(input.stream));
    expect(response, isA<ToolStreamOutput>());
    final streamResponse = response as ToolStreamOutput;

    Object? streamError;
    final doneCompleter = Completer<void>();
    streamResponse.stream.listen(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        streamError = error;
        if (!doneCompleter.isCompleted) {
          doneCompleter.complete();
        }
      },
      onDone: () {
        if (!doneCompleter.isCompleted) {
          doneCompleter.complete();
        }
      },
      cancelOnError: false,
    );

    input.add(TextContent(text: "bad"));
    await input.close();

    await doneCompleter.future.timeout(const Duration(seconds: 1));
    expect(streamError, isA<RoomServerException>());
    final roomError = streamError as RoomServerException;
    expect(roomError.message, contains("schema mismatch"));
    expect(roomError.statusCode, ControlCloseStatus.invalidData.code);

    await pair.dispose();
  });

  test('invokeTool stream preserves abnormal close error when close arrives before listener attaches', () async {
    final pair = _ProtocolPair();
    pair.serverProtocol.start(
      onMessage: (protocol, messageId, type, data) async {
        if (type != "room.invoke_tool") {
          return;
        }
        final request = unpackMessage(data).header;
        final toolCallId = request["tool_call_id"] as String;
        await protocol.send("__response__", ControlContent(method: "open").pack(), id: messageId);
        await protocol.send(
          "room.tool_call_response_chunk",
          packMessage({
            "tool_call_id": toolCallId,
            "toolkit": "test-stream-toolkit",
            "tool": "stream",
            "chunk": {
              "type": "control",
              "method": "close",
              "status_code": ControlCloseStatus.invalidData.code,
              "message": "schema mismatch",
            },
          }),
        );
      },
    );

    final room = RoomClient(protocol: pair.clientProtocol);
    final startFuture = room.start();
    await _sendRoomReady(pair.serverProtocol);
    await startFuture;

    final response = await room.agents.invokeTool(
      toolkit: "test-stream-toolkit",
      tool: "stream",
      input: ToolContentInput(JsonContent(json: {})),
    );
    expect(response, isA<ToolStreamOutput>());
    final streamResponse = response as ToolStreamOutput;

    Object? streamError;
    final doneCompleter = Completer<void>();
    streamResponse.stream.listen(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        streamError = error;
        if (!doneCompleter.isCompleted) {
          doneCompleter.complete();
        }
      },
      onDone: () {
        if (!doneCompleter.isCompleted) {
          doneCompleter.complete();
        }
      },
      cancelOnError: false,
    );

    await doneCompleter.future.timeout(const Duration(seconds: 1));
    expect(streamError, isA<RoomServerException>());
    final roomError = streamError as RoomServerException;
    expect(roomError.message, contains("schema mismatch"));
    expect(roomError.statusCode, ControlCloseStatus.invalidData.code);

    await pair.dispose();
  });
}

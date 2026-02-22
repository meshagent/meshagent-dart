import 'dart:async';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:meshagent/document.dart';
import 'package:meshagent/protocol.dart';
import 'package:meshagent/room_server_client.dart';
import 'package:uuid/uuid.dart';

sealed class ToolOutput {
  const ToolOutput();
}

class ToolChunkOutput extends ToolOutput {
  const ToolChunkOutput(this.chunk);

  final Chunk chunk;
}

class ToolStreamOutput extends ToolOutput {
  const ToolStreamOutput(this.stream);

  final Stream<Chunk> stream;
}

class ToolCallResponseChunk {
  ToolCallResponseChunk({required this.toolCallId, required this.chunk, this.toolkit, this.tool});

  final String toolCallId;
  final Chunk chunk;
  final String? toolkit;
  final String? tool;
}

sealed class ToolInput {
  const ToolInput();
}

class ToolContentInput extends ToolInput {
  const ToolContentInput(this.chunk);

  final Chunk chunk;
}

class ToolStreamInput extends ToolInput {
  const ToolStreamInput(this.chunks);

  final Stream<Chunk> chunks;
}

class AgentsClient extends ChangeEmitter {
  AgentsClient({required this.room}) {
    room.protocol.addHandler("agent.tool_call_response_chunk", _handleToolCallResponseChunk);
    unawaited(
      room.protocol.done.then((error) {
        final wrapped = error == null
            ? RoomServerException("room client was closed before tool call completed")
            : RoomServerException("room client closed with error: $error");
        _failToolCallStreams(error: wrapped);
      }),
    );
  }

  final RoomClient room;
  final _uuid = const Uuid();
  final _toolCallStreams = <String, StreamController<Chunk>>{};
  final _pendingInvokeResponses = <String, Completer<Chunk>>{};
  final _toolCallResponseChunks = StreamController<ToolCallResponseChunk>.broadcast();

  Future<void> _failToolCallStreams({required RoomServerException error}) async {
    if (_toolCallStreams.isEmpty) {
      return;
    }

    final streams = Map<String, StreamController<Chunk>>.from(_toolCallStreams);
    _toolCallStreams.clear();
    for (final stream in streams.values) {
      if (!stream.isClosed) {
        stream.addError(error);
        unawaited(stream.close());
      }
    }
  }

  Stream<ToolCallResponseChunk> get toolCallResponseChunks {
    return _toolCallResponseChunks.stream;
  }

  Future<void> call({required String name, required String url, required Map<String, dynamic> arguments}) async {
    await room.sendRequest("agent.call", {"name": name, "url": url, "arguments": arguments});
  }

  Future<List<ToolkitDescription>> listToolkits({String? participantId, String? participantName, int? timeout}) async {
    final request = <String, dynamic>{};
    if (participantId != null) {
      request["participant_id"] = participantId;
    }
    if (participantName != null) {
      request["participant_name"] = participantName;
    }
    if (timeout != null) {
      request["timeout"] = timeout;
    }

    final result = (await room.sendRequest("agent.list_toolkits", request)) as JsonChunk;

    final toolkits = <ToolkitDescription>[];
    final tools = result.json["tools"];

    for (final name in tools.keys) {
      final json = tools[name];
      toolkits.add(ToolkitDescription.fromJson(json, name: name));
    }

    return toolkits;
  }

  Future<Chunk> _awaitInvokeResponse({required String toolCallId, required Future<Chunk> requestFuture}) async {
    final pending = Completer<Chunk>();
    _pendingInvokeResponses[toolCallId] = pending;
    try {
      return await Future.any([requestFuture, pending.future]);
    } finally {
      final current = _pendingInvokeResponses[toolCallId];
      if (identical(current, pending)) {
        _pendingInvokeResponses.remove(toolCallId);
      }
    }
  }

  Future<ToolOutput> invokeTool({
    required String toolkit,
    required String tool,
    required ToolInput input,
    String? participantId,
    String? onBehalfOfId,
    Map<String, dynamic>? callerContext,
  }) async {
    final toolCallId = _uuid.v4();
    final controller = StreamController<Chunk>(
      onCancel: () {
        _toolCallStreams.remove(toolCallId);
      },
    );
    _toolCallStreams[toolCallId] = controller;

    final request = <String, dynamic>{
      "toolkit": toolkit,
      "tool": tool,
      "participant_id": participantId,
      "on_behalf_of_id": onBehalfOfId,
      "caller_context": callerContext,
      "tool_call_id": toolCallId,
    };

    Uint8List? invokeData;
    Future<void>? inputTask;

    if (input is ToolContentInput) {
      final packedInput = unpackMessage(input.chunk.pack());
      request["arguments"] = packedInput.header;
      invokeData = packedInput.payload.isEmpty ? null : packedInput.payload;
    } else if (input is ToolStreamInput) {
      final openChunk = unpackMessage(ControlChunk(method: "open").pack());
      request["arguments"] = openChunk.header;
      inputTask = _streamInvokeToolRequestChunks(toolCallId: toolCallId, inputChunks: input.chunks);
    } else {
      await _closeToolCallStream(toolCallId: toolCallId, controller: controller);
      throw RoomServerException("invokeTool input must be ToolContentInput or ToolStreamInput");
    }

    try {
      final response = await _awaitInvokeResponse(
        toolCallId: toolCallId,
        requestFuture: room.sendRequest("agent.invoke_tool", request, data: invokeData),
      );

      if (response is ControlChunk && response.method == "open") {
        if (inputTask != null) {
          unawaited(
            inputTask.catchError((Object error, StackTrace stackTrace) async {
              final wrapped = error is RoomServerException ? error : RoomServerException("request stream failed: $error");
              if (!controller.isClosed) {
                controller.addError(wrapped, stackTrace);
              }
              await _closeToolCallStream(toolCallId: toolCallId, controller: controller);
            }),
          );
        }
        return ToolStreamOutput(controller.stream);
      }

      if (inputTask != null) {
        await inputTask;
      }
      await _closeToolCallStream(toolCallId: toolCallId, controller: controller);
      return ToolChunkOutput(response);
    } catch (error, stackTrace) {
      if (inputTask != null) {
        await Future.wait([inputTask.catchError((_) {})]);
      }
      if (!controller.isClosed) {
        controller.addError(error, stackTrace);
      }
      await _closeToolCallStream(toolCallId: toolCallId, controller: controller);
      rethrow;
    }
  }

  Future<void> _closeToolCallStream({required String toolCallId, required StreamController<Chunk> controller}) async {
    _toolCallStreams.remove(toolCallId);
    if (!controller.isClosed) {
      unawaited(controller.close());
    }
  }

  Future<void> _sendToolCallRequestChunk({required String toolCallId, required Chunk chunk}) async {
    final packedChunk = unpackMessage(chunk.pack());
    await room.sendRequest("agent.tool_call_request_chunk", {
      "tool_call_id": toolCallId,
      "chunk": packedChunk.header,
    }, data: packedChunk.payload.isEmpty ? null : packedChunk.payload);
  }

  Future<void> _streamInvokeToolRequestChunks({required String toolCallId, required Stream<Chunk> inputChunks}) async {
    await Future<void>.delayed(Duration.zero);
    try {
      await for (final item in inputChunks) {
        await _sendToolCallRequestChunk(toolCallId: toolCallId, chunk: item);
      }
    } finally {
      await _sendToolCallRequestChunk(
        toolCallId: toolCallId,
        chunk: ControlChunk(method: "close"),
      );
    }
  }

  Future<void> _handleToolCallResponseChunk(Protocol protocol, int messageId, String type, Uint8List data) async {
    final message = unpackMessage(data);
    final header = message.header;
    final payload = message.payload;

    final toolCallId = header["tool_call_id"];
    if (toolCallId is! String || toolCallId.isEmpty) {
      Logger.root.warning("ignoring tool call chunk without tool_call_id");
      return;
    }

    final chunk = _decodeToolCallChunk(header: header, payload: payload);
    _toolCallResponseChunks.add(
      ToolCallResponseChunk(toolCallId: toolCallId, chunk: chunk, toolkit: header["toolkit"] as String?, tool: header["tool"] as String?),
    );

    final pendingInvoke = _pendingInvokeResponses[toolCallId];
    if (pendingInvoke != null && !pendingInvoke.isCompleted) {
      if (chunk is ErrorChunk) {
        pendingInvoke.completeError(RoomServerException(chunk.text));
      } else if (chunk is ControlChunk && chunk.method == "close") {
        pendingInvoke.completeError(RoomServerException("tool call closed before initial invoke response"));
      }
    }

    final stream = _toolCallStreams[toolCallId];
    if (stream == null || stream.isClosed) {
      return;
    }

    if (chunk is ErrorChunk) {
      stream.addError(RoomServerException(chunk.text));
      await _closeToolCallStream(toolCallId: toolCallId, controller: stream);
      return;
    }

    if (chunk is ControlChunk) {
      if (chunk.method == "close") {
        await _closeToolCallStream(toolCallId: toolCallId, controller: stream);
      }
      return;
    }

    stream.add(chunk);
  }

  Chunk _decodeToolCallChunk({required Map<String, dynamic> header, required Uint8List payload}) {
    final chunk = header["chunk"];
    if (chunk is Map) {
      final chunkMap = Map<String, dynamic>.from(chunk);
      if (chunkMap["type"] is String) {
        try {
          return unpackChunk(packMessage(chunkMap, payload.isEmpty ? null : payload));
        } catch (_) {
          return JsonChunk(json: chunkMap);
        }
      }
      return JsonChunk(json: chunkMap);
    }

    return JsonChunk(json: {"chunk": chunk});
  }
}

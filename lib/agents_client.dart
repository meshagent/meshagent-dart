import 'dart:async';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:meshagent/document.dart';
import 'package:meshagent/protocol.dart';
import 'package:meshagent/room_server_client.dart';
import 'package:uuid/uuid.dart';

sealed class ToolCallOutput {
  const ToolCallOutput();
}

class ToolContentOutput extends ToolCallOutput {
  const ToolContentOutput(this.content);

  final Content content;
}

class ToolStreamOutput extends ToolCallOutput {
  const ToolStreamOutput(this.stream);

  final Stream<Content> stream;
}

sealed class ToolInput {
  const ToolInput();
}

class ToolContentInput extends ToolInput {
  const ToolContentInput(this.content);

  final Content content;
}

class ToolStreamInput extends ToolInput {
  const ToolStreamInput(this.chunks);

  final Stream<Content> chunks;
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
  final _toolCallStreams = <String, StreamController<Content>>{};
  final _pendingInvokeResponses = <String, Completer<Content>>{};

  Future<void> _failToolCallStreams({required RoomServerException error}) async {
    if (_toolCallStreams.isEmpty) {
      return;
    }

    final streams = Map<String, StreamController<Content>>.from(_toolCallStreams);
    _toolCallStreams.clear();
    for (final stream in streams.values) {
      if (!stream.isClosed) {
        stream.addError(error);
        unawaited(stream.close());
      }
    }
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

    final result = (await room.sendRequest("agent.list_toolkits", request)) as JsonContent;

    final toolkits = <ToolkitDescription>[];
    final tools = result.json["tools"];

    for (final name in tools.keys) {
      final json = tools[name];
      toolkits.add(ToolkitDescription.fromJson(json, name: name));
    }

    return toolkits;
  }

  Future<Content> _awaitInvokeResponse({required String toolCallId, required Future<Content> requestFuture}) async {
    final pending = Completer<Content>();
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

  Future<ToolCallOutput> invokeTool({
    required String toolkit,
    required String tool,
    required ToolInput input,
    String? participantId,
    String? onBehalfOfId,
    Map<String, dynamic>? callerContext,
  }) async {
    final toolCallId = _uuid.v4();
    final controller = StreamController<Content>(
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
      final packedInput = unpackMessage(input.content.pack());
      request["arguments"] = packedInput.header;
      invokeData = packedInput.payload.isEmpty ? null : packedInput.payload;
    } else if (input is ToolStreamInput) {
      final openChunk = unpackMessage(ControlContent(method: "open").pack());
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

      if (response is ControlContent && response.method == "open") {
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
      return ToolContentOutput(response);
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

  Future<void> _closeToolCallStream({required String toolCallId, required StreamController<Content> controller}) async {
    _toolCallStreams.remove(toolCallId);
    if (!controller.isClosed) {
      unawaited(controller.close());
    }
  }

  Future<void> _sendToolCallRequestChunk({required String toolCallId, required Content chunk}) async {
    final packedChunk = unpackMessage(chunk.pack());
    await room.sendRequest("agent.tool_call_request_chunk", {
      "tool_call_id": toolCallId,
      "chunk": packedChunk.header,
    }, data: packedChunk.payload.isEmpty ? null : packedChunk.payload);
  }

  Future<void> _streamInvokeToolRequestChunks({required String toolCallId, required Stream<Content> inputChunks}) async {
    await Future<void>.delayed(Duration.zero);
    try {
      await for (final item in inputChunks) {
        await _sendToolCallRequestChunk(toolCallId: toolCallId, chunk: item);
      }
    } finally {
      await _sendToolCallRequestChunk(
        toolCallId: toolCallId,
        chunk: ControlContent(method: "close"),
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

    final content = _decodeToolCallContent(header: header, payload: payload);

    final pendingInvoke = _pendingInvokeResponses[toolCallId];
    if (pendingInvoke != null && !pendingInvoke.isCompleted) {
      if (content is ErrorContent) {
        pendingInvoke.completeError(RoomServerException(content.text, code: content.code));
      } else if (content is ControlContent && content.method == "close") {
        var detail = "tool call closed before initial invoke response";
        final closeStatus = content.statusCode ?? ControlCloseStatus.normal.code;
        if (closeStatus != ControlCloseStatus.normal.code) {
          detail = content.message ?? "tool call stream closed abnormally";
        }
        pendingInvoke.completeError(RoomServerException(detail, statusCode: closeStatus));
      }
    }

    final stream = _toolCallStreams[toolCallId];
    if (stream == null || stream.isClosed) {
      return;
    }

    if (content is ControlContent) {
      if (content.method == "close") {
        final closeStatus = content.statusCode ?? ControlCloseStatus.normal.code;
        if (closeStatus != ControlCloseStatus.normal.code) {
          var detail = content.message ?? "tool call stream closed abnormally";
          stream.addError(RoomServerException(detail, statusCode: closeStatus));
        }
        await _closeToolCallStream(toolCallId: toolCallId, controller: stream);
      }
      return;
    }

    stream.add(content);
  }

  Content _decodeToolCallContent({required Map<String, dynamic> header, required Uint8List payload}) {
    final chunk = header["chunk"];
    if (chunk is Map) {
      final chunkMap = Map<String, dynamic>.from(chunk);
      if (chunkMap["type"] is String) {
        try {
          return unpackContent(packMessage(chunkMap, payload.isEmpty ? null : payload));
        } catch (_) {
          return JsonContent(json: chunkMap);
        }
      }
      return JsonContent(json: chunkMap);
    }

    return JsonContent(json: {"chunk": chunk});
  }
}

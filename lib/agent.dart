import 'dart:async';
import 'dart:typed_data';

import 'package:json_schema/json_schema.dart';
import 'package:meshagent/agents_client.dart';
import 'package:logging/logging.dart';
import 'package:meshagent/datasets_client.dart';
import 'package:meshagent/protocol.dart';
import 'package:meshagent/room_server_client.dart';

enum ValidationMode { full, contentTypes, none }

class InvalidToolDataException extends RoomServerException {
  InvalidToolDataException(super.message);
}

abstract class BaseTool {
  BaseTool({
    required this.name,
    this.description,
    this.title,
    required this.inputSchema,
    this.inputSpec,
    this.outputSpec,
    this.outputSchema,
    this.thumbnailUrl,
    this.defs,
    this.pricing,
  });

  final String name;
  final String? description;
  final String? title;
  final String? thumbnailUrl;
  final Map<String, dynamic> inputSchema;
  final ToolContentSpec? inputSpec;
  final ToolContentSpec? outputSpec;
  final Map<String, dynamic>? outputSchema;
  final Map<String, dynamic>? defs;
  final String? pricing;
}

abstract class FunctionTool extends BaseTool {
  FunctionTool({
    required super.name,
    super.description,
    super.title,
    required super.inputSchema,
    super.outputSpec,
    super.outputSchema,
    super.thumbnailUrl,
    super.defs,
    super.pricing,
  });

  Future<Content> execute(ToolContext context, Map<String, dynamic> arguments);

  Stream<Content> executeStream(ToolContext context, Map<String, dynamic> arguments) async* {
    yield await execute(context, arguments);
  }
}

abstract class ContentTool extends BaseTool {
  ContentTool({
    required super.name,
    super.description,
    super.title,
    required super.inputSchema,
    super.inputSpec,
    super.outputSpec,
    super.outputSchema,
    super.thumbnailUrl,
    super.defs,
    super.pricing,
  });

  Future<ToolCallOutput> execute(ToolContext context, ToolInput input);
}

abstract class Toolkit {
  Toolkit({
    required this.name,
    this.title,
    this.description,
    this.thumbnailUrl,
    required this.tools,
    this.rules = const [],
    this.validationMode = ValidationMode.full,
  });

  final String name;
  final String? title;
  final String? description;
  final String? thumbnailUrl;
  final List<BaseTool> tools;
  final List<String> rules;
  final ValidationMode validationMode;

  BaseTool getTool(String name) {
    for (final tool in tools) {
      if (tool.name == name) {
        return tool;
      }
    }
    throw Exception("Tool was not found $name");
  }

  Map<String, dynamic> getTools() {
    final json = <String, dynamic>{};
    for (final tool in tools) {
      json[tool.name] = {
        "description": tool.description,
        "title": tool.title,
        "input_spec": _resolveInputSpec(tool)?.toJson(),
        "output_spec": _resolveOutputSpec(tool)?.toJson(),
        "thumbnail_url": tool.thumbnailUrl,
        "defs": tool.defs,
        "pricing": tool.pricing,
      };
    }
    return json;
  }

  Future<ToolCallOutput> execute(ToolContext context, String name, ToolInput input) async {
    final tool = getTool(name);
    if (tool is FunctionTool) {
      if (input is! ToolContentInput) {
        throw Exception("tool '$name' does not accept streamed input");
      }
      final arguments = _decodeFunctionToolArguments(toolName: name, input: input.content);
      final response = await tool.execute(context, arguments);
      return ToolContentOutput(response);
    }
    if (tool is ContentTool) {
      return await tool.execute(context, input);
    }
    throw Exception("tool '$name' has unsupported type");
  }

  Map<String, dynamic> _decodeFunctionToolArguments({required String toolName, required Content input}) {
    if (input is EmptyContent) {
      return <String, dynamic>{};
    }
    if (input is JsonContent) {
      return Map<String, dynamic>.from(input.json);
    }
    throw Exception("tool '$toolName' requires JSON object input");
  }

  bool get _shouldValidateContentTypes {
    return validationMode == ValidationMode.full || validationMode == ValidationMode.contentTypes;
  }

  bool get _shouldValidateSchema {
    return validationMode == ValidationMode.full;
  }

  ToolContentSpec? _resolveInputSpec(BaseTool tool) {
    if (tool is FunctionTool) {
      return ToolContentSpec(types: [ToolContentType.json], stream: false, schema: tool.inputSchema);
    }
    return tool.inputSpec;
  }

  ToolContentSpec? _resolveOutputSpec(BaseTool tool) {
    if (tool.outputSpec != null) {
      if (tool.outputSchema != null && tool.outputSpec!.schema == null && tool.outputSpec!.types.contains(ToolContentType.json)) {
        return ToolContentSpec(types: tool.outputSpec!.types, stream: tool.outputSpec!.stream, schema: tool.outputSchema);
      }
      return tool.outputSpec;
    }
    if (tool.outputSchema == null) {
      return null;
    }
    return ToolContentSpec(types: [ToolContentType.json], stream: false, schema: tool.outputSchema);
  }

  ToolContentType? _contentType(Content content) {
    if (content is BinaryContent) {
      return ToolContentType.binary;
    }
    if (content is JsonContent) {
      return ToolContentType.json;
    }
    if (content is TextContent) {
      return ToolContentType.text;
    }
    if (content is FileContent) {
      return ToolContentType.file;
    }
    if (content is LinkContent) {
      return ToolContentType.link;
    }
    if (content is EmptyContent) {
      return ToolContentType.empty;
    }
    return null;
  }

  String _contentTypeName(ToolContentType type) {
    return switch (type) {
      ToolContentType.binary => "binary",
      ToolContentType.json => "json",
      ToolContentType.text => "text",
      ToolContentType.file => "file",
      ToolContentType.link => "link",
      ToolContentType.empty => "empty",
    };
  }

  dynamic _schemaValue(Content content) {
    if (content is BinaryContent) {
      return content.headers;
    }
    if (content is JsonContent) {
      return content.json;
    }
    if (content is TextContent) {
      return content.text;
    }
    if (content is EmptyContent) {
      return null;
    }
    if (content is LinkContent) {
      return {"name": content.name, "url": content.url};
    }
    if (content is FileContent) {
      return {"name": content.name, "mime_type": content.mimeType, "size": content.data.length};
    }
    if (content is ControlContent) {
      return {"method": content.method};
    }
    if (content is ErrorContent) {
      return {"text": content.text, if (content.code != null) "code": content.code};
    }
    final packed = unpackMessage(content.pack());
    return packed.header;
  }

  Map<String, dynamic>? _schemaWithDefs({required Map<String, dynamic>? schema, required Map<String, dynamic>? defs}) {
    if (schema == null) {
      return null;
    }
    final merged = Map<String, dynamic>.from(schema);
    if (defs == null) {
      return merged;
    }
    final existingDefs = merged[r'$defs'];
    if (existingDefs is Map) {
      merged[r'$defs'] = {...defs, ...existingDefs.cast<String, dynamic>()};
    } else {
      merged[r'$defs'] = {...defs};
    }
    return merged;
  }

  void _validateStreamMode({required BaseTool tool, required String direction, required ToolContentSpec? spec, required bool stream}) {
    if (!_shouldValidateContentTypes || spec == null) {
      return;
    }
    if (spec.stream != stream) {
      final expected = spec.stream ? "streamed" : "single-content";
      final actual = stream ? "streamed" : "single-content";
      throw InvalidToolDataException("tool '${tool.name}' $direction is $actual but ${direction}_spec requires $expected $direction");
    }
  }

  void _validateContentType({required BaseTool tool, required String direction, required ToolContentSpec? spec, required Content content}) {
    if (!_shouldValidateContentTypes || spec == null) {
      return;
    }
    final type = _contentType(content);
    if (type == null || !spec.types.contains(type)) {
      final allowed = spec.types.map(_contentTypeName).join(", ");
      final actual = type == null ? content.runtimeType.toString() : _contentTypeName(type);
      throw InvalidToolDataException(
        "tool '${tool.name}' $direction content type '$actual' is not allowed by ${direction}_spec ($allowed)",
      );
    }
  }

  void _validateSchema({
    required BaseTool tool,
    required String direction,
    required Content content,
    required Map<String, dynamic>? schema,
  }) {
    if (!_shouldValidateSchema) {
      return;
    }
    final resolvedSchema = _schemaWithDefs(schema: schema, defs: tool.defs);
    if (resolvedSchema == null) {
      return;
    }
    final validator = JsonSchema.create(resolvedSchema);
    final result = validator.validate(_schemaValue(content));
    if (!result.isValid) {
      final message = result.errors.isEmpty ? "validation failed" : result.errors.first.message;
      throw InvalidToolDataException("tool '${tool.name}' $direction does not match ${direction}_schema: $message");
    }
  }

  void _validateInputContent({required BaseTool tool, required Content content}) {
    final spec = _resolveInputSpec(tool);
    _validateContentType(tool: tool, direction: "input", spec: spec, content: content);
    _validateSchema(tool: tool, direction: "input", content: content, schema: spec?.schema);
  }

  void _validateOutputContent({required BaseTool tool, required Content content}) {
    final spec = _resolveOutputSpec(tool);
    _validateContentType(tool: tool, direction: "output", spec: spec, content: content);
    _validateSchema(tool: tool, direction: "output", content: content, schema: spec?.schema);
  }
}

class ToolContext {
  const ToolContext({required this.room, this.caller, this.onBehalfOf, this.callerContext});

  final Participant? caller;
  final Participant? onBehalfOf;
  final Map<String, dynamic>? callerContext;
  final RoomClient room;
}

class HostedToolkit {
  HostedToolkit._({required this.toolkit, required Future<void> Function() stopHostedToolkit}) : _stopHostedToolkit = stopHostedToolkit;

  final Toolkit toolkit;
  final Future<void> Function() _stopHostedToolkit;

  Future<void> stop() async {
    await _stopHostedToolkit();
  }
}

Future<HostedToolkit> startHostedToolkit({required RoomClient room, required Toolkit toolkit, bool public = false}) async {
  final wrapper = _RemoteToolkitWrapper(room: room, toolkit: toolkit);
  await wrapper.start(public: public);
  return HostedToolkit._(toolkit: toolkit, stopHostedToolkit: () => wrapper.stop());
}

class _RemoteToolkitWrapper {
  _RemoteToolkitWrapper({required this.room, required this.toolkit});

  final RoomClient room;
  final Toolkit toolkit;
  String? _registrationId;
  bool _started = false;
  bool _public = false;
  Future<void>? _registerTask;
  StreamSubscription<RoomEvent>? _roomSubscription;
  final Map<String, StreamController<Content>> _requestStreams = {};
  final Map<String, BaseTool> _requestStreamTools = {};
  final Map<String, List<Content>> _pendingRequestChunks = {};
  late final ProtocolMessageHandler _toolCallHandler = _toolCall;
  late final ProtocolMessageHandler _toolCallRequestChunkHandler = _toolCallRequestChunk;

  Future<void> start({bool public = false}) async {
    if (_started) {
      throw RoomServerException("toolkit '${toolkit.name}' is already started");
    }
    _public = public;
    room.protocol.addHandler("room.tool_call.${toolkit.name}", _toolCallHandler);
    room.protocol.addHandler("room.tool_call_request_chunk.${toolkit.name}", _toolCallRequestChunkHandler);
    _roomSubscription = room.listen(_onRoomEvent);
    try {
      await _register(public: public);
      _started = true;
      unawaited(
        room.waitForClose().then((_) async {
          await _failActiveRequestStreams(error: _roomClosedStreamError());
        }),
      );
    } catch (_) {
      await _roomSubscription?.cancel();
      _roomSubscription = null;
      room.protocol.removeHandler("room.tool_call.${toolkit.name}", _toolCallHandler);
      room.protocol.removeHandler("room.tool_call_request_chunk.${toolkit.name}", _toolCallRequestChunkHandler);
      rethrow;
    }
  }

  Future<void> stop() async {
    if (!_started) {
      return;
    }
    _started = false;
    await _roomSubscription?.cancel();
    _roomSubscription = null;
    await _failActiveRequestStreams(error: RoomServerException("hosted toolkit stopped"));
    try {
      await _unregister();
    } finally {
      room.protocol.removeHandler("room.tool_call.${toolkit.name}", _toolCallHandler);
      room.protocol.removeHandler("room.tool_call_request_chunk.${toolkit.name}", _toolCallRequestChunkHandler);
    }
  }

  Future<void> _register({bool public = false}) async {
    final response = await room.sendRequest("room.register_toolkit", {
      "name": toolkit.name,
      "title": toolkit.title,
      "description": toolkit.description,
      "tools": toolkit.getTools(),
      "public": public,
      "thumbnail_url": toolkit.thumbnailUrl,
    });
    _registrationId = (response as JsonContent).json["id"];
  }

  Future<void> _unregister() async {
    final registrationId = _registrationId;
    _registrationId = null;
    if (registrationId == null || room.isClosed) {
      return;
    }
    await room.sendRequest("room.unregister_toolkit", {"id": registrationId});
  }

  Future<void> _failActiveRequestStreams({required RoomServerException error}) async {
    final streams = Map<String, StreamController<Content>>.from(_requestStreams);
    _requestStreams.clear();
    _requestStreamTools.clear();
    _pendingRequestChunks.clear();
    for (final stream in streams.values) {
      if (!stream.isClosed) {
        stream.addError(error);
        await stream.close();
      }
    }
  }

  Future<void> _closeRequestStream({required String toolCallId}) async {
    _pendingRequestChunks.remove(toolCallId);
    _requestStreamTools.remove(toolCallId);
    final requestStreamController = _requestStreams.remove(toolCallId);
    if (requestStreamController != null && !requestStreamController.isClosed) {
      await requestStreamController.close();
    }
  }

  RoomServerException _roomClosedStreamError() {
    final closeReason = room.closeReason;
    if (closeReason == null || closeReason.isEmpty) {
      return RoomServerException("room client was closed before streamed tool call request completed");
    }
    return RoomServerException("room client was closed before streamed tool call request completed: $closeReason");
  }

  RoomServerException _roomDisconnectedStreamError(String message) {
    final normalized = message.trim();
    if (normalized.isEmpty) {
      return RoomServerException("room connection lost before streamed tool call request completed");
    }
    return RoomServerException("room connection lost before streamed tool call request completed: $normalized");
  }

  void _scheduleRegisterIfNeeded() {
    if (!_started || _registrationId != null || _registerTask != null || room.isClosed) {
      return;
    }
    _registerTask = _register(public: _public)
        .catchError((Object error, StackTrace stackTrace) {
          Logger.root.log(Level.WARNING, "unable to reregister hosted toolkit ${toolkit.name}", error, stackTrace);
        })
        .whenComplete(() {
          _registerTask = null;
        });
  }

  void _onRoomEvent(RoomEvent event) {
    if (!_started || event is! RoomStatusEvent) {
      return;
    }
    if (event.status == "disconnected") {
      _registrationId = null;
      unawaited(_failActiveRequestStreams(error: _roomDisconnectedStreamError(event.message)));
      return;
    }
    if (event.status == "reconnected") {
      _scheduleRegisterIfNeeded();
    }
  }

  Future<bool> _sendToolCallResponse({required int messageId, required Content chunk}) async {
    try {
      await room.protocol.send("room.tool_call_response", chunk.pack(), id: messageId);
      return true;
    } catch (error, stackTrace) {
      Logger.root.fine("unable to send tool call response", error, stackTrace);
      return false;
    }
  }

  Future<void> _toolCall(Protocol protocol, int messageId, String type, Uint8List data) async {
    final unpackedMessage = unpackMessage(data);
    final message = unpackedMessage.header;
    final attachment = unpackedMessage.payload;
    final toolName = message["name"] as String;
    final rawArguments = message["arguments"];
    final toolCallId = (message["tool_call_id"] as String?) ?? "$messageId";
    final callerId = message["caller_id"] as String?;
    final onBehalfOfId = message["on_behalf_of_id"] as String?;
    final callerContext = message["caller_context"] is Map ? (message["caller_context"] as Map).cast<String, dynamic>() : null;

    Content? inputChunk;
    var requestStream = false;
    if (rawArguments is Map) {
      try {
        inputChunk = unpackContent(packMessage(Map<String, dynamic>.from(rawArguments), attachment.isEmpty ? null : attachment));
      } catch (_) {}
    }
    if (inputChunk == null) {
      if (rawArguments is! Map) {
        await _sendToolCallResponse(
          messageId: messageId,
          chunk: ErrorContent(text: "'arguments' must be a content header object"),
        );
        return;
      }
      inputChunk = JsonContent(json: Map<String, dynamic>.from(rawArguments));
    }

    if (inputChunk is ControlContent) {
      if (inputChunk.method != "open") {
        await _sendToolCallResponse(
          messageId: messageId,
          chunk: ErrorContent(text: "request stream must start with an open control chunk"),
        );
        return;
      }
      requestStream = true;
    }

    final caller = _resolveParticipant(callerId);
    final onBehalfOf = _resolveParticipant(onBehalfOfId);
    final context = ToolContext(room: room, caller: caller, onBehalfOf: onBehalfOf, callerContext: callerContext);

    BaseTool tool;
    try {
      tool = toolkit.getTool(toolName);
    } catch (error) {
      await _sendToolCallResponse(
        messageId: messageId,
        chunk: ErrorContent(text: "$error"),
      );
      return;
    }

    var openedResponseStream = false;
    StreamController<Content>? requestStreamController;
    try {
      toolkit._validateStreamMode(tool: tool, direction: "input", spec: toolkit._resolveInputSpec(tool), stream: requestStream);

      ToolInput resolvedInput;
      if (requestStream) {
        requestStreamController = StreamController<Content>();
        _requestStreams[toolCallId] = requestStreamController;
        _requestStreamTools[toolCallId] = tool;
        _enqueueRequestStreamChunk(
          stream: requestStreamController,
          chunk: ControlContent(method: "open"),
          tool: tool,
        );
        final buffered = _pendingRequestChunks.remove(toolCallId) ?? <Content>[];
        for (final chunk in buffered) {
          _enqueueRequestStreamChunk(stream: requestStreamController, chunk: chunk, tool: tool);
        }
        resolvedInput = ToolStreamInput(requestStreamController.stream);
      } else {
        toolkit._validateInputContent(tool: tool, content: inputChunk);
        resolvedInput = ToolContentInput(inputChunk);
      }

      final output = await toolkit.execute(context, toolName, resolvedInput);
      switch (output) {
        case ToolContentOutput(:final content):
          toolkit._validateStreamMode(tool: tool, direction: "output", spec: toolkit._resolveOutputSpec(tool), stream: false);
          toolkit._validateOutputContent(tool: tool, content: content);
          await _sendToolCallResponse(messageId: messageId, chunk: content);
          return;
        case ToolStreamOutput(:final stream):
          toolkit._validateStreamMode(tool: tool, direction: "output", spec: toolkit._resolveOutputSpec(tool), stream: true);
          openedResponseStream = true;
          if (!await _sendToolCallResponse(
            messageId: messageId,
            chunk: ControlContent(method: "open"),
          )) {
            return;
          }
          await for (final chunk in stream) {
            toolkit._validateOutputContent(tool: tool, content: chunk);
            if (!await _sendToolCallResponseChunk(messageId: messageId, toolCallId: toolCallId, chunk: chunk)) {
              return;
            }
          }
          await _sendToolCallResponseChunk(
            messageId: messageId,
            toolCallId: toolCallId,
            chunk: ControlContent(method: "close"),
          );
          return;
      }
    } catch (error) {
      if (!openedResponseStream) {
        await _sendToolCallResponse(
          messageId: messageId,
          chunk: ErrorContent(text: "$error"),
        );
        return;
      }

      if (error is! InvalidToolDataException) {
        await _sendToolCallResponseChunk(
          messageId: messageId,
          toolCallId: toolCallId,
          chunk: ErrorContent(text: "$error"),
        );
      }
      await _sendToolCallResponseChunk(
        messageId: messageId,
        toolCallId: toolCallId,
        chunk: error is InvalidToolDataException
            ? ControlContent(method: "close", statusCode: ControlCloseStatus.invalidData.code, message: error.message)
            : ControlContent(method: "close"),
      );
    } finally {
      await _closeRequestStream(toolCallId: toolCallId);
    }
  }

  Future<void> _toolCallRequestChunk(Protocol protocol, int messageId, String type, Uint8List data) async {
    final unpackedMessage = unpackMessage(data);
    final message = unpackedMessage.header;
    final payload = unpackedMessage.payload;
    final toolCallId = message["tool_call_id"];
    if (toolCallId is! String || toolCallId.isEmpty) {
      Logger.root.warning("ignoring request stream chunk without tool_call_id");
      return;
    }

    final chunkHeader = message["chunk"];
    if (chunkHeader is! Map) {
      Logger.root.warning("ignoring request stream chunk without chunk header");
      return;
    }

    try {
      final chunk = unpackContent(packMessage(Map<String, dynamic>.from(chunkHeader), payload.isEmpty ? null : payload));
      final stream = _requestStreams[toolCallId];
      if (stream == null) {
        final buffered = _pendingRequestChunks.putIfAbsent(toolCallId, () => <Content>[]);
        buffered.add(chunk);
        return;
      }
      _enqueueRequestStreamChunk(stream: stream, chunk: chunk, tool: _requestStreamTools[toolCallId]);
    } catch (error, stackTrace) {
      Logger.root.warning("ignoring malformed request stream chunk", error, stackTrace);
    }
  }

  void _enqueueRequestStreamChunk({required StreamController<Content> stream, required Content chunk, BaseTool? tool}) {
    if (chunk is ControlContent) {
      if (chunk.method == "open") {
        return;
      }
      if (chunk.method == "close") {
        if (!stream.isClosed) {
          unawaited(stream.close());
        }
        return;
      }
      Logger.root.warning("ignoring unknown control chunk method ${chunk.method}");
      return;
    }

    if (tool != null) {
      try {
        toolkit._validateInputContent(tool: tool, content: chunk);
      } catch (error, stackTrace) {
        if (!stream.isClosed) {
          stream.addError(error, stackTrace);
          unawaited(stream.close());
        }
        return;
      }
    }

    if (!stream.isClosed) {
      stream.add(chunk);
    }
  }

  Participant? _resolveParticipant(String? participantId) {
    if (participantId == null || participantId.isEmpty) {
      return null;
    }
    final local = room.localParticipant;
    if (local != null && local.id == participantId) {
      return local;
    }
    for (final remote in room.messaging.remoteParticipants) {
      if (remote.id == participantId) {
        return remote;
      }
    }
    return RemoteParticipant(client: room, id: participantId, role: "user");
  }

  Future<bool> _sendToolCallResponseChunk({required int messageId, required String toolCallId, required Content chunk}) async {
    final packedChunk = unpackMessage(chunk.pack());
    try {
      await room.protocol.send(
        "room.tool_call_response_chunk",
        packMessage({"tool_call_id": toolCallId, "chunk": packedChunk.header}, packedChunk.payload.isEmpty ? null : packedChunk.payload),
        id: messageId,
      );
      return true;
    } catch (error, stackTrace) {
      Logger.root.fine("unable to send tool call response chunk", error, stackTrace);
      return false;
    }
  }
}

/// Install (create + index + optimize) a RequiredTable in the current room.
Future<void> installTable(RoomClient room, RequiredTable table, {Logger? logger, bool optimize = true}) async {
  logger ??= Logger.root;
  final datasets = room.datasets;

  await datasets.createTableWithSchema(
    name: table.name,
    mode: CreateMode.createIfNotExists,
    schema: table.schema,
    namespace: table.namespace,
  );

  final indexes = await datasets.listIndexes(table.name, namespace: table.namespace);

  bool indexExists(String column) {
    for (final idx in indexes) {
      if (idx.columns.contains(column)) return true;
    }
    return false;
  }

  for (final vi in table.vectorIndexes ?? const <String>[]) {
    if (indexExists(vi)) continue;
    try {
      await datasets.createVectorIndex(table: table.name, column: vi, namespace: table.namespace, replace: true);
    } catch (error, st) {
      logger.warning('unable to create vector index for "$vi": $error', error, st);
    }
  }

  for (final ti in table.fullTextSearchIndexes ?? const <String>[]) {
    if (indexExists(ti)) continue;
    try {
      await datasets.createFullTextSearchIndex(table: table.name, column: ti, namespace: table.namespace, replace: true);
    } catch (error, st) {
      logger.warning('unable to create full text search index for "$ti": $error', error, st);
    }
  }

  for (final si in table.scalarIndexes ?? const <String>[]) {
    if (indexExists(si)) continue;
    try {
      await datasets.createScalarIndex(table: table.name, column: si, namespace: table.namespace, replace: true);
    } catch (error, st) {
      logger.warning('unable to create scalar index for "$si": $error', error, st);
    }
  }

  if (optimize) {
    logger.info('optimizing table ${table.name} in ${table.namespace}');
    await datasets.optimize(table: table.name, namespace: table.namespace);
  }
}

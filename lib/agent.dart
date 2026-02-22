import 'dart:async';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:meshagent/database_client.dart';
import 'package:meshagent/protocol.dart';
import 'package:meshagent/room_server_client.dart';

abstract class Tool {
  Tool({required this.name, this.description, this.title, required this.inputSchema, this.thumbnailUrl, this.supportsContext = false});

  final String name;
  final String? description;
  final String? title;
  final String? thumbnailUrl;
  final Map<String, dynamic> inputSchema;
  final bool supportsContext;

  Future<Chunk> execute(ToolContext context, Map<String, dynamic> arguments);

  Stream<Chunk> executeStream(ToolContext context, Map<String, dynamic> arguments) async* {
    yield await execute(context, arguments);
  }
}

abstract class Toolkit {
  Toolkit({required this.name, this.title, this.description, this.thumbnailUrl, required this.tools, required this.rules});

  final String name;
  final String? title;
  final String? description;
  final String? thumbnailUrl;
  final List<Tool> tools;
  final List<String> rules;

  Tool getTool(String name) {
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
        "input_schema": tool.inputSchema,
        "thumbnail_url": tool.thumbnailUrl,
        "supports_context": tool.supportsContext,
      };
    }
    return json;
  }

  Future<Chunk> execute(ToolContext context, String name, Map<String, dynamic> arguments) async {
    return await getTool(name).execute(context, arguments);
  }

  Stream<Chunk> executeStream(ToolContext context, String name, Map<String, dynamic> arguments) {
    return getTool(name).executeStream(context, arguments);
  }
}

class ToolContext {
  const ToolContext({required this.room, this.caller, this.onBehalfOf, this.callerContext});

  final Participant? caller;
  final Participant? onBehalfOf;
  final Map<String, dynamic>? callerContext;
  final RoomClient room;
}

class RemoteToolkit extends Toolkit {
  RemoteToolkit({
    required super.name,
    super.title,
    super.description,
    super.thumbnailUrl,
    required this.room,
    required super.tools,
    super.rules = const [],
  });

  final RoomClient room;
  String? _registrationId;

  Future<void> start({bool public = false}) async {
    room.protocol.addHandler("agent.tool_call.$name", _toolCall);
    await _register(public: public);
  }

  Future<void> stop() async {
    await _unregister();
    room.protocol.removeHandler("agent.tool_call.$name", _toolCall);
  }

  Future<void> _register({bool public = false}) async {
    final response = await room.sendRequest("agent.register_toolkit", {
      "name": name,
      "title": title,
      "description": description,
      "tools": getTools(),
      "public": public,
      "thumbnail_url": thumbnailUrl,
    });
    _registrationId = (response as JsonChunk).json["id"];
  }

  Future<void> _unregister() async {
    if (_registrationId != null) {
      await room.sendRequest("agent.unregister_toolkit", {"id": _registrationId!});
    }
  }

  Future<void> _toolCall(Protocol protocol, int messageId, String type, Uint8List data) async {
    final unpackedMessage = unpackMessage(data);
    final message = unpackedMessage.header;
    final attachment = unpackedMessage.payload;
    final toolName = message["name"] as String;
    final rawArguments = message["arguments"];
    final toolCallId = (message["tool_call_id"] as String?) ?? "$messageId";
    var args = <String, dynamic>{};
    var requestStream = false;

    if (rawArguments is! Map) {
      await room.protocol.send("agent.tool_call_response", ErrorChunk(text: "'arguments' must be a JSON object").pack(), id: messageId);
      return;
    }

    try {
      final argChunk = unpackChunk(packMessage(Map<String, dynamic>.from(rawArguments), attachment.isEmpty ? null : attachment));
      if (argChunk is ControlChunk) {
        requestStream = argChunk.method == "open";
      } else if (argChunk is JsonChunk) {
        args = Map<String, dynamic>.from(argChunk.json);
      } else if (argChunk is EmptyChunk) {
        args = <String, dynamic>{};
      } else {
        args = Map<String, dynamic>.from(rawArguments);
      }
    } catch (_) {
      args = Map<String, dynamic>.from(rawArguments);
    }

    if (requestStream) {
      await room.protocol.send(
        "agent.tool_call_response",
        ErrorChunk(text: "streamed tool input is not supported by the Dart RemoteToolkit yet").pack(),
        id: messageId,
      );
      return;
    }

    var openedStream = false;

    try {
      final stream = executeStream(ToolContext(room: room), toolName, args);
      final iterator = StreamIterator<Chunk>(stream);

      if (!await iterator.moveNext()) {
        await room.protocol.send("agent.tool_call_response", EmptyChunk().pack(), id: messageId);
        return;
      }

      final firstChunk = iterator.current;
      if (!await iterator.moveNext()) {
        await room.protocol.send("agent.tool_call_response", firstChunk.pack(), id: messageId);
        return;
      }

      openedStream = true;
      await room.protocol.send("agent.tool_call_response", ControlChunk(method: "open").pack(), id: messageId);

      await _sendToolCallResponseChunk(messageId: messageId, toolCallId: toolCallId, chunk: firstChunk);
      await _sendToolCallResponseChunk(messageId: messageId, toolCallId: toolCallId, chunk: iterator.current);

      while (await iterator.moveNext()) {
        await _sendToolCallResponseChunk(messageId: messageId, toolCallId: toolCallId, chunk: iterator.current);
      }

      await _sendToolCallResponseChunk(
        messageId: messageId,
        toolCallId: toolCallId,
        chunk: ControlChunk(method: "close"),
      );
      await iterator.cancel();
    } catch (error) {
      if (!openedStream) {
        await room.protocol.send("agent.tool_call_response", ErrorChunk(text: "$error").pack(), id: messageId);
        return;
      }

      await _sendToolCallResponseChunk(
        messageId: messageId,
        toolCallId: toolCallId,
        chunk: ErrorChunk(text: "$error"),
      );
      await _sendToolCallResponseChunk(
        messageId: messageId,
        toolCallId: toolCallId,
        chunk: ControlChunk(method: "close"),
      );
    }
  }

  Future<void> _sendToolCallResponseChunk({required int messageId, required String toolCallId, required Chunk chunk}) async {
    final packedChunk = unpackMessage(chunk.pack());
    await room.protocol.send(
      "agent.tool_call_response_chunk",
      packMessage({"tool_call_id": toolCallId, "chunk": packedChunk.header}, packedChunk.payload.isEmpty ? null : packedChunk.payload),
      id: messageId,
    );
  }
}

/// Install (create + index + optimize) a RequiredTable in the current room.
Future<void> installTable(RoomClient room, RequiredTable table, {Logger? logger, bool optimize = true}) async {
  logger ??= Logger.root;
  final database = room.database;

  await database.createTableWithSchema(
    name: table.name,
    mode: CreateMode.createIfNotExists,
    schema: table.schema,
    namespace: table.namespace,
  );

  final indexes = await database.listIndexes(table.name, namespace: table.namespace);

  bool indexExists(String column) {
    for (final idx in indexes) {
      if (idx.columns.contains(column)) return true;
    }
    return false;
  }

  for (final vi in table.vectorIndexes ?? const <String>[]) {
    if (indexExists(vi)) continue;
    try {
      await database.createVectorIndex(table: table.name, column: vi, namespace: table.namespace, replace: true);
    } catch (error, st) {
      logger.warning('unable to create vector index for "$vi": $error', error, st);
    }
  }

  for (final ti in table.fullTextSearchIndexes ?? const <String>[]) {
    if (indexExists(ti)) continue;
    try {
      await database.createFullTextSearchIndex(table: table.name, column: ti, namespace: table.namespace, replace: true);
    } catch (error, st) {
      logger.warning('unable to create full text search index for "$ti": $error', error, st);
    }
  }

  for (final si in table.scalarIndexes ?? const <String>[]) {
    if (indexExists(si)) continue;
    try {
      await database.createScalarIndex(table: table.name, column: si, namespace: table.namespace, replace: true);
    } catch (error, st) {
      logger.warning('unable to create scalar index for "$si": $error', error, st);
    }
  }

  if (optimize) {
    logger.info('optimizing table ${table.name} in ${table.namespace}');
    await database.optimize(table: table.name, namespace: table.namespace);
  }
}

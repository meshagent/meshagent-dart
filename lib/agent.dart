import 'dart:typed_data';
import 'package:logging/logging.dart';
import 'package:meshagent/database_client.dart';
import 'package:meshagent/room_server_client.dart';
import 'package:meshagent/protocol.dart';

abstract class Tool {
  Tool({required this.name, this.description, this.title, required this.inputSchema, this.thumbnailUrl, this.supportsContext = false});

  final String name;
  final String? description;
  final String? title;
  final String? thumbnailUrl;
  final Map<String, dynamic> inputSchema;
  final bool supportsContext;

  Future<Response> execute(ToolContext context, Map<String, dynamic> arguments);
}

abstract class Toolkit {
  final String name;
  final String? title;
  final String? description;
  final String? thumbnailUrl;

  final List<Tool> tools;
  final List<String> rules;

  Toolkit({required this.name, this.title, this.description, this.thumbnailUrl, required this.tools, required this.rules});

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

  Future<Response> execute(ToolContext context, String name, Map<String, dynamic> arguments) async {
    return await getTool(name).execute(context, arguments);
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
  final RoomClient room;

  RemoteToolkit({
    required super.name,
    super.title,
    super.description,
    super.thumbnailUrl,
    required this.room,
    required super.tools,
    super.rules = const [],
  });

  Future<void> start({bool public = false}) async {
    room.protocol.addHandler("agent.tool_call.$name", _toolCall);

    await _register(public: public);
  }

  Future<void> stop() async {
    await _unregister();

    room.protocol.removeHandler("agent.tool_call.$name", _toolCall);
  }

  String? _registrationId;

  Future<void> _register({bool public = false}) async {
    final response = await room.sendRequest("agent.register_toolkit", {
      "name": name,
      "title": title,
      "description": description,
      "tools": getTools(),
      "public": public,
      "thumbnail_url": thumbnailUrl,
    });
    _registrationId = (response as JsonResponse).json["id"];
  }

  Future<void> _unregister() async {
    if (_registrationId != null) {
      await room.sendRequest("agent.unregister_toolkit", {"id": _registrationId!});
    }
  }

  Future<void> _toolCall(Protocol protocol, int messageId, String type, Uint8List data) async {
    var message = unpackMessage(data).header;
    var toolName = message["name"];
    var args = message["arguments"] as Map<String, dynamic>;

    try {
      var response = await execute(ToolContext(room: room), toolName, args);
      await room.protocol.send(id: messageId, "agent.tool_call_response", response.pack());
    } catch (e) {
      await room.protocol.send(id: messageId, "agent.tool_call_response", ErrorResponse(text: "$e").pack());
    }
  }
}

/// Install (create + index + optimize) a RequiredTable in the current room.
///
/// Mirrors the Python logic:
/// - create_table_with_schema(mode=create_if_not_exists)
/// - list_indexes + index_exists(column in i.columns)
/// - create missing indexes (vector / full-text / scalar), each guarded w/ try/catch
/// - optimize(table)
///
/// Notes:
/// - This assumes your DatabaseClient exposes the methods used below with the same
///   parameter names (or close). If your method names differ, keep the structure
///   and swap the calls.
/// - `listIndexes()` is assumed to return items that either have a `columns`
///   field (List<String>) or a JSON map containing `columns`.

Future<void> installTable(RoomClient room, RequiredTable table, {Logger? logger, bool optimize = true}) async {
  logger ??= Logger.root;

  final database = room.database;

  // 1) Create table (idempotent)
  await database.createTableWithSchema(
    name: table.name,
    mode: CreateMode.createIfNotExists,
    schema: table.schema,
    namespace: table.namespace,
  );

  // 2) Read current indexes once
  final indexes = await database.listIndexes(table.name, namespace: table.namespace);

  bool indexExists(String column) {
    for (final idx in indexes) {
      if (idx.columns.contains(column)) return true;
    }
    return false;
  }

  // 3) Create missing vector indexes
  for (final vi in table.vectorIndexes ?? const <String>[]) {
    if (indexExists(vi)) continue;

    try {
      await database.createVectorIndex(table: table.name, column: vi, namespace: table.namespace, replace: true);
    } catch (e, st) {
      logger.warning('unable to create vector index for "$vi": $e', e, st);
    }
  }

  // 4) Create missing full text search indexes
  for (final ti in table.fullTextSearchIndexes ?? const <String>[]) {
    if (indexExists(ti)) continue;

    try {
      await database.createFullTextSearchIndex(table: table.name, column: ti, namespace: table.namespace, replace: true);
    } catch (e, st) {
      logger.warning('unable to create full text search index for "$ti": $e', e, st);
    }
  }

  // 5) Create missing scalar indexes
  for (final si in table.scalarIndexes ?? const <String>[]) {
    if (indexExists(si)) continue;

    try {
      await database.createScalarIndex(table: table.name, column: si, namespace: table.namespace, replace: true);
    } catch (e, st) {
      logger.warning('unable to create scalar index for "$si": $e', e, st);
    }
  }

  if (optimize) {
    logger.info('optimizing table ${table.name} in ${table.namespace}');
    // TODO: use index_stats to determine when indexes need to be updated
    await database.optimize(table: table.name, namespace: table.namespace);
  }
}

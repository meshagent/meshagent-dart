import 'dart:typed_data';
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

import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:meshagent/room_server_client.dart';
import 'package:meshagent/protocol.dart';

class AgentChatContext {
  List<Map<String, dynamic>> messages;

  AgentChatContext(
      {List<Map<String, dynamic>>? messages, this.systemRole = "system"})
      : messages = messages != null
            ? List<Map<String, dynamic>>.from(messages)
            : <Map<String, dynamic>>[];

  final String systemRole;

  void appendRules(List<String> rules) {
    Map<String, dynamic>? systemMessage;

    for (var m in messages) {
      if (m["role"] == systemRole) {
        systemMessage = m;
        break;
      }
    }

    if (systemMessage == null) {
      systemMessage = {"role": systemRole, "content": ""};
      messages.add(systemMessage);
    }

    var plan = """
            Rules:
            -${rules.join("\n-")}
        """;

    systemMessage["content"] = systemMessage["content"] + plan;
  }

  void appendUserMessage(String message) {
    messages.add({"role": "user", "content": message});
  }

  void appendUserImage(String url) {
    messages.add({
      "role": "user",
      "content": [
        {
          "type": "image_url",
          "image_url": {"url": url, "detail": "auto"}
        }
      ]
    });
  }

  AgentChatContext copy() {
    // Deep copy using json decode/encode:
    var cloned = jsonDecode(jsonEncode(messages)) as List<dynamic>;
    return AgentChatContext(
        messages: cloned.map((e) => Map<String, dynamic>.from(e)).toList(),
        systemRole: systemRole);
  }

  Map<String, dynamic> to_json() {
    return {"messages": messages, "system_role": systemRole};
  }

  static AgentChatContext from_json(Map<String, dynamic> json) {
    return AgentChatContext(
        messages: List<Map<String, dynamic>>.from(json["messages"]));
  }
}

class AgentCallContext {
  final String _jwt;
  final AgentChatContext _chat;
  final String _apiUrl;

  AgentCallContext(
      {required AgentChatContext chat,
      required String jwt,
      required String api_url})
      : _jwt = jwt,
        _chat = chat,
        _apiUrl = api_url;

  AgentChatContext get chat => _chat;
  String get jwt => _jwt;
  String get api_url => _apiUrl;
}

abstract class Tool {
  Tool(
      {required this.name,
      required this.description,
      required this.title,
      required this.inputSchema,
      this.thumbnailUrl});

  final String name;
  final String description;
  final String title;
  final String? thumbnailUrl;
  final Map<String, dynamic> inputSchema;

  Future<Response> execute(Map<String, dynamic> arguments);
}

abstract class Toolkit {
  final List<Tool> tools;
  final List<String> rules;

  Toolkit({required this.tools, required this.rules});

  Tool getTool(String name) {
    for (final tool in tools) {
      if (tool.name == name) {
        return tool;
      }
    }
    throw Exception("Tool was not found ${name}");
  }

  Map<String, dynamic> getTools() {
    final json = <String, dynamic>{};
    for (final tool in tools) {
      json[tool.name] = {
        "description": tool.description,
        "title": tool.title,
        "input_schema": tool.inputSchema,
        "thumbnail_url": tool.thumbnailUrl,
      };
    }
    return json;
  }

  Future<Response> execute(String name, Map<String, dynamic> arguments) async {
    return await getTool(name).execute(arguments);
  }
}

abstract class RemoteToolkit extends Toolkit {
  final RoomClient client;
  final String name;
  final String title;
  final String description;
  final String? thumbnailUrl;

  RemoteToolkit(
      {required String name,
      required String title,
      required String description,
      this.thumbnailUrl,
      required RoomClient room,
      required super.tools,
      super.rules = const []})
      : client = room,
        name = name,
        description = description,
        title = title;

  Future<void> start({bool public = false}) async {
    client.protocol.addHandler("agent.tool_call.${name}", _toolCall);

    await _register(public: public);
  }

  Future<void> stop() async {
    await _unregister();

    client.protocol.removeHandler("agent.tool_call.${name}", _toolCall);
  }

  String? _registrationId;

  Future<void> _register({bool public = false}) async {
    final response = await client.sendRequest("agent.register_toolkit", {
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
    await client
        .sendRequest("agent.unregister_toolkit", {"id": _registrationId!});
  }

  Future<void> _toolCall(
      Protocol protocol, int messageId, String type, List<int> data) async {
    var message = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
    var toolName = message["name"];
    var args = message["arguments"] as Map<String, dynamic>;

    try {
      var response = await execute(toolName, args);
      await client.protocol
          .send(id: messageId, "agent.tool_call_response", response.pack());
    } catch (e) {
      await client.protocol.send(
          id: messageId,
          "agent.tool_call_response",
          ErrorResponse(text: "${e}").pack());
    }
  }
}

abstract class RemoteTaskRunner {
  final RoomClient client;
  final String name;
  final String description;

  final Map<String, dynamic>? inputSchema;
  final Map<String, dynamic>? outputSchema;

  final bool supportsTools;

  String? _registrationId;

  RemoteTaskRunner({
    required String name,
    required String description,
    required RoomClient client,
    this.inputSchema,
    this.outputSchema,
    this.supportsTools = false,
    this.required = const [],
  })  : client = client,
        name = name,
        description = description;

  final List<Requirement> required;

  Future<void> start() async {
    client.protocol.addHandler("agent.ask", _ask);

    await _register();
  }

  Future<void> stop() async {
    await _unregister();

    client.protocol.removeHandler("agent.ask", _ask);
  }

  Future<void> _register() async {
    final response = (await client.sendRequest("agent.register_agent", {
      "name": this.name,
      "description": this.description,
      "input_schema": this.inputSchema,
      "output_schema": this.outputSchema,
      "supports_tools": this.supportsTools,
      "requires": [
        ...this.required.map((r) => r.toJson())
      ]
    }) as JsonResponse)
        .json;
    _registrationId = response["id"];
  }

  Future<void> _unregister() async {
    await client
        .sendRequest("agent.unregister_agent", {"id": _registrationId!});
  }

  Future<Map<String, dynamic>> ask(AgentCallContext context, Map<String, dynamic> arguments);

  Future<void> _ask(Protocol protocol, int message_id, String msg_type, List<int> data) async {
    var message = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
    Logger.root.info("got message $message");

    var jwt = message["jwt"] as String;
    var args = message["arguments"] as Map<String, dynamic>;
    var task_id = message["task_id"] as String;
    var context_json = message["context"] as Map<String, dynamic>;
    var api_url = message["api_url"] as String;

    try {
      var chat_context = AgentChatContext.from_json(context_json);
      var context = AgentCallContext(chat: chat_context, jwt: jwt, api_url: api_url);
      var response = await ask(context, args);

      await protocol.send(
          "agent.ask_response",
          utf8.encode(jsonEncode({
            "task_id": task_id,
            "response": response,
          })));
    } catch (e) {
      await protocol.send(
          "agent.ask_response",
          utf8.encode(jsonEncode({
            "task_id": task_id,
            "error": e.toString(),
          })));
    }
  }
}

import 'dart:typed_data';

import 'package:meshagent/document.dart';
import 'package:meshagent/room_server_client.dart';

class AgentsClient extends ChangeEmitter {
  AgentsClient({required this.room});

  RoomClient room;

  Future<void> call({required String name, required String url, required Map<String, dynamic> arguments}) async {
    await room.sendRequest("agent.call", {"name": name, "url": url, "arguments": arguments});
  }

  Future<List<ToolkitDescription>> listToolkits({String? participantId}) async {
    final result = (await room.sendRequest("agent.list_toolkits", {"participant_id": participantId})) as JsonResponse;

    final toolkits = <ToolkitDescription>[];
    final tools = result.json["tools"];

    for (final name in tools.keys) {
      final json = tools[name];

      toolkits.add(ToolkitDescription.fromJson(json, name: name));
    }

    return toolkits;
  }

  Future<Response> invokeTool({
    required String toolkit,
    required String tool,
    required Map<String, dynamic> arguments,
    String? participantId,
    String? onBehalfOfId,
    Uint8List? attachment,
  }) async {
    return await room.sendRequest("agent.invoke_tool", {
      "toolkit": toolkit,
      "tool": tool,
      "arguments": arguments,
      "participant_id": participantId,
      "on_behalf_of_id": onBehalfOfId,
    }, data: attachment);
  }
}

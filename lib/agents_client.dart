import 'dart:async';

import 'package:meshagent/document.dart';
import 'package:meshagent/room_server_client.dart';

sealed class ToolCallOutput {
  const ToolCallOutput();
}

class ToolContentOutput extends ToolCallOutput {
  const ToolContentOutput(this.content);

  final Content content;
}

class ToolStreamOutput extends ToolCallOutput {
  const ToolStreamOutput(this.stream, {this.inputClosed});

  final Stream<Content> stream;
  final Future<void>? inputClosed;
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
  AgentsClient({required this.room});

  final RoomClient room;

  Future<void> call({required String name, required String url, required Map<String, dynamic> arguments}) async {
    await room.call(name: name, url: url, arguments: arguments);
  }

  Future<List<ToolkitDescription>> listToolkits({String? participantId, String? participantName, int? timeout}) async {
    return room.listToolkits(participantId: participantId, participantName: participantName, timeout: timeout);
  }

  Future<ToolCallOutput> invokeTool({
    required String toolkit,
    required String tool,
    required ToolInput input,
    String? participantId,
    String? onBehalfOfId,
  }) async {
    return room.invoke(toolkit: toolkit, tool: tool, input: input, participantId: participantId, onBehalfOfId: onBehalfOfId);
  }
}

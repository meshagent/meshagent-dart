import 'package:meshagent/agents_client.dart';
import 'package:meshagent/room_server_client.dart';

class QueuesClient {
  QueuesClient({required this.room});

  RoomClient room;

  RoomServerException _unexpectedResponseError(String operation) {
    return RoomServerException("unexpected return type from queues.$operation");
  }

  Future<Content> _invoke(String operation, Map<String, dynamic> arguments) async {
    final output = await room.invoke(
      toolkit: "queues",
      tool: operation,
      input: ToolContentInput(JsonContent(json: arguments)),
    );
    if (output is! ToolContentOutput) {
      throw _unexpectedResponseError(operation);
    }
    return output.content;
  }

  Future<List<Queue>> list() async {
    final response = await _invoke("list", {});
    if (response is! JsonContent) {
      throw _unexpectedResponseError("list");
    }

    return (response.json["queues"] as List).map((i) => Queue(name: i["name"], size: i["size"])).toList();
  }

  Future<void> open(String name) async {
    final response = await _invoke("open", {"name": name});
    if (response is! EmptyContent) {
      throw _unexpectedResponseError("open");
    }
  }

  Future<void> drain(String name) async {
    final response = await _invoke("drain", {"name": name});
    if (response is! EmptyContent) {
      throw _unexpectedResponseError("drain");
    }
  }

  Future<void> close(String name) async {
    final response = await _invoke("close", {"name": name});
    if (response is! EmptyContent) {
      throw _unexpectedResponseError("close");
    }
  }

  Future<void> send(String name, Map<String, dynamic> message, {bool create = true}) async {
    final response = await _invoke("send", {"name": name, "create": create, "message": message});
    if (response is! EmptyContent) {
      throw _unexpectedResponseError("send");
    }
  }

  Future<Map<String, dynamic>?> receive(String name, {bool create = true, bool wait = true}) async {
    final response = await _invoke("receive", {"name": name, "create": create, "wait": wait});

    if (response is EmptyContent) {
      return null;
    }
    if (response is JsonContent) {
      return response.json;
    }
    throw _unexpectedResponseError("receive");
  }
}

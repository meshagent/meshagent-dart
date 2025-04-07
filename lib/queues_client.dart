import 'package:meshagent/room_server_client.dart';

class QueuesClient {
  QueuesClient({required this.room});

  RoomClient room;

  Future<List<Queue>> list() async {
    final response = (await room.sendRequest("queues.list", {})) as JsonResponse;

    return (response.json["queues"] as List).map((i) => Queue(name: i["name"], size: i["size"])).toList();
  }

  Future<void> open(String name) async {
    await room.sendRequest("queues.open", {"name": name});
  }

  Future<void> drain(String name) async {
    await room.sendRequest("queues.drain", {"name": name});
  }

  Future<void> close(String name) async {
    await room.sendRequest("queues.close", {"name": name});
  }

  Future<void> send(String name, Map<String, dynamic> message, {bool create = true}) async {
    await room.sendRequest("queues.send", {"name": name, "create": create, "message": message});
  }

  Future<Map<String, dynamic>?> receive(String name, {bool create = true, bool wait = true}) async {
    final response = await room.sendRequest("queues.receive", {"name": name, "create": create, "wait": wait});

    if (response is EmptyResponse) {
      return null;
    } else {
      return (response as JsonResponse).json;
    }
  }
}

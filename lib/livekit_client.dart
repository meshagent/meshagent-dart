import 'package:meshagent/room_server_client.dart';

class LivekitConnectionInfo {
  const LivekitConnectionInfo({required this.url, required this.token});

  final String url;
  final String token;
}

class LivekitClient {
  LivekitClient({required this.room});

  RoomClient room;

  Future<LivekitConnectionInfo> getConnectionInfo({String? breakoutRoom}) async {
    final response = (await room.sendRequest("livekit.connect", {"breakout_room": breakoutRoom}) as JsonResponse).json;

    return LivekitConnectionInfo(token: response["token"], url: response["url"]);
  }
}

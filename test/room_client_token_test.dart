import 'package:meshagent/meshagent.dart';
import 'package:test/test.dart';

void main() {
  test('apiGrant is available when room client uses a raw websocket protocol', () {
    final token = ParticipantToken(name: 'user', projectId: 'project');
    token.addRoomGrant('room');
    token.addApiGrant(ApiScope(developer: DeveloperGrant(logs: true), storage: StorageGrant(), admin: AdminGrant()));

    final room = RoomClient(
      protocol: Protocol(
        channel: WebSocketProtocolChannel(
          url: Uri.parse('ws://localhost:8080/rooms/room'),
          jwt: token.toJwt(token: 'secret'),
        ),
      ),
    );

    final apiGrant = room.apiGrant;
    expect(apiGrant, isNotNull);
    expect(apiGrant!.developer?.logs, isTrue);
    expect(apiGrant.storage, isNotNull);
    expect(apiGrant.admin, isNotNull);
  });
}

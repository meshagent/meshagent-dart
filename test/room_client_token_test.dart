import 'package:meshagent/meshagent.dart';
import 'package:test/test.dart';

void main() {
  test('apiGrant is available when room client uses a raw websocket protocol', () {
    final token = ParticipantToken(name: 'user', projectId: 'project');
    token.addRoomGrant('room');
    token.addApiGrant(ApiScope(developer: DeveloperGrant(logs: true), storage: StorageGrant(), llm: LLMGrant(), admin: AdminGrant()));

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
    expect(apiGrant.llm, isNotNull);
    expect(apiGrant.admin, isNotNull);
  });

  test('llm grant enforces provider and model restrictions', () {
    final grant = LLMGrant(models: ['openai/gpt-4o*', 'anthropic/claude-sonnet-4-5']);

    expect(grant.canUseProvider('openai'), isTrue);
    expect(grant.canUseProvider('google'), isFalse);
    expect(grant.canUseModel(provider: 'openai', model: 'gpt-4o-mini'), isTrue);
    expect(grant.canUseModel(provider: 'openai', model: 'gpt-4.1'), isFalse);
  });
}

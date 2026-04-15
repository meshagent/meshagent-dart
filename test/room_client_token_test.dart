import 'package:meshagent/meshagent.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:test/test.dart';

void main() {
  test('apiGrant is available when room client uses a raw websocket protocol', () {
    final token = ParticipantToken(name: 'user', projectId: 'project');
    token.addRoomGrant('room');
    token.addApiGrant(ApiScope(developer: DeveloperGrant(logs: true), storage: StorageGrant(), llm: LLMGrant(), admin: AdminGrant()));

    final room = RoomClient(
      protocolFactory: WebSocketClientProtocol.createFactory(
        url: Uri.parse('ws://localhost:8080/rooms/room'),
        token: token.toJwt(token: 'secret'),
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

  test('participant token json round trip preserves extra payload', () {
    final token = ParticipantToken(name: 'user', extra: {'meshagent_bootstrap': true});
    token.addRoomGrant('room');

    final decoded = ParticipantToken.fromJson(token.toJson());

    expect(decoded.extra, containsPair('meshagent_bootstrap', true));
    expect(decoded.grantScope('room'), equals('room'));
  });

  test('explicit raw secret preserves kid on participant tokens', () {
    final token = ParticipantToken(name: 'user', projectId: 'project-1', apiKeyId: 'should-preserve');

    final jwt = token.toJwt(token: 'explicit-secret');
    final decoded = JWT.verify(jwt, SecretKey('explicit-secret'), checkHeaderType: false);

    expect(decoded.payload['kid'], equals('should-preserve'));
    expect(decoded.payload['sub'], equals('project-1'));
  });
}

import 'dart:io';

import 'package:meshagent/meshagent.dart';
import 'package:uuid/uuid.dart';

const String roomServerE2eSecret = 'test-secret-secure-secret-sample2560binarykey';

String? get roomServerE2eSkipReason {
  if ((Platform.environment['MESHAGENT_API_URL'] ?? '').isEmpty) {
    return 'MESHAGENT_API_URL must point at a local room server.';
  }
  return null;
}

RoomClient newRoomServerE2eClient({required String roomName, required String participantName, ApiScope? apiScope}) {
  final baseUrl = Platform.environment['MESHAGENT_API_URL']!;
  final url = Uri.parse('${baseUrl.replaceFirst(RegExp(r'^http'), 'ws')}/rooms/$roomName');
  final token =
      ParticipantToken(
          name: participantName,
          projectId: Platform.environment['MESHAGENT_PROJECT_ID'] ?? 'testproject',
          apiKeyId: Platform.environment['MESHAGENT_KEY_ID'] ?? 'test-key-secure-key-sample2560binarykey',
        )
        ..addRoomGrant(roomName)
        ..addRoleGrant('agent')
        ..addApiGrant(apiScope ?? ApiScope.agentDefault());

  return RoomClient(
    protocolFactory: WebSocketClientProtocol.createFactory(
      url: url,
      token: token.toJwt(
        token: Platform.environment['MESHAGENT_SECRET'] ?? roomServerE2eSecret,
        apiKey: Platform.environment['MESHAGENT_API_KEY'],
      ),
    ),
    reconnectTimeout: Duration.zero,
  );
}

Future<void> withRoomServerE2eClient(
  Future<void> Function(RoomClient client) callback, {
  ApiScope? apiScope,
  String roomNamePrefix = 'dart-room',
}) async {
  final roomName = '$roomNamePrefix-${const Uuid().v4()}';
  final client = newRoomServerE2eClient(roomName: roomName, participantName: 'client1', apiScope: apiScope);
  await client.start();
  try {
    await callback(client);
  } finally {
    client.dispose();
  }
}

Future<void> withTwoRoomServerE2eClients(
  Future<void> Function(RoomClient client1, RoomClient client2) callback, {
  ApiScope? apiScope1,
  ApiScope? apiScope2,
  String roomNamePrefix = 'dart-room',
}) async {
  final roomName = '$roomNamePrefix-${const Uuid().v4()}';
  final client1 = newRoomServerE2eClient(roomName: roomName, participantName: 'client1', apiScope: apiScope1);
  final client2 = newRoomServerE2eClient(roomName: roomName, participantName: 'client2', apiScope: apiScope2);
  await client1.start();
  await client2.start();
  try {
    await callback(client1, client2);
  } finally {
    client1.dispose();
    client2.dispose();
  }
}

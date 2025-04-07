import 'dart:async';
import 'dart:convert';

import 'room_server_client.dart';
import 'participant_token.dart';
import 'schema.dart';
import 'protocol.dart';

/// Validate schema name.
void _validateSchemaName(String name) {
  if (name.contains('.')) {
    throw MeshSchemaValidationException("schema name cannot contain '.'");
  }
}

/// Deploy schema to the room’s storage.
Future<void> deploySchema({required RoomClient room, required MeshSchema schema, required String name, bool overwrite = true}) async {
  _validateSchemaName(name);

  final handle = await room.storage.open('.schemas/$name.json', overwrite: overwrite);

  // Convert schema to JSON, then to bytes.
  final data = utf8.encode(jsonEncode(schema.toJson()));

  await room.storage.write(handle, data);
  await room.storage.close(handle);
}

/// Return the base URL for meshagent, checking environment variables first.
String meshagentBaseUrl([String? baseUrl]) {
  // If baseUrl is already provided, just return it.
  if (baseUrl != null && baseUrl.isNotEmpty) {
    return baseUrl;
  }

  // Otherwise, check environment variable or default.
  final envUrl = String.fromEnvironment('MESHAGENT_API_URL', defaultValue: "");
  if (envUrl.isEmpty) {
    return 'https://api.meshagent.com';
  }

  return envUrl;
}

/// Construct the WebSocket URL for a room.
Uri websocketRoomUrl({required String roomName, String? baseUrl}) {
  // If no `baseUrl` provided, derive from environment.
  baseUrl ??= String.fromEnvironment('MESHAGENT_API_URL', defaultValue: "");

  if (baseUrl.isEmpty) {
    // Default if not set:
    baseUrl = 'wss://api.meshagent.com';
  } else {
    // Convert http/https to ws/wss if needed:
    if (baseUrl.startsWith('https:')) {
      baseUrl = 'wss:${baseUrl.substring('https:'.length)}';
    } else if (baseUrl.startsWith('http:')) {
      baseUrl = 'ws:${baseUrl.substring('http:'.length)}';
    }
  }

  return Uri.parse('$baseUrl/rooms/$roomName');
}

/// Create a participant token, requires environment variables to be set.
ParticipantToken participantToken({required String participantName, required String roomName, String? role}) {
  final projectId = String.fromEnvironment('MESHAGENT_PROJECT_ID', defaultValue: "");
  final keyId = String.fromEnvironment('MESHAGENT_KEY_ID', defaultValue: "");

  if (projectId.isEmpty) {
    throw Exception('MESHAGENT_PROJECT_ID must be set. You can find this value in Meshagent Studio under API keys.');
  }

  if (keyId.isEmpty) {
    throw Exception('MESHAGENT_KEY_ID must be set. You can find this value in Meshagent Studio under API keys.');
  }

  final token = ParticipantToken(name: participantName, projectId: projectId, apiKeyId: keyId);

  token.addRoomGrant(roomName);

  if (role != null) {
    token.addRoleGrant(role);
  }

  return token;
}

/// Create a WebSocket protocol instance for the given participant and room.
WebSocketClientProtocol websocketProtocol({required String participantName, required String roomName, String? role}) {
  final url = websocketRoomUrl(roomName: roomName);
  final token = participantToken(participantName: participantName, roomName: roomName, role: role);

  final secret = String.fromEnvironment('MESHAGENT_SECRET', defaultValue: "");
  if (secret.isEmpty) {
    throw Exception('MESHAGENT_SECRET must be set in the environment.');
  }

  return WebSocketClientProtocol(url: url, token: token.toJwt(token: secret));
}

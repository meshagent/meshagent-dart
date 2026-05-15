import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meshagent/meshagent.dart';
import 'package:test/test.dart';

void main() {
  test('createAgent omits null permissions', () async {
    Map<String, dynamic>? body;
    final client = MockClient((request) async {
      body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'id': 'agent-1',
          'name': 'chatbot',
          'configuration': {'name': 'chatbot'},
        }),
        200,
      );
    });
    final meshagent = Meshagent(baseUrl: 'http://example.test', token: 'test-token', client: client);

    await meshagent.createAgent(projectId: 'proj_123', configuration: {'name': 'chatbot'});

    expect(body, {
      'configuration': {'name': 'chatbot'},
      'if_not_exists': false,
    });
  });

  test('RoomSession omits null managed-agent fields', () {
    final session = RoomSession(
      id: 'session-1',
      roomId: 'room-1',
      roomName: 'general',
      createdAt: DateTime.parse('2026-05-15T12:00:00Z'),
      isActive: true,
      participants: null,
    );

    expect(session.toJson(), {
      'id': 'session-1',
      'room_id': 'room-1',
      'room_name': 'general',
      'started_at': '2026-05-15T12:00:00.000Z',
      'is_active': true,
      'kind': 'room',
    });
  });
}

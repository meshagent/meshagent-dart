import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:meshagent/meshagent.dart';
import 'package:test/test.dart';

class _ProtocolPair {
  _ProtocolPair() {
    clientProtocol = Protocol(
      channel: StreamProtocolChannel(input: _serverToClient.stream, output: _clientToServer.sink),
    );
    serverProtocol = Protocol(
      channel: StreamProtocolChannel(input: _clientToServer.stream, output: _serverToClient.sink),
    );
  }

  final _clientToServer = StreamController<Uint8List>();
  final _serverToClient = StreamController<Uint8List>();
  late final Protocol clientProtocol;
  late final Protocol serverProtocol;

  Future<void> dispose() async {
    try {
      clientProtocol.dispose();
    } catch (_) {}
    try {
      serverProtocol.dispose();
    } catch (_) {}
    await _clientToServer.close();
    if (!_serverToClient.isClosed) {
      await _serverToClient.close();
    }
  }
}

Future<void> _sendRoomReady(Protocol protocol) async {
  await protocol.send(
    'room_ready',
    packMessage({'room_name': 'test-room', 'room_url': 'ws://example/rooms/test-room', 'session_id': 'session-1'}),
  );
}

class _RecordedRequest {
  _RecordedRequest({required this.tool, required this.input});

  final String tool;
  final Content input;
}

class _SecretsHarness {
  _SecretsHarness({required this.pair, required this.room, required this.server});

  final _ProtocolPair pair;
  final RoomClient room;
  final _FakeSecretsServer server;

  Future<void> dispose() async {
    room.dispose();
    await pair.dispose();
  }
}

class _FakeSecretsServer {
  final requests = <_RecordedRequest>[];

  Future<void> handleMessage(Protocol protocol, int messageId, String type, Uint8List data) async {
    if (type != 'room.invoke_tool') {
      return;
    }

    final message = unpackMessage(data);
    final request = message.header;
    if (request['toolkit'] != 'secrets') {
      return;
    }

    final tool = request['tool'] as String;
    final input = _decodeInput(message: message, request: request);
    requests.add(_RecordedRequest(tool: tool, input: input));

    switch (tool) {
      case 'get_secret':
        await protocol.send(
          '__response__',
          FileContent(data: Uint8List.fromList('secret'.codeUnits), name: 'secret.txt', mimeType: 'text/plain').pack(),
          id: messageId,
        );
        return;
      case 'request_secret':
        await protocol.send(
          '__response__',
          FileContent(data: Uint8List.fromList('delegated'.codeUnits), name: 'delegated.txt', mimeType: 'text/plain').pack(),
          id: messageId,
        );
        return;
      case 'list_secrets':
        await protocol.send(
          '__response__',
          JsonContent(
            json: {
              'secrets': [
                {'id': 'secret-1', 'type': 'text/plain', 'name': 'secret.txt', 'delegated_to': null},
              ],
            },
          ).pack(),
          id: messageId,
        );
        return;
      case 'request_oauth_token':
        await protocol.send('__response__', JsonContent(json: {'access_token': 'oauth-token'}).pack(), id: messageId);
        return;
      case 'get_offline_oauth_token':
        await protocol.send('__response__', JsonContent(json: {'access_token': 'offline-token'}).pack(), id: messageId);
        return;
      default:
        await protocol.send('__response__', EmptyContent().pack(), id: messageId);
        return;
    }
  }

  Content _decodeInput({required Message message, required Map<String, dynamic> request}) {
    final arguments = Map<String, dynamic>.from(request['arguments'] as Map);
    return unpackContent(packMessage(arguments, message.payload.isEmpty ? null : message.payload));
  }
}

Future<_SecretsHarness> _startSecretsHarness() async {
  final pair = _ProtocolPair();
  final server = _FakeSecretsServer();
  pair.serverProtocol.start(onMessage: server.handleMessage);

  final room = RoomClient(protocol: pair.clientProtocol);
  final startFuture = room.start();
  await _sendRoomReady(pair.serverProtocol);
  await startFuture;

  return _SecretsHarness(pair: pair, room: room, server: server);
}

void main() {
  test('secrets client uses room.invoke and encodes strict payloads', () async {
    final harness = await _startSecretsHarness();

    await harness.room.secrets.provideOAuthAuthorization(requestId: 'req-1', code: 'code-1');
    await harness.room.secrets.rejectOAuthAuthorization(requestId: 'req-2', error: 'nope');
    await harness.room.secrets.provideSecret(requestId: 'req-3', data: Uint8List.fromList('secret-bytes'.codeUnits));
    await harness.room.secrets.rejectSecret(requestId: 'req-4', error: 'declined');
    expect(
      await harness.room.secrets.getOfflineOAuthToken(
        delegatedBy: 'provider',
        oauth: OAuthClientConfig(
          clientId: 'client-id',
          authorizationEndpoint: 'https://example.com/authorize',
          tokenEndpoint: 'https://example.com/token',
        ),
      ),
      'offline-token',
    );
    expect(
      await harness.room.secrets.requestOAuthToken(
        fromParticipantId: 'provider-id',
        redirectUri: Uri.parse('http://localhost/callback'),
        delegateTo: 'delegate',
        oauth: OAuthClientConfig(
          clientId: 'client-id',
          authorizationEndpoint: 'https://example.com/authorize',
          tokenEndpoint: 'https://example.com/token',
        ),
      ),
      'oauth-token',
    );
    final secrets = await harness.room.secrets.listSecrets();
    expect(secrets, hasLength(1));
    await harness.room.secrets.deleteSecret(secretId: 'secret-1');
    await harness.room.secrets.deleteRequestedSecret(url: 'https://example.com/secret', type: 'text/plain');
    expect(
      await harness.room.secrets.requestSecret(fromParticipantId: 'provider-id', url: 'https://example.com/secret', type: 'text/plain'),
      Uint8List.fromList('delegated'.codeUnits),
    );
    await harness.room.secrets.setSecret(secretId: 'secret-1', data: Uint8List.fromList('payload'.codeUnits));
    final secret = await harness.room.secrets.getSecret(secretId: 'secret-1');
    expect(secret, isNotNull);
    expect(utf8.decode(secret!.data), 'secret');
    await harness.room.secrets.setSecret(type: 'text/plain', name: 'named-secret', data: Uint8List.fromList('named'.codeUnits));
    final namedSecret = await harness.room.secrets.getSecret(type: 'text/plain', name: 'named-secret');
    expect(namedSecret, isNotNull);

    expect(harness.server.requests.map((entry) => entry.tool).toList(), [
      'provide_oauth_authorization',
      'provide_oauth_authorization',
      'provide_secret',
      'provide_secret',
      'get_offline_oauth_token',
      'request_oauth_token',
      'list_secrets',
      'delete_secret',
      'delete_requested_secret',
      'request_secret',
      'set_secret',
      'get_secret',
      'set_secret',
      'get_secret',
    ]);

    final provideSecretInput = harness.server.requests[2].input;
    expect(provideSecretInput, isA<BinaryContent>());
    expect((provideSecretInput as BinaryContent).headers, {"request_id": "req-3", "error": null});
    expect(utf8.decode(provideSecretInput.data), 'secret-bytes');

    final rejectSecretInput = harness.server.requests[3].input;
    expect(rejectSecretInput, isA<BinaryContent>());
    expect((rejectSecretInput as BinaryContent).headers, {"request_id": "req-4", "error": "declined"});
    expect(rejectSecretInput.data, isEmpty);

    final setSecretInput = harness.server.requests[10].input;
    expect(setSecretInput, isA<BinaryContent>());
    expect((setSecretInput as BinaryContent).headers, {
      "secret_id": "secret-1",
      "type": null,
      "name": null,
      "delegated_to": null,
      "for_identity": null,
      "has_data": true,
    });
    expect(utf8.decode(setSecretInput.data), 'payload');

    final getSecretInput = harness.server.requests[11].input;
    expect(getSecretInput, isA<JsonContent>());
    expect((getSecretInput as JsonContent).json['secret_id'], 'secret-1');

    final namedSetSecretInput = harness.server.requests[12].input;
    expect(namedSetSecretInput, isA<BinaryContent>());
    expect((namedSetSecretInput as BinaryContent).headers, {
      "secret_id": null,
      "type": "text/plain",
      "name": "named-secret",
      "delegated_to": null,
      "for_identity": null,
      "has_data": true,
    });

    final namedGetSecretInput = harness.server.requests[13].input;
    expect(namedGetSecretInput, isA<JsonContent>());
    expect((namedGetSecretInput as JsonContent).json, {
      'secret_id': null,
      'type': 'text/plain',
      'name': 'named-secret',
      'delegated_to': null,
    });

    await harness.dispose();
  });
}

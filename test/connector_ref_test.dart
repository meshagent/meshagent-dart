import 'package:meshagent/meshagent.dart';
import 'package:test/test.dart';

void main() {
  group('Connector.buildConnectorRef', () {
    test('coerces legacy header maps into strict header entries', () {
      final server = MCPServer.fromJson({
        'server_label': 'custom',
        'headers': {'Meshagent-OAuth-Client-Secret-Id': 'secret-123'},
      });

      expect(server.headers, isNotNull);
      expect(server.headers!.map((header) => header.toJson()).toList(), [
        {'name': 'Meshagent-OAuth-Client-Secret-Id', 'value': 'secret-123'},
      ]);
      expect(server.toJson()['headers'], [
        {'name': 'Meshagent-OAuth-Client-Secret-Id', 'value': 'secret-123'},
      ]);
    });

    test('returns null for public MCP server with only server_url', () {
      final server = MCPServer(serverLabel: 'deepwiki', serverUrl: 'https://mcp.deepwiki.com/mcp');

      final connectorRef = Connector.buildConnectorRef(server: server);

      expect(connectorRef, isNull);
    });

    test('builds ref when OAuth config is provided with server_url', () {
      final server = MCPServer(serverLabel: 'mcp', serverUrl: 'https://mcp.notion.com/mcp');
      final oauth = OAuthClientConfig(
        clientId: 'client-id',
        authorizationEndpoint: 'https://auth.example.com/authorize',
        tokenEndpoint: 'https://auth.example.com/token',
      );

      final connectorRef = Connector.buildConnectorRef(server: server, oauth: oauth);

      expect(connectorRef, isNotNull);
      expect(connectorRef?.serverUrl, 'https://mcp.notion.com/mcp');
      expect(connectorRef?.openaiConnectorId, isNull);
    });

    test('builds ref when openai connector id is provided', () {
      final server = MCPServer(serverLabel: 'dropbox', openaiConnectorId: 'connector_dropbox');

      final connectorRef = Connector.buildConnectorRef(server: server);

      expect(connectorRef, isNotNull);
      expect(connectorRef?.openaiConnectorId, 'connector_dropbox');
    });

    test('builds ref when custom OAuth secret header is present', () {
      final server = MCPServer(
        serverLabel: 'custom',
        serverUrl: 'https://mcp.example.com',
        headers: const [MCPHeader(name: 'Meshagent-OAuth-Client-Secret-Id', value: 'secret-123')],
      );

      final connectorRef = Connector.buildConnectorRef(server: server);

      expect(connectorRef, isNotNull);
      expect(connectorRef?.clientSecretId, 'secret-123');
      expect(connectorRef?.serverUrl, 'https://mcp.example.com');
    });
  });
}

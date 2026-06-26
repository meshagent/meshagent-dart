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

  group('mcpConnectorsFromRoomServices', () {
    test('builds MCP connectors from matching room services', () {
      final connectors = mcpConnectorsFromRoomServices(
        agentName: 'chatbot',
        services: [
          ServiceSpec(
            metadata: ServiceMetadata(name: 'local-mcp'),
            ports: [
              PortSpec(
                num: PortNum.fromInt(8080),
                endpoints: [
                  EndpointSpec(
                    path: '/mcp',
                    mcp: MCPEndpointSpec(label: 'Local MCP', requireApproval: 'always', headers: const {'Authorization': 'Bearer token'}),
                  ),
                ],
              ),
            ],
          ),
          ServiceSpec(
            metadata: ServiceMetadata(name: 'external-mcp', annotations: const {'meshagent.agent.filter': 'chatbot'}),
            external: ExternalServiceSpec(url: 'mcp.example.com/root'),
            ports: [
              PortSpec(
                num: PortNum.fromInt(443),
                endpoints: [
                  EndpointSpec(
                    path: 'remote',
                    mcp: MCPEndpointSpec(label: 'External MCP'),
                  ),
                ],
              ),
            ],
          ),
          ServiceSpec(
            metadata: ServiceMetadata(name: 'filtered-out', annotations: const {'meshagent.agent.filter': 'other-agent'}),
            ports: [
              PortSpec(
                num: PortNum.fromInt(9090),
                endpoints: [
                  EndpointSpec(
                    path: '/ignored',
                    mcp: MCPEndpointSpec(label: 'Ignored MCP'),
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      expect(connectors.map((connector) => connector.name).toList(), ['Local MCP', 'External MCP']);
      expect(connectors.first.server.serverUrl, 'http://localhost:8080/mcp');
      expect(connectors.first.server.requireApproval, 'always');
      expect(connectors.first.server.openaiConnectorId, isNull);
      expect(connectors.first.server.headers?.map((header) => header.toJson()).toList(), [
        {'name': 'Authorization', 'value': 'Bearer token'},
      ]);
      expect(connectors.last.server.serverUrl, 'https://mcp.example.com:443/root/remote');
    });

    test('hides OAuth MCP connectors unless they are proxy backed', () {
      final connectors = mcpConnectorsFromRoomServices(
        services: [
          ServiceSpec(
            metadata: ServiceMetadata(name: 'legacy-oauth-mcp'),
            ports: [
              PortSpec(
                num: PortNum.fromInt(8080),
                endpoints: [
                  EndpointSpec(
                    path: '/legacy',
                    mcp: MCPEndpointSpec(label: 'Legacy OAuth MCP', openaiConnectorId: 'connector_legacy'),
                  ),
                ],
              ),
            ],
          ),
          ServiceSpec(
            metadata: ServiceMetadata(name: 'proxy-oauth-mcp'),
            external: ExternalServiceSpec(url: 'https://mcp.example.com'),
            ports: [
              PortSpec(
                num: PortNum.fromInt(443),
                endpoints: [
                  EndpointSpec(
                    path: '/mcp',
                    mcp: MCPEndpointSpec(label: 'Proxy OAuth MCP', openaiConnectorId: 'connector_proxy', useProxySecret: 'secret-123'),
                  ),
                ],
              ),
            ],
          ),
        ],
        meshagentProxyConfig: const MeshagentProxyConfig(apiUrl: 'https://api.meshagent.test', apiKey: 'api-token'),
      );

      expect(connectors.map((connector) => connector.name).toList(), ['Proxy OAuth MCP']);
      final connector = connectors.single;
      final proxyUri = Uri.parse(connector.server.serverUrl!);
      expect('${proxyUri.origin}${proxyUri.path}', 'https://api.meshagent.test/proxy-request');
      expect(proxyUri.queryParameters['secret-id'], 'secret-123');
      expect(connector.server.headers?.map((header) => header.toJson()).toList(), [
        {'name': 'Authorization', 'value': 'Bearer api-token'},
      ]);
      expect(connector.oauth, isNull);
    });

    test('hides proxy-backed MCP connectors when proxy config is unavailable', () {
      final connectors = mcpConnectorsFromRoomServices(
        services: [
          ServiceSpec(
            metadata: ServiceMetadata(name: 'proxy-oauth-mcp'),
            external: ExternalServiceSpec(url: 'https://mcp.example.com'),
            ports: [
              PortSpec(
                num: PortNum.fromInt(443),
                endpoints: [
                  EndpointSpec(
                    path: '/mcp',
                    mcp: MCPEndpointSpec(label: 'Proxy OAuth MCP', useProxySecret: 'secret-123'),
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      expect(connectors, isEmpty);
    });
  });
}

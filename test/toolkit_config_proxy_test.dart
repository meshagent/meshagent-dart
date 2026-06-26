import 'package:meshagent/meshagent.dart';
import 'package:test/test.dart';

void main() {
  test('mcpConnectorsFromRoomServices routes proxy-backed mcp endpoints', () {
    final services = [
      ServiceSpec.fromJson({
        'version': 'v1',
        'kind': 'Service',
        'metadata': {'name': 'external-mcp'},
        'external': {'url': 'https://mcp.example.com'},
        'ports': [
          {
            'num': 443,
            'endpoints': [
              {
                'path': '/mcp',
                'mcp': {
                  'label': 'Proxy MCP',
                  'use_proxy_secret': 'secret-123',
                  'oauth': {
                    'client_id': 'client-id',
                    'authorization_endpoint': 'https://auth.example.com/authorize',
                    'token_endpoint': 'https://auth.example.com/token',
                  },
                },
              },
            ],
          },
        ],
      }),
    ];

    final connectors = mcpConnectorsFromRoomServices(
      services: services,
      meshagentProxyConfig: const MeshagentProxyConfig(
        apiUrl: 'https://api.meshagent.test/',
        apiKey: 'ma-test-key',
        user: 'user@example.com',
      ),
    );

    final connector = connectors.single;
    final proxyUri = Uri.parse(connector.server.serverUrl!);
    expect('${proxyUri.origin}${proxyUri.path}', 'https://api.meshagent.test/proxy-request');
    expect(proxyUri.queryParameters['url'], 'https://mcp.example.com:443/mcp');
    expect(proxyUri.queryParameters['secret-id'], 'secret-123');
    expect(proxyUri.queryParameters['user'], 'user@example.com');
    expect(connector.server.headers!.map((header) => header.toJson()).toList(), [
      {'name': 'Authorization', 'value': 'Bearer ma-test-key'},
    ]);
    expect(connector.oauth, isNull);
  });
}

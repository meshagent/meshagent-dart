import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meshagent/meshagent.dart';
import 'package:test/test.dart';

Map<String, dynamic> customDomainJson(String domain) => {
  'domain': domain,
  'project_id': 'project-1',
  'phase': 'pending_dns',
  'available': false,
  'dns_authorization_record': {'name': '_acme.example.com.', 'type': 'CNAME', 'data': 'token.authorize.certificatemanager.goog.'},
  'routing_records': [
    {'name': domain, 'type': 'A', 'data': '203.0.113.10'},
  ],
  'conditions': <Object>[],
  'created_at': '2026-08-31T12:00:00Z',
};

void main() {
  test('createCustomDomain sends the immutable domain name and parses DNS instructions', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(jsonEncode({'custom_domain': customDomainJson('*.example.com')}), 202);
    });
    final meshagent = Meshagent(baseUrl: 'https://api.example.test', token: 'token', client: client);

    final domain = await meshagent.createCustomDomain(projectId: 'project-1', domain: '*.example.com');

    expect(captured.method, 'POST');
    expect(captured.url.path, '/accounts/projects/project-1/custom-domains');
    expect(jsonDecode(captured.body), {'domain': '*.example.com'});
    expect(domain.domain, '*.example.com');
    expect(domain.wildcard, isTrue);
    expect(domain.dnsAuthorizationRecord?.type, 'CNAME');
    expect(domain.routingRecords.single.data, '203.0.113.10');
  });

  test('getCustomDomain percent-encodes wildcard resource keys', () async {
    late Uri requested;
    final client = MockClient((request) async {
      requested = request.url;
      return http.Response(jsonEncode({'custom_domain': customDomainJson('*.example.com')}), 200);
    });
    final meshagent = Meshagent(baseUrl: 'https://api.example.test', token: 'token', client: client);

    await meshagent.getCustomDomain(projectId: 'project-1', domain: '*.example.com');

    expect(requested.pathSegments.last, '*.example.com');
  });
}

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meshagent/meshagent.dart';
import 'package:test/test.dart';

void main() {
  test('getSysadminUsage requests the all-project usage endpoint with filters', () async {
    final requests = <String>[];
    final client = MockClient((request) async {
      requests.add('${request.method} ${request.url}');
      return http.Response(
        jsonEncode({
          'usage': [
            {
              'project_id': 'project-1',
              'project_name': 'Acme Project',
              'provider': 'openai',
              'model': 'gpt-4.1-mini',
              'type': 'input_tokens',
              'total': 1000,
              'price': 1.0,
            },
          ],
        }),
        200,
      );
    });
    final meshagent = Meshagent(baseUrl: 'http://example.test', token: 'test-token', client: client);

    final usage = await meshagent.getSysadminUsage(
      start: DateTime.utc(2026, 4, 1),
      end: DateTime.utc(2026, 5, 1),
      interval: 'day',
      report: 'cost_by_provider',
      projectId: ' project-1 ',
      provider: ' openai ',
      model: ' gpt-4.1-mini ',
      usageType: ' input_tokens ',
      client: ' meshagent-cli/1.0 ',
      annotations: {'team': 'Search'},
    );

    expect(requests, [
      'GET http://example.test/accounts/sysadmin/usage?start=2026-04-01T00%3A00%3A00.000Z&end=2026-05-01T00%3A00%3A00.000Z&interval=day&report=cost_by_provider&project_id=project-1&provider=openai&model=gpt-4.1-mini&usage_type=input_tokens&client=meshagent-cli%2F1.0&annotations=%7B%22team%22%3A%22Search%22%7D',
    ]);
    expect(usage, [
      {
        'project_id': 'project-1',
        'project_name': 'Acme Project',
        'provider': 'openai',
        'model': 'gpt-4.1-mini',
        'type': 'input_tokens',
        'total': 1000,
        'price': 1.0,
      },
    ]);
  });
}

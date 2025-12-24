import 'package:meshagent/room_server_client.dart';
import 'package:test/test.dart';

void main() {
  group('AgentDescription', () {
    AgentDescription createAgent({
      Map<String, dynamic>? outputSchema,
      List<Requirement>? requires,
      bool supportsTools = false,
      List<String>? labels,
    }) {
      return AgentDescription(
        name: 'example-agent',
        title: 'Example Agent',
        description: 'An example agent.',
        inputSchema: const {'type': 'object'},
        outputSchema: outputSchema,
        supportsTools: supportsTools,
        labels: labels,
      );
    }

    test('defaults optional parameters when omitted', () {
      final agent = createAgent();

      expect(agent.outputSchema, isNull);
      expect(agent.supportsTools, isFalse);
      expect(agent.labels, isEmpty);
    });

    test('null list arguments fall back to new empty lists', () {
      final agent1 = createAgent(requires: null, labels: null);
      final agent2 = createAgent(requires: null, labels: null);

      expect(agent1.labels, isEmpty);
      expect(identical(agent1.labels, agent2.labels), isFalse);

      agent1.labels?.add('primary');

      expect(agent2.labels, isEmpty);
    });

    test('fromJson applies defaults when values are missing', () {
      final agent = AgentDescription.fromJson({
        'name': 'json-agent',
        'title': 'Json Agent',
        'description': 'Loaded from JSON',
        'input_schema': const {'type': 'object'},
      });

      expect(agent.outputSchema, isNull);
      expect(agent.supportsTools, isFalse);
      expect(agent.labels, isEmpty);
    });

    test('AgentDescription toJson serializes parsed data', () {
      final source = {
        'name': 'sample_agent',
        'title': 'Sample Agent',
        'description': 'Provides sample functionality',
        'input_schema': {
          'type': 'object',
          'properties': {
            'input': {'type': 'string'},
          },
        },
        'output_schema': {
          'type': 'object',
          'properties': {
            'output': {'type': 'number'},
          },
        },
        'labels': ['beta', 'demo'],
        'supports_tools': true,
      };

      final description = AgentDescription.fromJson(source);

      expect(description.toJson(), source);
    });
  });
}

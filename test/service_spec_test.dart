import 'package:meshagent/meshagent.dart';
import 'package:test/test.dart';

void main() {
  test('service spec channels roundtrip through toJson/fromJson', () {
    final service = ServiceSpec(
      metadata: ServiceMetadata(name: 'channel-service'),
      container: ContainerSpec(image: 'meshagent/example'),
      agents: [
        AgentSpec(
          name: 'agent-1',
          description: 'Handles requests',
          annotations: {'role': 'support'},
          channels: ChannelsSpec(
            email: [
              EmailChannel(address: 'support@example.com', private: false, annotations: {'label': 'inbox'}),
            ],
            chat: [
              ChatChannel(
                prompts: [PromptTemplate(name: 'welcome', prompt: 'Hello there')],
              ),
            ],
            queue: [
              QueueChannel(
                queue: 'jobs',
                messageSchema: {
                  'type': 'object',
                  'properties': {
                    'task': {'type': 'string'},
                  },
                },
              ),
            ],
            toolkit: [ToolkitChannel(name: 'helper-tools')],
          ),
        ),
      ],
    );

    final restored = ServiceSpec.fromJson(service.toJson());

    expect(restored.agents, hasLength(1));
    expect(restored.agents.single.channels, isNotNull);
    expect(restored.agents.single.channels!.email, hasLength(1));
    expect(restored.agents.single.channels!.email.single.address, 'support@example.com');
    expect(restored.agents.single.channels!.email.single.private, isFalse);
    expect(restored.agents.single.channels!.chat.single.prompts, hasLength(1));
    expect(restored.agents.single.channels!.chat.single.prompts.single.name, 'welcome');
    expect(restored.agents.single.channels!.chat.single.prompts.single.description, isNull);
    expect(restored.agents.single.channels!.queue.single.messageSchema, {
      'type': 'object',
      'properties': {
        'task': {'type': 'string'},
      },
    });
    expect(restored.agents.single.channels!.toolkit.single.name, 'helper-tools');
  });

  test('service template toServiceSpec fills and preserves agent channels', () {
    final template = ServiceTemplateSpec.fromJson({
      'version': 'v1',
      'kind': 'ServiceTemplate',
      'metadata': {'name': 'channel-template'},
      'agents': [
        {
          'name': 'helper-{role}',
          'description': 'Handles {role}',
          'annotations': {'role': '{role}'},
          'channels': {
            'email': [
              {
                'address': 'support+{role}@example.com',
                'annotations': {'label': '{role}-inbox'},
              },
            ],
            'chat': [
              {
                'prompts': [
                  {'name': 'summary-{role}', 'prompt': 'Summarize the {role} request'},
                ],
              },
            ],
            'queue': [
              {
                'queue': 'jobs-{role}',
                'message_schema': {'type': 'object', 'description': 'Schema for {role}'},
              },
            ],
            'toolkit': [
              {'name': 'docs-{role}'},
            ],
          },
        },
      ],
      'container': {'image': 'meshagent/example'},
    });

    final service = template.toServiceSpec(values: const {'role': 'ops'});

    expect(service.agents, hasLength(1));
    expect(service.agents.single.channels, isNotNull);
    expect(service.agents.single.name, 'helper-ops');
    expect(service.agents.single.description, 'Handles ops');
    expect(service.agents.single.annotations['role'], 'ops');
    expect(service.agents.single.channels!.email.single.address, 'support+ops@example.com');
    expect(service.agents.single.channels!.email.single.annotations['label'], 'ops-inbox');
    expect(service.agents.single.channels!.chat.single.prompts.single.name, 'summary-ops');
    expect(service.agents.single.channels!.chat.single.prompts.single.description, isNull);
    expect(service.agents.single.channels!.chat.single.prompts.single.prompt, 'Summarize the ops request');
    expect(service.agents.single.channels!.queue.single.queue, 'jobs-ops');
    expect(service.agents.single.channels!.queue.single.messageSchema, {'type': 'object', 'description': 'Schema for ops'});
    expect(service.agents.single.channels!.toolkit.single.name, 'docs-ops');
  });
}

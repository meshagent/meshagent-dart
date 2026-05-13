import 'package:meshagent/meshagent.dart';
import 'package:test/test.dart';

void main() {
  test('token value preserves role through json', () {
    final token = TokenValue(identity: 'TravelAssistant', role: 'agent');

    final payload = token.toJson();
    final restored = TokenValue.fromJson(payload);

    expect(payload['role'], 'agent');
    expect(restored.role, 'agent');
  });

  test('service spec channels roundtrip through toJson/fromJson', () {
    final service = ServiceSpec(
      metadata: ServiceMetadata(name: 'channel-service'),
      container: ContainerSpec(image: 'meshagent/example'),
      agents: [
        AgentSpec(
          name: 'agent-1',
          description: 'Handles requests',
          annotations: {'role': 'support'},
          email: EmailSpec(address: 'assistant@example.com', public: true),
          heartbeat: HeartbeatSpec(
            queue: 'assistant-scheduled-tasks',
            threadId: '/agents/assistant/threads/heartbeats/{YYYY}/{MM}/{DD}/{HH}/{mm}/heartbeat.thread',
            prompt: [
              AgentFileContent(url: 'room:///agents/assistant/heartbeat.md'),
              AgentTextContent(text: 'Review the latest support queue.'),
            ],
            minutes: 60,
          ),
          channels: ChannelsSpec(
            email: [
              EmailChannel(address: 'support@example.com', private: false, annotations: {'label': 'inbox'}),
            ],
            messaging: [
              MessagingChannel(
                prompts: [PromptTemplate(name: 'welcome', prompt: 'Hello there')],
              ),
            ],
            queue: [
              QueueChannel(
                queue: 'jobs',
                threadingMode: 'default-new',
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

    final payload = service.toJson();
    final restored = ServiceSpec.fromJson(payload);

    expect(restored.agents, hasLength(1));
    expect(restored.agents.single.channels, isNotNull);
    expect(restored.agents.single.email, isNotNull);
    expect(restored.agents.single.email!.address, 'assistant@example.com');
    expect(restored.agents.single.email!.public, isTrue);
    expect(restored.agents.single.heartbeat, isNotNull);
    expect(restored.agents.single.heartbeat!.queue, 'assistant-scheduled-tasks');
    expect(restored.agents.single.heartbeat!.threadId, '/agents/assistant/threads/heartbeats/{YYYY}/{MM}/{DD}/{HH}/{mm}/heartbeat.thread');
    expect(restored.agents.single.heartbeat!.minutes, 60);
    expect(restored.agents.single.heartbeat!.prompt, hasLength(2));
    expect(restored.agents.single.heartbeat!.prompt.first, isA<AgentFileContent>());
    expect((restored.agents.single.heartbeat!.prompt.first as AgentFileContent).url, 'room:///agents/assistant/heartbeat.md');
    expect(restored.agents.single.heartbeat!.prompt.last, isA<AgentTextContent>());
    expect((restored.agents.single.heartbeat!.prompt.last as AgentTextContent).text, 'Review the latest support queue.');
    expect(restored.agents.single.channels!.email, hasLength(1));
    expect(restored.agents.single.channels!.email.single.address, 'support@example.com');
    expect(restored.agents.single.channels!.email.single.private, isFalse);
    expect(
      (((payload['agents'] as List).single as Map<String, dynamic>)['channels'] as Map<String, dynamic>)['messaging'][0]['protocol'],
      'meshagent.agent-message.v1',
    );
    expect(restored.agents.single.channels!.messaging.single.protocol, 'meshagent.agent-message.v1');
    expect(restored.agents.single.channels!.messaging.single.prompts, hasLength(1));
    expect(restored.agents.single.channels!.messaging.single.prompts.single.name, 'welcome');
    expect(restored.agents.single.channels!.messaging.single.prompts.single.description, isNull);
    expect(restored.agents.single.channels!.queue.single.threadingMode, 'default-new');
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
          'email': {'address': 'assistant+{role}@example.com'},
          'heartbeat': {
            'queue': 'assistant-scheduled-tasks-{role}',
            'thread_id': '/agents/{role}/heartbeat.thread',
            'prompt': [
              {'type': 'file', 'url': 'room:///agents/{role}/heartbeat.md'},
              {'type': 'text', 'text': 'Review the {role} queue'},
            ],
            'minutes': 60,
          },
          'channels': {
            'email': [
              {
                'address': 'support+{role}@example.com',
                'annotations': {'label': '{role}-inbox'},
              },
            ],
            'messaging': [
              {
                'prompts': [
                  {'name': 'summary-{role}', 'prompt': 'Summarize the {role} request'},
                ],
              },
            ],
            'queue': [
              {
                'queue': 'jobs-{role}',
                'threading_mode': 'default-new',
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
    expect(service.agents.single.email, isNotNull);
    expect(service.agents.single.email!.address, 'assistant+ops@example.com');
    expect(service.agents.single.email!.public, isFalse);
    expect(service.agents.single.heartbeat, isNotNull);
    expect(service.agents.single.heartbeat!.queue, 'assistant-scheduled-tasks-ops');
    expect(service.agents.single.heartbeat!.threadId, '/agents/ops/heartbeat.thread');
    expect(service.agents.single.heartbeat!.minutes, 60);
    expect(service.agents.single.heartbeat!.prompt, hasLength(2));
    expect(service.agents.single.heartbeat!.prompt.first, isA<AgentFileContent>());
    expect((service.agents.single.heartbeat!.prompt.first as AgentFileContent).url, 'room:///agents/ops/heartbeat.md');
    expect(service.agents.single.heartbeat!.prompt.last, isA<AgentTextContent>());
    expect((service.agents.single.heartbeat!.prompt.last as AgentTextContent).text, 'Review the ops queue');
    expect(service.agents.single.channels!.email.single.address, 'support+ops@example.com');
    expect(service.agents.single.channels!.email.single.annotations['label'], 'ops-inbox');
    expect(service.agents.single.channels!.messaging.single.protocol, 'meshagent.agent-message.v1');
    expect(service.agents.single.channels!.messaging.single.prompts.single.name, 'summary-ops');
    expect(service.agents.single.channels!.messaging.single.prompts.single.description, isNull);
    expect(service.agents.single.channels!.messaging.single.prompts.single.prompt, 'Summarize the ops request');
    expect(service.agents.single.channels!.queue.single.queue, 'jobs-ops');
    expect(service.agents.single.channels!.queue.single.threadingMode, 'default-new');
    expect(service.agents.single.channels!.queue.single.messageSchema, {'type': 'object', 'description': 'Schema for ops'});
    expect(service.agents.single.channels!.toolkit.single.name, 'docs-ops');
  });

  test('service template storage preserves files and config mounts', () {
    final template = ServiceTemplateSpec.fromJson({
      'version': 'v1',
      'kind': 'ServiceTemplate',
      'metadata': {'name': 'storage-template'},
      'container': {
        'image': 'meshagent/example',
        'storage': {
          'files': [
            {'path': '/rules/assistant.txt', 'text': 'Follow the rules.'},
          ],
          'configs': [{}],
        },
      },
    });

    final service = template.toServiceSpec(values: const {});

    expect(service.container, isNotNull);
    expect(service.container!.storage, isNotNull);
    expect(service.container!.storage!.files, hasLength(1));
    expect(service.container!.storage!.files!.single.path, '/rules/assistant.txt');
    expect(service.container!.storage!.files!.single.text, 'Follow the rules.');
    expect(service.container!.storage!.configs, hasLength(1));
    expect(service.container!.storage!.configs!.single.path, '/var/run/meshagent');
  });

  test('service spec storage preserves config mount defaults from dynamic maps', () {
    final service = ServiceSpec.fromJson({
      'version': 'v1',
      'kind': 'Service',
      'metadata': {'name': 'storage-service'},
      'container': {
        'image': 'meshagent/example',
        'storage': {
          'configs': [{}],
        },
      },
    });

    expect(service.container, isNotNull);
    expect(service.container!.storage, isNotNull);
    expect(service.container!.storage!.configs, hasLength(1));
    expect(service.container!.storage!.configs!.single.path, '/var/run/meshagent');
  });
}

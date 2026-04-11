import 'package:meshagent/meshagent.dart';
import 'package:test/test.dart';

class _NoopTool extends FunctionTool {
  _NoopTool({required super.name, required super.inputSchema});

  @override
  Future<Content> execute(ToolContext context, Map<String, dynamic> arguments) async {
    return JsonContent(json: {'ok': true});
  }
}

class _NoopContentTool extends ContentTool {
  _NoopContentTool({required super.name, required super.inputSchema, super.inputSpec});

  @override
  Future<ToolCallOutput> execute(ToolContext context, ToolInput input) async {
    return ToolContentOutput(JsonContent(json: {'ok': true}));
  }
}

class _NoopToolkit extends Toolkit {
  _NoopToolkit({required super.name, required super.tools}) : super(rules: const []);
}

void main() {
  test('Toolkit.getTools emits json input_spec by default for FunctionTool', () async {
    final toolkit = _NoopToolkit(
      name: 'sample',
      tools: [
        _NoopTool(
          name: 'echo',
          inputSchema: const {
            'type': 'object',
            'properties': {
              'text': {'type': 'string'},
            },
          },
        ),
      ],
    );

    final encoded = toolkit.getTools();
    expect(encoded['echo']['input_spec'], {
      'types': ['json'],
      'stream': false,
      'schema': {
        'type': 'object',
        'properties': {
          'text': {'type': 'string'},
        },
      },
    });
  });

  test('Toolkit.getTools preserves explicit input_spec', () async {
    final toolkit = _NoopToolkit(
      name: 'sample',
      tools: [
        _NoopContentTool(
          name: 'echo',
          inputSchema: const {'type': 'object'},
          inputSpec: ToolContentSpec(types: [ToolContentType.text], stream: true),
        ),
      ],
    );

    final encoded = toolkit.getTools();
    expect(encoded['echo']['input_spec'], {
      'types': ['text'],
      'stream': true,
    });
  });
}

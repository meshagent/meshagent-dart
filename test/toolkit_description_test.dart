import 'package:meshagent/room_server_client.dart';
import 'package:test/test.dart';

void main() {
  test('ToolkitDescription toJson serializes parsed data', () {
    final source = {
      'name': 'sample_toolkit',
      'description': 'A sample toolkit',
      'title': 'Sample Toolkit',
      'tools': [
        {
          'name': 'tool_a',
          'title': 'Tool A',
          'description': 'Performs task A',
          'input_spec': {
            'types': ['json'],
            'stream': false,
            'schema': {'type': 'object'},
          },
          'output_spec': {
            'types': ['json', 'text'],
            'stream': true,
            'schema': {
              'type': 'object',
              'properties': {
                'result': {'type': 'string'},
              },
            },
          },
          'defs': {'ref': '#/definitions/tool_a'},
        },
        {
          'name': 'tool_b',
          'title': 'Tool B',
          'description': 'Performs task B',
          'input_spec': {
            'types': ['json'],
            'stream': false,
            'schema': {
              'type': 'object',
              'required': ['value'],
            },
          },
          'output_spec': {
            'types': ['file'],
            'stream': false,
          },
          'thumbnail_url': null,
          'defs': null,
          'pricing': null,
        },
      ],
    };

    final toolkit = ToolkitDescription.fromJson(source);

    expect(toolkit.toJson(), {
      'name': 'sample_toolkit',
      'description': 'A sample toolkit',
      'title': 'Sample Toolkit',
      'tools': [
        {
          'name': 'tool_a',
          'title': 'Tool A',
          'description': 'Performs task A',
          'input_spec': {
            'types': ['json'],
            'stream': false,
            'schema': {'type': 'object'},
          },
          'output_spec': {
            'types': ['json', 'text'],
            'stream': true,
            'schema': {
              'type': 'object',
              'properties': {
                'result': {'type': 'string'},
              },
            },
          },
          'defs': {'ref': '#/definitions/tool_a'},
        },
        {
          'name': 'tool_b',
          'title': 'Tool B',
          'description': 'Performs task B',
          'input_spec': {
            'types': ['json'],
            'stream': false,
            'schema': {
              'type': 'object',
              'required': ['value'],
            },
          },
          'output_spec': {
            'types': ['file'],
            'stream': false,
          },
          'defs': null,
        },
      ],
    });
  });

  test('ToolkitDescription leaves input_spec undefined when missing', () {
    final toolkit = ToolkitDescription.fromJson({
      'name': 'sample_toolkit',
      'description': 'A sample toolkit',
      'title': 'Sample Toolkit',
      'tools': [
        {'name': 'tool_a', 'title': 'Tool A', 'description': 'Performs task A'},
      ],
    });

    expect(toolkit.toJson()['tools'][0]['input_spec'], isNull);
  });

  test('ToolkitDescription keeps schema under input_spec.schema', () {
    final toolkit = ToolkitDescription.fromJson({
      'name': 'sample_toolkit',
      'description': 'A sample toolkit',
      'title': 'Sample Toolkit',
      'tools': [
        {
          'name': 'tool_a',
          'title': 'Tool A',
          'description': 'Performs task A',
          'input_spec': {
            'types': ['json'],
            'stream': false,
            'schema': {
              'type': 'object',
              'properties': {
                'value': {'type': 'string'},
              },
            },
          },
        },
      ],
    });

    expect(toolkit.tools[0].inputSpec?.schema, {
      'type': 'object',
      'properties': {
        'value': {'type': 'string'},
      },
    });
  });
}

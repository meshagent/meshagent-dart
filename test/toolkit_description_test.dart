import 'package:meshagent/room_server_client.dart';
import 'package:test/test.dart';

void main() {
  test('ToolkitDescription toJson serializes parsed data', () {
    final source = {
      'name': 'sample_toolkit',
      'description': 'A sample toolkit',
      'title': 'Sample Toolkit',
      'thumbnail_url': 'https://example.com/toolkit.png',
      'tools': [
        {
          'name': 'tool_a',
          'title': 'Tool A',
          'description': 'Performs task A',
          'input_schema': {'type': 'object'},
          'thumbnail_url': 'https://example.com/tool_a.png',
          'defs': {'ref': '#/definitions/tool_a'},
          'pricing': 'free',
          'supports_context': true,
        },
        {
          'name': 'tool_b',
          'title': 'Tool B',
          'description': 'Performs task B',
          'input_schema': {
            'type': 'object',
            'required': ['value'],
          },
          'thumbnail_url': null,
          'defs': null,
          'pricing': null,
          'supports_context': false,
        },
      ],
    };

    final toolkit = ToolkitDescription.fromJson(source);

    expect(toolkit.toJson(), {
      'name': 'sample_toolkit',
      'description': 'A sample toolkit',
      'title': 'Sample Toolkit',
      'thumbnail_url': 'https://example.com/toolkit.png',
      'tools': [
        {
          'name': 'tool_a',
          'title': 'Tool A',
          'description': 'Performs task A',
          'input_schema': {'type': 'object'},
          'thumbnail_url': 'https://example.com/tool_a.png',
          'defs': {'ref': '#/definitions/tool_a'},
          'pricing': 'free',
          'supports_context': true,
        },
        {
          'name': 'tool_b',
          'title': 'Tool B',
          'description': 'Performs task B',
          'input_schema': {
            'type': 'object',
            'required': ['value'],
          },
          'thumbnail_url': null,
          'defs': null,
          'pricing': null,
          'supports_context': false,
        },
      ],
    });
  });
}

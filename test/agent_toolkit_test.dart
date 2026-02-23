import 'dart:async';
import 'dart:typed_data';

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

class _NoopRemoteToolkit extends RemoteToolkit {
  _NoopRemoteToolkit({required super.name, required super.tools, required super.room}) : super(rules: const []);
}

class _RoomHarness {
  _RoomHarness() {
    clientProtocol = Protocol(
      channel: StreamProtocolChannel(input: _serverToClient.stream, output: _clientToServer.sink),
    );
    room = RoomClient(protocol: clientProtocol);
  }

  final _clientToServer = StreamController<Uint8List>();
  final _serverToClient = StreamController<Uint8List>();
  late final Protocol clientProtocol;
  late final RoomClient room;

  void dispose() {
    try {
      clientProtocol.dispose();
    } catch (_) {}
    unawaited(_clientToServer.close());
    unawaited(_serverToClient.close());
  }
}

void main() {
  test('RemoteToolkit.getTools emits json input_spec by default for FunctionTool', () async {
    final harness = _RoomHarness();
    addTearDown(harness.dispose);

    final toolkit = _NoopRemoteToolkit(
      name: 'sample',
      room: harness.room,
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

  test('RemoteToolkit.getTools preserves explicit input_spec', () async {
    final harness = _RoomHarness();
    addTearDown(harness.dispose);

    final toolkit = _NoopRemoteToolkit(
      name: 'sample',
      room: harness.room,
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

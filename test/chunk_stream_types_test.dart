import 'package:meshagent/meshagent.dart';
import 'package:test/test.dart';

void main() {
  test('ToolContentOutput wraps a chunk', () {
    final result = ToolContentOutput(TextContent(text: 'done'));

    expect(result.content, isA<TextContent>());
    expect((result.content as TextContent).text, 'done');
  });

  test('ToolStreamOutput wraps a stream', () async {
    final result = ToolStreamOutput(Stream<Content>.fromIterable([TextContent(text: 'a'), TextContent(text: 'b')]));
    final values = await result.stream.toList();

    expect(values.length, 2);
    expect((values.first as TextContent).text, 'a');
    expect((values.last as TextContent).text, 'b');
  });

  test('ControlContent roundtrips through pack/unpackContent', () {
    final packed = ControlContent(method: 'open').pack();
    final unpacked = unpackContent(packed);

    expect(unpacked, isA<ControlContent>());
    expect((unpacked as ControlContent).method, 'open');
  });

  test('ErrorContent roundtrips optional code through pack/unpackContent', () {
    final packed = ErrorContent(text: 'invalid request', code: 1002).pack();
    final unpacked = unpackContent(packed);

    expect(unpacked, isA<ErrorContent>());
    final error = unpacked as ErrorContent;
    expect(error.text, 'invalid request');
    expect(error.code, 1002);
  });
}

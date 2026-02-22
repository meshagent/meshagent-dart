import 'package:meshagent/meshagent.dart';
import 'package:test/test.dart';

void main() {
  test('ToolCallChunkResult wraps a chunk', () {
    final result = ToolCallChunkResult(TextChunk(text: 'done'));

    expect(result.chunk, isA<TextChunk>());
    expect((result.chunk as TextChunk).text, 'done');
  });

  test('ToolCallStreamResult wraps a stream', () async {
    final result = ToolCallStreamResult(Stream<Chunk>.fromIterable([TextChunk(text: 'a'), TextChunk(text: 'b')]));
    final values = await result.stream.toList();

    expect(values.length, 2);
    expect((values.first as TextChunk).text, 'a');
    expect((values.last as TextChunk).text, 'b');
  });

  test('ControlChunk roundtrips through pack/unpackChunk', () {
    final packed = ControlChunk(method: 'open').pack();
    final unpacked = unpackChunk(packed);

    expect(unpacked, isA<ControlChunk>());
    expect((unpacked as ControlChunk).method, 'open');
  });
}

import 'package:meshagent/api_keys.dart';
import 'package:test/test.dart';

void main() {
  group('base36 encoding', () {
    const uuid = '123e4567-e89b-12d3-a456-426614174000';
    final uuidInt = BigInt.parse(uuid.replaceAll('-', ''), radix: 16);

    test('round-trips representative UUID value', () {
      final encoded = base36Encode(uuidInt);
      expect(base36Decode(encoded), uuidInt);
    });

    test('accepts uppercase input when decoding', () {
      final encoded = base36Encode(uuidInt).toUpperCase();
      expect(base36Decode(encoded), uuidInt);
    });

    test('throws for negative values', () {
      expect(() => base36Encode(BigInt.from(-1)), throwsArgumentError);
    });

    test('throws for invalid characters', () {
      expect(() => base36Decode('xyz!'), throwsArgumentError);
    });

    test('throws for empty input', () {
      expect(base36Decode(''), BigInt.zero);
    });
  });

  group('base36 UUID compression', () {
    const uuid = '123e4567-e89b-12d3-a456-426614174000';

    test('round-trips canonical UUIDs', () {
      final compressed = compressUuid(uuid);
      expect(decompressUuid(compressed), equals(uuid));
    });

    test('rejects invalid UUID strings', () {
      expect(() => compressUuid('not-a-uuid'), throwsFormatException);
    });

    test('rejects invalid compressed values', () {
      expect(() => decompressUuid('!invalid!'), throwsArgumentError);
    });
  });

  group('base64 UUID compression', () {
    const uuid = '123e4567-e89b-12d3-a456-426614174000';

    test('round-trips canonical UUIDs', () {
      final compressed = base64CompressUuid(uuid);
      expect(base64DecompressUuid(compressed), equals(uuid));
    });

    test('rejects empty values', () {
      expect(() => base64DecompressUuid(''), throwsFormatException);
    });

    test('rejects invalid base64 strings', () {
      expect(() => base64DecompressUuid('@@@'), throwsFormatException);
    });

    test('rejects values decoding to non-UUID length', () {
      expect(() => base64DecompressUuid('abcd'), throwsFormatException);
    });
  });

  group('API key codec', () {
    const apiKey = ApiKey(
      id: '123e4567-e89b-12d3-a456-426614174000',
      projectId: '987e6543-e21b-45d3-b321-abcdef012345',
      secret: 'super-secret-token',
    );

    test('round-trips encoded values', () {
      final encoded = encodeApiKey(apiKey);
      expect(parseApiKey(encoded).id, equals(apiKey.id));
      expect(parseApiKey(encoded).projectId, equals(apiKey.projectId));
      expect(parseApiKey(encoded).secret, equals(apiKey.secret));
    });

    test('fails without prefix', () {
      expect(() => parseApiKey('invalid'), throwsArgumentError);
    });

    test('fails when missing separator', () {
      expect(() => parseApiKey('ma-abc'), throwsArgumentError);
    });
  });
}

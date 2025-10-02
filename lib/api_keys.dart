import 'dart:convert';
import 'dart:typed_data';

const _base36Alphabet = '0123456789abcdefghijklmnopqrstuvwxyz';
const _hexDigits = '0123456789abcdef';

String base36Encode(dynamic value) {
  final number = _toBigInt(value);

  if (number < BigInt.zero) {
    throw ArgumentError('number must be non-negative');
  }

  if (number == BigInt.zero) {
    return '0';
  }

  const base = 36;
  final chars = <String>[];
  var current = number;

  while (current > BigInt.zero) {
    final remainder = current % BigInt.from(base);

    chars.add(_base36Alphabet[remainder.toInt()]);
    current = current ~/ BigInt.from(base);
  }

  return chars.reversed.join();
}

BigInt base36Decode(String numberStr) {
  final sanitized = numberStr.trim().toLowerCase();

  if (sanitized.isEmpty) {
    return BigInt.zero;
  }

  var result = BigInt.zero;

  for (final char in sanitized.split('')) {
    final index = _base36Alphabet.indexOf(char);

    if (index == -1) {
      throw ArgumentError("Invalid character '$char' for base36 encoding");
    }

    result = result * BigInt.from(36) + BigInt.from(index);
  }

  return result;
}

String compressUuid(String guidString) {
  final hex = _normalizeUuidHex(guidString);
  final guidInt = BigInt.parse(hex, radix: 16);

  return base36Encode(guidInt);
}

String decompressUuid(String compressedUuid) {
  final guidInt = base36Decode(compressedUuid);
  final hex = guidInt.toRadixString(16).padLeft(32, '0');

  return _formatUuidFromHex(hex);
}

String base64CompressUuid(String id) {
  final hex = _normalizeUuidHex(id);
  final bytes = _hexToBytes(hex);
  final base64 = base64UrlEncode(bytes).replaceAll('-', '.').replaceAll('=', '');

  return base64;
}

String base64DecompressUuid(String id) {
  var base64 = id.replaceAll('.', '-');
  final paddingNeeded = base64.length % 4;

  if (paddingNeeded != 0) {
    base64 += '=' * (4 - paddingNeeded);
  }

  final bytes = Uint8List.fromList(base64Url.decode(base64));

  if (bytes.length != 16) {
    throw FormatException('invalid uuid length');
  }

  return _formatUuidFromHex(_bytesToHex(bytes));
}

class ApiKey {
  final String id;
  final String projectId;
  final String secret;

  const ApiKey({required this.id, required this.projectId, required this.secret});
}

ApiKey parseApiKey(String key) {
  if (!key.startsWith('ma-')) {
    throw ArgumentError('invalid api key');
  }

  final rest = key.substring(3);
  final firstSeparator = rest.indexOf('-');

  if (firstSeparator == -1) {
    throw ArgumentError('invalid api key');
  }

  final secondSeparator = rest.indexOf('-', firstSeparator + 1);

  if (secondSeparator == -1) {
    throw ArgumentError('invalid api key');
  }

  final idPart = rest.substring(0, firstSeparator);
  final projectPart = rest.substring(firstSeparator + 1, secondSeparator);
  final secret = rest.substring(secondSeparator + 1);

  return ApiKey(id: base64DecompressUuid(idPart), projectId: base64DecompressUuid(projectPart), secret: secret);
}

String encodeApiKey(ApiKey key) {
  final id = base64CompressUuid(key.id);
  final project = base64CompressUuid(key.projectId);

  return 'ma-$id-$project-${key.secret}';
}

BigInt _toBigInt(dynamic value) {
  if (value is BigInt) {
    return value;
  }

  if (value is int) {
    return BigInt.from(value);
  }

  throw ArgumentError('number must be an integer');
}

String _normalizeUuidHex(String id) {
  final trimmed = id.trim().toLowerCase().replaceAll('-', '');

  if (!_isValidUuidHex(trimmed)) {
    throw FormatException('invalid uuid format');
  }

  return trimmed;
}

bool _isValidUuidHex(String value) {
  if (value.length != 32) {
    return false;
  }

  for (var i = 0; i < value.length; i++) {
    final char = value[i];

    if (!_hexDigits.contains(char)) {
      return false;
    }
  }

  return true;
}

String _formatUuidFromHex(String hex) {
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

Uint8List _hexToBytes(String hex) {
  final bytes = Uint8List(hex.length ~/ 2);

  for (var i = 0; i < hex.length; i += 2) {
    bytes[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
  }

  return bytes;
}

String _bytesToHex(Uint8List bytes) {
  final buffer = StringBuffer();

  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }

  return buffer.toString();
}

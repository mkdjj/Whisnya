import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

class PasswordLock {
  const PasswordLock._();

  static const _pbkdf2Prefix = 'pbkdf2-sha256';
  static const _iterations = 120000;
  static const _keyLength = 32;

  static String newSalt() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  static String hash(String value, String salt) {
    final bytes = _pbkdf2(
      utf8.encode(value.trim()),
      utf8.encode(salt),
      _iterations,
      _keyLength,
    );
    return '$_pbkdf2Prefix:$_iterations:${base64UrlEncode(bytes)}';
  }

  static bool verify(String value, String salt, String expectedHash) {
    if (expectedHash.startsWith('$_pbkdf2Prefix:')) {
      final parts = expectedHash.split(':');
      if (parts.length != 3) return false;
      final iterations = int.tryParse(parts[1]);
      if (iterations == null || iterations <= 0) return false;
      final expected = base64Url.decode(parts[2]);
      final actual = _pbkdf2(
        utf8.encode(value.trim()),
        utf8.encode(salt),
        iterations,
        expected.length,
      );
      return _constantTimeEquals(actual, expected);
    }
    final legacy = sha256.convert(utf8.encode('$salt:${value.trim()}')).bytes;
    final expected = _hexToBytes(expectedHash);
    return expected != null && _constantTimeEquals(legacy, expected);
  }

  static bool needsRehash(String expectedHash) {
    return expectedHash.isNotEmpty &&
        !expectedHash.startsWith('$_pbkdf2Prefix:');
  }

  static String normalizeAnswer(String value) {
    return value.trim().toLowerCase();
  }

  static List<int> _pbkdf2(
    List<int> password,
    List<int> salt,
    int iterations,
    int length,
  ) {
    final hmac = Hmac(sha256, password);
    final output = <int>[];
    for (var block = 1; output.length < length; block++) {
      var u = hmac.convert([...salt, ..._int32(block)]).bytes;
      final t = [...u];
      for (var i = 1; i < iterations; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < t.length; j++) {
          t[j] ^= u[j];
        }
      }
      output.addAll(t);
    }
    return output.take(length).toList();
  }

  static List<int> _int32(int value) {
    return [
      (value >> 24) & 0xff,
      (value >> 16) & 0xff,
      (value >> 8) & 0xff,
      value & 0xff,
    ];
  }

  static List<int>? _hexToBytes(String hex) {
    if (hex.length.isOdd) return null;
    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      final byte = int.tryParse(hex.substring(i, i + 2), radix: 16);
      if (byte == null) return null;
      bytes.add(byte);
    }
    return bytes;
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    var diff = a.length ^ b.length;
    for (var i = 0; i < a.length && i < b.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

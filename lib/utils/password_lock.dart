import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

class PasswordLock {
  const PasswordLock._();

  static String newSalt() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  static String hash(String value, String salt) {
    return sha256.convert(utf8.encode('$salt:${value.trim()}')).toString();
  }

  static bool verify(String value, String salt, String expectedHash) {
    return hash(value, salt) == expectedHash;
  }

  static String normalizeAnswer(String value) {
    return value.trim().toLowerCase();
  }
}

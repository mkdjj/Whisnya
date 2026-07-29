import 'dart:convert';

import 'package:whisnya/utils/password_lock.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('hashes and verifies pbkdf2 passwords', () {
    final salt = PasswordLock.newSalt();
    final hash = PasswordLock.hash('secret', salt);

    expect(hash, startsWith('pbkdf2-sha256:'));
    expect(PasswordLock.needsRehash(hash), isFalse);
    expect(PasswordLock.verify('secret', salt, hash), isTrue);
    expect(PasswordLock.verify('wrong', salt, hash), isFalse);
  });

  test('verifies legacy sha256 password hashes', () {
    const salt = 'legacy-salt';
    final hash = sha256.convert(utf8.encode('$salt:secret')).toString();

    expect(PasswordLock.needsRehash(hash), isTrue);
    expect(PasswordLock.verify('secret', salt, hash), isTrue);
    expect(PasswordLock.verify('wrong', salt, hash), isFalse);
  });

  test('rejects malformed pbkdf2 hashes', () {
    for (final hash in [
      'pbkdf2-sha256:1:',
      'pbkdf2-sha256:120000:not-base64!',
      'pbkdf2-sha256:999999999:${base64UrlEncode(List.filled(32, 0))}',
      'pbkdf2-sha256:120000:${base64UrlEncode([0])}',
    ]) {
      expect(PasswordLock.verify('anything', 'salt', hash), isFalse);
    }
  });
}

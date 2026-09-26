import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/helpers.dart';

/// Argon2id password hashing, stored as a PHC string.
///
/// `$argon2id$v=19$m=19456,t=2,p=1$<salt>$<hash>` carries its own parameters,
/// so raising the cost later only affects new hashes and every old one still
/// verifies. The defaults are OWASP's minimum for Argon2id: 19 MiB, two
/// passes, one lane. Tests pass a cheaper [PasswordHasher] rather than lowering
/// these.
final class PasswordHasher {
  const PasswordHasher({
    this.memoryKiB = 19 * 1024,
    this.iterations = 2,
    this.parallelism = 1,
  });

  /// A deliberately weak setting for tests, where the cost is pure overhead.
  const PasswordHasher.fast() : this(memoryKiB: 64, iterations: 1);

  final int memoryKiB;
  final int iterations;
  final int parallelism;

  static const _hashLength = 32;
  static const _saltLength = 16;

  /// Hashes [password] with a fresh random salt.
  Future<String> hash(String password) async {
    final salt = SecretKeyData.random(length: _saltLength).bytes;
    final digest = await _derive(
      password,
      salt,
      memoryKiB: memoryKiB,
      iterations: iterations,
      parallelism: parallelism,
    );
    return '\$argon2id\$v=19\$m=$memoryKiB,t=$iterations,p=$parallelism'
        '\$${_b64(salt)}\$${_b64(digest)}';
  }

  /// Whether [password] produces [encoded], using the parameters stored in it.
  ///
  /// The comparison is constant-time: `==` on the bytes would stop at the
  /// first difference, and how long that took leaks how much was right.
  Future<bool> verify(String password, String encoded) async {
    final parts = encoded.split(r'$');
    // ['', 'argon2id', 'v=19', 'm=..,t=..,p=..', salt, hash]
    if (parts.length != 6 || parts[1] != 'argon2id') return false;
    final params = {
      for (final pair in parts[3].split(','))
        if (pair.split('=') case [final key, final value])
          key: int.tryParse(value),
    };
    final (m, t, p) = (params['m'], params['t'], params['p']);
    if (m == null || t == null || p == null) return false;

    final expected = _unb64(parts[5]);
    final actual = await _derive(
      password,
      _unb64(parts[4]),
      memoryKiB: m,
      iterations: t,
      parallelism: p,
    );
    return constantTimeBytesEquality.equals(actual, expected);
  }

  static Future<List<int>> _derive(
    String password,
    List<int> salt, {
    required int memoryKiB,
    required int iterations,
    required int parallelism,
  }) async {
    final algorithm = Argon2id(
      memory: memoryKiB,
      iterations: iterations,
      parallelism: parallelism,
      hashLength: _hashLength,
    );
    final key = await algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    return key.extractBytes();
  }

  // PHC strings use unpadded standard base64.
  static String _b64(List<int> bytes) =>
      base64.encode(bytes).replaceAll('=', '');

  static List<int> _unb64(String text) =>
      base64.decode(text.padRight((text.length + 3) & ~3, '='));
}

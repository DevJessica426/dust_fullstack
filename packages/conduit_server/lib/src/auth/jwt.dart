import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// HS256 JSON Web Tokens: what RealWorld calls a `token`.
///
/// Only the one algorithm is issued or accepted. A verifier that reads `alg`
/// from the token and does what it says is how `alg: none` tokens get in, so
/// the header is checked against a constant instead.
final class JwtCodec {
  JwtCodec(List<int> secret, {this.lifetime = const Duration(days: 30)})
    : _hmac = Hmac(sha256, secret) {
    if (secret.length < 32) {
      throw ArgumentError.value(
        secret.length,
        'secret',
        'an HS256 secret needs at least 32 bytes',
      );
    }
  }

  /// A codec with a random secret: tokens stop working when the process ends.
  factory JwtCodec.ephemeral() {
    final random = Random.secure();
    return JwtCodec(List<int>.generate(32, (_) => random.nextInt(256)));
  }

  /// How long an issued token is valid.
  final Duration lifetime;

  final Hmac _hmac;

  static final _header = _encodeJson({'alg': 'HS256', 'typ': 'JWT'});

  /// A token naming user [userId], valid from [now] for [lifetime].
  String issue(int userId, {DateTime? now}) {
    final issuedAt = (now ?? DateTime.now()).toUtc();
    final payload = _encodeJson({
      'sub': '$userId',
      'iat': issuedAt.millisecondsSinceEpoch ~/ 1000,
      'exp': issuedAt.add(lifetime).millisecondsSinceEpoch ~/ 1000,
    });
    final signingInput = '$_header.$payload';
    return '$signingInput.${_sign(signingInput)}';
  }

  /// The user id [token] names, or null when it is malformed, forged or
  /// expired. Every failure is the same null: telling a caller *which* check
  /// failed helps an attacker more than it helps them.
  int? verify(String token, {DateTime? now}) {
    final parts = token.split('.');
    if (parts.length != 3 || parts[0] != _header) return null;

    final expected = _sign('${parts[0]}.${parts[1]}');
    if (!_constantTimeEquals(expected, parts[2])) return null;

    final Object? claims;
    try {
      claims = jsonDecode(utf8.decode(base64Url.decode(_pad(parts[1]))));
    } on FormatException {
      return null;
    }
    if (claims case {'sub': final String sub, 'exp': final int exp}) {
      final nowSeconds = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
      if (exp <= nowSeconds) return null;
      return int.tryParse(sub);
    }
    return null;
  }

  String _sign(String input) =>
      _unpad(base64Url.encode(_hmac.convert(utf8.encode(input)).bytes));

  static String _encodeJson(Object value) =>
      _unpad(base64Url.encode(utf8.encode(jsonEncode(value))));

  static String _unpad(String value) => value.replaceAll('=', '');

  static String _pad(String value) =>
      value.padRight((value.length + 3) & ~3, '=');

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

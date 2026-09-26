import 'dart:convert';

import 'package:conduit_server/conduit_server.dart';
import 'package:test/test.dart';

/// The pieces that need no database.
void main() {
  group('JwtCodec', () {
    final codec = JwtCodec(List<int>.filled(32, 1));
    final now = DateTime.utc(2026, 9, 26, 12);

    test('a token it issued names the same user', () {
      expect(codec.verify(codec.issue(42, now: now), now: now), 42);
    });

    test('a token from another secret is refused', () {
      final other = JwtCodec(List<int>.filled(32, 2));

      expect(codec.verify(other.issue(42, now: now), now: now), isNull);
    });

    test('an expired token is refused', () {
      final token = codec.issue(42, now: now);

      expect(codec.verify(token, now: now.add(const Duration(days: 31))),
          isNull);
    });

    test('a token whose payload was edited is refused', () {
      final [header, _, signature] = codec.issue(42, now: now).split('.');
      final forged = base64Url
          .encode(utf8.encode('{"sub":"1","exp":9999999999}'))
          .replaceAll('=', '');

      expect(codec.verify('$header.$forged.$signature', now: now), isNull);
    });

    test('alg "none" is refused', () {
      String part(Object json) =>
          base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
      final unsigned =
          '${part({'alg': 'none', 'typ': 'JWT'})}.${part({'sub': '1', 'exp': 9999999999})}.';

      expect(codec.verify(unsigned, now: now), isNull);
    });

    test('garbage is refused rather than thrown', () {
      for (final token in ['', 'a.b', 'a.b.c', '...', 'not a token']) {
        expect(codec.verify(token, now: now), isNull, reason: token);
      }
    });

    test('a short secret is a configuration error', () {
      expect(() => JwtCodec(List<int>.filled(16, 1)), throwsArgumentError);
    });
  });

  group('PasswordHasher', () {
    const hasher = PasswordHasher.fast();

    test('stores Argon2id parameters with the hash', () async {
      final encoded = await hasher.hash('correct horse');

      expect(encoded, startsWith(r'$argon2id$v=19$m=64,t=1,p=1$'));
    });

    test('verifies the right password and refuses the wrong one', () async {
      final encoded = await hasher.hash('correct horse');

      expect(await hasher.verify('correct horse', encoded), isTrue);
      expect(await hasher.verify('correct horsf', encoded), isFalse);
    });

    test('salts every hash', () async {
      expect(await hasher.hash('same'), isNot(await hasher.hash('same')));
    });

    test('verifies with the parameters in the hash, not its own', () async {
      final encoded = await const PasswordHasher.fast().hash('pw');

      expect(await const PasswordHasher().verify('pw', encoded), isTrue);
    });

    test('a malformed hash never verifies', () async {
      for (final encoded in ['', r'$argon2id$', r'$bcrypt$v=1$m=1$a$b']) {
        expect(await hasher.verify('pw', encoded), isFalse, reason: encoded);
      }
    });
  });

  group('slugify', () {
    test('lowercases and dashes', () {
      expect(slugify('How to Train Your Dragon!'), 'how-to-train-your-dragon');
    });

    test('keeps letters from any script', () {
      expect(slugify('Ελληνικά και ไทย'), 'ελληνικά-και-ไทย');
    });

    test('never answers empty', () {
      expect(slugify('!!!'), 'article');
    });

    test('is bounded', () {
      expect(slugify('word ' * 100).length, lessThanOrEqualTo(80));
      expect(slugify('word ' * 100), isNot(endsWith('-')));
    });
  });

  test('normalizeTags trims, drops blanks and duplicates, keeps order', () {
    expect(normalizeTags([' b ', 'a', 'b', '', '  ', 'c']), ['b', 'a', 'c']);
  });

  group('ServerConfig', () {
    test('reads the environment', () {
      final config = ServerConfig.fromEnvironment({
        'DATABASE_URL': 'postgres://u:secret@db:5432/app',
        'PORT': '9000',
        'JWT_SECRET': 'x' * 40,
        'WEB_ROOT': '/does/not/exist',
      });

      expect(config.port, 9000);
      expect(config.jwtSecret, hasLength(40));
      expect(config.webRoot, isNull, reason: 'a missing directory is skipped');
      expect(config.redactedDatabaseUrl, isNot(contains('secret')));
    });
  });
}

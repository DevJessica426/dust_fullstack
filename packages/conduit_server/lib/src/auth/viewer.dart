import 'package:dust_server/server.dart';

import '../db/database.dart';
import '../db/rows.dart';
import '../db/users_repo.dart';
import 'jwt.dart';
import 'passwords.dart';

/// What the auth extractors need, attached to the router with `withState`.
final class Auth {
  const Auth({required this.jwt, this.passwords = const PasswordHasher()});

  final JwtCodec jwt;
  final PasswordHasher passwords;
}

/// The signed-in user making a request, and the token they sent.
final class Viewer {
  const Viewer(this.user, this.token);

  final UserRow user;
  final String token;

  int get id => user.id;
}

/// Requires a signed-in user: `Authorization: Token <jwt>`.
///
/// RealWorld's scheme is `Token`; `Bearer` is accepted too, because generic
/// HTTP clients send it and refusing it would only confuse. A missing header
/// and a bad token are both 401 — "is missing" versus "is invalid" — which
/// `RealWorldErrors` reports under the `token` key.
final class RequireViewer implements FromRequestParts<Viewer> {
  const RequireViewer();

  @override
  Future<Result<Viewer, Rejection>> extract(Request request) async {
    return switch (_credential(request)) {
      _Absent() => const Err(_missing),
      _Malformed() => const Err(_invalid),
      _Present(:final token) => await _resolve(request, token),
    };
  }
}

/// A signed-in user if there is one, and `null` when nobody is.
///
/// Absent is fine; *wrong* is not. A client sending a token it believes is
/// valid wants to know it expired, not to be silently shown the signed-out
/// view.
final class OptionalViewer implements FromRequestParts<Viewer?> {
  const OptionalViewer();

  @override
  Future<Result<Viewer?, Rejection>> extract(Request request) async {
    return switch (_credential(request)) {
      _Absent() => const Ok(null),
      _Malformed() => const Err(_invalid),
      _Present(:final token) => await _resolve(request, token),
    };
  }
}

const _missing = Rejection.unauthorized('is missing', challenge: 'Token');
const _invalid = Rejection.unauthorized('is invalid', challenge: 'Token');

sealed class _Credential {
  const _Credential();
}

final class _Absent extends _Credential {
  const _Absent();
}

final class _Malformed extends _Credential {
  const _Malformed();
}

final class _Present extends _Credential {
  const _Present(this.token);
  final String token;
}

_Credential _credential(Request request) {
  final header = request.headers['authorization']?.trim();
  if (header == null || header.isEmpty) return const _Absent();

  final space = header.indexOf(' ');
  if (space < 0) return const _Malformed();
  final scheme = header.substring(0, space).toLowerCase();
  final token = header.substring(space + 1).trim();
  if ((scheme != 'token' && scheme != 'bearer') || token.isEmpty) {
    return const _Malformed();
  }
  return _Present(token);
}

Future<Result<Viewer, Rejection>> _resolve(
  Request request,
  String token,
) async {
  final auth = await const StateExtractable<Auth>().extract(request);
  final database = await const StateExtractable<ConduitDatabase>().extract(
    request,
  );
  if ((auth, database) case (Ok(value: final auth), Ok(value: final db))) {
    final userId = auth.jwt.verify(token);
    if (userId == null) return const Err(_invalid);

    switch (await UsersRepo(db.connection).byId(userId)) {
      case Err(:final error):
        // A database fault is a 500, not a 401: telling someone their token is
        // bad while the database is down sends them to sign in again for
        // nothing.
        ServerErrors.report(error, StackTrace.current);
        return const Err(Rejection.internal());
      case Ok(value: final user?):
        return Ok(Viewer(user, token));
      case Ok():
        // Signed, unexpired, and naming a user who no longer exists.
        return const Err(_invalid);
    }
  }
  return const Err(Rejection.internal('auth is not configured'));
}

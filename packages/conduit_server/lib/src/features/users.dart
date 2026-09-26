import 'package:conduit_shared/conduit_shared.dart';
import 'package:dust_dart/db.dart' show SqlxError;
import 'package:dust_server/server.dart';

import '../auth/viewer.dart';
import '../db/database.dart';
import '../db/users_repo.dart';
import '../http/errors.dart';
import '../http/mapping.dart';

/// `/users`, `/users/login` and `/user`.
Router userRoutes() => Router()
  ..route('/users', post(register, status: 201))
  ..route('/users/login', post(login))
  ..route('/user', get(currentUser).put(updateUser));

/// `POST /users` — sign up, and get a token straight away.
Future<Result<UserEnvelope, ApiError>> register(Request request) async {
  final input = (await request.body(RegisterRequest.fromJson)).user;
  if (invalid(input.validate()) case final error?) return Err(error);

  final auth = await request.state<Auth>();
  final db = await request.state<ConduitDatabase>();

  final inserted = await UsersRepo(db.connection).insert(
    input.username.trim(),
    input.email.trim(),
    await auth.passwords.hash(input.password),
  );
  if (inserted case Err(:final error)) {
    if (_takenField(error) case final field?) return Err(ApiError.taken(field));
    throw error;
  }

  final user = inserted.orThrow;
  return Ok(UserEnvelope(user: userOf(user, auth.jwt.issue(user.id))));
}

/// `POST /users/login` — exchange an email and password for a token.
///
/// One answer for every failure. "No such email" and "wrong password" both
/// say `credentials: invalid`, and the password is hashed even when no user
/// matched, so neither the message nor the time taken reveals which emails
/// have accounts.
Future<Result<UserEnvelope, ApiError>> login(Request request) async {
  final input = (await request.body(LoginRequest.fromJson)).user;
  if (invalid(input.validate()) case final error?) return Err(error);

  final auth = await request.state<Auth>();
  final db = await request.state<ConduitDatabase>();

  final refused = Err<UserEnvelope, ApiError>(
    ApiError.of(401, 'credentials', 'invalid'),
  );

  final user = (await UsersRepo(
    db.connection,
  ).byEmail(input.email.trim())).orThrow;
  if (user == null) {
    // Same work, thrown away, so the timing matches a real account.
    await auth.passwords.verify(input.password, await _decoyHash(auth));
    return refused;
  }
  if (!await auth.passwords.verify(input.password, user.passwordHash)) {
    return refused;
  }
  return Ok(UserEnvelope(user: userOf(user, auth.jwt.issue(user.id))));
}

/// `GET /user` — who the token belongs to.
Future<UserEnvelope> currentUser(Request request) async {
  final viewer = await request.extract<Viewer>(const RequireViewer());
  return UserEnvelope(user: userOf(viewer.user, viewer.token));
}

/// `PUT /user` — change any of email, username, password, bio and image.
///
/// A patch: absent keys are left alone. `bio` and `image` accept `null` or
/// `""` to clear them; `email`, `username` and `password` are required
/// fields, so `null` there is a 422 rather than a clear.
Future<Result<UserEnvelope, ApiError>> updateUser(Request request) async {
  final viewer = await request.extract<Viewer>(const RequireViewer());
  final (patch, sent) = await request.body(
    (json) => (UpdateUserRequest.fromJson(json).user, _keysOf(json['user'])),
  );

  final failures = [
    for (final field in const ['email', 'username', 'password'])
      if (sent[field] == _Sent.asNull)
        ValidationError(field: field, message: "can't be blank"),
    ...patch.validate().errors,
  ];
  if (failures.isNotEmpty) return Err(ApiError.invalid(failures));

  final auth = await request.state<Auth>();
  final db = await request.state<ConduitDatabase>();
  final current = viewer.user;

  String? clearable(String key, String? value, String? existing) =>
      switch (sent[key]) {
        null => existing,
        _ => (value == null || value.trim().isEmpty) ? null : value.trim(),
      };

  final updated = await UsersRepo(db.connection).update(
    current.id,
    patch.username?.trim() ?? current.username,
    patch.email?.trim() ?? current.email,
    switch (patch.password) {
      final password? => await auth.passwords.hash(password),
      null => current.passwordHash,
    },
    clearable('bio', patch.bio, current.bio),
    clearable('image', patch.image, current.image),
  );
  if (updated case Err(:final error)) {
    if (_takenField(error) case final field?) return Err(ApiError.taken(field));
    throw error;
  }

  // The token names the user by id, so it survives a new username or email.
  return Ok(UserEnvelope(user: userOf(updated.orThrow, viewer.token)));
}

/// Which field a unique violation on `users` was about.
String? _takenField(SqlxError error) => switch (uniqueViolation(error)) {
  'users_username_key' => 'username',
  'users_email_key' => 'email',
  _ => null,
};

enum _Sent { asValue, asNull }

/// Which keys a JSON object carried, and whether each was `null`.
///
/// The generated deserializer reads an absent key and an explicit `null` the
/// same way, which is right for a model and wrong for a patch.
Map<String, _Sent> _keysOf(Object? json) => {
  if (json is Map)
    for (final MapEntry(:key, :value) in json.entries)
      if (key is String) key: value == null ? _Sent.asNull : _Sent.asValue,
};

String? _decoy;

/// A real hash of nothing in particular, computed once, so a sign-in for an
/// unknown email spends the same time verifying as one for a real account.
Future<String> _decoyHash(Auth auth) async =>
    _decoy ??= await auth.passwords.hash('conduit decoy password');

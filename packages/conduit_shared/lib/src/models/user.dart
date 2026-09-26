import 'package:dust_dart/serde.dart';

part 'user.g.dart';

// Every required text field uses `regex: r'\S'` — at least one visible
// character — rather than `Length(min: 1)`, which would accept `"   "`.
// "can't be blank" is the message the RealWorld spec asserts on.

/// The signed-in user, as `/users`, `/users/login` and `/user` return it.
@Derive([ToString(), Eq(), CopyWith(), Serialize(), Deserialize()])
final class User with _$User {
  const User({
    required this.email,
    required this.token,
    required this.username,
    this.bio,
    this.image,
  });

  factory User.fromJson(Map<String, Object?> json) => _$UserFromJson(json);

  final String email;

  /// The JWT to send back as `Authorization: Token <token>`.
  final String token;

  final String username;
  final String? bio;
  final String? image;
}

/// `{"user": {...}}`.
@Derive([ToString(), Eq(), Serialize(), Deserialize()])
final class UserEnvelope with _$UserEnvelope {
  const UserEnvelope({required this.user});

  factory UserEnvelope.fromJson(Map<String, Object?> json) =>
      _$UserEnvelopeFromJson(json);

  final User user;
}

/// Credentials for `POST /users/login`.
@Derive([ToString(), Serialize(), Deserialize(), Validate()])
final class LoginUser with _$LoginUser {
  const LoginUser({required this.email, required this.password});

  factory LoginUser.fromJson(Map<String, Object?> json) =>
      _$LoginUserFromJson(json);

  @Validate(regex: r'\S', message: "can't be blank")
  final String email;

  @Validate(regex: r'\S', message: "can't be blank")
  final String password;
}

/// `{"user": {"email": ..., "password": ...}}`.
@Derive([Serialize(), Deserialize()])
final class LoginRequest with _$LoginRequest {
  const LoginRequest({required this.user});

  factory LoginRequest.fromJson(Map<String, Object?> json) =>
      _$LoginRequestFromJson(json);

  final LoginUser user;
}

/// A registration, for `POST /users`.
///
/// The password rules follow NIST SP 800-63B, which the RealWorld suite uses:
/// at least eight characters, no composition rules.
@Derive([ToString(), Serialize(), Deserialize(), Validate()])
final class NewUser with _$NewUser {
  const NewUser({
    required this.username,
    required this.email,
    required this.password,
  });

  factory NewUser.fromJson(Map<String, Object?> json) =>
      _$NewUserFromJson(json);

  @Validate(regex: r'\S', message: "can't be blank")
  @Validate(length: Length(max: 64), message: 'is too long (maximum is 64 characters)')
  final String username;

  @Validate(regex: r'\S', message: "can't be blank")
  @Validate(email: true, message: 'is invalid')
  final String email;

  @Validate(regex: r'\S', message: "can't be blank")
  @Validate(
    length: Length(min: 8, max: 256),
    message: 'must be 8 to 256 characters',
  )
  final String password;
}

/// `{"user": {"username": ..., "email": ..., "password": ...}}`.
@Derive([Serialize(), Deserialize()])
final class RegisterRequest with _$RegisterRequest {
  const RegisterRequest({required this.user});

  factory RegisterRequest.fromJson(Map<String, Object?> json) =>
      _$RegisterRequestFromJson(json);

  final NewUser user;
}

/// A partial update for `PUT /user`.
///
/// This is a patch: a key that is absent leaves the field alone. Dust writes a
/// `null` field as `null`, and on the wire `"bio": null` means "clear my bio",
/// so [toJson] is written by hand to drop the fields that were not set. An
/// empty `bio` or `image` also clears it; the server normalises `""` to `null`.
@Derive([ToString(), Eq(), Deserialize(), Validate()])
final class UpdateUser with _$UpdateUser {
  const UpdateUser({
    this.email,
    this.username,
    this.password,
    this.bio,
    this.image,
  });

  factory UpdateUser.fromJson(Map<String, Object?> json) =>
      _$UpdateUserFromJson(json);

  @Validate(regex: r'\S', message: "can't be blank")
  @Validate(email: true, message: 'is invalid')
  final String? email;

  @Validate(regex: r'\S', message: "can't be blank")
  @Validate(length: Length(max: 64), message: 'is too long (maximum is 64 characters)')
  final String? username;

  @Validate(
    length: Length(min: 8, max: 256),
    message: 'must be 8 to 256 characters',
  )
  final String? password;

  final String? bio;
  final String? image;

  /// Only the fields that were set.
  Map<String, Object?> toJson() => {
        if (email != null) 'email': email,
        if (username != null) 'username': username,
        if (password != null) 'password': password,
        if (bio != null) 'bio': bio,
        if (image != null) 'image': image,
      };
}

/// `{"user": {...changed fields}}`.
@Derive([Serialize(), Deserialize()])
final class UpdateUserRequest with _$UpdateUserRequest {
  const UpdateUserRequest({required this.user});

  factory UpdateUserRequest.fromJson(Map<String, Object?> json) =>
      _$UpdateUserRequestFromJson(json);

  final UpdateUser user;
}

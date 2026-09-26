import 'package:dust_dart/serde.dart';

part 'profile.g.dart';

/// A public view of a user, as seen by whoever is asking.
@Derive([ToString(), Eq(), CopyWith(), Serialize(), Deserialize()])
final class Profile with _$Profile {
  const Profile({
    required this.username,
    required this.following,
    this.bio,
    this.image,
  });

  factory Profile.fromJson(Map<String, Object?> json) =>
      _$ProfileFromJson(json);

  final String username;
  final String? bio;
  final String? image;

  /// Whether the viewer follows this user. Always `false` when signed out.
  final bool following;
}

/// `{"profile": {...}}`.
@Derive([ToString(), Eq(), Serialize(), Deserialize()])
final class ProfileEnvelope with _$ProfileEnvelope {
  const ProfileEnvelope({required this.profile});

  factory ProfileEnvelope.fromJson(Map<String, Object?> json) =>
      _$ProfileEnvelopeFromJson(json);

  final Profile profile;
}

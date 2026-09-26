import 'package:dust_dart/db.dart';

import 'rows.dart';

part 'users_repo.g.dart';

/// Every query about users, profiles and follows.
///
/// `$2` in the profile queries is the viewer's id, or 0 when nobody is signed
/// in — ids start at 1, so 0 follows nobody and needs no second query.
@SqlxDao()
abstract final class UsersRepo {
  const factory UsersRepo(Executor db) = _$UsersRepo;

  /// Creates a user. A taken username or email fails on its unique index.
  @Query(r'''
INSERT INTO users (username, email, password_hash)
VALUES ($1, $2, $3)
RETURNING id, username, email, password_hash, bio, image
''')
  Future<Result<UserRow, SqlxError>> insert(
    String username,
    String email,
    String passwordHash,
  );

  @Query(r'''
SELECT id, username, email, password_hash, bio, image FROM users
WHERE id = $1
''')
  Future<Result<UserRow?, SqlxError>> byId(int id);

  /// For signing in. Emails match case-insensitively, as the index does.
  @Query(r'''
SELECT id, username, email, password_hash, bio, image FROM users
WHERE lower(email) = lower($1)
''')
  Future<Result<UserRow?, SqlxError>> byEmail(String email);

  /// Replaces every editable field. The handler merges the patch first, so
  /// one statement covers any combination of changed fields.
  @Query(r'''
UPDATE users
SET username = $2, email = $3, password_hash = $4, bio = $5, image = $6
WHERE id = $1
RETURNING id, username, email, password_hash, bio, image
''')
  Future<Result<UserRow, SqlxError>> update(
    int id,
    String username,
    String email,
    String passwordHash,
    String? bio,
    String? image,
  );

  /// A profile, as [viewerId] sees it.
  @Query(r'''
SELECT u.id, u.username, u.bio, u.image,
       EXISTS (
         SELECT 1 FROM follows f
         WHERE f.follower_id = $2 AND f.followee_id = u.id
       ) AS following
FROM users u
WHERE u.username = $1
''')
  Future<Result<ProfileRow?, SqlxError>> profile(String username, int viewerId);

  /// Idempotent: following twice is still following.
  @Query(r'''
INSERT INTO follows (follower_id, followee_id) VALUES ($1, $2)
ON CONFLICT DO NOTHING
''')
  Future<Result<Unit, SqlxError>> follow(int followerId, int followeeId);

  @Query(r'''
DELETE FROM follows WHERE follower_id = $1 AND followee_id = $2
''')
  Future<Result<Unit, SqlxError>> unfollow(int followerId, int followeeId);
}

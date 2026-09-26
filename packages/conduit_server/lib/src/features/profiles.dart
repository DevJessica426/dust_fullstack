import 'package:conduit_shared/conduit_shared.dart';
import 'package:dust_server/server.dart';

import '../auth/viewer.dart';
import '../db/database.dart';
import '../db/users_repo.dart';
import '../http/errors.dart';
import '../http/mapping.dart';

/// `/profiles/{username}` and following.
Router profileRoutes() => Router()
  ..route('/profiles/{username}', get(readProfile))
  ..route('/profiles/{username}/follow', post(follow).delete(unfollow));

/// `GET /profiles/{username}` — anyone may look; `following` needs a viewer.
Future<Result<ProfileEnvelope, ApiError>> readProfile(Request request) async {
  final viewer = await request.extract<Viewer?>(const OptionalViewer());
  final username = await request.path<String>('username');
  final db = await request.state<ConduitDatabase>();

  final profile =
      (await UsersRepo(db.connection).profile(username, viewer?.id ?? 0))
          .orThrow;
  return profile == null
      ? Err(ApiError.notFound('profile'))
      : Ok(ProfileEnvelope(profile: profileOf(profile)));
}

/// `POST /profiles/{username}/follow`
Future<Result<ProfileEnvelope, ApiError>> follow(Request request) =>
    _setFollowing(request, following: true);

/// `DELETE /profiles/{username}/follow`
Future<Result<ProfileEnvelope, ApiError>> unfollow(Request request) =>
    _setFollowing(request, following: false);

Future<Result<ProfileEnvelope, ApiError>> _setFollowing(
  Request request, {
  required bool following,
}) async {
  final viewer = await request.extract<Viewer>(const RequireViewer());
  final username = await request.path<String>('username');
  final db = await request.state<ConduitDatabase>();
  final users = UsersRepo(db.connection);

  final target = (await users.profile(username, viewer.id)).orThrow;
  if (target == null) return Err(ApiError.notFound('profile'));
  if (target.id == viewer.id) {
    return Err(ApiError.of(422, 'profile', 'cannot follow yourself'));
  }

  (following
          ? await users.follow(viewer.id, target.id)
          : await users.unfollow(viewer.id, target.id))
      .orThrow;

  return Ok(
    ProfileEnvelope(profile: profileOf(target).copyWith(following: following)),
  );
}

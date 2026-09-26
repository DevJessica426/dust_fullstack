import 'package:conduit_shared/conduit_shared.dart';
import 'package:dust_server/server.dart';

import '../auth/viewer.dart';
import '../db/articles_repo.dart';
import '../db/comments_repo.dart';
import '../db/database.dart';
import '../http/errors.dart';
import '../http/mapping.dart';

/// `/articles/{slug}/comments`.
Router commentRoutes() => Router()
  ..route(
    '/articles/{slug}/comments',
    get(listComments).post(addComment, status: 201),
  )
  ..route('/articles/{slug}/comments/{id}', delete(deleteComment));

/// `GET /articles/{slug}/comments` — newest first.
Future<Result<CommentsList, ApiError>> listComments(Request request) async {
  final viewer = await request.extract<Viewer?>(const OptionalViewer());
  final slug = await request.path<String>('slug');
  final db = await request.state<ConduitDatabase>();

  final article = (await ArticlesRepo(db.connection).keyBySlug(slug)).orThrow;
  if (article == null) return Err(ApiError.notFound('article'));

  final rows = (await CommentsRepo(db.connection)
          .forArticle(article.id, viewer?.id ?? 0))
      .orThrow;
  return Ok(CommentsList(comments: rows.map(commentOf).toList()));
}

/// `POST /articles/{slug}/comments`
Future<Result<CommentEnvelope, ApiError>> addComment(Request request) async {
  final viewer = await request.extract<Viewer>(const RequireViewer());
  final slug = await request.path<String>('slug');
  final db = await request.state<ConduitDatabase>();

  final article = (await ArticlesRepo(db.connection).keyBySlug(slug)).orThrow;
  if (article == null) return Err(ApiError.notFound('article'));

  final input = (await request.body(NewCommentRequest.fromJson)).comment;
  if (invalid(input.validate()) case final error?) return Err(error);

  final written = (await CommentsRepo(db.connection)
          .insert(article.id, viewer.id, input.body.trim()))
      .orThrow;
  return Ok(
    CommentEnvelope(
      comment: Comment(
        id: written.id,
        createdAt: written.createdAt.toUtc(),
        updatedAt: written.updatedAt.toUtc(),
        body: written.body,
        author: ownProfileOf(viewer.user),
      ),
    ),
  );
}

/// `DELETE /articles/{slug}/comments/{id}` — the comment's author only.
///
/// A comment id from another article is "not found" rather than "forbidden":
/// the URL names a comment on *this* article, and there is none.
Future<Result<Null, ApiError>> deleteComment(Request request) async {
  final viewer = await request.extract<Viewer>(const RequireViewer());
  final slug = await request.path<String>('slug');
  final id = await request.path<int>('id');
  final db = await request.state<ConduitDatabase>();

  final article = (await ArticlesRepo(db.connection).keyBySlug(slug)).orThrow;
  if (article == null) return Err(ApiError.notFound('article'));

  final comments = CommentsRepo(db.connection);
  final comment = (await comments.keyById(id)).orThrow;
  if (comment == null || comment.articleId != article.id) {
    return Err(ApiError.notFound('comment'));
  }
  if (comment.authorId != viewer.id) return Err(ApiError.forbidden('comment'));

  (await comments.delete(comment.id)).orThrow;
  return const Ok(null);
}

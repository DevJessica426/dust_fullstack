import 'package:dust_dart/db.dart';

import 'rows.dart';

part 'comments_repo.g.dart';

/// Every query about comments.
@SqlxDao()
abstract final class CommentsRepo {
  const factory CommentsRepo(Executor db) = _$CommentsRepo;

  /// An article's comments, newest first, as [viewerId] sees their authors.
  @Query(r'''
SELECT c.id, c.body, c.created_at, c.updated_at,
       u.id AS author_id, u.username AS author_username,
       u.bio AS author_bio, u.image AS author_image,
       EXISTS (
         SELECT 1 FROM follows f WHERE f.follower_id = $2 AND f.followee_id = u.id
       ) AS author_following
FROM comments c
JOIN users u ON u.id = c.author_id
WHERE c.article_id = $1
ORDER BY c.id DESC
''')
  Future<Result<List<CommentRow>, SqlxError>> forArticle(
    int articleId,
    int viewerId,
  );

  @Query(r'''
INSERT INTO comments (article_id, author_id, body)
VALUES ($1, $2, $3)
RETURNING id, body, created_at, updated_at
''')
  Future<Result<NewCommentRow, SqlxError>> insert(
    int articleId,
    int authorId,
    String body,
  );

  @Query(r'SELECT id, article_id, author_id FROM comments WHERE id = $1')
  Future<Result<CommentKey?, SqlxError>> keyById(int id);

  @Query(r'DELETE FROM comments WHERE id = $1')
  Future<Result<Unit, SqlxError>> delete(int id);
}

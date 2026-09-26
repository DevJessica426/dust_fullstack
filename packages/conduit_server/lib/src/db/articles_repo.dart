import 'package:dust_dart/db.dart';

import 'rows.dart';

part 'articles_repo.g.dart';

/// Every query about articles, favorites and tags.
///
/// The column list repeats in each read because `dust db build` validates the
/// literal at the annotation: a shared constant would be rejected as dynamic
/// SQL. The viewer's id is always the last placeholder, 0 when signed out.
///
/// Optional filters are one static query, not SQL assembled at run time: each
/// `$n::text IS NULL OR ...` switches itself off when its argument is null,
/// and the explicit casts are what let PostgreSQL type a parameter it only
/// ever sees compared with NULL.
@SqlxDao()
abstract final class ArticlesRepo {
  const factory ArticlesRepo(Executor db) = _$ArticlesRepo;

  /// One article by slug, body included.
  @Query(r'''
SELECT a.id, a.slug, a.title, a.description, a.body, a.tag_list,
       a.created_at, a.updated_at,
       EXISTS (
         SELECT 1 FROM favorites fv WHERE fv.user_id = $2 AND fv.article_id = a.id
       ) AS favorited,
       (SELECT count(*) FROM favorites fv WHERE fv.article_id = a.id) AS favorites_count,
       u.id AS author_id, u.username AS author_username,
       u.bio AS author_bio, u.image AS author_image,
       EXISTS (
         SELECT 1 FROM follows f WHERE f.follower_id = $2 AND f.followee_id = u.id
       ) AS author_following
FROM articles a
JOIN users u ON u.id = a.author_id
WHERE a.slug = $1
''')
  Future<Result<ArticleRow?, SqlxError>> bySlug(String slug, int viewerId);

  /// A page of articles, newest first, narrowed by any of tag, author and
  /// favorited-by. The body is not read: list responses do not carry it.
  @Query(r'''
SELECT a.id, a.slug, a.title, a.description, NULL::text AS body, a.tag_list,
       a.created_at, a.updated_at,
       EXISTS (
         SELECT 1 FROM favorites fv WHERE fv.user_id = $6 AND fv.article_id = a.id
       ) AS favorited,
       (SELECT count(*) FROM favorites fv WHERE fv.article_id = a.id) AS favorites_count,
       u.id AS author_id, u.username AS author_username,
       u.bio AS author_bio, u.image AS author_image,
       EXISTS (
         SELECT 1 FROM follows f WHERE f.follower_id = $6 AND f.followee_id = u.id
       ) AS author_following
FROM articles a
JOIN users u ON u.id = a.author_id
WHERE ($1::text IS NULL OR a.tag_list @> ARRAY[$1::text])
  AND ($2::text IS NULL OR u.username = $2::text)
  AND ($3::text IS NULL OR EXISTS (
        SELECT 1 FROM favorites fv
        JOIN users fu ON fu.id = fv.user_id
        WHERE fv.article_id = a.id AND fu.username = $3::text
      ))
ORDER BY a.created_at DESC, a.id DESC
LIMIT $4 OFFSET $5
''')
  Future<Result<List<ArticleRow>, SqlxError>> list(
    String? tag,
    String? author,
    String? favoritedBy,
    int limit,
    int offset,
    int viewerId,
  );

  // TODO(dust#584): mark the counts non-null (`count(*) AS "count!"`) once the
  // drivers strip the marker; today a marked column can't be read at run time.
  /// How many articles [list] would page through with the same filters.
  @Query(r'''
SELECT count(*) AS count
FROM articles a
JOIN users u ON u.id = a.author_id
WHERE ($1::text IS NULL OR a.tag_list @> ARRAY[$1::text])
  AND ($2::text IS NULL OR u.username = $2::text)
  AND ($3::text IS NULL OR EXISTS (
        SELECT 1 FROM favorites fv
        JOIN users fu ON fu.id = fv.user_id
        WHERE fv.article_id = a.id AND fu.username = $3::text
      ))
''')
  Future<Result<int, SqlxError>> count(
    String? tag,
    String? author,
    String? favoritedBy,
  );

  /// A page of articles by the people [viewerId] follows, newest first.
  @Query(r'''
SELECT a.id, a.slug, a.title, a.description, NULL::text AS body, a.tag_list,
       a.created_at, a.updated_at,
       EXISTS (
         SELECT 1 FROM favorites fv WHERE fv.user_id = $1 AND fv.article_id = a.id
       ) AS favorited,
       (SELECT count(*) FROM favorites fv WHERE fv.article_id = a.id) AS favorites_count,
       u.id AS author_id, u.username AS author_username,
       u.bio AS author_bio, u.image AS author_image,
       TRUE AS author_following
FROM articles a
JOIN users u ON u.id = a.author_id
JOIN follows f ON f.followee_id = a.author_id AND f.follower_id = $1
ORDER BY a.created_at DESC, a.id DESC
LIMIT $2 OFFSET $3
''')
  Future<Result<List<ArticleRow>, SqlxError>> feed(
    int viewerId,
    int limit,
    int offset,
  );

  @Query(r'''
SELECT count(*) AS count
FROM articles a
JOIN follows f ON f.followee_id = a.author_id AND f.follower_id = $1
''')
  Future<Result<int, SqlxError>> feedCount(int viewerId);

  /// What a write needs to know before it is allowed.
  @Query(r'''
SELECT id, slug, author_id, title, description, body, tag_list
FROM articles
WHERE slug = $1
''')
  Future<Result<ArticleKey?, SqlxError>> keyBySlug(String slug);

  /// Creates an article. A taken slug fails on `articles_slug_key`.
  @Query(r'''
INSERT INTO articles (slug, title, description, body, tag_list, author_id)
VALUES ($1, $2, $3, $4, $5, $6)
RETURNING id
''')
  Future<Result<int, SqlxError>> insert(
    String slug,
    String title,
    String description,
    String body,
    List<String> tagList,
    int authorId,
  );

  /// Replaces the editable fields.
  ///
  /// `updated_at` moves forward by at least a microsecond even when the clock
  /// has not, so a client comparing timestamps always sees an edit.
  @Query(r'''
UPDATE articles
SET slug = $2, title = $3, description = $4, body = $5, tag_list = $6,
    updated_at = GREATEST(clock_timestamp(), updated_at + interval '1 microsecond')
WHERE id = $1
''')
  Future<Result<Unit, SqlxError>> update(
    int id,
    String slug,
    String title,
    String description,
    String body,
    List<String> tagList,
  );

  /// Removes an article; its comments and favorites cascade with it.
  @Query(r'DELETE FROM articles WHERE id = $1')
  Future<Result<Unit, SqlxError>> delete(int id);

  @Query(r'''
INSERT INTO favorites (user_id, article_id) VALUES ($1, $2)
ON CONFLICT DO NOTHING
''')
  Future<Result<Unit, SqlxError>> favorite(int userId, int articleId);

  @Query(r'DELETE FROM favorites WHERE user_id = $1 AND article_id = $2')
  Future<Result<Unit, SqlxError>> unfavorite(int userId, int articleId);

  /// Every tag in use, most used first.
  @Query(r'''
SELECT tag, count(*) AS uses
FROM articles, unnest(tag_list) AS tag
GROUP BY tag
ORDER BY count(*) DESC, tag
''')
  Future<Result<List<TagRow>, SqlxError>> tags();
}

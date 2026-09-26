import 'package:dust_dart/db.dart';

part 'rows.g.dart';

// What the queries select, one type per shape. `dust build` writes the row
// mapping; `dust db build` checks every column against these fields.
//
// Rows stay on the server. What the API answers with is the shared models in
// `conduit_shared`, built from these in `mapping.dart`, so a column that must
// never leave the database (a password hash) has no path to the wire.

// TODO(dust#589): drop this converter, and the `@Sqlx(tryFrom:)` on each list
// field, once `FromRow` maps `List<T>` itself.
/// Reads a PostgreSQL `TEXT[]` column as a Dart list.
///
/// Row fields map scalars directly; a list goes through a converter. The
/// driver decodes the array, so this only narrows its element type.
final class TextArray implements SqlxTryFrom<List<String>, List<Object?>> {
  const TextArray();

  @override
  List<String> decode(List<Object?> value) =>
      List<String>.unmodifiable(value.cast<String>());
}

/// A user as stored, hash included.
@Derive([FromRow()])
@Sqlx(renameAll: SqlxRename.snakeCase)
final class UserRow {
  const UserRow({
    required this.id,
    required this.username,
    required this.email,
    required this.passwordHash,
    this.bio,
    this.image,
  });

  final int id;
  final String username;
  final String email;
  final String passwordHash;
  final String? bio;
  final String? image;
}

/// Someone's profile, and whether the viewer follows them.
@Derive([FromRow()])
@Sqlx(renameAll: SqlxRename.snakeCase)
final class ProfileRow {
  const ProfileRow({
    required this.id,
    required this.username,
    required this.following,
    this.bio,
    this.image,
  });

  final int id;
  final String username;
  final String? bio;
  final String? image;
  final bool following;
}

/// An article joined with its author, as the viewer sees it.
///
/// [body] is null in list queries, which select `NULL` for it: the list
/// response has no body, and a 40 KB article should not be read to be dropped.
@Derive([FromRow()])
@Sqlx(renameAll: SqlxRename.snakeCase)
final class ArticleRow {
  const ArticleRow({
    required this.id,
    required this.slug,
    required this.title,
    required this.description,
    required this.tagList,
    required this.createdAt,
    required this.updatedAt,
    required this.favorited,
    required this.favoritesCount,
    required this.authorId,
    required this.authorUsername,
    required this.authorFollowing,
    this.body,
    this.authorBio,
    this.authorImage,
  });

  final int id;
  final String slug;
  final String title;
  final String description;
  final String? body;
  @Sqlx(tryFrom: TextArray())
  final List<String> tagList;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool favorited;
  final int favoritesCount;
  final int authorId;
  final String authorUsername;
  final String? authorBio;
  final String? authorImage;
  final bool authorFollowing;
}

/// Just enough of an article to authorize a write against it.
@Derive([FromRow()])
@Sqlx(renameAll: SqlxRename.snakeCase)
final class ArticleKey {
  const ArticleKey({
    required this.id,
    required this.slug,
    required this.authorId,
    required this.title,
    required this.description,
    required this.body,
    required this.tagList,
  });

  final int id;
  final String slug;
  final int authorId;
  final String title;
  final String description;
  final String body;
  @Sqlx(tryFrom: TextArray())
  final List<String> tagList;
}

/// A comment joined with its author, as the viewer sees it.
@Derive([FromRow()])
@Sqlx(renameAll: SqlxRename.snakeCase)
final class CommentRow {
  const CommentRow({
    required this.id,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    required this.authorId,
    required this.authorUsername,
    required this.authorFollowing,
    this.authorBio,
    this.authorImage,
  });

  final int id;
  final String body;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int authorId;
  final String authorUsername;
  final String? authorBio;
  final String? authorImage;
  final bool authorFollowing;
}

/// A freshly written comment, read back through `RETURNING`.
@Derive([FromRow()])
@Sqlx(renameAll: SqlxRename.snakeCase)
final class NewCommentRow {
  const NewCommentRow({
    required this.id,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String body;
  final DateTime createdAt;
  final DateTime updatedAt;
}

/// Who wrote a comment, and on which article — for authorizing a delete.
@Derive([FromRow()])
@Sqlx(renameAll: SqlxRename.snakeCase)
final class CommentKey {
  const CommentKey({
    required this.id,
    required this.articleId,
    required this.authorId,
  });

  final int id;
  final int articleId;
  final int authorId;
}

/// One tag and how many articles carry it.
@Derive([FromRow()])
@Sqlx(renameAll: SqlxRename.snakeCase)
final class TagRow {
  const TagRow({required this.tag, required this.uses});

  final String tag;
  final int uses;
}

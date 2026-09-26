import 'dart:math';

import 'package:conduit_shared/conduit_shared.dart';
import 'package:dust_dart/db.dart' show SqlxError;
import 'package:dust_server/server.dart';

import '../auth/viewer.dart';
import '../db/articles_repo.dart';
import '../db/database.dart';
import '../db/rows.dart';
import '../http/errors.dart';
import '../http/mapping.dart';

/// Articles, the feed, favorites and tags.
///
/// `/articles/feed` is declared as a literal beside `/articles/{slug}`; the
/// router ranks a literal segment above a placeholder, so `feed` is never read
/// as a slug.
Router articleRoutes() => Router()
  ..route('/articles', get(listArticles).post(createArticle, status: 201))
  ..route('/articles/feed', get(feed))
  ..route(
    '/articles/{slug}',
    get(readArticle).put(updateArticle).delete(deleteArticle),
  )
  ..route('/articles/{slug}/favorite', post(favorite).delete(unfavorite))
  ..route('/tags', get(listTags));

/// The page size when a client does not ask, and the most it may ask for.
const defaultLimit = 20;
const maxLimit = 100;

/// `GET /articles?tag=&author=&favorited=&limit=&offset=` — newest first.
Future<ArticlesPage> listArticles(Request request) async {
  final viewer = await request.extract<Viewer?>(const OptionalViewer());
  final tag = await request.query<String?>('tag');
  final author = await request.query<String?>('author');
  final favorited = await request.query<String?>('favorited');
  final (limit, offset) = await _page(request);
  final articles = ArticlesRepo((await request.state<ConduitDatabase>()).connection);

  final rows = (await articles.list(
    tag,
    author,
    favorited,
    limit,
    offset,
    viewer?.id ?? 0,
  ))
      .orThrow;
  final total = (await articles.count(tag, author, favorited)).orThrow;

  return ArticlesPage(
    articles: rows.map(previewOf).toList(),
    articlesCount: total,
  );
}

/// `GET /articles/feed` — articles by the people the viewer follows.
Future<ArticlesPage> feed(Request request) async {
  final viewer = await request.extract<Viewer>(const RequireViewer());
  final (limit, offset) = await _page(request);
  final articles = ArticlesRepo((await request.state<ConduitDatabase>()).connection);

  final rows = (await articles.feed(viewer.id, limit, offset)).orThrow;
  final total = (await articles.feedCount(viewer.id)).orThrow;

  return ArticlesPage(
    articles: rows.map(previewOf).toList(),
    articlesCount: total,
  );
}

/// `GET /articles/{slug}`
Future<Result<ArticleEnvelope, ApiError>> readArticle(Request request) async {
  final viewer = await request.extract<Viewer?>(const OptionalViewer());
  final slug = await request.path<String>('slug');
  final articles = ArticlesRepo((await request.state<ConduitDatabase>()).connection);

  return _envelope(articles, slug, viewer?.id ?? 0);
}

/// `POST /articles`
Future<Result<ArticleEnvelope, ApiError>> createArticle(Request request) async {
  final viewer = await request.extract<Viewer>(const RequireViewer());
  final input = (await request.body(NewArticleRequest.fromJson)).article;

  final tags = normalizeTags(input.tagList);
  final failures = [...input.validate().errors, ..._tagProblems(tags)];
  if (failures.isNotEmpty) return Err(ApiError.invalid(failures));

  final articles = ArticlesRepo((await request.state<ConduitDatabase>()).connection);
  final slug = await _withUniqueSlug(
    input.title,
    (slug) => articles.insert(
      slug,
      input.title.trim(),
      input.description.trim(),
      input.body,
      tags,
      viewer.id,
    ),
  );

  return _envelope(articles, slug, viewer.id);
}

/// `PUT /articles/{slug}` — the author changes any of title, description,
/// body and tags. A new title means a new slug.
Future<Result<ArticleEnvelope, ApiError>> updateArticle(Request request) async {
  final viewer = await request.extract<Viewer>(const RequireViewer());
  final slug = await request.path<String>('slug');
  final articles = ArticlesRepo((await request.state<ConduitDatabase>()).connection);

  // Found, then allowed, then valid: a stranger editing a missing article is
  // told it is missing, not that their draft has a blank title.
  final existing = (await articles.keyBySlug(slug)).orThrow;
  if (existing == null) return Err(ApiError.notFound('article'));
  if (existing.authorId != viewer.id) return Err(ApiError.forbidden('article'));

  final (patch, nulls) = await request.body(
    (json) => (
      UpdateArticleRequest.fromJson(json).article,
      _nullKeysOf(json['article']),
    ),
  );
  final tags = patch.tagList == null ? null : normalizeTags(patch.tagList!);
  final failures = [
    for (final field in const ['title', 'description', 'body', 'tagList'])
      if (nulls.contains(field))
        ValidationError(
          field: field,
          message: field == 'tagList' ? "can't be null" : "can't be blank",
        ),
    ...patch.validate().errors,
    if (tags != null) ..._tagProblems(tags),
  ];
  if (failures.isNotEmpty) return Err(ApiError.invalid(failures));

  final title = patch.title?.trim() ?? existing.title;
  Future<Result<Object?, SqlxError>> write(String slug) => articles.update(
        existing.id,
        slug,
        title,
        patch.description?.trim() ?? existing.description,
        patch.body ?? existing.body,
        tags ?? existing.tagList,
      );

  final String newSlug;
  if (title == existing.title) {
    (await write(existing.slug)).orThrow;
    newSlug = existing.slug;
  } else {
    newSlug = await _withUniqueSlug(title, write);
  }

  return _envelope(articles, newSlug, viewer.id);
}

/// `DELETE /articles/{slug}` — the author only. 204 on success.
Future<Result<Null, ApiError>> deleteArticle(Request request) async {
  final viewer = await request.extract<Viewer>(const RequireViewer());
  final slug = await request.path<String>('slug');
  final articles = ArticlesRepo((await request.state<ConduitDatabase>()).connection);

  final existing = (await articles.keyBySlug(slug)).orThrow;
  if (existing == null) return Err(ApiError.notFound('article'));
  if (existing.authorId != viewer.id) return Err(ApiError.forbidden('article'));

  (await articles.delete(existing.id)).orThrow;
  return const Ok(null);
}

/// `POST /articles/{slug}/favorite`
Future<Result<ArticleEnvelope, ApiError>> favorite(Request request) =>
    _setFavorite(request, favorite: true);

/// `DELETE /articles/{slug}/favorite`
Future<Result<ArticleEnvelope, ApiError>> unfavorite(Request request) =>
    _setFavorite(request, favorite: false);

Future<Result<ArticleEnvelope, ApiError>> _setFavorite(
  Request request, {
  required bool favorite,
}) async {
  final viewer = await request.extract<Viewer>(const RequireViewer());
  final slug = await request.path<String>('slug');
  final articles = ArticlesRepo((await request.state<ConduitDatabase>()).connection);

  final existing = (await articles.keyBySlug(slug)).orThrow;
  if (existing == null) return Err(ApiError.notFound('article'));

  (favorite
          ? await articles.favorite(viewer.id, existing.id)
          : await articles.unfavorite(viewer.id, existing.id))
      .orThrow;
  return _envelope(articles, existing.slug, viewer.id);
}

/// `GET /tags` — every tag in use, most used first.
Future<TagsList> listTags(Request request) async {
  final articles = ArticlesRepo((await request.state<ConduitDatabase>()).connection);
  final rows = (await articles.tags()).orThrow;
  return TagsList(tags: [for (final row in rows) row.tag]);
}

// --- helpers ---

Future<Result<ArticleEnvelope, ApiError>> _envelope(
  ArticlesRepo articles,
  String slug,
  int viewerId,
) async {
  final ArticleRow? row = (await articles.bySlug(slug, viewerId)).orThrow;
  return row == null
      ? Err(ApiError.notFound('article'))
      : Ok(ArticleEnvelope(article: articleOf(row)));
}

Future<(int, int)> _page(Request request) async {
  final limit = await request.query<int?>('limit') ?? defaultLimit;
  final offset = await request.query<int?>('offset') ?? 0;
  // Clamped rather than trusted: `?limit=1000000` is a denial of service
  // dressed as pagination.
  return (limit.clamp(1, maxLimit), max(0, offset));
}

/// Trimmed, blank ones dropped, duplicates removed, order kept.
List<String> normalizeTags(List<String> tags) {
  final seen = <String>{};
  return [
    for (final tag in tags.map((tag) => tag.trim()))
      if (tag.isNotEmpty && seen.add(tag)) tag,
  ];
}

Iterable<ValidationError> _tagProblems(List<String> tags) sync* {
  if (tags.any((tag) => tag.length > 40)) {
    yield const ValidationError(
      field: 'tagList',
      message: 'has a tag longer than 40 characters',
    );
  }
}

/// Which keys a JSON object carried as an explicit `null`.
Set<String> _nullKeysOf(Object? json) => {
      if (json is Map)
        for (final MapEntry(:key, :value) in json.entries)
          if (key is String && value == null) key,
    };

final _random = Random.secure();

/// `How to Train Your Dragon!` becomes `how-to-train-your-dragon`.
///
/// Letters and digits in any script are kept, so a title in Thai or Greek
/// still reads in the URL; everything else collapses to single dashes.
String slugify(String title) {
  final slug = title
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final clipped = slug.length > 80 ? slug.substring(0, 80) : slug;
  return clipped.isEmpty ? 'article' : clipped.replaceAll(RegExp(r'-+$'), '');
}

/// Runs [write] with the title's slug, and again with a random suffix each
/// time the slug is taken.
///
/// The unique index decides, not a lookup beforehand: two authors publishing
/// the same title at once would both see it free. Duplicate titles are
/// allowed; each copy gets `title-xxxxxx`.
Future<String> _withUniqueSlug(
  String title,
  Future<Result<Object?, SqlxError>> Function(String slug) write,
) async {
  final base = slugify(title);
  var slug = base;
  for (var attempt = 0; attempt < 8; attempt++) {
    switch (await write(slug)) {
      case Ok():
        return slug;
      case Err(:final error) when uniqueViolation(error) == 'articles_slug_key':
        slug = '$base-${_suffix()}';
      case Err(:final error):
        throw error;
    }
  }
  throw StateError('could not find a free slug for "$title"');
}

String _suffix() => [
      for (var i = 0; i < 6; i++)
        'abcdefghijklmnopqrstuvwxyz0123456789'[_random.nextInt(36)],
    ].join();

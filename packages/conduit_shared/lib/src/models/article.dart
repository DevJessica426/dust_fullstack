import 'package:dust_dart/serde.dart';

import 'profile.dart';

part 'article.g.dart';

// TODO(dust#590): `@Validate` takes string literals only; see user.dart.

/// One article, body included, as `/articles/{slug}` returns it.
@Derive([ToString(), Eq(), CopyWith(), Serialize(), Deserialize()])
final class Article with _$Article {
  const Article({
    required this.slug,
    required this.title,
    required this.description,
    required this.body,
    required this.tagList,
    required this.createdAt,
    required this.updatedAt,
    required this.favorited,
    required this.favoritesCount,
    required this.author,
  });

  factory Article.fromJson(Map<String, Object?> json) =>
      _$ArticleFromJson(json);

  final String slug;
  final String title;
  final String description;

  /// Markdown.
  final String body;

  /// In the order the author gave them.
  final List<String> tagList;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Whether the viewer has favorited it. Always `false` when signed out.
  final bool favorited;

  final int favoritesCount;
  final Profile author;
}

/// An article in a list: everything but the body.
///
/// RealWorld 2.0 drops `body` from list responses, and a separate type makes
/// that a compile-time fact on both sides rather than a nullable field that is
/// sometimes filled in.
@Derive([ToString(), Eq(), CopyWith(), Serialize(), Deserialize()])
final class ArticlePreview with _$ArticlePreview {
  const ArticlePreview({
    required this.slug,
    required this.title,
    required this.description,
    required this.tagList,
    required this.createdAt,
    required this.updatedAt,
    required this.favorited,
    required this.favoritesCount,
    required this.author,
  });

  factory ArticlePreview.fromJson(Map<String, Object?> json) =>
      _$ArticlePreviewFromJson(json);

  final String slug;
  final String title;
  final String description;
  final List<String> tagList;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool favorited;
  final int favoritesCount;
  final Profile author;
}

/// `{"article": {...}}`.
@Derive([ToString(), Eq(), Serialize(), Deserialize()])
final class ArticleEnvelope with _$ArticleEnvelope {
  const ArticleEnvelope({required this.article});

  factory ArticleEnvelope.fromJson(Map<String, Object?> json) =>
      _$ArticleEnvelopeFromJson(json);

  final Article article;
}

/// One page of articles, and how many match in total.
@Derive([ToString(), Eq(), Serialize(), Deserialize()])
final class ArticlesPage with _$ArticlesPage {
  const ArticlesPage({required this.articles, required this.articlesCount});

  factory ArticlesPage.fromJson(Map<String, Object?> json) =>
      _$ArticlesPageFromJson(json);

  final List<ArticlePreview> articles;

  /// Every match, not just this page — what a pager needs.
  final int articlesCount;
}

/// A draft, for `POST /articles`.
@Derive([ToString(), Serialize(), Deserialize(), Validate()])
final class NewArticle with _$NewArticle {
  const NewArticle({
    required this.title,
    required this.description,
    required this.body,
    this.tagList = const [],
  });

  factory NewArticle.fromJson(Map<String, Object?> json) =>
      _$NewArticleFromJson(json);

  @Validate(regex: r'\S', message: "can't be blank")
  @Validate(
    length: Length(max: 200),
    message: 'is too long (maximum is 200 characters)',
  )
  final String title;

  @Validate(regex: r'\S', message: "can't be blank")
  @Validate(
    length: Length(max: 500),
    message: 'is too long (maximum is 500 characters)',
  )
  final String description;

  @Validate(regex: r'\S', message: "can't be blank")
  final String body;

  @SerDe(defaultValue: <String>[])
  @Validate(
    length: Length(max: 20),
    message: 'has too many tags (maximum is 20)',
  )
  final List<String> tagList;
}

/// `{"article": {...}}` for a create.
@Derive([Serialize(), Deserialize()])
final class NewArticleRequest with _$NewArticleRequest {
  const NewArticleRequest({required this.article});

  factory NewArticleRequest.fromJson(Map<String, Object?> json) =>
      _$NewArticleRequestFromJson(json);

  final NewArticle article;
}

/// A partial update, for `PUT /articles/{slug}`.
///
/// A patch like [UpdateUser]: absent keys are left alone, so [toJson] drops
/// the unset ones. `tagList: []` removes every tag; `tagList: null` is refused.
@Derive([ToString(), Eq(), Deserialize(), Validate()])
final class UpdateArticle with _$UpdateArticle {
  const UpdateArticle({this.title, this.description, this.body, this.tagList});

  factory UpdateArticle.fromJson(Map<String, Object?> json) =>
      _$UpdateArticleFromJson(json);

  @Validate(regex: r'\S', message: "can't be blank")
  @Validate(
    length: Length(max: 200),
    message: 'is too long (maximum is 200 characters)',
  )
  final String? title;

  @Validate(regex: r'\S', message: "can't be blank")
  @Validate(
    length: Length(max: 500),
    message: 'is too long (maximum is 500 characters)',
  )
  final String? description;

  @Validate(regex: r'\S', message: "can't be blank")
  final String? body;

  @Validate(
    length: Length(max: 20),
    message: 'has too many tags (maximum is 20)',
  )
  final List<String>? tagList;

  /// Only the fields that were set.
  Map<String, Object?> toJson() => {
    if (title != null) 'title': title,
    if (description != null) 'description': description,
    if (body != null) 'body': body,
    if (tagList != null) 'tagList': tagList,
  };
}

/// `{"article": {...changed fields}}`.
@Derive([Serialize(), Deserialize()])
final class UpdateArticleRequest with _$UpdateArticleRequest {
  const UpdateArticleRequest({required this.article});

  factory UpdateArticleRequest.fromJson(Map<String, Object?> json) =>
      _$UpdateArticleRequestFromJson(json);

  final UpdateArticle article;
}

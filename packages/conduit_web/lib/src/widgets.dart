import 'package:conduit_shared/conduit_shared.dart';
import 'package:web/web.dart' as web;

import 'app.dart';
import 'dom.dart';
import 'format.dart';
import 'routes.dart';

/// The avatar, author and date block every article and preview starts with.
List<web.HTMLElement> authorBlock(Profile author, DateTime date) => [
  link(profileHref(author.username), image(avatarUrl(author.image))),
  h(
    'div',
    cls: 'info',
    children: [
      link(profileHref(author.username), author.username, cls: 'author'),
      h('span', cls: 'date', children: formatDate(date)),
    ],
  ),
];

/// `<ul class="tag-list">` of outlined pills, as articles display them.
web.HTMLElement? articleTags(List<String> tags) => tags.isEmpty
    ? null
    : h(
        'ul',
        cls: 'tag-list',
        children: [
          for (final tag in tags)
            h('li', cls: 'tag-default tag-pill tag-outline', children: tag),
        ],
      );

/// A paged list of article previews, with favorite buttons and a pager.
///
/// Used by the home feeds and both profile tabs; they differ only in what
/// they load and what they say when there is nothing.
final class ArticleList {
  ArticleList(
    this.app, {
    required this.route,
    required this.load,
    required this.empty,
    required this.isDisposed,
  });

  final App app;
  final ListRoute route;
  final Future<ArticlesPage> Function(int limit, int offset) load;
  final web.HTMLElement Function() empty;
  final bool Function() isDisposed;

  final root = h('div', cls: 'article-list');

  ArticlesPage? _page;

  /// Bumped on every load, so a late answer for an old list is dropped.
  var _loads = 0;

  Future<void> start() async {
    _loads++;
    // Not `.article-preview`: tests and readers count previews, and a
    // placeholder must not be one.
    replace(
      root,
      h('div', cls: 'article-loading', children: 'Loading articles...'),
    );
    try {
      _page = await load(pageSize, (route.page - 1) * pageSize);
    } on Object catch (error) {
      if (isDisposed()) return;
      replace(
        root,
        h(
          'div',
          cls: 'article-loading',
          children: [
            'Could not load articles. ',
            errorLines(ConduitFailure.from(error).errors).join(' '),
          ],
        ),
      );
      return;
    }
    if (isDisposed()) return;
    _render();
  }

  void _render() {
    final page = _page!;
    if (page.articles.isEmpty) {
      replace(root, empty());
      return;
    }
    replace(root, [
      for (final (index, article) in page.articles.indexed)
        _preview(index, article),
      _pager(pageCount(page.articlesCount, pageSize)),
    ]);
  }

  web.HTMLElement _preview(int index, ArticlePreview article) {
    final favorite = h(
      'button',
      cls:
          'btn btn-sm pull-xs-right '
          '${article.favorited ? 'btn-primary' : 'btn-outline-primary'}',
      attrs: {'type': 'button'},
      children: [icon('ion-heart'), ' ${article.favoritesCount}'],
      onClick: (_) => _toggleFavorite(index, article),
    );
    return h(
      'div',
      cls: 'article-preview',
      children: [
        h(
          'div',
          cls: 'article-meta',
          children: [
            ...authorBlock(article.author, article.createdAt),
            favorite,
          ],
        ),
        link(articleHref(article.slug), [
          h('h1', children: article.title),
          h('p', children: article.description),
          h('span', children: 'Read more...'),
          articleTags(article.tagList),
        ], cls: 'preview-link'),
      ],
    );
  }

  Future<void> _toggleFavorite(int index, ArticlePreview article) async {
    if (!app.session.isAuthenticated) {
      app.signInFirst();
      return;
    }
    final load = _loads;

    // Optimistic: the heart changes now, and changes back if the server says no.
    final guess = article.copyWith(
      favorited: !article.favorited,
      favoritesCount: article.favoritesCount + (article.favorited ? -1 : 1),
    );
    _replace(load, index, guess);
    try {
      final saved =
          (article.favorited
                  ? await app.api.unfavorite(article.slug)
                  : await app.api.favorite(article.slug))
              .article;
      _replace(
        load,
        index,
        guess.copyWith(
          favorited: saved.favorited,
          favoritesCount: saved.favoritesCount,
        ),
      );
    } on Object {
      _replace(load, index, article);
    }
  }

  /// Swaps one preview, unless the list has been reloaded since [load].
  void _replace(int load, int index, ArticlePreview article) {
    final page = _page;
    if (isDisposed() || page == null || load != _loads) return;
    final articles = [...page.articles]..[index] = article;
    _page = ArticlesPage(articles: articles, articlesCount: page.articlesCount);
    final old = root.querySelectorAll('.article-preview').item(index);
    if (old != null) {
      root.replaceChild(_preview(index, article), old);
    }
  }

  web.HTMLElement? _pager(int pages) {
    final window = pageWindow(route.page, pages);
    if (window.isEmpty) return null;
    return h(
      'ul',
      cls: 'pagination',
      children: [
        for (final number in window)
          if (number == null)
            h(
              'li',
              cls: 'page-item disabled',
              children: h('span', cls: 'page-link', children: '…'),
            )
          else
            h(
              'li',
              cls: number == route.page ? 'page-item active' : 'page-item',
              children: link(
                route.hrefForPage(number),
                '$number',
                cls: 'page-link',
              ),
            ),
      ],
    );
  }
}

/// The "no articles" placeholder most lists use.
web.HTMLElement noArticles() => h(
  'div',
  cls: 'empty-feed-message',
  children: 'No articles are here... yet.',
);

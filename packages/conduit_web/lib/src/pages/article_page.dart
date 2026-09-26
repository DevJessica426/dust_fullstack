import 'package:conduit_shared/conduit_shared.dart';
import 'package:web/web.dart' as web;

import '../dom.dart';
import '../format.dart';
import '../markdown.dart';
import '../routes.dart';
import '../widgets.dart';
import 'page.dart';

/// `/article/:slug`: the article, its author's controls, and its comments.
final class ArticlePage extends Page {
  ArticlePage(super.app, this.slug);

  final String slug;

  Article? _article;
  List<Comment> _comments = const [];
  var _busy = false;

  final _banner = h('div', cls: 'container');
  final _content = h('div', cls: 'container page');
  final _commentErrors = h('div');
  final _commentList = h('div');
  late final _metaTop = h('div', cls: 'article-meta');
  late final _metaBottom = h('div', cls: 'article-meta');

  @override
  late final web.HTMLElement root = h(
    'div',
    cls: 'article-page',
    children: [
      h('div', cls: 'banner', children: _banner),
      _content,
    ],
  );

  @override
  Future<void> start() async {
    replace(_banner, h('p', children: 'Loading article...'));
    await app.session.ready;
    if (disposed) return;

    try {
      final article = (await app.api.article(slug)).article;
      if (disposed) return;
      _article = article;
    } on Object catch (error) {
      if (disposed) return;
      final failure = ConduitFailure.from(error);
      replace(
        _banner,
        h(
          'h2',
          children: failure.status == 404
              ? 'Article not found'
              : 'This article could not be loaded',
        ),
      );
      replace(_content, h('p', children: errorLines(failure.errors).join(' ')));
      return;
    }
    _render();
    await _loadComments();
  }

  bool get _isAuthor => app.session.user?.username == _article?.author.username;

  void _render() {
    final article = _article!;
    replace(_banner, [h('h1', children: article.title), _metaTop]);
    replace(_content, [
      h(
        'div',
        cls: 'row article-content',
        children: h(
          'div',
          cls: 'col-md-12',
          children: [
            markdownNodes(renderMarkdown(article.body)),
            articleTags(article.tagList),
          ],
        ),
      ),
      h('hr'),
      h('div', cls: 'article-actions', children: _metaBottom),
      h(
        'div',
        cls: 'row',
        children: h(
          'div',
          cls: 'col-xs-12 col-md-8 offset-md-2',
          children: [_commentErrors, _commentForm(), _commentList],
        ),
      ),
    ]);
    _renderMeta();
  }

  /// Both copies of the meta block — under the title and under the body —
  /// are rebuilt together, so a favorite clicked in one shows in the other.
  void _renderMeta() {
    for (final meta in [_metaTop, _metaBottom]) {
      replace(meta, _metaChildren());
    }
  }

  List<Object?> _metaChildren() {
    final article = _article!;
    return [
      ...authorBlock(article.author, article.createdAt),
      if (_isAuthor) ...[
        link(EditorRoute(article.slug).href, [
          icon('ion-edit'),
          ' Edit Article',
        ], cls: 'btn btn-sm btn-outline-secondary'),
        ' ',
        h(
          'button',
          cls: 'btn btn-sm btn-outline-danger',
          attrs: {'type': 'button'},
          children: [icon('ion-trash-a'), ' Delete Article'],
          onClick: (_) => _delete(),
        ),
      ] else ...[
        h(
          'button',
          cls: article.author.following
              ? 'btn btn-sm btn-secondary'
              : 'btn btn-sm btn-outline-secondary',
          attrs: {'type': 'button'},
          children: [
            icon('ion-plus-round'),
            ' ${article.author.following ? 'Unfollow' : 'Follow'} '
                '${article.author.username}',
          ],
          onClick: (_) => _toggleFollow(),
        ),
        '  ',
        h(
          'button',
          cls: article.favorited
              ? 'btn btn-sm btn-primary'
              : 'btn btn-sm btn-outline-primary',
          attrs: {'type': 'button'},
          children: [
            icon('ion-heart'),
            ' ${article.favorited ? 'Unfavorite' : 'Favorite'} Article ',
            h('span', cls: 'counter', children: '(${article.favoritesCount})'),
          ],
          onClick: (_) => _toggleFavorite(),
        ),
      ],
    ];
  }

  Future<void> _toggleFavorite() async {
    final article = _article;
    if (article == null || _busy) return;
    if (!app.session.isAuthenticated) return app.signInFirst();

    _busy = true;
    try {
      final updated = article.favorited
          ? await app.api.unfavorite(article.slug)
          : await app.api.favorite(article.slug);
      if (disposed) return;
      _article = article.copyWith(
        favorited: updated.article.favorited,
        favoritesCount: updated.article.favoritesCount,
      );
      _renderMeta();
    } on Object {
      // Left as it was: the button still says what is true.
    } finally {
      _busy = false;
    }
  }

  Future<void> _toggleFollow() async {
    final article = _article;
    if (article == null || _busy) return;
    if (!app.session.isAuthenticated) return app.signInFirst();

    _busy = true;
    try {
      final username = article.author.username;
      final profile = article.author.following
          ? await app.api.unfollow(username)
          : await app.api.follow(username);
      if (disposed) return;
      _article = article.copyWith(
        author: article.author.copyWith(following: profile.profile.following),
      );
      _renderMeta();
    } on Object {
      // Unchanged, as above.
    } finally {
      _busy = false;
    }
  }

  Future<void> _delete() async {
    final article = _article;
    if (article == null || _busy) return;
    _busy = true;
    try {
      await app.api.deleteArticle(article.slug);
      if (disposed) return;
      app.go('/');
    } on Object catch (error) {
      if (disposed) return;
      replace(
        _commentErrors,
        errorList(errorLines(ConduitFailure.from(error).errors)),
      );
    } finally {
      _busy = false;
    }
  }

  // --- comments ---

  web.HTMLElement _commentForm() {
    final user = app.session.user;
    if (!app.session.isAuthenticated || user == null) {
      // Both come back here afterwards. (They also keep the navbar's plain
      // `/login` link the only one with that exact href.)
      final here = ArticleRoute(slug).href;
      return h(
        'p',
        children: [
          link(LoginRoute(redirect: here).href, 'Sign in'),
          ' or ',
          link(RegisterRoute(redirect: here).href, 'sign up'),
          ' to add comments on this article.',
        ],
      );
    }

    final body = textarea(
      placeholder: 'Write a comment...',
      rows: 3,
      cls: 'form-control',
    );
    final post = h(
      'button',
      cls: 'btn btn-sm btn-primary',
      attrs: {'type': 'submit'},
      children: 'Post Comment',
    );
    final form = h(
      'form',
      cls: 'card comment-form',
      children: [
        h('div', cls: 'card-block', children: body),
        h(
          'div',
          cls: 'card-footer',
          children: [
            image(avatarUrl(user.image), cls: 'comment-author-img'),
            post,
          ],
        ),
      ],
    );
    form.onSubmit.listen((event) {
      event.preventDefault();
      _postComment(body, post);
    });
    return form;
  }

  Future<void> _postComment(
    web.HTMLTextAreaElement body,
    web.HTMLElement post,
  ) async {
    final comment = NewComment(body: body.value);
    if (comment.validate() case Invalid(:final errors)) {
      replace(
        _commentErrors,
        errorList([for (final e in errors) '${e.field} ${e.message}']),
      );
      return;
    }

    post.toggleAttribute('disabled', true);
    try {
      final saved = (await app.api.addComment(
        slug,
        NewCommentRequest(comment: comment),
      )).comment;
      if (disposed) return;
      body.value = '';
      replace(_commentErrors, null);
      _comments = [saved, ..._comments];
      _renderComments();
    } on Object catch (error) {
      if (disposed) return;
      replace(
        _commentErrors,
        errorList(errorLines(ConduitFailure.from(error).errors)),
      );
    } finally {
      post.toggleAttribute('disabled', false);
    }
  }

  Future<void> _loadComments() async {
    try {
      final comments = (await app.api.comments(slug)).comments;
      if (disposed) return;
      _comments = comments;
      _renderComments();
    } on Object catch (error) {
      if (disposed) return;
      replace(
        _commentList,
        h(
          'p',
          children: [
            'Comments could not be loaded. ',
            errorLines(ConduitFailure.from(error).errors).join(' '),
          ],
        ),
      );
    }
  }

  void _renderComments() => replace(_commentList, [
    for (final comment in _comments) _commentCard(comment),
  ]);

  web.HTMLElement _commentCard(Comment comment) {
    final mine = app.session.user?.username == comment.author.username;
    final author = comment.author;
    return h(
      'div',
      cls: 'card',
      children: [
        h(
          'div',
          cls: 'card-block',
          children: h('p', cls: 'card-text', children: comment.body),
        ),
        h(
          'div',
          cls: 'card-footer',
          children: [
            link(
              profileHref(author.username),
              image(avatarUrl(author.image), cls: 'comment-author-img'),
              cls: 'comment-author',
            ),
            ' ',
            link(
              profileHref(author.username),
              author.username,
              cls: 'comment-author',
            ),
            h(
              'span',
              cls: 'date-posted',
              children: formatDate(comment.createdAt),
            ),
            if (mine)
              h(
                'span',
                cls: 'mod-options',
                children: h(
                  'i',
                  cls: 'ion-trash-a',
                  attrs: {'role': 'button', 'aria-label': 'Delete comment'},
                  onClick: (_) => _deleteComment(comment),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _deleteComment(Comment comment) async {
    try {
      await app.api.deleteComment(slug, comment.id);
      if (disposed) return;
      replace(_commentErrors, null);
      _comments = [
        for (final other in _comments)
          if (other.id != comment.id) other,
      ];
      _renderComments();
    } on Object catch (error) {
      if (disposed) return;
      replace(
        _commentErrors,
        errorList(errorLines(ConduitFailure.from(error).errors)),
      );
    }
  }
}

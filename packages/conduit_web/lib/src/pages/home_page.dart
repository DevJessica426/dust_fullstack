import 'package:web/web.dart' as web;

import '../dom.dart';
import '../routes.dart';
import '../session.dart';
import '../widgets.dart';
import 'page.dart';

/// `/`, `/?feed=following` and `/tag/:tag`: the three home tabs.
final class HomePage extends Page {
  HomePage(super.app, this.route);

  final ListRoute route;

  final _toggle = h('div', cls: 'feed-toggle');
  final _list = h('div');
  final _tags = h('div', cls: 'tag-list');

  @override
  late final web.HTMLElement root = h(
    'div',
    cls: 'home-page',
    children: [
      h(
        'div',
        cls: 'banner',
        children: h(
          'div',
          cls: 'container',
          children: [
            h('h1', cls: 'logo-font', children: 'conduit'),
            h('p', children: 'A place to share your knowledge.'),
          ],
        ),
      ),
      h(
        'div',
        cls: 'container page',
        children: h(
          'div',
          cls: 'row',
          children: [
            h('div', cls: 'col-md-9', children: [_toggle, _list]),
            h(
              'div',
              cls: 'col-md-3',
              children: h(
                'div',
                cls: 'sidebar',
                children: [
                  h('p', children: 'Popular Tags'),
                  _tags,
                ],
              ),
            ),
          ],
        ),
      ),
    ],
  );

  @override
  Future<void> start() async {
    _renderToggle();
    replace(_tags, 'Loading tags...');

    if (route is FeedRoute) {
      if (!await requireSignedIn()) return;
    } else {
      await app.session.ready;
      if (disposed) return;
    }
    _renderToggle();

    final current = route;
    final list = ArticleList(
      app,
      route: current,
      isDisposed: () => disposed,
      load: (limit, offset) => switch (current) {
        FeedRoute() => app.api.feed(limit: limit, offset: offset),
        TagRoute(:final tag) => app.api.articles(
          tag: tag,
          limit: limit,
          offset: offset,
        ),
        _ => app.api.articles(limit: limit, offset: offset),
      },
      empty: () => current is FeedRoute ? _emptyFeed() : noArticles(),
    );
    replace(_list, list.root);

    await Future.wait([list.start(), _loadTags()]);
  }

  void _renderToggle() {
    web.HTMLElement tab(String href, Object? label, {required bool active}) =>
        h(
          'li',
          cls: 'nav-item',
          children: link(
            href,
            label,
            cls: active ? 'nav-link active' : 'nav-link',
          ),
        );

    final route = this.route;
    replace(
      _toggle,
      h(
        'ul',
        cls: 'nav nav-pills outline-active',
        children: [
          if (app.session.state == AuthState.authenticated)
            tab('/?feed=following', 'Your Feed', active: route is FeedRoute),
          tab('/', 'Global Feed', active: route is GlobalRoute),
          if (route is TagRoute)
            tab(route.hrefForPage(1), [
              icon('ion-pound'),
              ' ${route.tag}',
            ], active: true),
        ],
      ),
    );
  }

  Future<void> _loadTags() async {
    try {
      final tags = (await app.api.tags()).tags;
      if (disposed) return;
      replace(
        _tags,
        tags.isEmpty
            ? 'No tags are here... yet.'
            : [
                for (final tag in tags)
                  link(tagHref(tag), tag, cls: 'tag-pill tag-default'),
              ],
      );
    } on Object {
      if (disposed) return;
      replace(_tags, 'Tags could not be loaded.');
    }
  }

  web.HTMLElement _emptyFeed() => h(
    'div',
    cls: 'empty-feed-message',
    children: [
      'Your feed is empty. Follow some authors, or ',
      link('/', 'browse all articles'),
      '.',
    ],
  );
}

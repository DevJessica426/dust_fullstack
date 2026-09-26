import 'package:conduit_shared/conduit_shared.dart';
import 'package:web/web.dart' as web;

import '../dom.dart';
import '../format.dart';
import '../routes.dart';
import '../widgets.dart';
import 'page.dart';

/// `/profile/:username` and `/profile/:username/favorites`.
final class ProfilePage extends Page {
  ProfilePage(super.app, this.route);

  final ProfileRoute route;

  Profile? _profile;
  var _busy = false;

  // `.user-info` exists only once there is a profile to show: an error page
  // that still had one would look like an empty profile rather than an error.
  final _header = h('div');
  final _list = h('div');

  @override
  late final web.HTMLElement root = h(
    'div',
    cls: 'profile-page',
    children: [
      _header,
      h(
        'div',
        cls: 'container',
        children: h(
          'div',
          cls: 'row',
          children: h(
            'div',
            cls: 'col-xs-12 col-md-10 offset-md-1',
            children: [_tabs(), _list],
          ),
        ),
      ),
    ],
  );

  web.HTMLElement _tabs() {
    web.HTMLElement tab(String href, String label, {required bool active}) => h(
      'li',
      cls: 'nav-item',
      children: link(href, label, cls: active ? 'nav-link active' : 'nav-link'),
    );
    return h(
      'div',
      cls: 'articles-toggle',
      children: h(
        'ul',
        cls: 'nav nav-pills outline-active',
        children: [
          tab(
            profileHref(route.username),
            'My Articles',
            active: !route.favorites,
          ),
          tab(
            profileHref(route.username, favorites: true),
            'Favorited Articles',
            active: route.favorites,
          ),
        ],
      ),
    );
  }

  @override
  Future<void> start() async {
    replace(
      _header,
      h(
        'div',
        cls: 'container',
        children: h('p', children: 'Loading profile...'),
      ),
    );
    await app.session.ready;
    if (disposed) return;

    final list = ArticleList(
      app,
      route: route,
      isDisposed: () => disposed,
      load: (limit, offset) => route.favorites
          ? app.api.articles(
              favorited: route.username,
              limit: limit,
              offset: offset,
            )
          : app.api.articles(
              author: route.username,
              limit: limit,
              offset: offset,
            ),
      empty: noArticles,
    );
    replace(_list, list.root);

    await Future.wait([_loadProfile(), list.start()]);
  }

  Future<void> _loadProfile() async {
    try {
      final profile = (await app.api.profile(route.username)).profile;
      if (disposed) return;
      _profile = profile;
      _renderHeader();
    } on Object catch (error) {
      if (disposed) return;
      final failure = ConduitFailure.from(error);
      replace(
        _header,
        h(
          'div',
          cls: 'container',
          children: h(
            'p',
            children: failure.status == 404
                ? 'There is no user called ${route.username}.'
                : 'This profile could not be loaded. '
                      '${errorLines(failure.errors).join(' ')}',
          ),
        ),
      );
    }
  }

  void _renderHeader() {
    final profile = _profile!;
    final own = app.session.user?.username == profile.username;
    replace(
      _header,
      h(
        'div',
        cls: 'user-info',
        children: h(
          'div',
          cls: 'container',
          children: h(
            'div',
            cls: 'row',
            children: h(
              'div',
              cls: 'col-xs-12 col-md-10 offset-md-1',
              children: [
                image(avatarUrl(profile.image), cls: 'user-img'),
                h('h4', children: profile.username),
                h('p', children: profile.bio ?? ''),
                if (own)
                  link('/settings', [
                    icon('ion-gear-a'),
                    ' Edit Profile Settings',
                  ], cls: 'btn btn-sm btn-outline-secondary action-btn')
                else
                  h(
                    'button',
                    cls: profile.following
                        ? 'btn btn-sm btn-secondary action-btn'
                        : 'btn btn-sm btn-outline-secondary action-btn',
                    attrs: {'type': 'button'},
                    children: [
                      icon('ion-plus-round'),
                      ' ${profile.following ? 'Unfollow' : 'Follow'} '
                          '${profile.username}',
                    ],
                    onClick: (_) => _toggleFollow(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggleFollow() async {
    final profile = _profile;
    if (profile == null || _busy) return;
    if (!app.session.isAuthenticated) return app.signInFirst();

    _busy = true;
    try {
      final updated = profile.following
          ? await app.api.unfollow(profile.username)
          : await app.api.follow(profile.username);
      if (disposed) return;
      _profile = profile.copyWith(following: updated.profile.following);
      _renderHeader();
    } on Object {
      // A refused follow leaves the button as it was, which is still true.
    } finally {
      _busy = false;
    }
  }
}

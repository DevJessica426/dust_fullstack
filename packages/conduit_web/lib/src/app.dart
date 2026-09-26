import 'dart:js_interop';

import 'package:conduit_shared/conduit_shared.dart';
import 'package:web/web.dart' as web;

import 'dom.dart';
import 'format.dart';
import 'navigation.dart';
import 'pages/article_page.dart';
import 'pages/auth_page.dart';
import 'pages/editor_page.dart';
import 'pages/home_page.dart';
import 'pages/not_found_page.dart';
import 'pages/page.dart';
import 'pages/profile_page.dart';
import 'pages/settings_page.dart';
import 'routes.dart';
import 'session.dart';

/// What every page is handed: the API, who is reading, and where to go next.
final class App {
  App({required this.client, required this.session, required this.navigation});

  final ConduitClient client;
  final Session session;
  final Navigation navigation;

  ConduitApi get api => client.api;

  void go(String href, {bool replace = false}) =>
      navigation.go(href, replace: replace);

  /// Sends a signed-out reader to sign in, and back here afterwards.
  void signInFirst() => go(LoginRoute(redirect: navigation.current.href).href);
}

/// The frame around every page: navbar, the current page, footer.
final class Shell {
  Shell(this.app, this.root);

  final App app;
  final web.Element root;

  final _nav = h('nav', cls: 'navbar navbar-light');
  final _outlet = h('div', cls: 'outlet');
  Page? _page;

  void start() {
    replace(root, [_nav, _outlet, _footer()]);
    app.session.changes.listen((_) => _renderNav());
    app.navigation.changes.listen(_show);
    _show(app.navigation.current);
  }

  void _show(AppRoute route) {
    _page?.dispose();
    final page = _pageFor(route);
    _page = page;
    replace(_outlet, page.root);
    _renderNav();
    web.window.scrollTo(0.toJS, 0);
    page.start();
  }

  Page _pageFor(AppRoute route) => switch (route) {
    GlobalRoute() ||
    FeedRoute() ||
    TagRoute() => HomePage(app, route as ListRoute),
    LoginRoute(:final redirect) => AuthPage(
      app,
      signUp: false,
      redirect: redirect,
    ),
    RegisterRoute(:final redirect) => AuthPage(
      app,
      signUp: true,
      redirect: redirect,
    ),
    SettingsRoute() => SettingsPage(app),
    EditorRoute(:final slug) => EditorPage(app, slug),
    ArticleRoute(:final slug) => ArticlePage(app, slug),
    ProfileRoute() => ProfilePage(app, route),
    NotFoundRoute() => NotFoundPage(app),
  };

  void _renderNav() {
    final route = app.navigation.current;
    final session = app.session;

    web.HTMLElement item(
      String href,
      Object? children, {
      required bool active,
    }) => h(
      'li',
      cls: 'nav-item',
      children: link(
        href,
        children,
        cls: active ? 'nav-link active' : 'nav-link',
      ),
    );

    final home = item(
      '/',
      'Home',
      active: route is ListRoute && route is! ProfileRoute,
    );

    final items = switch (session.state) {
      AuthState.authenticated => [
        home,
        item('/editor', [
          icon('ion-compose'),
          ' New Article',
        ], active: route is EditorRoute && route.slug == null),
        item('/settings', [
          icon('ion-gear-a'),
          ' Settings',
        ], active: route is SettingsRoute),
        item(
          profileHref(session.user!.username),
          [
            image(avatarUrl(session.user!.image), cls: 'user-pic'),
            session.user!.username,
          ],
          active:
              route is ProfileRoute && route.username == session.user!.username,
        ),
      ],
      AuthState.unavailable => [
        home,
        h(
          'li',
          cls: 'nav-item',
          children: h(
            'button',
            cls: 'nav-link btn btn-link',
            attrs: {'type': 'button', 'title': 'Retry'},
            children: 'Connecting…',
            onClick: (_) => session.start(),
          ),
        ),
      ],
      AuthState.loading => [home],
      AuthState.unauthenticated => [
        home,
        item('/login', 'Sign in', active: route is LoginRoute),
        item('/register', 'Sign up', active: route is RegisterRoute),
      ],
    };

    replace(
      _nav,
      h(
        'div',
        cls: 'container',
        children: [
          link('/', 'conduit', cls: 'navbar-brand'),
          h('ul', cls: 'nav navbar-nav pull-xs-right', children: items),
        ],
      ),
    );
  }

  web.HTMLElement _footer() => h(
    'footer',
    children: h(
      'div',
      cls: 'container',
      children: [
        link('/', 'conduit', cls: 'logo-font'),
        h(
          'span',
          cls: 'attribution',
          children:
              ' A RealWorld clone in Dart: dust_server, PostgreSQL, '
              'and a Dart web app. Code & design licensed under MIT.',
        ),
      ],
    ),
  );
}

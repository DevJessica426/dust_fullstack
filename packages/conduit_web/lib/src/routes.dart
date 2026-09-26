/// Every page the app has, parsed from and written back to a URL.
///
/// Routes follow the RealWorld front-end contract exactly (`/tag/:tag`,
/// `/?feed=following`, `/?page=N`, ...), because the shared E2E suite
/// navigates by URL and asserts on the URLs the app writes.
library;

/// How many articles a list shows per page.
const pageSize = 10;

sealed class AppRoute {
  const AppRoute();

  /// Reads a route out of a URL's path and query.
  factory AppRoute.parse(Uri uri) {
    final segments = [
      for (final segment in uri.pathSegments)
        if (segment.isNotEmpty) segment,
    ];
    final page = _page(uri.queryParameters['page']);

    return switch (segments) {
      [] =>
        uri.queryParameters['feed'] == 'following'
            ? FeedRoute(page: page)
            : GlobalRoute(page: page),
      ['tag', final tag] => TagRoute(tag, page: page),
      ['login'] => LoginRoute(redirect: _redirect(uri)),
      ['register'] => RegisterRoute(redirect: _redirect(uri)),
      ['settings'] => const SettingsRoute(),
      ['editor'] => const EditorRoute(),
      ['editor', final slug] => EditorRoute(slug),
      ['article', final slug] => ArticleRoute(slug),
      ['profile', final username] => ProfileRoute(username, page: page),
      ['profile', final username, 'favorites'] => ProfileRoute(
        username,
        favorites: true,
        page: page,
      ),
      _ => NotFoundRoute(uri.path),
    };
  }

  /// The URL this route lives at.
  String get href;

  /// Whether the page makes no sense signed out.
  bool get requiresAuth => false;

  /// Where to go after signing in: a path on this site, or nowhere.
  static String? _redirect(Uri uri) {
    final target = uri.queryParameters['redirect'];
    return target != null && target.startsWith('/') && !target.startsWith('//')
        ? target
        : null;
  }

  static int _page(String? raw) {
    final page = int.tryParse(raw ?? '') ?? 1;
    return page < 1 ? 1 : page;
  }
}

/// A route whose list is paged.
sealed class ListRoute extends AppRoute {
  const ListRoute({this.page = 1});

  final int page;

  /// The same list at another page. Page 1 has no `page` parameter, so the
  /// first page of a feed has one canonical URL.
  String hrefForPage(int page);
}

final class GlobalRoute extends ListRoute {
  const GlobalRoute({super.page});

  @override
  String get href => hrefForPage(page);

  @override
  String hrefForPage(int page) => page == 1 ? '/' : '/?page=$page';
}

final class FeedRoute extends ListRoute {
  const FeedRoute({super.page});

  @override
  String get href => hrefForPage(page);

  @override
  bool get requiresAuth => true;

  @override
  String hrefForPage(int page) =>
      page == 1 ? '/?feed=following' : '/?feed=following&page=$page';
}

final class TagRoute extends ListRoute {
  const TagRoute(this.tag, {super.page});

  final String tag;

  @override
  String get href => hrefForPage(page);

  @override
  String hrefForPage(int page) {
    final base = '/tag/${Uri.encodeComponent(tag)}';
    return page == 1 ? base : '$base?page=$page';
  }
}

/// `/login` and `/register` share an optional `?redirect=/path`: where to
/// send the reader once they are signed in.
sealed class AuthRoute extends AppRoute {
  const AuthRoute({this.redirect});

  final String? redirect;

  String get _path;

  @override
  String get href => redirect == null
      ? _path
      : '$_path?redirect=${Uri.encodeQueryComponent(redirect!)}';
}

final class LoginRoute extends AuthRoute {
  const LoginRoute({super.redirect});

  @override
  String get _path => '/login';
}

final class RegisterRoute extends AuthRoute {
  const RegisterRoute({super.redirect});

  @override
  String get _path => '/register';
}

final class SettingsRoute extends AppRoute {
  const SettingsRoute();

  @override
  String get href => '/settings';

  @override
  bool get requiresAuth => true;
}

final class EditorRoute extends AppRoute {
  const EditorRoute([this.slug]);

  /// The article being edited, or null for a new one.
  final String? slug;

  @override
  String get href =>
      slug == null ? '/editor' : '/editor/${Uri.encodeComponent(slug!)}';

  @override
  bool get requiresAuth => true;
}

final class ArticleRoute extends AppRoute {
  const ArticleRoute(this.slug);

  final String slug;

  @override
  String get href => '/article/${Uri.encodeComponent(slug)}';
}

final class ProfileRoute extends ListRoute {
  const ProfileRoute(this.username, {this.favorites = false, super.page});

  final String username;

  /// The "Favorited Articles" tab rather than "My Articles".
  final bool favorites;

  @override
  String get href => hrefForPage(page);

  @override
  String hrefForPage(int page) {
    final base =
        '/profile/${Uri.encodeComponent(username)}'
        '${favorites ? '/favorites' : ''}';
    return page == 1 ? base : '$base?page=$page';
  }
}

final class NotFoundRoute extends AppRoute {
  const NotFoundRoute(this.path);

  final String path;

  @override
  String get href => path;
}

/// The href of each profile tab.
String profileHref(String username, {bool favorites = false}) =>
    ProfileRoute(username, favorites: favorites).href;

String articleHref(String slug) => ArticleRoute(slug).href;

String tagHref(String tag) => TagRoute(tag).href;

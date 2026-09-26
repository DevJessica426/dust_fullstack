import 'package:conduit_shared/conduit_shared.dart';
import 'package:conduit_web/src/format.dart';
import 'package:conduit_web/src/markdown.dart';
import 'package:conduit_web/src/routes.dart';
import 'package:test/test.dart';

/// The parts of the browser app that are plain Dart, run on the VM.
void main() {
  group('routes', () {
    AppRoute parse(String url) => AppRoute.parse(Uri.parse(url));

    test('read every URL the RealWorld contract names', () {
      expect(parse('/'), isA<GlobalRoute>());
      expect(
        parse('/?page=3'),
        isA<GlobalRoute>().having((r) => r.page, 'page', 3),
      );
      expect(parse('/?feed=following'), isA<FeedRoute>());
      expect(
        parse('/tag/dragons?page=2'),
        isA<TagRoute>().having((r) => r.tag, 'tag', 'dragons'),
      );
      expect(parse('/login'), isA<LoginRoute>());
      expect(parse('/register'), isA<RegisterRoute>());
      expect(parse('/settings'), isA<SettingsRoute>());
      expect(
        parse('/editor'),
        isA<EditorRoute>().having((r) => r.slug, 'slug', isNull),
      );
      expect(
        parse('/editor/how-to'),
        isA<EditorRoute>().having((r) => r.slug, 'slug', 'how-to'),
      );
      expect(parse('/article/how-to'), isA<ArticleRoute>());
      expect(
        parse('/profile/jake'),
        isA<ProfileRoute>().having((r) => r.favorites, 'favorites', false),
      );
      expect(
        parse('/profile/jake/favorites'),
        isA<ProfileRoute>().having((r) => r.favorites, 'favorites', true),
      );
      expect(parse('/nope/nope'), isA<NotFoundRoute>());
    });

    test('write the URLs the contract asserts on', () {
      expect(const GlobalRoute().hrefForPage(1), '/');
      expect(const GlobalRoute().hrefForPage(2), '/?page=2');
      expect(const FeedRoute().hrefForPage(1), '/?feed=following');
      expect(const FeedRoute().hrefForPage(2), '/?feed=following&page=2');
      expect(const TagRoute('a b').hrefForPage(2), '/tag/a%20b?page=2');
      expect(
        const ProfileRoute('jake', favorites: true).href,
        '/profile/jake/favorites',
      );
    });

    test('round-trip through a URL', () {
      for (final href in [
        '/',
        '/?page=4',
        '/?feed=following&page=2',
        '/tag/r%C3%A9sum%C3%A9?page=2',
        '/profile/jake/favorites?page=3',
        '/editor/some-slug',
      ]) {
        expect(AppRoute.parse(Uri.parse(href)).href, href);
      }
    });

    test('sign-in pages carry a same-site redirect, and only that', () {
      expect(
        (AppRoute.parse(Uri.parse('/login?redirect=%2Farticle%2Fx'))
                as LoginRoute)
            .redirect,
        '/article/x',
      );
      expect(
        const LoginRoute(redirect: '/article/x').href,
        '/login?redirect=%2Farticle%2Fx',
      );
      for (final hostile in ['https://evil.example', '//evil.example', 'x']) {
        final route =
            AppRoute.parse(
                  Uri.parse(
                    '/register?redirect=${Uri.encodeQueryComponent(hostile)}',
                  ),
                )
                as RegisterRoute;
        expect(route.redirect, isNull, reason: hostile);
      }
    });

    test('a nonsense page number is page 1', () {
      expect((AppRoute.parse(Uri.parse('/?page=-4')) as GlobalRoute).page, 1);
      expect((AppRoute.parse(Uri.parse('/?page=x')) as GlobalRoute).page, 1);
    });
  });

  group('avatarUrl', () {
    test('keeps http, https, and same-origin paths', () {
      expect(
        avatarUrl('https://example.com/a.png'),
        'https://example.com/a.png',
      );
      expect(avatarUrl('/avatars/a.svg'), '/avatars/a.svg');
    });

    test('replaces everything else with the default', () {
      for (final hostile in [
        null,
        '',
        '   ',
        'javascript:alert(1)',
        'JavaScript:alert(1)',
        'java\tscript:alert(1)',
        'data:text/html,<script>alert(1)</script>',
        '//evil.example/a.png',
        'https://example.com/img.jpg"onerror="alert(1)',
      ]) {
        expect(avatarUrl(hostile), defaultAvatar, reason: '$hostile');
      }
    });
  });

  group('markdown', () {
    Iterable<SafeNode> walk(List<SafeNode> nodes) sync* {
      for (final node in nodes) {
        yield node;
        if (node is SafeElement) yield* walk(node.children);
      }
    }

    Iterable<SafeElement> elements(String source) =>
        walk(renderMarkdown(source)).whereType<SafeElement>();

    String text(String source) => walk(
      renderMarkdown(source),
    ).whereType<SafeText>().map((t) => t.text).join();

    test('renders ordinary Markdown', () {
      final tags = elements(
        '# Hi\n\nSome **bold** and a [link](https://x.test).',
      ).map((e) => e.tag);

      expect(tags, containsAll(['h1', 'p', 'strong', 'a']));
    });

    test('raw HTML stays text, never an element', () {
      for (final payload in [
        '<script>alert(1)</script>',
        '<img src=x onerror="alert(1)">',
        '<svg onload="alert(1)">',
        '<iframe srcdoc="<script>alert(1)</script>">',
        '<div onmouseover="alert(1)">hover me</div>',
      ]) {
        final source = 'Before payload: $payload After payload';

        expect(
          elements(source).map((e) => e.tag),
          everyElement('p'),
          reason: payload,
        );
        expect(text(source), contains('Before payload:'), reason: payload);
      }
    });

    test('javascript: links lose their href', () {
      final link = elements(
        '[click](javascript:alert(1))',
      ).where((e) => e.tag == 'a').single;

      expect(link.attributes.containsKey('href'), isFalse);
    });

    test('safe links keep theirs, with rel added', () {
      final link = elements(
        '[ok](https://dart.dev)',
      ).where((e) => e.tag == 'a').single;

      expect(link.attributes['href'], 'https://dart.dev');
      expect(link.attributes['rel'], contains('noopener'));
    });

    test('ampersands are text, not entities', () {
      expect(text('Salt & pepper'), 'Salt & pepper');
    });

    test('fenced code keeps its language hint and its contents', () {
      final code = elements(
        '```dart\nvoid main() {}\n```',
      ).where((e) => e.tag == 'code').single;

      expect(code.attributes['class'], 'language-dart');
      expect(text('```dart\nif (a < b) {}\n```'), contains('a < b'));
    });
  });

  test('errorLines names the field unless there is none', () {
    expect(
      errorLines(
        const ApiErrors(
          errors: {
            'email': ['has already been taken'],
            'network': ['Unable to connect to the server'],
          },
        ),
      ),
      ['email has already been taken', 'Unable to connect to the server'],
    );
  });

  group('pageWindow', () {
    test('small counts show every page', () {
      expect(pageWindow(1, 1), isEmpty);
      expect(pageWindow(2, 3), [1, 2, 3]);
    });

    test('large counts elide around the current page', () {
      expect(pageWindow(10, 40), [1, null, 8, 9, 10, 11, 12, null, 40]);
      expect(pageWindow(1, 40), [1, 2, 3, null, 40]);
    });
  });
}

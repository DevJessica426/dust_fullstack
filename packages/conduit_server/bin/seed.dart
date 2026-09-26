import 'dart:io';

import 'package:conduit_shared/conduit_shared.dart';

/// Fills a running server with demo users, articles, follows and comments —
/// through the API, with the same generated client the browser uses.
///
///     dart run conduit_server:seed                         # localhost:8080
///     dart run conduit_server:seed http://localhost:8080/api
///
/// Safe to run twice: an existing user is signed in instead of created, and
/// an author who already has articles is left alone. `johndoe` is the user the
/// RealWorld E2E suite expects a demo backend to have.
Future<void> main(List<String> arguments) async {
  final api = arguments.isEmpty ? 'http://localhost:8080/api' : arguments.first;
  stdout.writeln('Seeding $api');

  final john = await _user(
    api,
    'johndoe',
    bio: 'I write about Dart on the server.',
  );
  final jane = await _user(
    api,
    'janedoe',
    bio: 'Front ends, typography, and tea.',
  );
  final sam = await _user(api, 'samsmith', bio: null);

  final johnsArticles = await _articles(john, [
    (
      title: 'Full-stack Dart with Dust',
      description:
          'One language, one set of models, from PostgreSQL to the browser.',
      body: _dustBody,
      tags: ['dart', 'dust', 'fullstack'],
    ),
    (
      title: 'Why we validate SQL at build time',
      description:
          'dust db build describes every query against the real schema.',
      body: _sqlBody,
      tags: ['postgres', 'dust', 'sql'],
    ),
  ]);
  final janesArticles = await _articles(jane, [
    (
      title: 'Rendering Markdown without innerHTML',
      description:
          'Parse to an AST, rebuild what is allowed, never trust a string.',
      body: _markdownBody,
      tags: ['security', 'web', 'dart'],
    ),
    (
      title: 'A pager that fits on a phone',
      description: 'First, last, and two either side of where you are.',
      body: 'Most feeds need five or six page links, not four hundred.',
      tags: ['web', 'ux'],
    ),
  ]);

  // Some social activity, so feeds and counts have something to show.
  for (final (who, whom) in [
    (jane, 'johndoe'),
    (sam, 'johndoe'),
    (john, 'janedoe'),
  ]) {
    await who.api.follow(whom);
  }
  for (final slug in johnsArticles) {
    await jane.api.favorite(slug);
    await sam.api.favorite(slug);
  }
  for (final slug in janesArticles) {
    await john.api.favorite(slug);
  }
  if (johnsArticles.isNotEmpty) {
    final comments = (await john.api.comments(johnsArticles.first)).comments;
    if (comments.isEmpty) {
      await jane.api.addComment(
        johnsArticles.first,
        const NewCommentRequest(
          comment: NewComment(
            body: 'Sharing the models is the whole trick. Nice write-up!',
          ),
        ),
      );
      await john.api.addComment(
        johnsArticles.first,
        const NewCommentRequest(
          comment: NewComment(
            body: 'Thanks! The generated client does most of the work.',
          ),
        ),
      );
    }
  }

  for (final client in [john, jane, sam]) {
    client.close();
  }
  stdout.writeln('Done: johndoe, janedoe, samsmith (password: password123)');
}

const _password = 'password123';

/// Signs [username] up, or in when they already exist.
Future<ConduitClient> _user(String api, String username, {String? bio}) async {
  final client = ConduitClient(baseUrl: api);
  final email = '$username@example.com';
  User user;
  try {
    user = (await client.api.register(
      RegisterRequest(
        user: NewUser(username: username, email: email, password: _password),
      ),
    )).user;
    stdout.writeln('  created $username');
  } on Object catch (error) {
    if (ConduitFailure.from(error).status != 409) rethrow;
    user = (await client.api.login(
      LoginRequest(
        user: LoginUser(email: email, password: _password),
      ),
    )).user;
    stdout.writeln('  found $username');
  }
  client.token = user.token;
  if (bio != null && user.bio == null) {
    await client.api.updateUser(UpdateUserRequest(user: UpdateUser(bio: bio)));
  }
  return client;
}

typedef _Draft = ({
  String title,
  String description,
  String body,
  List<String> tags,
});

/// Publishes [drafts] unless the author already has articles; returns slugs.
Future<List<String>> _articles(
  ConduitClient author,
  List<_Draft> drafts,
) async {
  final me = (await author.api.currentUser()).user.username;
  final existing = await author.api.articles(author: me);
  if (existing.articlesCount > 0) {
    return [for (final article in existing.articles) article.slug];
  }
  return [
    for (final draft in drafts)
      (await author.api.createArticle(
        NewArticleRequest(
          article: NewArticle(
            title: draft.title,
            description: draft.description,
            body: draft.body,
            tagList: draft.tags,
          ),
        ),
      )).article.slug,
  ];
}

const _dustBody = '''
This site is a [RealWorld](https://github.com/gothinkster/realworld) clone
written in Dart from the database to the browser:

- **conduit_shared** holds the models. `@Derive([Serialize(), Deserialize(), Validate()])`
  and `dust build` write their JSON and validation.
- **conduit_server** answers with those models on `dust_server`, over PostgreSQL.
- **conduit_web** decodes them in the browser through a Dust-generated `ConduitApi`.

Rename a field and both sides stop compiling, which is the point.

```dart
final article = (await api.article(slug)).article;
```
''';

const _sqlBody = '''
Every `@Query` in the server is plain SQL that `dust db build` hands to
PostgreSQL to *describe* before any code is generated. A typo in a column name
is a build error, not a 500 in production.

The query metadata is committed under `.dust_sql/`, so CI checks the SQL with
`dust check --db --offline` and no database at all.
''';

const _markdownBody = '''
Article bodies are Markdown, and Markdown allows raw HTML — so a naive renderer
is an XSS hole. This app parses Markdown to an AST and rebuilds only allowed
elements, so `<script>alert(1)</script>` shows up as exactly that: text.

> Never assign a string you did not build to `innerHTML`.
''';

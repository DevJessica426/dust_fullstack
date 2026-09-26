@Tags(['postgres'])
library;

import 'package:conduit_server/conduit_server.dart' show slugify;
import 'package:conduit_shared/conduit_shared.dart';
import 'package:test/test.dart';

import 'support.dart';

/// The API end to end: a real server on a real socket over a real PostgreSQL,
/// driven by the same generated `ConduitApi` the browser uses.
///
/// Nothing here builds JSON by hand. If a model drifts between the server and
/// the client, these stop compiling before they stop passing.
void main() {
  if (testDatabaseUrl == null) {
    test('API over PostgreSQL', () {}, skip: skipWithoutDatabase);
    return;
  }

  late TestServer app;

  setUpAll(() async => app = await TestServer.start());
  tearDownAll(() => app.stop());
  tearDown(() => expect(app.errors, isEmpty, reason: 'no request may 500'));

  group('users', () {
    test('register, sign in, and read yourself back', () async {
      final username = unique('ada');
      final client = app.client();

      final registered = (await client.api.register(
        RegisterRequest(
          user: NewUser(
            username: username,
            email: '$username@example.com',
            password: 'correct horse',
          ),
        ),
      )).user;
      expect(registered.username, username);
      expect(registered.bio, isNull);

      final signedIn = (await client.api.login(
        LoginRequest(
          user: LoginUser(
            // Emails match case-insensitively.
            email: '${username.toUpperCase()}@EXAMPLE.COM',
            password: 'correct horse',
          ),
        ),
      )).user;
      expect(signedIn.username, username);

      client.token = signedIn.token;
      expect(
        (await client.api.currentUser()).user.email,
        '$username@example.com',
      );
    });

    test('a wrong password and an unknown email look the same', () async {
      final (_, user) = await signUp(app);
      final client = app.client();

      final wrongPassword = await refusal(
        () => client.api.login(
          LoginRequest(
            user: LoginUser(email: user.email, password: 'not it at all'),
          ),
        ),
      );
      final unknownEmail = await refusal(
        () => client.api.login(
          const LoginRequest(
            user: LoginUser(email: 'nobody@example.com', password: 'x'),
          ),
        ),
      );

      expect(wrongPassword, refusedWith(401, 'credentials', 'invalid'));
      expect(unknownEmail.errors, wrongPassword.errors);
    });

    test('usernames are unique regardless of case', () async {
      final (_, user) = await signUp(app);

      final failure = await refusal(
        () => app.client().api.register(
          RegisterRequest(
            user: NewUser(
              username: user.username.toUpperCase(),
              email: 'other_${user.email}',
              password: 'password123',
            ),
          ),
        ),
      );

      expect(failure, refusedWith(409, 'username', 'has already been taken'));
    });

    test('every broken registration rule is reported at once', () async {
      final failure = await refusal(
        () => app.client().api.register(
          const RegisterRequest(
            user: NewUser(username: ' ', email: 'nope', password: 'short'),
          ),
        ),
      );

      expect(failure.status, 422);
      expect(
        failure.errors.errors.keys,
        containsAll(['username', 'email', 'password']),
      );
    });

    test('an update is a patch; empty bio clears it', () async {
      final (client, user) = await signUp(app);

      var updated = (await client.api.updateUser(
        const UpdateUserRequest(
          user: UpdateUser(
            bio: 'I like dragons',
            image: 'https://x.test/a.png',
          ),
        ),
      )).user;
      expect(updated.bio, 'I like dragons');
      expect(updated.username, user.username, reason: 'untouched');

      updated = (await client.api.updateUser(
        const UpdateUserRequest(user: UpdateUser(bio: '')),
      )).user;
      expect(updated.bio, isNull);
      expect(updated.image, 'https://x.test/a.png', reason: 'untouched');
    });

    test('a new password works and the old one stops working', () async {
      final (client, user) = await signUp(app);
      await client.api.updateUser(
        const UpdateUserRequest(user: UpdateUser(password: 'brand new pass')),
      );

      final anonymous = app.client();
      await anonymous.api.login(
        LoginRequest(
          user: LoginUser(email: user.email, password: 'brand new pass'),
        ),
      );
      expect(
        await refusal(
          () => anonymous.api.login(
            LoginRequest(
              user: LoginUser(email: user.email, password: 'password123'),
            ),
          ),
        ),
        refusedWith(401, 'credentials'),
      );
    });

    test('taking someone else\'s email on update is a 409', () async {
      final (_, first) = await signUp(app);
      final (second, _) = await signUp(app);

      expect(
        await refusal(
          () => second.api.updateUser(
            UpdateUserRequest(user: UpdateUser(email: first.email)),
          ),
        ),
        refusedWith(409, 'email', 'has already been taken'),
      );
    });

    test('a missing, malformed, or forged token is a 401', () async {
      expect(
        await refusal(() => app.client().api.currentUser()),
        refusedWith(401, 'token', 'is missing'),
      );
      expect(
        await refusal(() => app.client(token: 'garbage').api.currentUser()),
        refusedWith(401, 'token', 'is invalid'),
      );

      final (_, user) = await signUp(app);
      final forged = '${user.token.substring(0, user.token.length - 2)}xx';
      expect(
        await refusal(() => app.client(token: forged).api.currentUser()),
        refusedWith(401, 'token', 'is invalid'),
      );
    });
  });

  group('profiles', () {
    test('follow and unfollow', () async {
      final (reader, _) = await signUp(app);
      final (_, writer) = await signUp(app);

      expect(
        (await reader.api.follow(writer.username)).profile.following,
        isTrue,
      );
      expect(
        (await reader.api.profile(writer.username)).profile.following,
        isTrue,
      );
      expect(
        (await app.client().api.profile(writer.username)).profile.following,
        isFalse,
        reason: 'signed out',
      );
      expect(
        (await reader.api.unfollow(writer.username)).profile.following,
        isFalse,
      );
    });

    test('following yourself is refused', () async {
      final (client, user) = await signUp(app);

      expect(
        await refusal(() => client.api.follow(user.username)),
        refusedWith(422, 'profile'),
      );
    });

    test('an unknown profile is a 404', () async {
      expect(
        await refusal(() => app.client().api.profile(unique('ghost'))),
        refusedWith(404, 'profile', 'not found'),
      );
    });
  });

  group('articles', () {
    test('publish, read, edit, delete', () async {
      final (author, user) = await signUp(app);
      final title = unique('How to train your dragon');

      final created = await publish(
        author,
        title: title,
        tags: ['dragons', 'training'],
      );
      expect(created.slug, slugify(title));
      expect(created.tagList, ['dragons', 'training']);
      expect(created.author.username, user.username);
      expect(created.createdAt, created.updatedAt);

      final read = (await app.client().api.article(created.slug)).article;
      expect(read, created);

      final edited = (await author.api.updateArticle(
        created.slug,
        const UpdateArticleRequest(article: UpdateArticle(body: 'New body')),
      )).article;
      expect(edited.body, 'New body');
      expect(edited.slug, created.slug, reason: 'same title, same slug');
      expect(edited.tagList, created.tagList, reason: 'tags untouched');
      expect(edited.updatedAt.isAfter(created.updatedAt), isTrue);
      expect(edited.createdAt, created.createdAt);

      await author.api.deleteArticle(created.slug);
      expect(
        await refusal(() => app.client().api.article(created.slug)),
        refusedWith(404, 'article', 'not found'),
      );
    });

    test('a new title moves the slug', () async {
      final (author, _) = await signUp(app);
      final created = await publish(author);
      final title = unique('Renamed');

      final renamed = (await author.api.updateArticle(
        created.slug,
        UpdateArticleRequest(article: UpdateArticle(title: title)),
      )).article;

      expect(renamed.title, title);
      expect(renamed.slug, isNot(created.slug));
      expect(
        (await app.client().api.article(renamed.slug)).article.title,
        title,
      );
    });

    test('duplicate titles get distinct slugs', () async {
      final (author, _) = await signUp(app);
      final title = unique('Same title');

      final first = await publish(author, title: title);
      final second = await publish(author, title: title);

      expect(second.slug, isNot(first.slug));
      expect(second.slug, startsWith(first.slug));
    });

    test('tags are trimmed, de-duplicated, and kept in order', () async {
      final (author, _) = await signUp(app);

      final article = await publish(
        author,
        tags: [' zeta ', 'alpha', 'zeta', '', 'mid'],
      );

      expect(article.tagList, ['zeta', 'alpha', 'mid']);
    });

    test('an empty tag list clears the tags', () async {
      final (author, _) = await signUp(app);
      final article = await publish(author, tags: ['a', 'b']);

      final cleared = (await author.api.updateArticle(
        article.slug,
        const UpdateArticleRequest(article: UpdateArticle(tagList: [])),
      )).article;
      expect(cleared.tagList, isEmpty);
    });

    test('only the author may edit or delete', () async {
      final (author, _) = await signUp(app);
      final (stranger, _) = await signUp(app);
      final article = await publish(author);

      expect(
        await refusal(
          () => stranger.api.updateArticle(
            article.slug,
            const UpdateArticleRequest(
              article: UpdateArticle(body: 'mine now'),
            ),
          ),
        ),
        refusedWith(403, 'article', 'forbidden'),
      );
      expect(
        await refusal(() => stranger.api.deleteArticle(article.slug)),
        refusedWith(403, 'article', 'forbidden'),
      );
      expect(
        (await app.client().api.article(article.slug)).article.body,
        article.body,
      );
    });

    test('blank fields are refused with every field named', () async {
      final (author, _) = await signUp(app);

      final failure = await refusal(
        () => author.api.createArticle(
          const NewArticleRequest(
            article: NewArticle(title: '', description: ' ', body: ''),
          ),
        ),
      );

      expect(failure.status, 422);
      expect(failure.errors.errors, {
        'title': ["can't be blank"],
        'description': ["can't be blank"],
        'body': ["can't be blank"],
      });
    });

    test('lists filter by tag, author and favorited, newest first', () async {
      final (author, user) = await signUp(app);
      final (fan, fanUser) = await signUp(app);
      final tag = unique('tag');

      final older = await publish(author, tags: [tag]);
      final newer = await publish(author, tags: [tag]);
      await publish(author); // untagged

      final byTag = await app.client().api.articles(tag: tag);
      expect(byTag.articlesCount, 2);
      expect(byTag.articles.map((a) => a.slug), [newer.slug, older.slug]);

      final byAuthor = await app.client().api.articles(author: user.username);
      expect(byAuthor.articlesCount, 3);

      await fan.api.favorite(older.slug);
      final favorited = await app.client().api.articles(
        favorited: fanUser.username,
      );
      expect(favorited.articles.single.slug, older.slug);
      expect(favorited.articles.single.favoritesCount, 1);

      final both = await app.client().api.articles(
        tag: tag,
        author: user.username,
        favorited: fanUser.username,
      );
      expect(both.articles.single.slug, older.slug);
    });

    test('pages are bounded and counted', () async {
      final (author, user) = await signUp(app);
      for (var i = 0; i < 3; i++) {
        await publish(author);
      }

      final page = await app.client().api.articles(
        author: user.username,
        limit: 2,
        offset: 1,
      );
      expect(page.articles, hasLength(2));
      expect(page.articlesCount, 3);

      final huge = await app.client().api.articles(
        author: user.username,
        limit: 1000000,
      );
      expect(huge.articles, hasLength(3), reason: 'clamped, not refused');
    });

    test('the feed shows the people you follow', () async {
      final (reader, _) = await signUp(app);
      final (followed, followedUser) = await signUp(app);
      final (ignored, _) = await signUp(app);

      expect((await reader.api.feed()).articlesCount, 0);

      await reader.api.follow(followedUser.username);
      final wanted = await publish(followed);
      await publish(ignored);

      final feed = await reader.api.feed();
      expect(feed.articles.map((a) => a.slug), [wanted.slug]);
      expect(feed.articles.single.author.following, isTrue);

      expect(
        await refusal(() => app.client().api.feed()),
        refusedWith(401, 'token', 'is missing'),
      );
    });

    test('favorite and unfavorite count once per reader', () async {
      final (author, _) = await signUp(app);
      final (fan, _) = await signUp(app);
      final article = await publish(author);

      await fan.api.favorite(article.slug);
      final twice = (await fan.api.favorite(article.slug)).article;
      expect(twice.favorited, isTrue);
      expect(twice.favoritesCount, 1, reason: 'idempotent');

      expect(
        (await author.api.article(article.slug)).article.favorited,
        isFalse,
        reason: 'favorited is per viewer',
      );

      final undone = (await fan.api.unfavorite(article.slug)).article;
      expect(undone.favorited, isFalse);
      expect(undone.favoritesCount, 0);
    });

    test('tags lists what is in use', () async {
      final (author, _) = await signUp(app);
      final tag = unique('popular');
      await publish(author, tags: [tag]);
      await publish(author, tags: [tag]);

      final tags = (await app.client().api.tags()).tags;
      expect(tags, contains(tag));
    });
  });

  group('comments', () {
    test('add, list newest first, delete', () async {
      final (author, user) = await signUp(app);
      final article = await publish(author);

      final first = (await author.api.addComment(
        article.slug,
        const NewCommentRequest(comment: NewComment(body: 'First!')),
      )).comment;
      final second = (await author.api.addComment(
        article.slug,
        const NewCommentRequest(comment: NewComment(body: 'Second')),
      )).comment;
      expect(first.author.username, user.username);

      final listed = (await app.client().api.comments(article.slug)).comments;
      expect(listed.map((c) => c.id), [second.id, first.id]);

      await author.api.deleteComment(article.slug, first.id);
      expect(
        (await app.client().api.comments(
          article.slug,
        )).comments.map((c) => c.id),
        [second.id],
      );
    });

    test('only the comment author may delete it', () async {
      final (author, _) = await signUp(app);
      final (stranger, _) = await signUp(app);
      final article = await publish(author);
      final comment = (await author.api.addComment(
        article.slug,
        const NewCommentRequest(comment: NewComment(body: 'Mine')),
      )).comment;

      expect(
        await refusal(
          () => stranger.api.deleteComment(article.slug, comment.id),
        ),
        refusedWith(403, 'comment', 'forbidden'),
      );
    });

    test('a comment id from another article is not found here', () async {
      final (author, _) = await signUp(app);
      final one = await publish(author);
      final other = await publish(author);
      final comment = (await author.api.addComment(
        one.slug,
        const NewCommentRequest(comment: NewComment(body: 'On one')),
      )).comment;

      expect(
        await refusal(() => author.api.deleteComment(other.slug, comment.id)),
        refusedWith(404, 'comment', 'not found'),
      );
    });

    test('deleting an article takes its comments with it', () async {
      final (author, _) = await signUp(app);
      final article = await publish(author);
      await author.api.addComment(
        article.slug,
        const NewCommentRequest(comment: NewComment(body: 'Soon gone')),
      );

      await author.api.deleteArticle(article.slug);

      expect(
        await refusal(() => app.client().api.comments(article.slug)),
        refusedWith(404, 'article'),
      );
    });
  });
}

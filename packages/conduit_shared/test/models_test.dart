import 'package:conduit_shared/conduit_shared.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

/// The contract both sides compile against. Each group pins one rule the
/// RealWorld spec asserts on, so a regenerated model that drifts fails here
/// before it fails in a browser.
void main() {
  group('User', () {
    test('writes null bio and image rather than dropping them', () {
      const user = User(email: 'a@b.co', token: 't', username: 'ada');

      expect(const UserEnvelope(user: user).toJson(), {
        'user': {
          'email': 'a@b.co',
          'token': 't',
          'username': 'ada',
          'bio': null,
          'image': null,
        },
      });
    });

    test('round-trips through JSON', () {
      const user = User(
        email: 'a@b.co',
        token: 't',
        username: 'ada',
        bio: 'hi',
        image: 'https://example.com/a.png',
      );

      expect(
        UserEnvelope.fromJson(const UserEnvelope(user: user).toJson()),
        const UserEnvelope(user: user),
      );
    });
  });

  group('validation messages', () {
    List<String> problems(ValidationResult result, String field) => [
      for (final error in result.errors)
        if (error.field == field) error.message,
    ];

    test("blank registration fields say can't be blank first", () {
      final result = const NewUser(
        username: ' ',
        email: '',
        password: '',
      ).validate();

      expect(problems(result, 'username'), ["can't be blank"]);
      expect(problems(result, 'email').first, "can't be blank");
      expect(problems(result, 'password').first, "can't be blank");
    });

    test('passwords follow NIST: 8 is enough, 7 is not, 64 is fine', () {
      NewUser withPassword(String password) => NewUser(
        username: 'ada',
        email: 'ada@example.com',
        password: password,
      );

      expect(withPassword('short7c').validate().isValid, isFalse);
      expect(withPassword('bonjour1').validate().isValid, isTrue);
      expect(withPassword('a' * 64).validate().isValid, isTrue);
    });

    test('an update validates only the fields it carries', () {
      expect(const UpdateUser(bio: '').validate().isValid, isTrue);
      expect(
        problems(const UpdateUser(email: '').validate(), 'email').first,
        "can't be blank",
      );
      expect(const UpdateUser(password: 'short').validate().isValid, isFalse);
    });

    test('an article needs a title, description and body', () {
      final result = const NewArticle(
        title: '',
        description: '',
        body: '',
      ).validate();

      expect(result.errors.map((e) => e.field).toSet(), {
        'title',
        'description',
        'body',
      });
    });

    test('a comment needs a body', () {
      expect(problems(const NewComment(body: '  ').validate(), 'body'), [
        "can't be blank",
      ]);
    });
  });

  group('patch requests', () {
    test('an update sends only the fields that were set', () {
      expect(const UpdateUserRequest(user: UpdateUser(bio: 'new')).toJson(), {
        'user': {'bio': 'new'},
      });
    });

    test('an empty tag list is sent, so it can clear the tags', () {
      expect(
        const UpdateArticleRequest(
          article: UpdateArticle(tagList: []),
        ).toJson(),
        {
          'article': {'tagList': <String>[]},
        },
      );
    });

    test('a new article defaults to no tags when the key is absent', () {
      final article = NewArticleRequest.fromJson(const {
        'article': {'title': 't', 'description': 'd', 'body': 'b'},
      }).article;

      expect(article.tagList, isEmpty);
    });
  });

  group('Article', () {
    test('decodes timestamps and the nested author', () {
      final article = ArticleEnvelope.fromJson(const {
        'article': {
          'slug': 'how-to-train-your-dragon',
          'title': 'How to train your dragon',
          'description': 'Ever wonder how?',
          'body': 'It takes a Jacobian',
          'tagList': ['dragons', 'training'],
          'createdAt': '2016-02-18T03:22:56.637Z',
          'updatedAt': '2016-02-18T03:48:35.824Z',
          'favorited': false,
          'favoritesCount': 0,
          'author': {
            'username': 'jake',
            'bio': 'I work at statefarm',
            'image': 'https://i.stack.imgur.com/xHWG8.jpg',
            'following': false,
          },
        },
      }).article;

      expect(article.createdAt, DateTime.utc(2016, 2, 18, 3, 22, 56, 637));
      expect(article.author.username, 'jake');
      expect(article.tagList, ['dragons', 'training']);
    });

    test('a list item has no body key at all', () {
      final preview = ArticlePreview(
        slug: 's',
        title: 't',
        description: 'd',
        tagList: const [],
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        favorited: false,
        favoritesCount: 0,
        author: const Profile(username: 'ada', following: false),
      );

      expect(preview.toJson().containsKey('body'), isFalse);
    });
  });

  group('ConduitFailure', () {
    DioException refused(int status, Object? data) {
      final options = RequestOptions(path: '/articles');
      return DioException.badResponse(
        statusCode: status,
        requestOptions: options,
        response: Response<Object?>(
          requestOptions: options,
          statusCode: status,
          data: data,
        ),
      );
    }

    test("reads the API's errors object", () {
      final failure = ConduitFailure.from(
        refused(422, {
          'errors': {
            'title': ["can't be blank"],
          },
        }),
      );

      expect(failure.status, 422);
      expect(failure.errors.messages, ["title can't be blank"]);
    });

    test('no response at all reads "Unable to connect"', () {
      final failure = ConduitFailure.from(
        DioException.connectionError(
          requestOptions: RequestOptions(path: '/tags'),
          reason: 'refused',
        ),
      );

      expect(failure.status, 0);
      expect(failure.isClientError, isFalse);
      expect(failure.errors.errors[ConduitFailure.network], [
        'Unable to connect to the server',
      ]);
    });

    test('falls back when the body is not the API shape', () {
      final failure = ConduitFailure.from(refused(502, '<html>bad gateway'));

      expect(failure.status, 502);
      expect(failure.errors.errors.keys, ['server']);
    });
  });
}

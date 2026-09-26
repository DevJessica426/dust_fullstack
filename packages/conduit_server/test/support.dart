import 'dart:io';

import 'package:conduit_server/conduit_server.dart';
import 'package:conduit_shared/conduit_shared.dart';
import 'package:dust_server/server.dart';
import 'package:test/test.dart';

/// The database the integration tests own. Everything in it is dropped.
///
/// There is no in-memory PostgreSQL, so the suite needs a real server and is
/// skipped without one — the same rule `dust_db_postgres` follows. The
/// scripts in `tool/` set this for a local database.
final String? testDatabaseUrl =
    Platform.environment['CONDUIT_TEST_DATABASE_URL'];

const skipWithoutDatabase =
    'set CONDUIT_TEST_DATABASE_URL to a PostgreSQL database the tests may wipe';

/// A running server on a free port, over a freshly migrated schema.
final class TestServer {
  TestServer._(this.database, this.server, this.errors);

  final ConduitDatabase database;
  final ServerHandle server;

  /// Everything the router reported through `onError`. A test that expects no
  /// 500s asserts this stays empty.
  final List<Object> errors;

  Uri get baseUri => Uri.parse('http://127.0.0.1:${server.port}');
  String get apiUrl => '$baseUri/api';

  /// A typed client, optionally signed in.
  ConduitClient client({String? token}) =>
      ConduitClient(baseUrl: apiUrl, token: token);

  static Future<TestServer> start({String? webRoot}) async {
    final database = ConduitDatabase.connect(testDatabaseUrl!);
    await _resetSchema(database);
    (await database.migrate()).unwrapOrElse((error) => throw error);

    final errors = <Object>[];
    final app = buildApp(
      database: database,
      // A real Argon2id hash, at a cost that does not dominate the suite.
      auth: Auth(
        jwt: JwtCodec(List<int>.filled(32, 7)),
        passwords: const PasswordHasher.fast(),
      ),
      webRoot: webRoot,
      onError: (error, stack) => errors.add(error),
    );
    final server = await serve(app, InternetAddress.loopbackIPv4, 0);
    return TestServer._(database, server, errors);
  }

  Future<void> stop() async {
    await server.close();
    await database.connection.close();
  }

  static Future<void> _resetSchema(ConduitDatabase database) async {
    // Tests own this database outright, so the fastest reset is the whole
    // schema, migration bookkeeping included.
    // dust:allow-unsafe-sql
    await database.unsafe.execute('DROP SCHEMA public CASCADE', const []);
    // dust:allow-unsafe-sql
    await database.unsafe.execute('CREATE SCHEMA public', const []);
  }
}

var _counter = 0;

/// A unique name per call, so tests never collide on the unique indexes.
String unique(String prefix) =>
    '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_counter++}';

/// Registers a new user and returns a client signed in as them.
Future<(ConduitClient, User)> signUp(TestServer app, [String? name]) async {
  final username = name ?? unique('user');
  final anonymous = app.client();
  final user = (await anonymous.api.register(
    RegisterRequest(
      user: NewUser(
        username: username,
        email: '$username@example.com',
        password: 'password123',
      ),
    ),
  ))
      .user;
  anonymous.close();
  return (app.client(token: user.token), user);
}

/// Publishes an article as [client].
Future<Article> publish(
  ConduitClient client, {
  String? title,
  List<String> tags = const [],
  String body = 'Some *markdown*.',
}) async =>
    (await client.api.createArticle(
      NewArticleRequest(
        article: NewArticle(
          title: title ?? unique('Title'),
          description: 'A description',
          body: body,
          tagList: tags,
        ),
      ),
    ))
        .article;

/// Runs [call] and returns what the API refused it with.
///
/// Fails the test when the call succeeds instead.
Future<ConduitFailure> refusal(Future<Object?> Function() call) async {
  try {
    await call();
  } on Object catch (error) {
    return ConduitFailure.from(error);
  }
  fail('expected the API to refuse the call');
}

/// Matches a [ConduitFailure] by status and its first `errors` entry.
Matcher refusedWith(int status, String key, [String? problem]) => isA<
        ConduitFailure>()
    .having((f) => f.status, 'status', status)
    .having((f) => f.errors.errors.keys, 'error keys', contains(key))
    .having(
      (f) => f.errors.errors[key],
      'errors[$key]',
      problem == null ? isNotEmpty : contains(problem),
    );

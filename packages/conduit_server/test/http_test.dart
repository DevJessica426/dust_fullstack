@Tags(['postgres'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:conduit_shared/conduit_shared.dart';
import 'package:test/test.dart';

import 'support.dart';

/// What only raw HTTP shows: the error shape for requests no typed client
/// would send, CORS, and the web app served beside the API.
void main() {
  if (testDatabaseUrl == null) {
    test('HTTP details', () {}, skip: skipWithoutDatabase);
    return;
  }

  late TestServer app;
  late Directory web;
  final http = HttpClient();

  setUpAll(() async {
    web = Directory.systemTemp.createTempSync('conduit_web_');
    File('${web.path}/index.html').writeAsStringSync('<div id="app"></div>');
    File('${web.path}/main.dart.js').writeAsStringSync('// app');
    app = await TestServer.start(webRoot: web.path);
  });
  tearDownAll(() async {
    http.close(force: true);
    await app.stop();
    web.deleteSync(recursive: true);
  });

  Future<(int, HttpHeaders, String)> send(
    String method,
    String path, {
    String? body,
    Map<String, String> headers = const {},
  }) async {
    final request = await http.openUrl(method, app.baseUri.resolve(path));
    headers.forEach(request.headers.set);
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(body);
    }
    final response = await request.close();
    return (
      response.statusCode,
      response.headers,
      await response.transform(utf8.decoder).join(),
    );
  }

  Map<String, Object?> errorsOf(String body) =>
      (jsonDecode(body) as Map<String, Object?>)['errors']!
          as Map<String, Object?>;

  test('malformed JSON is a 400 in the RealWorld error shape', () async {
    final (status, _, body) = await send(
      'POST',
      '/api/users/login',
      body: '{not json',
    );

    expect(status, 400);
    expect(errorsOf(body), contains('body'));
  });

  test('JSON of the wrong shape is a 422', () async {
    final (status, _, body) = await send(
      'POST',
      '/api/users',
      body: '{"user": "nope"}',
    );

    expect(status, 422);
    expect(errorsOf(body), contains('body'));
  });

  test('null for a required field on update is a 422, not a clear', () async {
    final (_, user) = await signUp(app);

    final (status, _, body) = await send(
      'PUT',
      '/api/user',
      body: '{"user": {"email": null}}',
      headers: {'authorization': 'Token ${user.token}'},
    );

    expect(status, 422);
    expect(errorsOf(body), {
      'email': ["can't be blank"],
    });
  });

  test('null bio clears it', () async {
    final (client, user) = await signUp(app);
    await client.api.updateUser(
      const UpdateUserRequest(user: UpdateUser(bio: 'temporary')),
    );

    final (status, _, body) = await send(
      'PUT',
      '/api/user',
      body: '{"user": {"bio": null}}',
      headers: {'authorization': 'Token ${user.token}'},
    );

    expect(status, 200);
    expect((jsonDecode(body) as Map)['user']['bio'], isNull);
  });

  test('a 401 carries a Token challenge', () async {
    final (status, headers, body) = await send('GET', '/api/user');

    expect(status, 401);
    expect(headers.value('www-authenticate'), 'Token');
    expect(errorsOf(body), {
      'token': ['is missing'],
    });
  });

  test('Bearer is accepted as well as Token', () async {
    final (_, user) = await signUp(app);

    final (status, _, _) = await send(
      'GET',
      '/api/user',
      headers: {'authorization': 'Bearer ${user.token}'},
    );

    expect(status, 200);
  });

  test('a non-numeric comment id is a 400', () async {
    final (_, user) = await signUp(app);

    final (status, _, body) = await send(
      'DELETE',
      '/api/articles/anything/comments/abc',
      headers: {'authorization': 'Token ${user.token}'},
    );

    expect(status, 400);
    expect(errorsOf(body), isNotEmpty);
  });

  test('an unknown API path is a JSON 404, not the web app', () async {
    final (status, headers, body) = await send('GET', '/api/nothing/here');

    expect(status, 404);
    expect(headers.contentType?.mimeType, 'application/json');
    expect(errorsOf(body), isNotEmpty);
  });

  test('a wrong method on a known path is a 405 with Allow', () async {
    final (status, headers, _) = await send('PATCH', '/api/tags');

    expect(status, 405);
    expect(headers.value('allow'), contains('GET'));
  });

  test(
    'any origin may call the API; preflights never reach a handler',
    () async {
      final (status, headers, _) = await send(
        'OPTIONS',
        '/api/articles',
        headers: {
          'origin': 'https://react-conduit.example',
          'access-control-request-method': 'POST',
          'access-control-request-headers': 'authorization, content-type',
        },
      );

      expect(status, 204);
      expect(headers.value('access-control-allow-origin'), isNotNull);
      expect(
        headers.value('access-control-allow-headers'),
        contains('authorization'),
      );
    },
  );

  test('client-side routes get the web app, revalidated', () async {
    for (final path in ['/', '/login', '/article/some-slug', '/profile/ada']) {
      final (status, headers, body) = await send('GET', path);

      expect(status, 200, reason: path);
      expect(body, contains('id="app"'), reason: path);
      expect(headers.value('cache-control'), 'no-cache', reason: path);
    }
  });

  test('health check', () async {
    final (status, _, body) = await send('GET', '/healthz');

    expect(status, 200);
    expect(jsonDecode(body), {'status': 'ok'});
  });
}

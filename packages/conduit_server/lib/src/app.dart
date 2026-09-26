import 'dart:io';

import 'package:dust_server/server.dart';

import 'auth/viewer.dart';
import 'db/database.dart';
import 'features/articles.dart';
import 'features/comments.dart';
import 'features/profiles.dart';
import 'features/users.dart';
import 'http/errors.dart';

/// The whole application: the API under `/api`, and the Dart web app on
/// every other path.
///
/// Dependencies are parameters, not globals, so a test hands in its own
/// database and a cheap password hasher and serves the same router.
Router buildApp({
  required ConduitDatabase database,
  required Auth auth,
  String? webRoot,
  void Function(Object error, StackTrace stack)? onError,
  void Function(AccessRecord record)? accessLog,
}) {
  // TODO(dust#548): generate the route modules from handler annotations once
  // dust_server can; each feature's Router is written by hand today.
  final api = Router()
    ..merge(userRoutes())
    ..merge(profileRoutes())
    ..merge(articleRoutes())
    ..merge(commentRoutes());

  final app = Router(onError: onError ?? _reportToStderr)
    // Outermost first. CORS answers preflights before anything else runs; the
    // API is public and authenticates with a header, never a cookie, so any
    // origin may call it — which is what lets another RealWorld front end
    // (React, Vue, Elm...) use this server unchanged.
    ..layer(
      Cors(
        methods: const {'GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'},
        headers: const {'authorization', 'content-type', 'x-requested-with'},
        exposeHeaders: const {'x-request-id'},
        maxAge: const Duration(hours: 1),
      ),
    )
    ..layer(const RequestId());
  if (accessLog != null) app.layer(AccessLog(accessLog));
  app
    ..layer(const RealWorldErrors())
    ..nest('/api', api)
    ..route('/healthz', get(_health))
    ..withState<ConduitDatabase>(database)
    ..withState(auth);

  if (webRoot != null) {
    // The fallback answers whatever no route matched: every other GET is a
    // page view the browser app routes itself. dust_server reads only the
    // outermost router's fallback, so the /api carve-out lives here — an
    // unknown API path is a client's typo and must stay a JSON 404, not a
    // 200 with an HTML page.
    // TODO(dust#587): drop the carve-out once dust_server keeps unmatched
    // paths under a nested prefix out of the outer fallback.
    final web = staticFiles(
      webRoot,
      html: true,
      // The Dart build emits fixed names rather than content hashes, so the
      // stylesheets and images are revalidated like the document and script.
      revalidate: const {
        ...defaultRevalidatedFiles,
        'styles.css',
        'icons.css',
        'favicon.svg',
        'default-avatar.svg',
      },
    );
    app.fallback(
      (request) => request.requestedUri.path.startsWith('/api/')
          ? Rejection.notFound(
              'no route for ${request.requestedUri.path}',
            ).intoResponse()
          : web(request),
    );
  }
  return app;
}

Map<String, Object?> _health(Request request) => const {'status': 'ok'};

void _reportToStderr(Object error, StackTrace stack) {
  stderr
    ..writeln('unhandled error: $error')
    ..writeln(stack);
}

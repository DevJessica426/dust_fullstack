/// The Conduit front end: a Dart web app talking to the API through the
/// Dust-generated `ConduitApi` from `conduit_shared`.
library;

import 'package:conduit_shared/conduit_shared.dart';
import 'package:web/web.dart' as web;

import 'src/app.dart';
import 'src/unload_safe.dart';
import 'src/navigation.dart';
import 'src/session.dart';

/// Starts the app inside `#app`.
///
/// The API is the page's own origin plus `/api`, unless the page names
/// another with `<meta name="conduit-api" content="https://...">` — which is
/// all it takes to point this front end at any RealWorld backend.
void runConduit() {
  final configured = web.document
      .querySelector('meta[name="conduit-api"]')
      ?.getAttribute('content');
  final apiUrl = (configured == null || configured.isEmpty)
      ? '${web.window.location.origin}/api'
      : configured;

  // Writes are recorded when requested and survive the page unloading; see
  // src/unload_safe.dart.
  final adapter = UnloadSafeAdapter()..flushOnPageHide(web.window);
  final client = ConduitClient(baseUrl: apiUrl, dio: UnloadSafeDio(adapter));
  final session = Session(client)..exposeDebugInterface();
  final navigation = Navigation()..start();
  final app = App(client: client, session: session, navigation: navigation);

  session.start();
  Shell(app, web.document.querySelector('#app')!).start();
}

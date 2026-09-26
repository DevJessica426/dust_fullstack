import 'package:web/web.dart' as web;

import '../app.dart';
import '../session.dart';

/// One screen. The shell builds it, mounts [root], calls [start], and calls
/// [dispose] when the reader navigates away.
abstract class Page {
  Page(this.app);

  final App app;

  bool _disposed = false;

  /// Whether the reader has left. Every `await` in a page is followed by a
  /// check of this, so a slow response never paints over the next page.
  bool get disposed => _disposed;

  web.HTMLElement get root;

  Future<void> start();

  void dispose() => _disposed = true;

  /// Waits for the session, then sends a signed-out reader to sign in.
  ///
  /// Returns whether the page may carry on. An unavailable session is let
  /// through: the reader may well be signed in, and the page says what it
  /// cannot do rather than bouncing them to a login form they do not need.
  Future<bool> requireSignedIn() async {
    await app.session.ready;
    if (disposed) return false;
    if (app.session.state == AuthState.unauthenticated) {
      app.go('/login', replace: true);
      return false;
    }
    return true;
  }
}

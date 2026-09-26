import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:conduit_shared/conduit_shared.dart';
import 'package:web/web.dart' as web;

/// Where the app is in knowing who the reader is.
enum AuthState {
  /// A token is stored and `GET /user` has not answered yet.
  loading,

  /// Signed in.
  authenticated,

  /// Signed out, or the stored token was refused.
  unauthenticated,

  /// A token is stored but the server could not be asked about it — a 5xx,
  /// no network, or an unreadable answer. The token is kept: it may well be
  /// fine, and throwing it away would sign someone out because of an outage.
  unavailable,
}

/// The signed-in user and their token, kept in `localStorage['jwtToken']`.
///
/// The token is only attached to requests once the server has accepted it.
/// While it is unchecked or unverifiable the app browses anonymously, so a
/// stale token never turns the public feed into a 401.
final class Session {
  Session(this.client);

  static const tokenKey = 'jwtToken';

  final ConduitClient client;

  final _changes = StreamController<void>.broadcast();

  AuthState _state = AuthState.loading;
  User? _user;
  Future<void> _ready = Future.value();

  /// Fires after every change of [state] or [user].
  Stream<void> get changes => _changes.stream;

  AuthState get state => _state;

  bool get isAuthenticated => _state == AuthState.authenticated;

  /// The signed-in user, when [isAuthenticated].
  User? get user => _user;

  /// Completes once the stored token has been checked, one way or the other.
  Future<void> get ready => _ready;

  String? get storedToken => web.window.localStorage.getItem(tokenKey);

  /// Checks the stored token against `GET /user`.
  Future<void> start() => _ready = _resolve();

  Future<void> _resolve() async {
    final token = storedToken;
    if (token == null || token.isEmpty) {
      _set(AuthState.unauthenticated, null);
      return;
    }

    _set(AuthState.loading, null);
    client.token = token;
    try {
      final user = (await client.api.currentUser()).user;
      _set(AuthState.authenticated, user);
    } on Object catch (error) {
      client.token = null;
      final failure = ConduitFailure.from(error);
      if (failure.isClientError) {
        // The server looked at the token and said no: it is dead.
        web.window.localStorage.removeItem(tokenKey);
        _set(AuthState.unauthenticated, null);
      } else {
        _set(AuthState.unavailable, null);
      }
    }
  }

  /// After sign-in, sign-up, or a settings change.
  void signIn(User user) {
    web.window.localStorage.setItem(tokenKey, user.token);
    client.token = user.token;
    _ready = Future.value();
    _set(AuthState.authenticated, user);
  }

  void signOut() {
    web.window.localStorage.removeItem(tokenKey);
    client.token = null;
    _ready = Future.value();
    _set(AuthState.unauthenticated, null);
  }

  void _set(AuthState state, User? user) {
    _state = state;
    _user = user;
    _changes.add(null);
  }

  /// Publishes `window.__conduit_debug__`, which the RealWorld E2E suite
  /// reads to check auth state without scraping the page.
  void exposeDebugInterface() {
    final debug = JSObject()
      ..['getToken'] = (() => storedToken?.toJS).toJS
      ..['getAuthState'] = (() => _state.name.toJS).toJS
      ..['getCurrentUser'] = (() {
        final user = _user;
        if (user == null) return null;
        return {
          'username': user.username,
          'email': user.email,
          'bio': user.bio,
          'image': user.image,
          'token': user.token,
        }.jsify();
      }).toJS;
    globalContext['__conduit_debug__'] = debug;
  }
}

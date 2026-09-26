import 'package:conduit_shared/conduit_shared.dart';
import 'package:web/web.dart' as web;

import '../dom.dart';
import '../format.dart';
import '../routes.dart';
import 'page.dart';

/// `/login` and `/register`.
///
/// The form runs the same Dust-generated `validate()` the server runs, so a
/// blank field is caught before a request is made — and caught identically if
/// someone skips the form and calls the API directly.
final class AuthPage extends Page {
  AuthPage(super.app, {required this.signUp, this.redirect});

  final bool signUp;

  /// Where to go once signed in; the home page when null.
  final String? redirect;

  var _username = '';
  var _email = '';
  var _password = '';
  var _busy = false;
  List<String> _errors = const [];

  final _errorsHost = h('div');
  late final _submit = h(
    'button',
    cls: 'btn btn-lg btn-primary pull-xs-right',
    attrs: {'type': 'submit'},
    children: signUp ? 'Sign up' : 'Sign in',
  );

  @override
  late final web.HTMLElement root = h(
    'div',
    cls: 'auth-page',
    children: h(
      'div',
      cls: 'container page',
      children: h(
        'div',
        cls: 'row',
        children: h(
          'div',
          cls: 'col-md-6 offset-md-3 col-xs-12',
          children: [
            h(
              'h1',
              cls: 'text-xs-center',
              children: signUp ? 'Sign up' : 'Sign in',
            ),
            h(
              'p',
              cls: 'text-xs-center',
              children: signUp
                  ? link(
                      LoginRoute(redirect: redirect).href,
                      'Have an account?',
                    )
                  : link(
                      RegisterRoute(redirect: redirect).href,
                      'Need an account?',
                    ),
            ),
            _errorsHost,
            _form(),
          ],
        ),
      ),
    ),
  );

  web.HTMLElement _form() {
    final form = h(
      'form',
      children: [
        if (signUp)
          _group(
            input(
              name: 'username',
              placeholder: 'Username',
              onInput: (value) => _username = value,
            ),
          ),
        _group(
          input(
            name: 'email',
            placeholder: 'Email',
            type: 'email',
            onInput: (value) => _email = value,
          ),
        ),
        _group(
          input(
            name: 'password',
            placeholder: 'Password',
            type: 'password',
            onInput: (value) => _password = value,
          ),
        ),
        _submit,
      ],
    );
    form.onSubmit.listen((event) {
      event.preventDefault();
      _send();
    });
    return form;
  }

  web.HTMLElement _group(web.HTMLElement field) =>
      h('fieldset', cls: 'form-group', children: field);

  @override
  Future<void> start() async {
    await app.session.ready;
    if (!disposed && app.session.isAuthenticated) {
      app.go(redirect ?? '/', replace: true);
    }
  }

  Future<void> _send() async {
    if (_busy) return;

    final ValidationResult checked;
    final Future<UserEnvelope> Function() request;
    if (signUp) {
      final user = NewUser(
        username: _username,
        email: _email,
        password: _password,
      );
      checked = user.validate();
      request = () => app.api.register(RegisterRequest(user: user));
    } else {
      final user = LoginUser(email: _email, password: _password);
      checked = user.validate();
      request = () => app.api.login(LoginRequest(user: user));
    }
    if (checked case Invalid(:final errors)) {
      _show([for (final error in errors) '${error.field} ${error.message}']);
      return;
    }

    _setBusy(true);
    try {
      final user = (await request()).user;
      if (disposed) return;
      app.session.signIn(user);
      app.go(redirect ?? '/');
    } on Object catch (error) {
      if (disposed) return;
      _show(errorLines(ConduitFailure.from(error).errors));
    } finally {
      _setBusy(false);
    }
  }

  void _setBusy(bool busy) {
    _busy = busy;
    _submit.toggleAttribute('disabled', busy);
  }

  void _show(List<String> errors) {
    _errors = errors;
    replace(_errorsHost, errorList(_errors));
  }
}

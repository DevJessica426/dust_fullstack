import 'package:conduit_shared/conduit_shared.dart';
import 'package:web/web.dart' as web;

import '../dom.dart';
import '../format.dart';
import '../routes.dart';
import '../session.dart';
import 'page.dart';

/// `/settings`: edit your profile, or sign out.
final class SettingsPage extends Page {
  SettingsPage(super.app);

  final _body = h('div', cls: 'col-md-6 offset-md-3 col-xs-12');
  final _errorsHost = h('div');
  var _busy = false;

  @override
  late final web.HTMLElement root = h(
    'div',
    cls: 'settings-page',
    children: h(
      'div',
      cls: 'container page',
      children: h('div', cls: 'row', children: _body),
    ),
  );

  @override
  Future<void> start() async {
    replace(_body, h('h1', cls: 'text-xs-center', children: 'Your Settings'));
    if (!await requireSignedIn()) return;

    final user = app.session.user;
    if (app.session.state == AuthState.unavailable || user == null) {
      append(
        _body,
        h(
          'p',
          cls: 'text-xs-center',
          children:
              'Your settings will be here once the server is reachable again.',
        ),
      );
      return;
    }
    _render(user);
  }

  void _render(User user) {
    final image = input(
      name: 'image',
      placeholder: 'URL of profile picture',
      value: user.image ?? '',
      cls: 'form-control',
    );
    final username = input(
      name: 'username',
      placeholder: 'Your Name',
      value: user.username,
    );
    final bio = textarea(
      name: 'bio',
      placeholder: 'Short bio about you',
      value: user.bio ?? '',
    );
    final email = input(
      name: 'email',
      placeholder: 'Email',
      value: user.email,
      type: 'email',
    );
    final password = input(
      name: 'password',
      placeholder: 'New Password',
      type: 'password',
    );
    final submit = h(
      'button',
      cls: 'btn btn-lg btn-primary pull-xs-right',
      attrs: {'type': 'submit'},
      children: 'Update Settings',
    );

    web.HTMLElement group(web.HTMLElement field) =>
        h('fieldset', cls: 'form-group', children: field);

    final form = h(
      'form',
      attrs: {'novalidate': ''},
      children: h(
        'fieldset',
        children: [
          group(image),
          group(username),
          group(bio),
          group(email),
          group(password),
          submit,
        ],
      ),
    );
    form.onSubmit.listen((event) {
      event.preventDefault();
      _save(
        UpdateUser(
          // Sent as typed: an emptied image or bio clears it on the server.
          image: image.value.trim(),
          username: username.value.trim(),
          bio: bio.value,
          email: email.value.trim(),
          // Blank means "keep my password", so it is left out of the patch.
          password: password.value.isEmpty ? null : password.value,
        ),
        submit,
      );
    });

    replace(_body, [
      h('h1', cls: 'text-xs-center', children: 'Your Settings'),
      _errorsHost,
      form,
      h('hr'),
      h(
        'button',
        cls: 'btn btn-outline-danger',
        attrs: {'type': 'button'},
        children: 'Or click here to logout.',
        onClick: (_) {
          app.session.signOut();
          app.go('/');
        },
      ),
    ]);
  }

  Future<void> _save(UpdateUser changes, web.HTMLElement submit) async {
    if (_busy) return;
    if (changes.validate() case Invalid(:final errors)) {
      replace(
        _errorsHost,
        errorList([for (final e in errors) '${e.field} ${e.message}']),
      );
      return;
    }

    _busy = true;
    submit.toggleAttribute('disabled', true);
    try {
      final user = (await app.api.updateUser(
        UpdateUserRequest(user: changes),
      )).user;
      if (disposed) return;
      app.session.signIn(user);
      app.go(profileHref(user.username));
    } on Object catch (error) {
      if (disposed) return;
      replace(
        _errorsHost,
        errorList(errorLines(ConduitFailure.from(error).errors)),
      );
    } finally {
      _busy = false;
      submit.toggleAttribute('disabled', false);
    }
  }
}

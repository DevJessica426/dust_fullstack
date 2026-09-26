import 'dart:async';

import 'package:web/web.dart' as web;

import 'routes.dart';

/// History-API routing: real URLs, no `#`.
///
/// Clicks on same-origin `<a href="/...">` are intercepted once, at the
/// document, so every link in the app is a plain anchor — middle-click, "open
/// in new tab" and copying a link all behave as a user expects.
final class Navigation {
  final _changes = StreamController<AppRoute>.broadcast();

  late AppRoute _current = _read();

  AppRoute get current => _current;

  /// Fires with the new route after every navigation.
  Stream<AppRoute> get changes => _changes.stream;

  void start() {
    web.window.onPopState.listen((_) => _emit());
    web.EventStreamProviders.clickEvent
        .forTarget(web.document)
        .listen(_interceptLinks);
  }

  /// Goes to [href]. [replace] swaps the history entry, for redirects the
  /// back button should skip.
  void go(String href, {bool replace = false}) {
    if (replace) {
      web.window.history.replaceState(null, '', href);
    } else {
      web.window.history.pushState(null, '', href);
    }
    _emit();
  }

  void _emit() {
    _current = _read();
    _changes.add(_current);
  }

  AppRoute _read() => AppRoute.parse(Uri.parse(web.window.location.href));

  void _interceptLinks(web.MouseEvent event) {
    if (event.defaultPrevented ||
        event.button != 0 ||
        event.metaKey ||
        event.ctrlKey ||
        event.shiftKey ||
        event.altKey) {
      return;
    }
    final target = event.target;
    if (target == null) return;
    final anchor = (target as web.Element).closest('a');
    if (anchor == null) return;

    final href = anchor.getAttribute('href');
    if (href == null ||
        !href.startsWith('/') ||
        href.startsWith('//') ||
        anchor.hasAttribute('target') ||
        anchor.hasAttribute('download')) {
      return;
    }
    event.preventDefault();
    go(href);
  }
}

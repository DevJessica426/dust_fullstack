import 'package:web/web.dart' as web;

import '../dom.dart';
import 'page.dart';

/// Any URL the app does not know.
final class NotFoundPage extends Page {
  NotFoundPage(super.app);

  @override
  final web.HTMLElement root = h(
    'div',
    cls: 'container page',
    children: [
      h('h2', children: 'Page not found'),
      h(
        'p',
        children: [
          'There is nothing here. ',
          link('/', 'Back to the feed'),
          '.',
        ],
      ),
    ],
  );

  @override
  Future<void> start() async {}
}

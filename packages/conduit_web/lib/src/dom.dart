import 'package:web/web.dart' as web;

import 'markdown.dart';

// A few lines of DOM building instead of a framework.
//
// Everything a user typed reaches the page through `createTextNode` or a DOM
// property/`setAttribute` call — never through `innerHTML` — so there is no
// markup string anywhere for a payload to escape from.

/// Creates `<tag class="cls" ...attrs>children</tag>`.
///
/// [children] may be a `String` (inserted as text), a DOM node, an
/// `Iterable` of either, or null (skipped), nested to any depth.
web.HTMLElement h(
  String tag, {
  String? cls,
  Map<String, String> attrs = const {},
  Object? children,
  void Function(web.MouseEvent event)? onClick,
}) {
  final element = web.document.createElement(tag) as web.HTMLElement;
  if (cls != null) element.className = cls;
  attrs.forEach((name, value) => element.setAttribute(name, value));
  append(element, children);
  if (onClick != null) element.onClick.listen(onClick);
  return element;
}

/// Appends [children] to [parent]; see [h] for what they may be.
void append(web.Node parent, Object? children) {
  switch (children) {
    case null:
      return;
    case final String text:
      parent.appendChild(web.document.createTextNode(text));
    case final Iterable<Object?> many:
      for (final child in many) {
        append(parent, child);
      }
    default:
      parent.appendChild(children as web.Node);
  }
}

/// Replaces everything inside [parent] with [children].
void replace(web.Element parent, Object? children) {
  parent.textContent = '';
  append(parent, children);
}

/// An `<a>` whose navigation the app handles itself.
web.HTMLElement link(String href, Object? children, {String? cls}) =>
    h('a', cls: cls, attrs: {'href': href}, children: children);

/// An `<img>`, with [src] set as a property rather than written into markup.
web.HTMLElement image(String src, {String? cls, String alt = ''}) {
  final img = web.document.createElement('img') as web.HTMLImageElement
    ..src = src
    ..alt = alt;
  if (cls != null) img.className = cls;
  return img;
}

/// `<i class="ion-...">` — see `web/icons.css`.
web.HTMLElement icon(String name) => h('i', cls: name);

/// A text input bound to [value], reporting edits through [onInput].
web.HTMLInputElement input({
  required String name,
  required String placeholder,
  String value = '',
  String type = 'text',
  String cls = 'form-control form-control-lg',
  void Function(String value)? onInput,
}) {
  final element = web.document.createElement('input') as web.HTMLInputElement
    ..type = type
    ..name = name
    ..placeholder = placeholder
    ..className = cls
    ..value = value;
  if (onInput != null) {
    element.onInput.listen((_) => onInput(element.value));
  }
  return element;
}

/// A `<textarea>` bound the same way as [input].
web.HTMLTextAreaElement textarea({
  required String placeholder,
  String? name,
  String value = '',
  int rows = 8,
  String cls = 'form-control form-control-lg',
  void Function(String value)? onInput,
}) {
  final element =
      web.document.createElement('textarea') as web.HTMLTextAreaElement
        ..placeholder = placeholder
        ..rows = rows
        ..className = cls
        ..value = value;
  if (name != null) element.name = name;
  if (onInput != null) {
    element.onInput.listen((_) => onInput(element.value));
  }
  return element;
}

/// `<ul class="error-messages">`, or nothing when there is nothing to say.
///
/// Rendered only when there are errors: the E2E contract treats the list
/// being visible as "an error was shown".
web.HTMLElement? errorList(List<String> lines) => lines.isEmpty
    ? null
    : h(
        'ul',
        cls: 'error-messages',
        children: [for (final line in lines) h('li', children: line)],
      );

/// Builds the DOM for sanitised Markdown.
List<web.Node> markdownNodes(List<SafeNode> nodes) => [
  for (final node in nodes)
    switch (node) {
      SafeText(:final text) => web.document.createTextNode(text),
      SafeElement(:final tag, :final attributes, :final children) => h(
        tag,
        attrs: attributes,
        children: markdownNodes(children),
      ),
    },
];

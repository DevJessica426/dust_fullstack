import 'package:markdown/markdown.dart' as md;

import 'format.dart';

/// Markdown turned into a tree that is safe to put in the page.
///
/// The usual approach — render Markdown to an HTML string, then sanitise the
/// string, then assign it to `innerHTML` — trusts two parsers to agree about
/// what the string means. This never produces a string: it parses the
/// Markdown to an AST and rebuilds only the elements and attributes on an
/// allowlist, so the DOM builder receives structure, not markup.
///
/// Raw HTML in the source (`<script>`, `<img onerror=...>`) is parsed by the
/// Markdown library as text, and text is what it stays: it shows up in the
/// article as the characters the author typed.
sealed class SafeNode {
  const SafeNode();
}

final class SafeText extends SafeNode {
  const SafeText(this.text);

  final String text;

  @override
  String toString() => 'SafeText($text)';
}

final class SafeElement extends SafeNode {
  const SafeElement(this.tag, this.attributes, this.children);

  final String tag;
  final Map<String, String> attributes;
  final List<SafeNode> children;

  @override
  String toString() => 'SafeElement($tag, $attributes, $children)';
}

/// Elements that may appear, and the attributes each may keep.
const _allowed = <String, Set<String>>{
  'p': {},
  'br': {},
  'hr': {},
  'h1': {},
  'h2': {},
  'h3': {},
  'h4': {},
  'h5': {},
  'h6': {},
  'em': {},
  'strong': {},
  'del': {},
  'blockquote': {},
  'ul': {},
  'ol': {'start'},
  'li': {},
  'pre': {},
  'code': {'class'},
  'a': {'href', 'title'},
  'img': {'src', 'alt', 'title'},
  'table': {},
  'thead': {},
  'tbody': {},
  'tr': {},
  'th': {'align'},
  'td': {'align'},
};

/// Parses [source] as GitHub-flavoured Markdown into a safe tree.
List<SafeNode> renderMarkdown(String source) {
  final document = md.Document(
    extensionSet: md.ExtensionSet.gitHubWeb,
    // Text nodes keep the characters the author typed; the DOM escapes them
    // when they are inserted as text. Encoding here would show `&amp;`.
    encodeHtml: false,
  );
  return _clean(document.parse(source));
}

List<SafeNode> _clean(List<md.Node> nodes) => [
  for (final node in nodes) ..._cleanOne(node),
];

Iterable<SafeNode> _cleanOne(md.Node node) sync* {
  switch (node) {
    case md.Text(:final text):
      yield SafeText(text);
    case md.Element(:final tag, :final children, :final attributes):
      final kept = _allowed[tag];
      final inner = _clean(children ?? const []);
      if (kept == null) {
        // Not on the list: drop the element, keep what it said.
        yield* inner;
        return;
      }
      yield SafeElement(tag, _attributes(tag, kept, attributes), inner);
    default:
      final text = node.textContent;
      if (text.isNotEmpty) yield SafeText(text);
  }
}

Map<String, String> _attributes(
  String tag,
  Set<String> kept,
  Map<String, String> attributes,
) {
  final result = <String, String>{};
  for (final MapEntry(:key, :value) in attributes.entries) {
    if (!kept.contains(key)) continue;
    switch (key) {
      case 'href':
        if (isSafeUrl(value)) result[key] = value;
      case 'src':
        if (isSafeUrl(value, allowMailto: false)) result[key] = value;
      case 'class':
        // Only the `language-xyz` hint a fenced code block carries.
        if (RegExp(r'^language-[\w+-]+$').hasMatch(value)) result[key] = value;
      case 'align':
        if (const {'left', 'right', 'center'}.contains(value)) {
          result[key] = value;
        }
      case 'start':
        if (int.tryParse(value) != null) result[key] = value;
      default:
        result[key] = value;
    }
  }
  if (tag == 'a' && result.containsKey('href')) {
    // Links in an article leave the app; they get no window.opener.
    result['rel'] = 'noopener noreferrer nofollow';
  }
  return result;
}

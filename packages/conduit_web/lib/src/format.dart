import 'package:conduit_shared/conduit_shared.dart';

/// Where the smiley lives when a user has no image.
const defaultAvatar = '/default-avatar.svg';

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', //
  'August', 'September', 'October', 'November', 'December',
];

/// `January 20, 2026`, in the reader's own time zone.
String formatDate(DateTime date) {
  final local = date.toLocal();
  return '${_months[local.month - 1]} ${local.day}, ${local.year}';
}

/// An image URL that is safe to put in `src`, or the default avatar.
///
/// Anyone can set their image to anything through the API, so the value is
/// treated as hostile: only `http(s)` and same-origin paths are used. A
/// `javascript:` or `data:` URL, or text that was never a URL, gets the
/// smiley instead. The value is always assigned as a DOM property, never
/// spliced into markup, so a quote in it cannot open an attribute.
String avatarUrl(String? image) {
  final url = image?.trim() ?? '';
  return isSafeUrl(url, allowMailto: false) && url.isNotEmpty
      ? url
      : defaultAvatar;
}

/// Whether [url] may be followed or loaded.
///
/// Absolute URLs must be `http`, `https` (or `mailto` for links); relative
/// ones must be paths, not protocol-relative `//host`. Control characters and
/// whitespace are refused outright, since browsers strip them before reading
/// the scheme — `java\tscript:` is still JavaScript to them.
bool isSafeUrl(String url, {bool allowMailto = true}) {
  if (url.isEmpty) return false;
  if (url.codeUnits.any((unit) => unit <= 0x20 || unit == 0x7f)) return false;
  // A real URL percent-encodes these. Seeing one raw means someone is trying
  // to close an attribute somewhere downstream.
  if (url.contains(RegExp('["\'<>`]'))) return false;
  if (url.startsWith('//')) return false;
  if (url.startsWith('/') || url.startsWith('#')) return true;

  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  if (!uri.hasScheme) return !url.contains(':');
  return switch (uri.scheme.toLowerCase()) {
    'http' || 'https' => true,
    'mailto' => allowMailto,
    _ => false,
  };
}

/// What an error list says, one line per problem.
///
/// Field errors read as "`email` has already been taken"; failures with no
/// field of their own — no network, a server fault — are shown as the bare
/// message, since "network Unable to connect" helps nobody.
List<String> errorLines(ApiErrors errors) => [
  for (final MapEntry(:key, :value) in errors.errors.entries)
    for (final problem in value) _line(key, problem),
];

const _unkeyed = {'network', 'server', 'message', 'error', 'resource'};

String _line(String key, String problem) {
  if (_unkeyed.contains(key)) return problem;
  if (key == 'credentials') return 'email or password is $problem';
  return '$key $problem';
}

/// The pages a pager shows around [current]: the first, the last, and a
/// window of two either side, with `null` where a run of pages is elided.
List<int?> pageWindow(int current, int pages) {
  if (pages <= 1) return const [];
  final shown = <int>{
    1,
    pages,
    for (var page = current - 2; page <= current + 2; page++)
      if (page >= 1 && page <= pages) page,
  }.toList()..sort();

  final window = <int?>[];
  for (final page in shown) {
    if (window.isNotEmpty && page - (window.last ?? page) > 1) window.add(null);
    window.add(page);
  }
  return window;
}

/// How many pages [total] items fill at [perPage] each.
int pageCount(int total, int perPage) => (total + perPage - 1) ~/ perPage;

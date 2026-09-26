import 'package:conduit_shared/conduit_shared.dart';
import 'package:web/web.dart' as web;

import '../dom.dart';
import '../format.dart';
import '../routes.dart';
import 'page.dart';

/// `/editor` and `/editor/:slug`: write a new article or edit one.
final class EditorPage extends Page {
  EditorPage(super.app, this.slug);

  /// The article being edited, or null for a new one.
  final String? slug;

  final _errorsHost = h('div');
  final _tagsHost = h('div', cls: 'tag-list');
  final _tags = <String>[];
  var _busy = false;

  late final _title = input(name: 'title', placeholder: 'Article Title');
  late final _description = input(
    name: 'description',
    placeholder: "What's this article about?",
    cls: 'form-control',
  );
  late final _body = textarea(
    name: 'body',
    placeholder: 'Write your article (in markdown)',
    cls: 'form-control',
  );
  late final _tagInput = input(
    name: 'tags',
    placeholder: 'Enter tags',
    cls: 'form-control',
  );
  late final _publish = h(
    'button',
    cls: 'btn btn-lg pull-xs-right btn-primary',
    attrs: {'type': 'button'},
    children: 'Publish Article',
    onClick: (_) => _save(),
  );

  @override
  late final web.HTMLElement root = h(
    'div',
    cls: 'editor-page',
    children: h(
      'div',
      cls: 'container page',
      children: h(
        'div',
        cls: 'row',
        children: h(
          'div',
          cls: 'col-md-10 offset-md-1 col-xs-12',
          children: [_errorsHost, _form()],
        ),
      ),
    ),
  );

  web.HTMLElement _form() {
    _tagInput.onKeyDown.listen((event) {
      if (event.key != 'Enter' && event.key != ',') return;
      // Enter adds a tag; it must not submit the form.
      event.preventDefault();
      _addTag(_tagInput.value);
      _tagInput.value = '';
    });

    web.HTMLElement group(Object? children) =>
        h('fieldset', cls: 'form-group', children: children);

    final form = h(
      'form',
      children: h(
        'fieldset',
        children: [
          group(_title),
          group(_description),
          group(_body),
          group([_tagInput, _tagsHost]),
          _publish,
        ],
      ),
    );
    form.onSubmit.listen((event) => event.preventDefault());
    return form;
  }

  @override
  Future<void> start() async {
    if (!await requireSignedIn()) return;
    final slug = this.slug;
    if (slug == null) return;

    _setBusy(true);
    try {
      final article = (await app.api.article(slug)).article;
      if (disposed) return;
      _title.value = article.title;
      _description.value = article.description;
      _body.value = article.body;
      _tags
        ..clear()
        ..addAll(article.tagList);
      _renderTags();
    } on Object catch (error) {
      if (disposed) return;
      _showErrors(errorLines(ConduitFailure.from(error).errors));
    } finally {
      _setBusy(false);
    }
  }

  void _addTag(String raw) {
    final tag = raw.trim();
    if (tag.isEmpty || _tags.contains(tag)) return;
    _tags.add(tag);
    _renderTags();
  }

  void _renderTags() => replace(_tagsHost, [
    for (final tag in _tags)
      h(
        'span',
        cls: 'tag-default tag-pill',
        children: [
          h(
            'i',
            cls: 'ion-close-round',
            attrs: {'role': 'button', 'aria-label': 'Remove $tag'},
            onClick: (_) {
              _tags.remove(tag);
              _renderTags();
            },
          ),
          ' $tag',
        ],
      ),
  ]);

  Future<void> _save() async {
    if (_busy) return;
    // A tag typed but not yet confirmed with Enter still counts.
    _addTag(_tagInput.value);
    _tagInput.value = '';

    final draft = NewArticle(
      title: _title.value,
      description: _description.value,
      body: _body.value,
      tagList: List.of(_tags),
    );
    if (draft.validate() case Invalid(:final errors)) {
      _showErrors([for (final e in errors) '${e.field} ${e.message}']);
      return;
    }

    _setBusy(true);
    try {
      final slug = this.slug;
      final saved = slug == null
          ? await app.api.createArticle(NewArticleRequest(article: draft))
          : await app.api.updateArticle(
              slug,
              UpdateArticleRequest(
                article: UpdateArticle(
                  title: draft.title,
                  description: draft.description,
                  body: draft.body,
                  // Always sent, even empty: `[]` is how the API is told to
                  // remove every tag, and leaving it out would keep them.
                  tagList: draft.tagList,
                ),
              ),
            );
      if (disposed) return;
      app.go(articleHref(saved.article.slug));
    } on Object catch (error) {
      if (disposed) return;
      _showErrors(errorLines(ConduitFailure.from(error).errors));
    } finally {
      _setBusy(false);
    }
  }

  void _setBusy(bool busy) {
    _busy = busy;
    _publish.toggleAttribute('disabled', busy);
  }

  void _showErrors(List<String> lines) =>
      replace(_errorsHost, errorList(lines));
}

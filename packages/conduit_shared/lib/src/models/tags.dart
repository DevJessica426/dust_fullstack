import 'package:dust_dart/serde.dart';

part 'tags.g.dart';

/// `{"tags": [...]}`, most used first.
@Derive([ToString(), Eq(), Serialize(), Deserialize()])
final class TagsList with _$TagsList {
  const TagsList({required this.tags});

  factory TagsList.fromJson(Map<String, Object?> json) =>
      _$TagsListFromJson(json);

  final List<String> tags;
}

/// Every failure the API reports: `{"errors": {"<field>": ["<problem>"]}}`.
///
/// The key names what the problem is about — a request field for a 422, or
/// the resource (`article`, `comment`, `profile`, `token`) otherwise.
@Derive([ToString(), Eq(), Serialize(), Deserialize()])
final class ApiErrors with _$ApiErrors {
  const ApiErrors({required this.errors});

  factory ApiErrors.fromJson(Map<String, Object?> json) =>
      _$ApiErrorsFromJson(json);

  /// One problem about one thing.
  factory ApiErrors.single(String key, String problem) => ApiErrors(
        errors: {
          key: [problem],
        },
      );

  final Map<String, List<String>> errors;

  /// `title can't be blank; body can't be blank` — for a banner or a log.
  List<String> get messages => [
        for (final MapEntry(:key, :value) in errors.entries)
          for (final problem in value) '$key $problem',
      ];
}

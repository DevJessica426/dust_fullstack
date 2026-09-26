import 'package:dust_dart/serde.dart';

import 'profile.dart';

part 'comment.g.dart';

// TODO(dust#590): `@Validate` takes string literals only; see user.dart.

/// A comment on an article.
@Derive([ToString(), Eq(), Serialize(), Deserialize()])
final class Comment with _$Comment {
  const Comment({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.body,
    required this.author,
  });

  factory Comment.fromJson(Map<String, Object?> json) =>
      _$CommentFromJson(json);

  final int id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String body;
  final Profile author;
}

/// `{"comment": {...}}`.
@Derive([ToString(), Eq(), Serialize(), Deserialize()])
final class CommentEnvelope with _$CommentEnvelope {
  const CommentEnvelope({required this.comment});

  factory CommentEnvelope.fromJson(Map<String, Object?> json) =>
      _$CommentEnvelopeFromJson(json);

  final Comment comment;
}

/// `{"comments": [...]}`, oldest first.
@Derive([ToString(), Eq(), Serialize(), Deserialize()])
final class CommentsList with _$CommentsList {
  const CommentsList({required this.comments});

  factory CommentsList.fromJson(Map<String, Object?> json) =>
      _$CommentsListFromJson(json);

  final List<Comment> comments;
}

/// What `POST /articles/{slug}/comments` accepts.
@Derive([ToString(), Serialize(), Deserialize(), Validate()])
final class NewComment with _$NewComment {
  const NewComment({required this.body});

  factory NewComment.fromJson(Map<String, Object?> json) =>
      _$NewCommentFromJson(json);

  @Validate(regex: r'\S', message: "can't be blank")
  @Validate(
    length: Length(max: 5000),
    message: 'is too long (maximum is 5000 characters)',
  )
  final String body;
}

/// `{"comment": {"body": ...}}`.
@Derive([Serialize(), Deserialize()])
final class NewCommentRequest with _$NewCommentRequest {
  const NewCommentRequest({required this.comment});

  factory NewCommentRequest.fromJson(Map<String, Object?> json) =>
      _$NewCommentRequestFromJson(json);

  final NewComment comment;
}

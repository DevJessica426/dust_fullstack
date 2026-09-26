import 'dart:convert';

import 'package:conduit_shared/conduit_shared.dart';
import 'package:dust_dart/db.dart';
import 'package:dust_server/server.dart';
import 'package:postgres/postgres.dart' as pg;

/// A failure in RealWorld's shape: `{"errors": {"<key>": ["<problem>"]}}`.
///
/// Handlers return it as `Err(ApiError...)`, and dust_server answers with
/// [intoResponse] — the body is the shared [ApiErrors] model, the same type
/// the browser decodes it into.
final class ApiError implements IntoResponse {
  const ApiError(this.status, this.errors);

  ApiError.of(this.status, String key, String problem)
    : errors = {
        key: [problem],
      };

  /// 404, keyed by the resource that is missing: `article`, `profile`, ...
  ApiError.notFound(String resource) : this.of(404, resource, 'not found');

  /// 403, keyed by the resource the caller may not change.
  ApiError.forbidden(String resource) : this.of(403, resource, 'forbidden');

  /// 409, keyed by the field whose value belongs to someone else.
  ApiError.taken(String field) : this.of(409, field, 'has already been taken');

  /// 422 with every failed rule, grouped by field.
  factory ApiError.invalid(Iterable<ValidationError> failures) {
    final errors = <String, List<String>>{};
    for (final failure in failures) {
      (errors[failure.field] ??= []).add(failure.message);
    }
    return ApiError(422, errors);
  }

  final int status;
  final Map<String, List<String>> errors;

  @override
  Response intoResponse() =>
      jsonResponse(ApiErrors(errors: errors), status: status);

  @override
  String toString() => 'ApiError($status, $errors)';
}

/// Runs a `Validate()` model's rules, as a 422 when any fail.
ApiError? invalid(ValidationResult result) =>
    result.isValid ? null : ApiError.invalid(result.errors);

// TODO(dust#570): on Dust 0.3, detect the duplicate with
// `error.kind == SqlxErrorKind.uniqueViolation`. The constraint's name, which
// says which field is taken, still has to come from `pg.ServerException`.
/// The unique index a failed write collided with, if that is what failed.
///
/// SQLSTATE `23505` is `unique_violation` in every PostgreSQL version and
/// locale, which makes it exact where matching on the message would not be.
String? uniqueViolation(SqlxError error) {
  final cause = error.cause;
  if (cause is pg.ServerException && cause.code == '23505') {
    return cause.constraintName ?? '';
  }
  return null;
}

// TODO(dust#571): on Dust 0.3, throw `Rejection.fromSqlxError(error)` here.
// Its 409 is `{"error": "Conflict"}`, so `ApiError.taken`, which names the
// field, stays for duplicates.
extension ResultOrThrow<T> on Result<T, SqlxError> {
  /// The value, or the database error thrown.
  ///
  /// A thrown error that is not a `Rejection` becomes an opaque 500 in
  /// dust_server, with the real error sent to the router's `onError` rather
  /// than to the client. That is exactly right for "the database is down",
  /// which no handler can do anything about.
  T get orThrow => unwrapOrElse((error) => throw error);
}

/// Rewrites dust_server's own failures into RealWorld's error shape.
///
/// Handlers already answer with [ApiError]. What this catches is everything
/// raised before a handler runs — a missing token, malformed JSON, an unknown
/// route — which dust_server encodes as `{"error": "...", "fields": {...}}`.
/// Doing it in a layer means no failure path is missed, including the
/// router's own 404 and 405.
final class RealWorldErrors implements Layer {
  const RealWorldErrors();

  @override
  Middleware toMiddleware() {
    return (Handler inner) {
      return (Request request) async {
        final response = await inner(request);
        if (response.statusCode < 400) return response;
        if (!(response.mimeType?.contains('json') ?? false)) return response;

        final text = await response.readAsString();
        final Object? decoded;
        try {
          decoded = jsonDecode(text);
        } on FormatException {
          return response.change(body: text);
        }

        final errors = switch (decoded) {
          {'errors': Map<String, Object?> _} => null, // already our shape
          {'fields': final Map<String, Object?> fields}
              when fields.isNotEmpty =>
            fields,
          {'error': final String message} => {
            _keyFor(response.statusCode): [message],
          },
          _ => null,
        };
        if (errors == null) return response.change(body: text);

        return Response(
          response.statusCode,
          body: jsonEncode({'errors': errors}),
          headers: {...response.headers, 'content-type': 'application/json'}
            ..remove('content-length'),
        );
      };
    };
  }

  /// What a failure with no field of its own is about.
  static String _keyFor(int status) => switch (status) {
    401 => 'token',
    403 || 404 => 'resource',
    405 => 'method',
    400 || 413 || 415 || 422 => 'body',
    _ => 'server',
  };
}

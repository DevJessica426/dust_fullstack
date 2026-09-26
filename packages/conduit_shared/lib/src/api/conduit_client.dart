import 'package:dio/dio.dart';

import '../models/tags.dart';
import 'conduit_api.dart';

/// A [ConduitApi] with the session attached.
///
/// RealWorld authenticates with `Authorization: Token <jwt>` — not `Bearer` —
/// so the header is added here, once, for every call made while [token] is
/// set. Both the browser app and the server's tests use this, which is what
/// keeps them honest about the same contract.
final class ConduitClient {
  ConduitClient({required String baseUrl, this.token, Dio? dio})
      : dio = dio ?? Dio(BaseOptions(baseUrl: baseUrl)) {
    this.dio.options.baseUrl = baseUrl;
    this.dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              final current = token;
              if (current != null) {
                options.headers['authorization'] = 'Token $current';
              }
              handler.next(options);
            },
          ),
        );
    api = ConduitApi(this.dio);
  }

  /// The transport, exposed for tests and for closing.
  final Dio dio;

  /// The generated client.
  late final ConduitApi api;

  /// The signed-in user's JWT, or null when signed out.
  String? token;

  /// Releases the underlying connections.
  void close() => dio.close(force: true);
}

/// A request the API refused, with what it said about why.
final class ConduitFailure implements Exception {
  const ConduitFailure(this.status, this.errors);

  /// Reads the failure out of whatever a [ConduitApi] call threw.
  ///
  /// A response in the API's `{"errors": ...}` shape is decoded into
  /// [ApiErrors]; anything else — no network, a proxy's HTML error page — is
  /// reported under `network` so a form still has something to show.
  factory ConduitFailure.from(Object error) {
    if (error is ConduitFailure) return error;
    if (error is DioException) {
      final response = error.response;
      final data = response?.data;
      if (data is Map && data['errors'] is Map) {
        try {
          return ConduitFailure(
            response?.statusCode ?? 0,
            ApiErrors.fromJson(Map<String, Object?>.from(data)),
          );
        } on Object {
          // Fall through to the generic answer below.
        }
      }
      return ConduitFailure(
        response?.statusCode ?? 0,
        ApiErrors.single(
          'network',
          response == null
              ? 'could not reach the server'
              : 'answered ${response.statusCode}',
        ),
      );
    }
    return ConduitFailure(0, ApiErrors.single('error', error.toString()));
  }

  /// The HTTP status, or 0 when no response arrived.
  final int status;

  /// What the server said.
  final ApiErrors errors;

  @override
  String toString() => 'ConduitFailure($status, ${errors.messages})';
}

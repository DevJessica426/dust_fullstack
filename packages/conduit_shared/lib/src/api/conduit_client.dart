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
  ConduitClient({required String baseUrl, String? token, Dio? dio})
    : dio = dio ?? Dio(BaseOptions(baseUrl: baseUrl)) {
    this.dio.options.baseUrl = baseUrl;
    this.token = token;
    api = ConduitApi(this.dio);
  }

  /// The transport, exposed for tests and for closing.
  final Dio dio;

  /// The generated client.
  late final ConduitApi api;

  String? _token;

  /// The signed-in user's JWT, or null when signed out.
  ///
  /// Kept in Dio's default headers rather than added by an interceptor, so a
  /// request carries it from the moment it is created: Dio runs interceptors
  /// on later turns of the event loop, and anything inspecting the request
  /// before then would see it unauthenticated.
  String? get token => _token;

  set token(String? value) {
    _token = value;
    if (value == null) {
      dio.options.headers.remove('authorization');
    } else {
      dio.options.headers['authorization'] = 'Token $value';
    }
  }

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
        response == null
            ? ApiErrors.single(network, 'Unable to connect to the server')
            : ApiErrors.single(
                'server',
                'answered ${response.statusCode} unexpectedly',
              ),
      );
    }
    // Not an HTTP failure at all: a 200 whose body was empty or not the
    // expected shape. Status 0, like a network failure, because the server
    // said nothing usable about *who* the caller is.
    return ConduitFailure(
      0,
      ApiErrors.single('server', 'sent a response the app could not read'),
    );
  }

  /// The key a failure is reported under when no response arrived at all.
  static const network = 'network';

  /// Whether the server answered with a 4xx: the request, or the caller's
  /// credentials, were refused. A 5xx or no answer at all is not a refusal.
  bool get isClientError => status >= 400 && status < 500;

  /// The HTTP status, or 0 when no response arrived.
  final int status;

  /// What the server said.
  final ApiErrors errors;

  @override
  String toString() => 'ConduitFailure($status, ${errors.messages})';
}

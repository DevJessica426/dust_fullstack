import 'dart:convert';
import 'dart:io';

/// Everything the server reads from its environment.
///
/// | Variable | Default |
/// | :--- | :--- |
/// | `DATABASE_URL` | `postgres://conduit:conduit@localhost:5432/conduit?sslmode=disable` |
/// | `PORT` | `8080` |
/// | `JWT_SECRET` | random per process — tokens die on restart |
/// | `WEB_ROOT` | `packages/conduit_web/build/web`, if it exists |
final class ServerConfig {
  const ServerConfig({
    required this.databaseUrl,
    required this.port,
    required this.jwtSecret,
    required this.webRoot,
  });

  factory ServerConfig.fromEnvironment([Map<String, String>? environment]) {
    final env = environment ?? Platform.environment;
    final secret = env['JWT_SECRET'];
    final webRoot = env['WEB_ROOT'] ?? _defaultWebRoot();

    return ServerConfig(
      databaseUrl:
          env['DATABASE_URL'] ??
          'postgres://conduit:conduit@localhost:5432/conduit?sslmode=disable',
      port: int.tryParse(env['PORT'] ?? '') ?? 8080,
      jwtSecret: secret == null ? null : utf8.encode(secret),
      webRoot: webRoot != null && Directory(webRoot).existsSync()
          ? webRoot
          : null,
    );
  }

  final String databaseUrl;
  final int port;

  /// Null means "make one up": fine for development, wrong for production.
  final List<int>? jwtSecret;

  /// The built web app to serve, or null to serve the API alone.
  final String? webRoot;

  /// The database URL with its password masked, for logs.
  String get redactedDatabaseUrl {
    final uri = Uri.tryParse(databaseUrl);
    if (uri == null || !uri.userInfo.contains(':')) return databaseUrl;
    final user = uri.userInfo.split(':').first;
    return uri.replace(userInfo: '$user:***').toString();
  }

  static String? _defaultWebRoot() {
    for (final candidate in const [
      'packages/conduit_web/build/web',
      '../conduit_web/build/web',
    ]) {
      if (Directory(candidate).existsSync()) return candidate;
    }
    return null;
  }
}

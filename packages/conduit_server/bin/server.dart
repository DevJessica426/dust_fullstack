import 'dart:async';
import 'dart:io';

import 'package:conduit_server/conduit_server.dart';
import 'package:dust_server/server.dart';

/// Connects, migrates, serves; drains on SIGINT or SIGTERM.
Future<void> main() async {
  final config = ServerConfig.fromEnvironment();

  final database = ConduitDatabase.connect(config.databaseUrl);
  // Before serving: a request arriving while the schema is still being
  // applied is a race you only lose in production.
  final migrated = await database.migrate();
  if (migrated case Err(:final error)) {
    stderr.writeln('migration failed on ${config.redactedDatabaseUrl}: $error');
    await database.connection.close();
    exitCode = 1;
    return;
  }

  final secret = config.jwtSecret;
  if (secret == null) {
    stderr.writeln(
      'JWT_SECRET is not set: using a random one, so tokens stop working '
      'when the server restarts.',
    );
  }
  final auth = Auth(
    jwt: secret == null ? JwtCodec.ephemeral() : JwtCodec(secret),
  );

  final server = await serve(
    buildApp(
      database: database,
      auth: auth,
      webRoot: config.webRoot,
      accessLog: (record) => stdout.writeln(
        '${record.method} ${record.path} ${record.status} '
        '${record.duration.inMilliseconds}ms',
      ),
    ),
    InternetAddress.anyIPv4,
    config.port,
  );

  stdout
    ..writeln('Conduit listening on http://localhost:${server.port}')
    ..writeln('  api       http://localhost:${server.port}/api')
    ..writeln('  web app   ${config.webRoot ?? '(not built — see README)'}')
    ..writeln('  database  ${config.redactedDatabaseUrl}');

  await Future.any([
    ProcessSignal.sigint.watch().first,
    if (!Platform.isWindows) ProcessSignal.sigterm.watch().first,
  ]);
  stdout.writeln('draining');
  await server.close(drain: const Duration(seconds: 10));
  await database.connection.close();
}

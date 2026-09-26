import 'package:dust_dart/db.dart';
import 'package:dust_db_postgres/dust_db_postgres.dart';

part 'database.g.dart';

/// The Conduit database: connecting, migrating, closing.
///
/// `dust db build` embeds `migrations/` into the generated facade, so a
/// deployed server carries its schema with it and [migrate] brings any
/// database up to date under an advisory lock — several instances can start
/// at once without racing to apply the same file.
@SqlxDatabase(type: SqlxDatabaseType.postgres, migrations: './migrations')
abstract class ConduitDatabase implements DatabaseClient {
  /// Opens a pool on [url], e.g.
  /// `postgres://conduit:conduit@localhost:5432/conduit?sslmode=disable`.
  factory ConduitDatabase.connect(String url, {PgConnectOptions? options}) =
      _$ConduitDatabase.connect;

  @override
  Connection get connection;
}

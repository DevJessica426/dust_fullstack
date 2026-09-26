/// The RealWorld "Conduit" API on dust_server and PostgreSQL.
///
/// ```text
/// lib/src/
///   app.dart            buildApp: layers, /api, the web app fallback
///   config.dart         environment variables
///   auth/               JWT, Argon2id passwords, the Token extractors
///   db/                 migrations facade, rows, DAOs (dust db build)
///   http/               RealWorld error shape, row -> wire model mapping
///   features/           one file of handlers per resource
/// ```
library;

export 'src/app.dart';
export 'src/auth/jwt.dart';
export 'src/auth/passwords.dart';
export 'src/auth/viewer.dart';
export 'src/config.dart';
export 'src/db/database.dart';
export 'src/features/articles.dart' show normalizeTags, slugify;
export 'src/http/errors.dart';

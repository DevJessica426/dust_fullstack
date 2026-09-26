/// The Conduit wire contract, shared by `conduit_server` and `conduit_web`.
///
/// Every model here is a Dust `@Derive` class: `dust build` writes its JSON,
/// equality, `copyWith`, and validation into the neighbouring `.g.dart`. The
/// server answers with these types and the browser decodes into them, so a
/// renamed field is a compile error on both sides rather than a blank page.
library;

export 'package:dust_dart/derive.dart'
    show Invalid, Valid, ValidationError, ValidationResult;

export 'src/api/conduit_api.dart';
export 'src/api/conduit_client.dart';
export 'src/models/article.dart';
export 'src/models/comment.dart';
export 'src/models/profile.dart';
export 'src/models/tags.dart';
export 'src/models/user.dart';

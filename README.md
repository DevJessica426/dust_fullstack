# Conduit in Dart, built with Dust

A full-stack clone of **[RealWorld "Conduit"](https://github.com/gothinkster/realworld)**
(the Medium-style demo app implemented in React, Angular, Go, Rust, Django,
Spring and many more) written in **Dart from the database to the browser**, using
**[Dust](https://github.com/y3l1n4ung/dust)**, Rust-powered code generation for
Dart.

| Layer | Package | Built with |
| :--- | :--- | :--- |
| Wire contract | [`conduit_shared`](packages/conduit_shared) | `dust_dart` models (`@Derive` serde, validation, `copyWith`) and a Dust-generated `@HttpClient` |
| API server | [`conduit_server`](packages/conduit_server) | `dust_server` routing and extraction, `dust_db_postgres` DAOs, PostgreSQL |
| Browser app | [`conduit_web`](packages/conduit_web) | Dart compiled to JavaScript with `package:web`, calling the generated client |

The server answers with the same Dust models that the browser decodes, so a
renamed field is a compile error on both sides instead of a blank page.

## Is it really a RealWorld clone?

Every RealWorld implementation is checked against the project's shared test
suites, and this one passes both. The API suite is used unchanged; three E2E
specs get one line so their mocks use the suite's own `API_BASE` setting rather
than a hard-coded public URL (see [`e2e/README.md`](e2e/README.md)):

| Suite | What it drives | Result |
| :--- | :--- | :--- |
| [RealWorld API spec](spec/realworld-hurl) (Hurl) | the HTTP API, over the network | **13/13 files, 154/154 requests** |
| [RealWorld front-end E2E](e2e) (Playwright) | the Dart app in Chromium, against this server | **139/139 tests**, [5 full runs in a row](#end-to-end-tests) |
| This repo's Dart tests | models, generated client, server over PostgreSQL, web logic | **101 tests** (28 shared, 57 server, 16 web) |

Because both halves follow the shared contract, they are meant to mix with
other implementations (not exercised here beyond the two suites above):

- **Other RealWorld front ends can use this server.** The API is at `/api`, CORS
  is open, and auth uses the standard `Authorization: Token <jwt>` header.
- **This front end can target another RealWorld server.** Set
  `<meta name="conduit-api" content="https://api.realworld.show/api">` in
  [`index.html`](packages/conduit_web/web/index.html).

## Layout

```text
pubspec.yaml                  pub workspace: the three packages below
packages/
  conduit_shared/             the contract
    lib/src/models/*.dart     @Derive models  ->  *.g.dart (dust build)
    lib/src/api/conduit_api.dart
                              @HttpClient ConduitApi  ->  conduit_api.g.dart
  conduit_server/
    migrations/               PostgreSQL schema, embedded by dust db build
    .dust_sql/                committed query metadata for offline SQL checks
    lib/src/db/               FromRow rows (dust build), @SqlxDao repos (dust db build)
    lib/src/features/         handlers: users, profiles, articles, comments
    lib/src/auth/             HS256 JWT, Argon2id passwords, Token extractors
    lib/src/http/errors.dart  RealWorld {"errors": {...}} shape, as a layer
    bin/server.dart           connect, migrate, serve, drain on SIGTERM
    bin/seed.dart             demo data, written through the typed client
  conduit_web/
    web/                      index.html, the shared RealWorld theme, icons
    lib/src/pages/            home, auth, editor, article, profile, settings
    lib/src/markdown.dart     Markdown -> allow-listed tree (never innerHTML)
spec/realworld-hurl/          official API conformance suite (vendored, MIT)
e2e/                          official front-end E2E suite (vendored, MIT)
tool/                         build_web.sh, conformance.sh, e2e.sh
```

## Running it

You need **Dart 3.9+** and **PostgreSQL 14+**. The generated `*.g.dart` files are
committed, so the Dust CLI is only needed if you change a model or a query.

```bash
# 1. A database (any PostgreSQL works; this is a local one)
createuser -P conduit            # password: conduit
createdb -O conduit conduit

# 2. Dependencies, and the web app
dart pub get
tool/build_web.sh                # dart compile js -> packages/conduit_web/build/web

# 3. The server: applies migrations, then serves the API and the web app
JWT_SECRET=change-me-to-32-or-more-random-bytes!! \
  dart run packages/conduit_server/bin/server.dart

# 4. Optional: demo users and articles (johndoe / janedoe / samsmith, password123)
dart run packages/conduit_server/bin/seed.dart
```

Open <http://localhost:8080>.

| Variable | Default |
| :--- | :--- |
| `DATABASE_URL` | `postgres://conduit:conduit@localhost:5432/conduit?sslmode=disable` |
| `PORT` | `8080` |
| `JWT_SECRET` | random per process, so tokens stop working on restart |
| `WEB_ROOT` | `packages/conduit_web/build/web`, if it exists |

## Working on it

Dust owns every `*.g.dart` file. After changing a model, a query, or a migration:

```bash
dust build --root packages/conduit_shared
dust build --root packages/conduit_server
DUST_DATABASE_URL=postgres://conduit:conduit@localhost:5432/scratch?sslmode=disable \
  dust db build --root packages/conduit_server   # validates the SQL against PostgreSQL

dust check --root packages/conduit_shared                    # nothing stale
dust check --db --offline --root packages/conduit_server     # SQL, with no database
```

`dust db build` asks PostgreSQL to describe every `@Query` against the
migrated schema before it writes any code, so a misspelled column is a build
error. The results are cached in `.dust_sql/`, which is committed, so CI can
run the check with no database.

## Tests

```bash
dart analyze packages

dart test packages/conduit_shared     # models, validation, generated request mapping
dart test packages/conduit_web        # routes, markdown sanitising, formatting (VM)

# Server integration tests: a real server on a real socket over PostgreSQL,
# driven by the generated ConduitApi. The database is wiped.
CONDUIT_TEST_DATABASE_URL=postgres://conduit:conduit@localhost:5432/conduit_test?sslmode=disable \
  dart test packages/conduit_server --concurrency=1

tool/conformance.sh                   # RealWorld API suite, against a running server (needs hurl)
tool/e2e.sh                           # RealWorld E2E suite: builds, serves, seeds, runs (needs node)
```

### End-to-end tests

`tool/e2e.sh` runs all **139** tests of the official suite in `spa` mode (the
browser holds the JWT and calls the API itself). They cover auth, articles,
comments, feeds, pagination, settings, social features, null fields, error
handling with mocked 4xx/5xx and network failures, and XSS payloads. The final
build passed **139/139 in five consecutive full runs**, with retries turned
off.

Getting there found one real bug, described under
[unload-safe writes](#things-worth-knowing). Before that fix, "favorite a
preview, then immediately load another page" failed in 3 of 5 full runs. The
only change to the upstream suite is documented in [`e2e/README.md`](e2e/README.md).

| | |
| :--- | :--- |
| ![Home, signed in](docs/screenshots/home-signed-in.png) | ![Article with comments](docs/screenshots/article.png) |
| ![Editor](docs/screenshots/editor.png) | ![Profile](docs/screenshots/profile.png) |

## Things worth knowing

- **Errors use RealWorld's shape everywhere.** Handlers return
  `Err(ApiError.notFound('article'))`, which is the shared `ApiErrors` model.
  Failures raised before a handler runs (a missing token, malformed JSON, an
  unknown route) come from dust_server as `{"error": ...}` and are rewritten by
  one layer, [`RealWorldErrors`](packages/conduit_server/lib/src/http/errors.dart).
- **Uniqueness is enforced by the database.** Usernames and emails have
  case-insensitive unique indexes. A duplicate becomes a 409 from SQLSTATE
  `23505` and the constraint name, not from a SELECT that could race.
- **Tags are a `TEXT[]` column** with a GIN index, so an article keeps the tag
  order its author gave, and "filter by tag" is `tag_list @> ARRAY[$1]`.
- **PATCH semantics are explicit.** `PUT /user` and `PUT /articles/:slug` tell an
  absent key ("leave it") from `null` ("clear it", or a 422 for required
  fields). The generated deserializer can't make that distinction, so the
  handlers also read the raw keys.
- **The browser never uses `innerHTML`.** Every user-supplied string reaches the
  DOM as a text node or a property. Markdown is parsed to an AST and only
  allow-listed elements and URL schemes are rebuilt, so the E2E suite's XSS
  payloads render as plain text.
- **Unload-safe writes.** Dio doesn't start a request when it's called: every
  step of its interceptor chain is a `Future(...)`, a separate turn of the
  event loop, so a favorite clicked just before a reload could vanish before
  reaching the network. The browser app records each write synchronously as
  the generated client makes it, and sends writes with
  `fetch(..., {keepalive: true})`. On `pagehide` it flushes anything not yet
  sent, and if the page is restored afterwards the pending call gets that
  response instead of sending twice
  ([`unload_safe.dart`](packages/conduit_web/lib/src/unload_safe.dart)).
- **Offline-first assets.** The eight `ion-*` icons are drawn as CSS masks in
  [`icons.css`](packages/conduit_web/web/icons.css), and nothing is loaded from a
  CDN.

### Dust notes from building this

This was also a test drive of Dust 0.2.0 across all three layers. It was a
smooth experience, and these were the rough edges:

1. **SQLx alias markers don't work at runtime on PostgreSQL.** `count(*) AS
   "total!"` validates, and the generator reads the column as `total`, but
   `dust_db_postgres` indexes result columns by their literal name `total!`, so
   the read fails with *"result has no column"*. PostgreSQL's nullability
   inference was accurate enough here that no markers were needed.
2. `FromRow` has no direct `List<T>` field support. A `TEXT[]` column goes
   through a small `SqlxTryFrom` converter
   ([`TextArray`](packages/conduit_server/lib/src/db/rows.dart)).
3. `@Validate(regex:, message:)` must be string literals, not `const`
   references.
4. dust_server reads `fallback` only from the outermost router, so a JSON 404
   for unknown `/api/*` paths is carved out in the root fallback, next to the
   web app.
5. In a pub workspace, `dust build` runs per package (`--root packages/x`).

## Licenses

MIT. Vendored from the RealWorld project (MIT): the theme
[`styles.css`](packages/conduit_web/web/styles.css), the
[default avatar](packages/conduit_web/web/default-avatar.svg), the
[API suite](spec/realworld-hurl), and the [E2E suite](e2e/specs).

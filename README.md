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
    migrations/               SQLx reversible pairs (sqlx migrate add -r); Dust embeds the .up.sql
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
run the check with no database. Run `dust` against each package with `--root`:
at the workspace root it scans nothing and still reports success. (TODO
[dust#586]: a plain `dust build` / `dust check` at the root once it covers the
members. Give `--root` a path from the repository root, not `.` inside a
member: [dust#588].)

### Migrations

Migrations are SQLx reversible pairs, one table each, named the way
[`sqlx migrate add -r`](https://github.com/launchbadge/sqlx/tree/main/sqlx-cli)
names them:

```text
packages/conduit_server/migrations/
  20260926000001_create_users.up.sql      20260926000001_create_users.down.sql
  20260926000002_create_follows.up.sql    ...
```

```bash
# A new pair (or create the two files by hand)
sqlx migrate add -r --source packages/conduit_server/migrations add_user_location

# Embed it. --clean because Dust's build cache does not track migration
# files: without it an edited migration can be skipped (see below).
# TODO(dust#585): drop --clean once migrations are part of the cache key.
dust build --clean --root packages/conduit_server
DUST_DATABASE_URL=... dust db build --root packages/conduit_server

# Undo the latest applied migration(s) in development
DATABASE_URL=postgres://conduit:conduit@localhost:5432/conduit tool/db_revert.sh [count]
```

The server applies pending `.up.sql` files at startup through Dust, which
records them in `__dust_schema_migrations` and never runs a `.down.sql`.
[`tool/db_revert.sh`](tool/db_revert.sh) runs the matching down migration and
deletes that record in one transaction, so the next start re-applies it.
`sqlx migrate run` / `revert` also work on these files (verified with sqlx-cli
0.9: run, revert to version 0, run). SQLx keeps its own `_sqlx_migrations`
table, though, so use one tool per database.

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

### Dust findings

This was also a test drive of Dust 0.2.0, the latest release. Each item
below was reproduced on its own and checked against the open and closed
issues on [y3l1n4ung/dust](https://github.com/y3l1n4ung/dust/issues). Every
workaround in the code is marked with the issue it waits on;
`git grep -n 'TODO(dust'` lists them.

**Reported from this project**

1. **Nullability alias markers break at runtime** (both drivers;
   [dust#584]). `docs/usage/db.md` and [dust#501] have `count(*) AS "total!"`
   override nullability, and the generator emits `row.read<int>('total')`
   with the marker stripped. Neither `dust_db_postgres` nor `dust_db_sqlite3`
   strips it when indexing result columns, so the read fails. For
   `SELECT 42 AS "total!"`, Postgres says *`PostgreSQL result has no column
   total`* and SQLite says *`Column total is null`* (it isn't; it's 42). This
   project uses no markers.
2. **`dust db build` ignores edited migrations once its cache is warm**
   ([dust#585]). The cache key is the Dart library's source hash plus package
   config and tool (`matches_cache_metadata` in `dust_driver`); migration
   files aren't in it. After an edit, `dust db build` reports `cached: 5` and
   the generated `database.g.dart` still embeds the old SQL.
   `dust check --db --offline` then fails with a misleading *`missing entry
   for UsersRepo.insert`*. Only an online `dust check --db` reports it as
   stale. It's a sibling of [dust#514], which fixed the cross-library case.
   Workaround: `dust build --clean`.
3. **At a pub workspace root, `dust build` and `dust check` scan 0 libraries and
   exit 0** ([dust#586]), so a CI step run from the repository root is green
   without checking anything. `dust doctor` says `workspace: ok libraries: 0`.
4. **dust_server's recommended API + web app setup turns API typos into 200s**
   ([dust#587]). With `nest('/api', api)` and
   `fallback(staticFiles(dir, html: true))`, as in
   `docs/dust_server/web-apps.md`, `GET /api/nots` returns the HTML shell with
   status 200 instead of a JSON 404. A `fallback` on the `/api` router doesn't
   help, because only the outermost one is read. Fixed here in the root
   fallback.
5. `--root .` from inside a workspace member fails with *`no shared package
   configuration was found above it`*; the same directory given as an
   absolute path works ([dust#588]).
6. `FromRow` can't map `List<T>` fields, although the Postgres driver already
   decodes arrays ([dust#589]). `TEXT[]` needs a `SqlxTryFrom` converter
   ([`TextArray`](packages/conduit_server/lib/src/db/rows.dart)).
7. `@Validate(regex:, message:)` accepts only string literals; a `const`
   reference fails with *`expects a string literal`*, which the validation
   guide doesn't mention ([dust#590]).

**Already tracked, and hit here too:** telling a duplicate apart from other
database failures ([dust#570]; this server reads SQLSTATE `23505` and
`ServerException.constraintName` directly), mapping database failures to HTTP
statuses ([dust#571]; done by hand in `ApiError`), and generated routes for
handler annotations ([dust#548], open; the server uses the runtime API).
[dust#570] and [dust#571] are fixed on `main` for 0.3.0, which isn't
released yet: `SqlxError.kind` and `Rejection.fromSqlxError`. The constraint's
name still comes from the driver, since `kind` doesn't carry it. Reversible
migrations are supported ([dust#257]), but there's no revert command yet,
hence [`tool/db_revert.sh`](tool/db_revert.sh).

[dust#257]: https://github.com/y3l1n4ung/dust/issues/257
[dust#501]: https://github.com/y3l1n4ung/dust/issues/501
[dust#514]: https://github.com/y3l1n4ung/dust/issues/514
[dust#548]: https://github.com/y3l1n4ung/dust/issues/548
[dust#570]: https://github.com/y3l1n4ung/dust/issues/570
[dust#571]: https://github.com/y3l1n4ung/dust/issues/571
[dust#584]: https://github.com/y3l1n4ung/dust/issues/584
[dust#585]: https://github.com/y3l1n4ung/dust/issues/585
[dust#586]: https://github.com/y3l1n4ung/dust/issues/586
[dust#587]: https://github.com/y3l1n4ung/dust/issues/587
[dust#588]: https://github.com/y3l1n4ung/dust/issues/588
[dust#589]: https://github.com/y3l1n4ung/dust/issues/589
[dust#590]: https://github.com/y3l1n4ung/dust/issues/590

**Not Dust bugs, for completeness:** Dio's interceptor chain yielding to the
event loop, which the browser handles in
[`unload_safe.dart`](packages/conduit_web/lib/src/unload_safe.dart), and
`clock_timestamp()` defaults that differed between two columns of one row (my
schema mistake, now `now()`).

## Licenses

MIT. Vendored from the RealWorld project (MIT): the theme
[`styles.css`](packages/conduit_web/web/styles.css), the
[default avatar](packages/conduit_web/web/default-avatar.svg), the
[API suite](spec/realworld-hurl), and the [E2E suite](e2e/specs).

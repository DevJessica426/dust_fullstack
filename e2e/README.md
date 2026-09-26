# RealWorld front-end E2E suite

`specs/` is the official RealWorld Playwright suite, copied from
[gothinkster/realworld `specs/e2e`](https://github.com/gothinkster/realworld/tree/main/specs/e2e)
at commit `ebbcdeb8d55b42a3a613c787560498b8ef10003f`, under the MIT license in
[`specs/LICENSE`](specs/LICENSE). Every RealWorld front end is checked against
it, via the [selectors contract](specs/SELECTORS.md) it defines.

Run it with `tool/e2e.sh` from the repository root. That script builds the Dart
web app, starts the server on port 8090 against its own PostgreSQL database
(wiped each run), seeds the demo users the suite expects (`johndoe` and
friends), and runs Playwright in `TEST_MODE=spa`, where the browser holds the
JWT and calls the API itself, as this app does.

## The one change to the upstream files

Three spec files hard-code the public demo API instead of reading the
suite's own `API_BASE` setting from `helpers/config.ts`:

| File | Upstream | Here |
| :--- | :--- | :--- |
| `error-handling.spec.ts` | `const API_BASE = 'https://api.realworld.show/api'` | `import { API_BASE } from './helpers/config'` |
| `user-fetch-errors.spec.ts` | same | same |
| `health.spec.ts` | `request.get('https://api.realworld.show/api/tags')` | ``request.get(`${API_BASE}/tags`)`` |

Without this, their `page.route()` mocks would intercept requests to a server
this app never calls, and they would be testing the real backend instead of
the mocked failures. Nothing else is modified; `diff -r` against the upstream
directory shows only these lines.

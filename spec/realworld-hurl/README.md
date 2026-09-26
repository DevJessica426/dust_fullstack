# RealWorld API conformance suite

These `.hurl` files are the official RealWorld API tests, copied unchanged from
[gothinkster/realworld](https://github.com/gothinkster/realworld/tree/main/specs/api/hurl)
at commit `ebbcdeb8d55b42a3a613c787560498b8ef10003f`, under the MIT license in
[`LICENSE`](LICENSE).

Every RealWorld backend (Node, Go, Rust, Django, Spring and the rest) is checked
against the same files, which is what makes "a RealWorld clone" a testable
claim rather than a description.

Run them against a running server with:

```bash
tool/conformance.sh                      # http://localhost:8080
HOST=http://localhost:3000 tool/conformance.sh
```

[Hurl](https://hurl.dev) must be installed (`cargo install hurl`, `brew install
hurl`, or a release binary).

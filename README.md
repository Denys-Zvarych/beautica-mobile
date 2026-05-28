# beautica_mobile

Beautica — beauty services booking platform (Flutter app)

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

---

## Regenerate API client

The Dart HTTP client under `api/` is **auto-generated** from the backend's
OpenAPI 3.1 spec using
[openapi-generator-cli](https://github.com/OpenAPITools/openapi-generator).
**Never edit `api/` by hand** — your changes will be overwritten on the
next regeneration.

### One-time tool setup

```bash
dart pub global activate openapi_generator_cli
```

This installs the `openapi-generator` binary under `~/.pub-cache/bin/`.

### Fetch the spec (when the backend contract has changed)

```bash
# Local backend must be running at http://localhost:8080
# cd beautica-backend && ./gradlew bootRun --args='--spring.profiles.active=local'

dart run tool/openapi/fetch_spec.dart
```

This writes `tool/openapi/api-spec.json`.  The snapshot is committed to git so
that CI can run codegen offline without a live backend.

> Production spec is disabled (`springdoc.api-docs.enabled=false`).
> Only `--source=local` (default) is supported.

### Regenerate the client

```bash
./scripts/regenerate_api.sh
```

The script:
1. Runs `openapi-generator generate -g dart-dio` against the committed snapshot.
2. Runs `dart run build_runner build` inside `api/` to produce `*.g.dart`.
3. Formats `api/lib/` with `dart format`.

Commit both `api/` and `tool/openapi/api-spec.json` together in a single
`chore(api): regenerate Dart client from updated spec` commit.

### CI gate

Every PR is gated by:

```yaml
- name: Verify OpenAPI client is up to date
  run: ./scripts/regenerate_api.sh --check
```

This regenerates into a temp dir and diffs against the committed `api/`.
The build fails if they diverge — ensuring no PR ever ships a stale client.

### Regeneration cadence

Regenerate after every backend release that changes a controller, DTO, or status
code. CI fails PRs where `api/` is out of sync with `tool/openapi/api-spec.json`.
As a rule of thumb: if a backend PR touches any `@RestController`, `*Request`,
`*Response`, or `ApiResponse` type, run `./scripts/regenerate_api.sh` and commit
the result alongside the consuming feature changes in the same PR.

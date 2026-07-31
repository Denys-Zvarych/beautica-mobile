#!/usr/bin/env bash
# Raw query-param cast gate (2026-07-31 — third-occurrence ratchet).
#
# THE BUG THIS GUARDS
# -------------------
# `integration_test/support/fake_backend.dart` routes read query params off
# `req.queryParameters` inside a DioAdapter `replyCallback`. Reading one with a
# DIRECT CAST —
#
#     final String? id = req.queryParameters['serviceId'] as String?;
#
# — is a latent `TypeError` bomb. The generated OpenAPI client does NOT always
# send a scalar: `encodeCollectionQueryParameter` wraps repeatable params in a
# Dio `ListParam<Object?>{value: [...], format: ListFormat.multi}`, and a plain
# `List` shows up for other shapes. Whether a given param is scalar or
# list-shaped is decided by the BACKEND SPEC, so it can flip under any
# `./scripts/regenerate_api.sh` with no mobile code change at all.
#
# When it flips, the cast throws INSIDE the route callback. That failure mode is
# uniquely nasty: it never surfaces as "the fake is broken". It surfaces as a
# failed request → the provider goes `AsyncError` → the screen paints an ERROR
# BODY (or an empty list), and the test fails several assertions downstream with
# a message that points at the widget tree, not at the fake.
#
# THIS HAS NOW LANDED THREE TIMES IN THIS ONE FILE:
#   1. `status` on `GET /bookings/me` — read as `query['status'] as String?`
#      while `getMyBookings` sends its `Set<BookingStatus>` with
#      `ListFormat.multi`. Read like "no bookings" instead of like a crash.
#   2. `serviceId` on `/masters/{id}/working-days` — after the `d42c7cf1`
#      OpenAPI regen re-declared it list-valued.
#   3. `serviceId` on `/masters/{id}/slots` — same regen, same cast, and it
#      reddened 4 tests across 2 unrelated flow files via a calendar error body.
#
# Three identical occurrences is the justification for a structural ratchet
# rather than a fourth code review.
#
# THE RULE
# --------
# Inside `integration_test/support/`, NEVER cast a `queryParameters` read.
# Route every read through the shape-tolerant helpers in `fake_backend.dart`:
#
#     _multiQueryParam(query, 'serviceId')  → List<String>?  (all values)
#     _scalarQueryParam(query, 'sort')      → String?        (first value)
#     _bookingStatusesFrom(query)           → List<String>?  (the status filter)
#     _pageFromRequest(query) / _intQueryParam(...)          (numeric params)
#
# They accept ALL four shapes — `ListParam`, raw `List`, bare scalar, absent —
# so they survive the NEXT regen too.
#
# Banned shapes (any type, not just String):
#     queryParameters['k'] as String?     req.queryParameters['k'] as int
#     query['k'] as String                (query['k'] as String?) ?? ''
#     ...['k']! as ...                    ...['k'] as List<String>
#
# A deliberate exception is unblocked with a
# `// query-param-cast-ok: <reason>` comment ON THE SAME LINE.
#
# CI hard-gate (run from `.github/workflows/pr-validate.yml`); also runnable
# locally before pushing.
# Self-test:  ./scripts/forbid_raw_query_param_cast.sh --self-test

set -euo pipefail

# A cast applied to a `[...]QueryParameters?['...']` subscript read.
#
# Anchored on the SUBSCRIPT, not on the identifier, so it fires for
# `queryParameters['k'] as X`, `req.queryParameters['k'] as X` and a
# pre-extracted `query['k'] as X` alike. `[!?]?` tolerates a `!` / `?` between
# the subscript and the cast. The cast target is `[A-Za-z_]` — any type.
cast_pattern="(query|queryParameters)[[:space:]]*\[[^]]*\][[:space:]]*[!?]?[[:space:]]*as[[:space:]]+[A-Za-z_]"

# Same-line unblock annotation.
annotation='//[[:space:]]*query-param-cast-ok:'

# ---------------------------------------------------------------------------
# scan <dir> → prints `file:line:text` for every offending line.
#
# Pure-comment lines (`///` doc comments, `//` notes) are skipped BEFORE the
# offender check: this file documents the banned shape in prose in several
# places, and a guard that trips on its own explanation is a guard that gets
# deleted. Annotated lines are skipped too.
# ---------------------------------------------------------------------------
scan() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  grep -rEn "$cast_pattern" "$dir" --include='*.dart' 2>/dev/null \
    | grep -vE ':[[:space:]]*///?' \
    | grep -vE "$annotation" \
    || true
}

# ---------------------------------------------------------------------------
# Self-test mode: assert the verdicts on pinned fixture snippets.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  mkdir -p "$tmp/support"

  # (1) the exact shape that shipped broken three times → OFFENDER
  cat > "$tmp/support/bad_service_id.dart" <<'EOF'
void register() {
  onRoute('/masters/x/slots', (req) {
    final String? serviceId = req.queryParameters['serviceId'] as String?;
    return ok(serviceId);
  });
}
EOF

  # (2) non-String cast, parenthesised + defaulted → OFFENDER
  cat > "$tmp/support/bad_other_types.dart" <<'EOF'
void register() {
  final String c = (req.queryParameters['categoryName'] as String?) ?? '';
  final int page = query['page'] as int;
  final List<String> ids = query['serviceId']! as List<String>;
}
EOF

  # (3) routed through the tolerant helpers → OK
  cat > "$tmp/support/good.dart" <<'EOF'
void register() {
  final List<String>? ids = _multiQueryParam(req.queryParameters, 'serviceId');
  final String? sort = _scalarQueryParam(req.queryParameters, 'sort');
  final int page = _pageFromRequest(req.queryParameters);
}
EOF

  # (4) the banned shape named in a DOC COMMENT (as this very file does) → OK
  cat > "$tmp/support/doc_only.dart" <<'EOF'
/// This branch used to read it as `query['status'] as String?`, which THREW
/// a `TypeError` inside the route callback.
// Reading it as query['serviceId'] as String? threw inside the callback.
void register() {}
EOF

  # (5) explicitly unblocked → OK
  cat > "$tmp/support/unblocked.dart" <<'EOF'
void register() {
  final String? x = req.queryParameters['k'] as String?; // query-param-cast-ok: spec pins this scalar
}
EOF

  flagged=""
  for snip in bad_service_id bad_other_types good doc_only unblocked; do
    out="$(scan "$tmp/support" | grep "/$snip.dart:" || true)"
    [ -n "$out" ] && flagged="$flagged $snip"
  done
  flagged="$(printf '%s' "$flagged" | tr -s ' ' | sed 's/^ //')"

  if [ "$flagged" != "bad_service_id bad_other_types" ]; then
    echo "SELF-TEST FAIL: expected 'bad_service_id bad_other_types', got: '$flagged'"
    exit 1
  fi
  echo "SELF-TEST PASS: both raw-cast fixtures flagged (String and non-String);"
  echo "                helper-routed / doc-comment / annotated files are clean."
  exit 0
fi

offenders="$(scan integration_test/support)"

if [ -n "$offenders" ]; then
  echo "Raw cast on a queryParameters read in integration_test/support:"
  echo "$offenders"
  echo
  echo "The generated OpenAPI client sends repeatable params as a Dio"
  echo "ListParam, NOT a scalar — and which params are repeatable is decided by"
  echo "the backend spec, so it flips under any ./scripts/regenerate_api.sh."
  echo "A direct cast then throws INSIDE the route callback, surfacing as an"
  echo "error body / empty list in the widget tree instead of as a broken fake."
  echo "This has already shipped three times (status, serviceId x2)."
  echo
  echo "Read through the shape-tolerant helpers in fake_backend.dart instead:"
  echo "    _multiQueryParam(req.queryParameters, 'serviceId')  // List<String>?"
  echo "    _scalarQueryParam(req.queryParameters, 'sort')      // String?"
  echo "    _pageFromRequest(req.queryParameters)               // int"
  echo "They accept ListParam / List / scalar / absent alike."
  echo "If a cast is genuinely intended, annotate ON THE SAME LINE:"
  echo "    // query-param-cast-ok: <why this param can never be list-shaped>"
  exit 1
fi

exit 0

#!/usr/bin/env bash
# scripts/verify_builtvalue_codegen.sh
#
# Structural drift-prevention gate for the generated `api/` OpenAPI/built_value
# client, guarding a specific incident (2026-07-02): running
# `scripts/regenerate_api.sh` twice in close succession left a stale
# `.dart_tool/build` incremental cache, so `build_runner build` silently wrote
# ZERO outputs for two already-existing generated files:
#   - api/lib/src/model/public_salon_response.g.dart lost its Builder setters
#     for `avgRating`/`reviewCount` (a genuine compile error: "setter isn't
#     defined") — this half was loud and got caught.
#   - api/lib/src/serializers.g.dart lost several `..add(<Type>.serializer)`
#     registrations — this half compiles FINE and only fails at runtime with
#     "Serializer not found for <Type>" the first time that endpoint's model
#     is (de)serialized. No compile error, no CI signal until someone hits it.
#
# `run_build_runner()` in regenerate_api.sh now does `rm -rf .dart_tool/build`
# before every regen, which structurally prevents this cache-staleness class
# of bug going forward. `regenerate_api.sh --check` ALSO would have caught
# this specific incident (it diffs a freshly-generated temp-dir output against
# the committed api/, and the temp dir has no prior cache to go stale) — but
# that diff is generic: a red run reports "files differ" over potentially
# thousands of lines, not "avgRating's setter is missing". This script is
# defense-in-depth with a NAMED assertion for the two ways codegen can go
# silently stale, so a red run says exactly what broke:
#
#   1. Every abstract `@BuiltValueField` getter declared in a hand-authored
#      `api/lib/src/model/*.dart` file (i.e. one with a `part '<x>.g.dart';`
#      directive) must have a matching `set <field>(` in its paired
#      `<x>.g.dart` Builder class.
#   2. Every type listed in `api/lib/src/serializers.dart`'s
#      `@SerializersFor([ … ])` list must have a corresponding
#      `..add(<Type>.serializer)` line in `api/lib/src/serializers.g.dart`.
#
# This check runs directly against the COMMITTED `api/` tree — no
# openapi-generator JAR, no `build_runner`, no network. It is fast and has no
# external tool dependency, so it can run as a cheap first-line check before
# (or independent of) the heavier `regenerate_api.sh --check` codegen diff,
# and it also catches a hand-edit to a `.g.dart` file (e.g. a bad merge
# conflict resolution) that never goes through codegen at all.
#
# Self-test:  ./scripts/verify_builtvalue_codegen.sh --self-test

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

MODEL_DIR="api/lib/src/model"
SERIALIZERS_DART="api/lib/src/serializers.dart"
SERIALIZERS_G_DART="api/lib/src/serializers.g.dart"

# ---------------------------------------------------------------------------
# check_model_setters <dart_file> <g_dart_file>
#   Extracts every abstract getter field name from <dart_file> — a line of
#   the form "<Type> get <field>;" — and asserts a matching `set <field>(`
#   exists in <g_dart_file>. Excludes `static ... get serializer =>` (a
#   computed property, not a Builder field; its declaration ends in `=>`,
#   never `;`, so the trailing-`;` anchor already excludes it — the `static`
#   filter is an explicit belt-and-braces second guard).
#   Prints one "<dart_file>:<field>" line per missing setter to stdout.
# ---------------------------------------------------------------------------
check_model_setters() {
  local dart_file="$1" g_file="$2"
  local fields
  fields="$(grep -E '^[[:space:]]+[A-Za-z_].*[[:space:]]get[[:space:]]+[A-Za-z_][A-Za-z0-9_]*;[[:space:]]*$' "$dart_file" \
    | grep -v '^[[:space:]]*static\b' \
    | sed -E 's/.*[[:space:]]get[[:space:]]+([A-Za-z_][A-Za-z0-9_]*);.*/\1/' || true)"
  [ -z "$fields" ] && return 0
  while IFS= read -r field; do
    [ -z "$field" ] && continue
    if ! grep -qE "(^|[^A-Za-z0-9_])set[[:space:]]+${field}\(" "$g_file" 2>/dev/null; then
      echo "${dart_file}:${field}"
    fi
  done <<< "$fields"
}

# ---------------------------------------------------------------------------
# check_serializers <serializers_dart> <serializers_g_dart>
#   Extracts every type named inside the `@SerializersFor([ … ])` list and
#   asserts a `..add(<Type>.serializer)` line exists in the generated file.
#   Prints one missing type name per line to stdout.
# ---------------------------------------------------------------------------
check_serializers() {
  local dart_file="$1" g_file="$2"
  local types
  types="$(sed -n '/@SerializersFor(\[/,/^\])/p' "$dart_file" \
    | grep -E '^[[:space:]]+[A-Za-z_]' \
    | sed -E 's/^[[:space:]]+([A-Za-z_][A-Za-z0-9_]*),?[[:space:]]*$/\1/' || true)"
  [ -z "$types" ] && return 0
  while IFS= read -r t; do
    [ -z "$t" ] && continue
    if ! grep -qE "\.\.add\(${t}\.serializer\)" "$g_file" 2>/dev/null; then
      echo "$t"
    fi
  done <<< "$types"
}

# ---------------------------------------------------------------------------
# Self-test mode: reproduce the exact 2026-07-02 failure shape in fixtures
# (a getter whose Builder setter silently disappeared; a @SerializersFor
# type whose ..add() registration silently disappeared), assert both are
# flagged, and assert clean fixtures pass. Pure bash + sed/grep/awk, no
# extra dependency.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  fail=0

  # --- setter check: clean fixture ---
  cat > "$tmp/ok.dart" <<'EOF'
part 'ok.g.dart';
abstract class Ok implements Built<Ok, OkBuilder> {
  @BuiltValueField(wireName: r'id')
  String? get id;

  @BuiltValueSerializer(custom: true)
  static Serializer<Ok> get serializer =>
      _$okSerializer;
}
EOF
  cat > "$tmp/ok.g.dart" <<'EOF'
part of 'ok.dart';
class OkBuilder {
  set id(String? id) => _$this._id = id;
}
EOF

  # --- setter check: stale fixture — mirrors public_salon_response losing
  #     the `avgRating` setter while `id`'s stayed intact ---
  cat > "$tmp/stale.dart" <<'EOF'
part 'stale.g.dart';
abstract class Stale implements Built<Stale, StaleBuilder> {
  @BuiltValueField(wireName: r'id')
  String? get id;

  @BuiltValueField(wireName: r'avgRating')
  num? get avgRating;
}
EOF
  cat > "$tmp/stale.g.dart" <<'EOF'
part of 'stale.dart';
class StaleBuilder {
  set id(String? id) => _$this._id = id;
}
EOF

  ok_missing="$(check_model_setters "$tmp/ok.dart" "$tmp/ok.g.dart")"
  stale_missing="$(check_model_setters "$tmp/stale.dart" "$tmp/stale.g.dart")"

  if [ -n "$ok_missing" ]; then
    echo "SELF-TEST FAIL: clean setter fixture flagged an offender: $ok_missing"
    fail=1
  fi
  if [ "$stale_missing" != "$tmp/stale.dart:avgRating" ]; then
    echo "SELF-TEST FAIL: stale setter fixture did not flag 'avgRating' (got: '$stale_missing')"
    fail=1
  fi

  # --- serializers check: clean + stale fixtures ---
  cat > "$tmp/serializers_ok.dart" <<'EOF'
@SerializersFor([
  Ok,
  Stale,
])
EOF
  cat > "$tmp/serializers_ok.g.dart" <<'EOF'
Serializers _$serializers = (Serializers().toBuilder()
      ..add(Ok.serializer)
      ..add(Stale.serializer)
);
EOF
  cat > "$tmp/serializers_stale.g.dart" <<'EOF'
Serializers _$serializers = (Serializers().toBuilder()
      ..add(Ok.serializer)
);
EOF

  ser_ok_missing="$(check_serializers "$tmp/serializers_ok.dart" "$tmp/serializers_ok.g.dart")"
  ser_stale_missing="$(check_serializers "$tmp/serializers_ok.dart" "$tmp/serializers_stale.g.dart")"

  if [ -n "$ser_ok_missing" ]; then
    echo "SELF-TEST FAIL: clean serializers fixture flagged: $ser_ok_missing"
    fail=1
  fi
  if [ "$ser_stale_missing" != "Stale" ]; then
    echo "SELF-TEST FAIL: stale serializers fixture did not flag 'Stale' (got: '$ser_stale_missing')"
    fail=1
  fi

  if [ "$fail" -ne 0 ]; then
    exit 1
  fi
  echo "SELF-TEST PASS: stale setter + stale serializer registration both detected; clean fixtures pass"
  exit 0
fi

# ---------------------------------------------------------------------------
# Main scan — real committed api/ tree.
# ---------------------------------------------------------------------------
FAILURES=""

for dart_file in "${MODEL_DIR}"/*.dart; do
  [[ "$dart_file" == *.g.dart ]] && continue
  grep -q "^part '" "$dart_file" || continue
  g_file="${dart_file%.dart}.g.dart"
  if [ ! -f "$g_file" ]; then
    FAILURES="${FAILURES}MISSING FILE: ${g_file} (referenced by 'part' in ${dart_file})"$'\n'
    continue
  fi
  missing="$(check_model_setters "$dart_file" "$g_file")"
  if [ -n "$missing" ]; then
    FAILURES="${FAILURES}${missing}"$'\n'
  fi
done

missing_serializers="$(check_serializers "$SERIALIZERS_DART" "$SERIALIZERS_G_DART")"
if [ -n "$missing_serializers" ]; then
  while IFS= read -r t; do
    [ -z "$t" ] && continue
    FAILURES="${FAILURES}${SERIALIZERS_G_DART}: missing '..add(${t}.serializer)' for @SerializersFor type '${t}'"$'\n'
  done <<< "$missing_serializers"
fi

if [ -n "$FAILURES" ]; then
  echo "ERROR: generated api/ client is internally inconsistent (stale build_runner output)."
  echo "  A model getter has no matching Builder setter, or a @SerializersFor type has no"
  echo "  serializer registration. This is the failure mode from the 2026-07-02 incident:"
  echo "  build_runner ran but silently skipped writing an already-existing generated file."
  echo ""
  echo "${FAILURES}"
  echo "Fix: ./scripts/regenerate_api.sh   (clears .dart_tool/build before regenerating)"
  exit 1
fi

echo "OK: every model getter has a matching Builder setter; every @SerializersFor type is registered."
exit 0

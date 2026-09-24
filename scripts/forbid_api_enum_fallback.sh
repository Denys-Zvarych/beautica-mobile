#!/usr/bin/env bash
# Generated-enum fallback gate (2026-09-24, Phase 348 re-audit INFO-1).
#
# THE FRAGILITY THIS GUARDS
# -------------------------
# `scripts/regenerate_api.sh` runs openapi-generator with
# `enumUnknownDefaultCase=true`, so every generated `beautica_api` built_value
# `EnumClass` carries a fallback member, `unknownDefaultOpenApi`, that ANY wire
# value this build predates decodes to. Before it, one new backend enum value
# (e.g. `citySettlementType: "HAMLET"`) failed the WHOLE response — for
# `/users/me` that ended in a wiped session.
#
# The fallback is a decoding artefact, never data. Exactly ONE place may read
# it: `lib/core/network/api_enum_names.dart` (`knownEnumName` /
# `isOpenApiUnknownDefault`), which turns it into `null` so it can never reach
# a domain model as if it were a real value. Two shapes re-open the hole:
#
#   1. `<GeneratedEnum>.valueOf(...)` in lib/ — hand-parsing a wire string
#      through the generated enum. Its unknown-value arm is the fallback, so a
#      caller silently receives `unknownDefaultOpenApi` and (usually) treats it
#      as a real member. Map the DTO's already-decoded enum via
#      `knownEnumName` / an explicit domain switch instead.
#   2. The literal `unknownDefaultOpenApi` in lib/ outside api_enum_names.dart —
#      a second, hand-rolled reading of the fallback that will drift from the
#      one policy (it did in review: a mapper branched on it directly).
#
# THE RULE
# --------
# In `lib/**/*.dart` (never `api/`, never tests):
#   - `<Name>.valueOf(` is forbidden when `<Name>` is a generated
#     `beautica_api` EnumClass. The name set is DERIVED from `api/lib` on every
#     run (`class X extends EnumClass`), so a regenerated enum is covered with
#     no list to maintain. An `api.`-prefixed call is matched too.
#   - The literal `unknownDefaultOpenApi` is forbidden in code, except in
#     `lib/core/network/api_enum_names.dart`. (The tolerance plugin,
#     `lib/core/network/unknown_enum_tolerance_plugin.dart`, does not need it
#     and is therefore NOT excused.)
# Comment lines (`//`, `///`) are ignored for both — a guard that trips on its
# own explanation gets deleted. Escape hatch, ON THE SAME LINE:
#     // api-enum-fallback-ok: <why>
#
# Usage:
#   ./scripts/forbid_api_enum_fallback.sh              scan lib/
#   ./scripts/forbid_api_enum_fallback.sh --self-test  pin the verdicts
set -euo pipefail

cd "$(dirname "$0")/.."

annotation='//[[:space:]]*api-enum-fallback-ok:'
allowed_literal_file='lib/core/network/api_enum_names.dart'

# Every generated EnumClass name, one per line.
generated_enum_names() {
  local api_dir="$1"
  grep -rhoE 'class [A-Za-z_][A-Za-z0-9_]* extends EnumClass' "$api_dir" \
    --include='*.dart' 2>/dev/null | awk '{print $2}' | sort -u
}

# scan <lib_dir> <api_dir> <allowed_literal_file>
scan() {
  local dir="$1" api_dir="$2" allowed="$3"
  [ -d "$dir" ] || return 0
  local names
  names="$(generated_enum_names "$api_dir" | paste -sd '|' -)"
  if [ -n "$names" ]; then
    grep -rEn "(^|[^A-Za-z0-9_])(api\.)?(${names})\.valueOf\(" "$dir" \
      --include='*.dart' 2>/dev/null \
      | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//' \
      | grep -vE "$annotation" \
      | sed 's/$/   <- generated enum .valueOf( (use knownEnumName \/ a domain switch)/' \
      || true
  fi
  grep -rEn 'unknownDefaultOpenApi' "$dir" --include='*.dart' 2>/dev/null \
    | grep -vE "^${allowed}:" \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//' \
    | grep -vE "$annotation" \
    | sed 's/$/   <- unknownDefaultOpenApi outside api_enum_names.dart/' \
    || true
}

if [ "${1:-}" = "--self-test" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  mkdir -p "$tmp/api" "$tmp/lib/core/network" "$tmp/lib/f"

  cat > "$tmp/api/kind.dart" <<'EOF'
class OverrideKindEnum extends EnumClass {}
class SettlementType extends EnumClass {}
EOF

  # (1) bare generated-enum valueOf → OFFENDER
  cat > "$tmp/lib/f/bad_value_of.dart" <<'EOF'
final k = OverrideKindEnum.valueOf(wire);
EOF
  # (2) api-prefixed, non-`Enum`-suffixed generated name → OFFENDER
  cat > "$tmp/lib/f/bad_prefixed.dart" <<'EOF'
final t = api.SettlementType.valueOf(raw);
EOF
  # (3) the literal in a mapper → OFFENDER
  cat > "$tmp/lib/f/bad_literal.dart" <<'EOF'
if (dto.kind == OverrideKindEnum.unknownDefaultOpenApi) return null;
EOF
  # (4) a NON-generated enum's valueOf, and a longer name containing a
  #     generated one → OK
  cat > "$tmp/lib/f/good_other_enum.dart" <<'EOF'
final r = UserRole.valueOf(x);
final s = MyOverrideKindEnum.valueOf(x);
EOF
  # (5) both shapes named only in comments → OK
  cat > "$tmp/lib/f/doc_only.dart" <<'EOF'
/// Never call `OverrideKindEnum.valueOf(wire)` here.
// The fallback (`unknownDefaultOpenApi`) maps to salonMaster.
void f() {}
EOF
  # (6) annotated on the same line → OK
  cat > "$tmp/lib/f/unblocked.dart" <<'EOF'
final k = OverrideKindEnum.valueOf(w); // api-enum-fallback-ok: test seam
EOF
  # (7) the one allowed home of the literal → OK
  cat > "$tmp/lib/core/network/api_enum_names.dart" <<'EOF'
const String kOpenApiUnknownEnumName = 'unknownDefaultOpenApi';
EOF

  out="$(cd "$tmp" && scan lib api lib/core/network/api_enum_names.dart)"
  flagged=""
  for snip in bad_value_of bad_prefixed bad_literal good_other_enum doc_only \
      unblocked api_enum_names; do
    if printf '%s\n' "$out" | grep -q "/$snip.dart:"; then
      flagged="$flagged $snip"
    fi
  done
  flagged="$(printf '%s' "$flagged" | sed 's/^ //')"
  if [ "$flagged" != "bad_value_of bad_prefixed bad_literal" ]; then
    echo "SELF-TEST FAIL: expected 'bad_value_of bad_prefixed bad_literal', got: '$flagged'"
    printf '%s\n' "$out"
    exit 1
  fi
  echo "SELF-TEST PASS: valueOf (bare + api.-prefixed) and the stray literal"
  echo "                flagged; other enums, comments, annotated lines and"
  echo "                api_enum_names.dart are clean."
  echo "SELF-TEST OK: forbid_api_enum_fallback.sh"
  exit 0
fi

offenders="$(scan lib api/lib "$allowed_literal_file")"

if [ -n "$offenders" ]; then
  echo "Generated-enum fallback read outside its one home:"
  echo "$offenders"
  echo
  echo "Every generated beautica_api enum decodes an unrecognised wire value to"
  echo "'unknownDefaultOpenApi' (enumUnknownDefaultCase=true). Read DTO enums"
  echo "through lib/core/network/api_enum_names.dart (knownEnumName /"
  echo "isOpenApiUnknownDefault), which turns the fallback into null, or through"
  echo "an explicit domain switch with a documented default arm. Never"
  echo "hand-parse a wire string with <GeneratedEnum>.valueOf(...)."
  echo "If genuinely intended, annotate ON THE SAME LINE:"
  echo "    // api-enum-fallback-ok: <why>"
  exit 1
fi

exit 0

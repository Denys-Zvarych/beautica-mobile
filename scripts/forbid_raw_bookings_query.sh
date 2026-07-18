#!/usr/bin/env bash
# MasterBookingsQuery.raw() containment gate (perf finding P4, Phase 7.1).
#
# THE REGRESSION THIS GUARDS
# --------------------------
# `MasterBookingsQuery` is the family key for `masterBookingsProvider`. Its
# `.of()` factory is the ONLY normalising path: it sorts `statuses`/`serviceIds`
# canonically and — the part that actually bites — truncates `from`/`to` to
# local midnight via `dateOnly`.
#
# That truncation is what stops a family leak. `from`/`to` are conceptually
# DATES, but a `DateTime` is an INSTANT. A date picker handing back
# `DateTime.now()`-derived values makes two taps on the same calendar day at
# 09:14:22 and 09:15:07 two DIFFERENT keys — two family members, two network
# fetches, two cached pages, for one filter the user sees as identical. Repeat
# per tap and the family grows without bound.
#
# `.raw()` is the freezed pass-through constructor and skips all of it. It has
# to be public (freezed derives `map`/`when` parameter names from the factory
# name, so a leading underscore is illegal there) — so nothing but convention
# keeps callers off it. Today every call site uses `.of()`; Phase 7.6 wires a
# date-range picker DIRECTLY to this key, and a single
# `MasterBookingsQuery.raw(from: picked.start, ...)` would reintroduce exactly
# the leak the class exists to prevent. No test and no lint would catch it: the
# screen would look and behave correctly, just issuing a fresh request per tap.
#
# THE RULE
# --------
# Zero `MasterBookingsQuery.raw(` under lib/ and test/, except in the declaring
# file itself (which must name it) and `.freezed.dart` codegen output (which
# generates it). Build queries with `MasterBookingsQuery.of(...)`.
#
# CI hard-gate (run from `.github/workflows/pr-validate.yml`); also runnable
# locally before pushing.
# Self-test:  ./scripts/forbid_raw_bookings_query.sh --self-test

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"

# The declaring file — it necessarily contains both the `.raw` factory
# declaration and the `.of` factory's own call to it.
declaring_file='lib/features/booking/domain/master_bookings_query.dart'

# ---------------------------------------------------------------------------
# run_scan <scan_root>
#   Emits "<path>:<line>:<text>" for every `MasterBookingsQuery.raw(`
#   occurrence under <scan_root>/lib and <scan_root>/test, excluding the
#   declaring file and freezed codegen output.
# ---------------------------------------------------------------------------
run_scan() {
  local scan_root="$1"
  local h loc
  while IFS= read -r h; do
    [ -z "$h" ] && continue
    loc="${h%%:*}"                       # repo-relative path
    [ "$loc" = "$declaring_file" ] && continue
    case "$loc" in
      *.freezed.dart) continue ;;        # codegen emits the raw ctor
    esac
    printf '%s\n' "$h"
  done < <(
    cd "$scan_root" && grep -rEn 'MasterBookingsQuery\.raw\(' \
      lib/ test/ 2>/dev/null | sort || true
  )
}

# ---------------------------------------------------------------------------
# Self-test mode: synthesize a tree with one legitimate site (the declaring
# file), one codegen site, and one real offender; assert only the offender is
# flagged.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  mkdir -p "$tmp/lib/features/booking/domain" "$tmp/test/features/booking"

  # The declaring file — exempt.
  cat > "$tmp/$declaring_file" <<'EOF'
  const factory MasterBookingsQuery.raw({
    return MasterBookingsQuery.raw(
EOF

  # Codegen output — exempt.
  cat > "$tmp/lib/features/booking/domain/master_bookings_query.freezed.dart" <<'EOF'
    return MasterBookingsQuery.raw(statuses: statuses);
EOF

  # A real offender in a test — must be flagged.
  cat > "$tmp/test/features/booking/leaky_test.dart" <<'EOF'
    final q = MasterBookingsQuery.raw(from: DateTime.now(), sort: s);
EOF

  out="$(run_scan "$tmp")"
  flagged="$(printf '%s\n' "$out" | grep -c . || true)"

  if [ "$flagged" -ne 1 ] || ! printf '%s' "$out" | grep -q 'leaky_test.dart:1'; then
    echo "SELF-TEST FAIL: expected exactly the leaky_test.dart site flagged, got:"
    printf '%s\n' "$out"
    exit 1
  fi
  echo "SELF-TEST PASS: the declaring file and .freezed.dart codegen are exempt;"
  echo "                the MasterBookingsQuery.raw( call in a test is flagged."
  exit 0
fi

# ---------------------------------------------------------------------------
# Real run over the working tree.
# ---------------------------------------------------------------------------
offenders="$(run_scan "$root")"

if [ -n "$offenders" ]; then
  echo "MasterBookingsQuery.raw( used outside its declaring file:"
  echo "$offenders"
  echo
  echo ".raw() is the freezed pass-through constructor — it skips ALL"
  echo "normalisation. In particular it does NOT truncate from/to to local"
  echo "midnight, so two taps on the same calendar day at 09:14 and 09:15"
  echo "become two different masterBookingsProvider family members: two"
  echo "fetches and two cached pages for one filter the user sees as identical."
  echo
  echo "Use the normalising factory instead:"
  echo "    MasterBookingsQuery.of(statuses: ..., from: ..., to: ..., sort: ...)"
  echo
  echo "It takes Sets and plain DateTimes and canonicalises both — see the"
  echo "file header of lib/features/booking/domain/master_bookings_query.dart."
  exit 1
fi

exit 0

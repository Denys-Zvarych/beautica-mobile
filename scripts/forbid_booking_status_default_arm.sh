#!/usr/bin/env bash
# BookingStatus switch catch-all gate (phase 438 D7).
#
# THE FRAGILITY THIS GUARDS
# -------------------------
# Domain `BookingStatus` (lib/features/booking/domain/booking_status.dart) has
# an explicit `unknown` member that `BookingStatus.fromWire` maps any wire
# status this build predates to. Every switch over it keeps an explicit
# `unknown` arm, and Dart exhaustiveness then forces a decision for every NEW
# domain value at compile time. A `default:` / `_ =>` / `case _:` arm defeats
# that: the next domain value is swallowed silently by whatever the catch-all
# returns.
#
# THE RULE
# --------
# In `lib/**/*.dart`, a `switch (...)` whose subject ends in `status` (e.g.
# `switch (b.status)`, `switch (status)`, `switch (booking.status)`) AND that
# has at least one `BookingStatus.<x>` PATTERN arm must not contain a
# catch-all arm (`default:`, `_ =>`, `case _:`). A wire-string mapper over a
# `status` String (e.g. `salon_mapper.dart` `_statusFromWire`) has no
# `BookingStatus.` pattern and is out of scope. The switch body is tracked by
# brace depth from the `switch` line. Comment lines are ignored.
# Escape hatch, ON THE SAME LINE as the catch-all:
#     // status-default-ok: <why>
#
# Self-test:  ./scripts/forbid_booking_status_default_arm.sh --self-test

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"

scan() {
  local root="$1"
  [ -d "$root/lib" ] || return 0
  find "$root/lib" -type f -name '*.dart' ! -name '*.g.dart' \
    ! -name '*.freezed.dart' -print0 |
    xargs -0 -r awk '
      function flush() {
        if (domain && pending != "") printf "%s", pending
        pending = ""; domain = 0
      }
      FNR == 1 { if (inside) flush(); depth = 0; inside = 0 }
      {
        line = $0
        if (line ~ /^[[:space:]]*\/\//) next
        if (!inside && line ~ /switch[[:space:]]*\(([A-Za-z_][A-Za-z0-9_]*\.)*[A-Za-z_]*[sS]tatus\)/) {
          inside = 1; depth = 0; started = 0; pending = ""; domain = 0
        }
        if (inside) {
          if (line ~ /^[[:space:]]*(case[[:space:]]+)?BookingStatus\.[A-Za-z]+/) domain = 1
          if (line ~ /(default[[:space:]]*:|^[[:space:]]*_[[:space:]]*=>|case[[:space:]]+_[[:space:]]*:)/ &&
              line !~ /status-default-ok:/) {
            pending = pending FILENAME ":" FNR ": " line "\n"
          }
          n = split(line, ch, "")
          for (i = 1; i <= n; i++) {
            if (ch[i] == "{") { depth++; started = 1 }
            else if (ch[i] == "}") { depth-- }
          }
          if (started && depth <= 0) { inside = 0; flush() }
        }
      }
      END { if (inside) flush() }'
}

if [ "${1:-}" = "--self-test" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  mkdir -p "$tmp/lib"
  cat > "$tmp/lib/clean.dart" <<'DART'
String a(BookingStatus status) => switch (status) {
  BookingStatus.confirmed => 'c',
  BookingStatus.unknown => 'u',
};
String b(Mode m) => switch (m) {
  _ => 'other switches may use a wildcard',
};
InviteStatus w(String? status) => switch (status) {
  'PENDING' => InviteStatus.pending,
  _ => InviteStatus.unknown,
};
// switch (b.status) { default: } — comment, ignored
String c(Booking s) => switch (s.status) {
  BookingStatus.confirmed => 'c',
  _ => 'x', // status-default-ok: planted escape hatch
};
DART
  if [ -n "$(scan "$tmp")" ]; then
    echo "SELF-TEST FAIL: clean fixture flagged:" >&2
    scan "$tmp" >&2
    exit 1
  fi
  cat > "$tmp/lib/bad.dart" <<'DART'
String a(Booking b) => switch (b.status) {
  BookingStatus.confirmed => 'c',
  _ => 'swallowed',
};
void d(BookingStatus status) {
  switch (status) {
    case BookingStatus.confirmed:
      break;
    default:
      break;
  }
}
void e(Booking booking) {
  switch (booking.status) {
    case BookingStatus.confirmed:
      break;
    case _:
      break;
  }
}
DART
  n="$(scan "$tmp" | wc -l)"
  if [ "$n" -ne 3 ]; then
    echo "SELF-TEST FAIL: expected 3 planted catch-alls, got $n" >&2
    scan "$tmp" >&2
    exit 1
  fi
  echo "SELF-TEST OK: $(basename "$0")"
  exit 0
fi

hits="$(scan "$repo")"
if [ -n "$hits" ]; then
  echo "FORBIDDEN: catch-all arm in a switch over a status (phase 438 D7):" >&2
  printf '  %s\n' "$hits" >&2
  echo "Keep an explicit BookingStatus.unknown arm and let exhaustiveness" >&2
  echo "force a decision for every new value." >&2
  exit 1
fi
echo "forbid_booking_status_default_arm: OK"

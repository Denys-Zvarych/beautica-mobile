#!/usr/bin/env bash
# Vacuous route-assertion gate (2026-07-22 vacuous-assertion audit).
#
# THE FRAGILITY THIS GUARDS
# -------------------------
# `RouteNames.home` is the single character `/`. `AppHarness.expectLocation`
# historically matched with `startsWith`, so
#
#     expectLocation(router, RouteNames.home);
#
# reduced to `startsWith('/')` — TRUE for every one of the ~59 route constants
# in the app. The assertion could not fail. It is not a hypothetical: TWO
# flows shipped it as the closing assertion of a login journey —
#   1. `integration_test/patrol/auth_login_patrol_test.dart` — "CLIENT login
#      navigates to home placeholder route". A CLIENT actually lands on
#      `/home` (`RouteNames.clientHome`) via `roleHomePath`; the test would
#      have passed had the CLIENT landed literally anywhere, including back on
#      `/login`. Its own comment even recorded the vacuity, and the assertion
#      was left in place regardless.
#   2. `integration_test/auth_login_flow_test.dart` — the SALON_OWNER case,
#      same shape.
#
# `AppHarness.expectLocation` now (a) matches segment-aware rather than by raw
# prefix and (b) fails loudly when handed `'/'`. This gate is the STATIC half
# of that fix: it stops the shape from being re-typed at all, including in a
# freshly hand-rolled local copy of the helper that would not inherit the
# runtime guard.
#
# NOT THE SAME AS `forbid_naive_router_location.sh`
# -------------------------------------------------
# That gate is the near-miss. It governs WHERE a test reads the location from
# (`currentConfiguration.uri`/`.fullPath` vs the push-safe
# `AppHarness.location`) and says nothing at all about WHAT the location is
# compared against. A test can route through the blessed helper, satisfy that
# gate completely, and still assert `startsWith('/')`. This gate covers the
# comparison side.
#
# THE RULE
# --------
# `expectLocation(…, RouteNames.home)` / `expectShellLocation(…,
# RouteNames.home)` — and the same call written with the literal `'/'` or
# `"/"` — are forbidden in `test/**` and `integration_test/**`. Assert the
# concrete landing route instead (`RouteNames.clientHome`,
# `RouteNames.masterProfile`, …).
#
# If you genuinely mean the literal `/` placeholder route (SALON_OWNER is
# post-MVP and does land there), assert it EXACTLY and unambiguously:
#
#     expect(AppHarness.location(router), equals(RouteNames.home));
#
# A deliberate exception — e.g. the host-side test that pins this very guard's
# runtime counterpart by asserting `expectLocation(router, '/')` FAILS — is
# unblocked with a `// expectlocation-home-ok: <reason>` comment on the same
# line or the line directly above.
#
# ZERO BASELINE, NO ALLOW-LIST. Unlike the ratcheted gates
# (`forbid_cyrillic_finder.sh`, `forbid_naive_router_location.sh`), the corpus
# is fully clean as of this gate's introduction — both historical occurrences
# were fixed in the same change — so there is nothing to grandfather and no
# allow-list file to drift.
#
# KNOWN LIMITATION: this is a textual, single-line gate. A call split across
# lines, or one that routes the expectation through an intermediate variable
# (`final expected = RouteNames.home; expectLocation(router, expected);`),
# evades it — the same way every sibling textual gate can be evaded by
# sufficiently indirect code. Textual gates catch the common case, which is
# the copy-paste.
#
# CI hard-gate (run from `.github/workflows/pr-validate.yml`); also runnable
# locally before pushing.
# Self-test:  ./scripts/forbid_expectlocation_home.sh --self-test

set -euo pipefail

# Match a single-line `expect{,Shell}Location(<router>, RouteNames.home)` or the
# same call with a literal '/' / "/" as the expected value. `RouteNames\.home`
# cannot match `RouteNames.clientHome` — the literal `.` anchors it.
pattern="expect(Shell)?Location\([^)]*,[[:space:]]*(RouteNames\.home|'/'|\"/\")[[:space:]]*\)"
# Annotation: `// expectlocation-home-ok:` (any leading whitespace before `//`).
annotation='//[[:space:]]*expectlocation-home-ok:'

# ---------------------------------------------------------------------------
# scan_file <path>
#   Emits "<path>:<line>:<text>" for each un-annotated occurrence. A line is
#   skipped when it is a genuine `//` (or `///`) comment line, when a `//`
#   precedes the match in string-stripped text, or when the
#   `// expectlocation-home-ok:` annotation is on the line itself or the line
#   directly above.
# ---------------------------------------------------------------------------
scan_file() {
  local f="$1"
  local hits
  hits="$(grep -nE "$pattern" "$f" 2>/dev/null | cut -d: -f1 | tr '\n' ' ')"
  [ -z "$hits" ] && return 0
  awk -v file="$f" -v ann="$annotation" -v hits=" $hits " '
    # Blank out the contents of string literals so a `//` inside a string is
    # not mistaken for a comment start. The `/` characters that form the
    # forbidden `'"'"'/'"'"'` argument live INSIDE a string, so this helper is used
    # only for the comment test, never for the match test.
    function strip_strings(s,   out, c, i, q, esc) {
      out = ""; q = ""; esc = 0
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (q != "") {
          if (esc) { esc = 0; continue }
          if (c == "\\") { esc = 1; continue }
          if (c == q) { q = "" }
          continue
        }
        if (c == "\"" || c == "'"'"'") { q = c; continue }
        out = out c
      }
      return out
    }
    {
      key = " " NR " "
      if (index(hits, key) > 0) {
        # (1a) Genuine comment line? First non-space token is `//` (covers `///`).
        firsttok = $0
        sub(/^[[:space:]]+/, "", firsttok)
        if (firsttok ~ /^[/][/]/) { prev = $0; next }
        # (1b) A `//` comment earlier on the line masking the match? Compare the
        #      position of the first `//` in string-stripped text against the
        #      position of the call itself.
        codeonly = strip_strings($0)
        ci = index(codeonly, "//")
        if (ci > 0) {
          mi = match(codeonly, /expect(Shell)?Location\(/)
          if (mi == 0 || ci < mi) { prev = $0; next }
        }
        # (2) Annotated on this line or the line directly above.
        if ($0 ~ ann)   { prev = $0; next }
        if (prev ~ ann) { prev = $0; next }
        printf "%s:%d:%s\n", file, NR, $0
      }
      prev = $0
    }
  ' "$f"
}

# ---------------------------------------------------------------------------
# run_scan <scan_root>
#   Scans every Dart file under <scan_root>/test and <scan_root>/integration_test.
# ---------------------------------------------------------------------------
run_scan() {
  local scan_root="$1"
  local f offenders=""
  local files=()
  mapfile -t files < <(
    cd "$scan_root" && {
      find test -type f -name '*.dart' 2>/dev/null || true
      find integration_test -type f -name '*.dart' 2>/dev/null || true
    } | sort -u
  )
  [ "${#files[@]}" -eq 0 ] && return 0
  cd "$scan_root"
  for f in "${files[@]}"; do
    local hit
    hit="$(scan_file "$f")"
    [ -n "$hit" ] && offenders+="$hit"$'\n'
  done
  printf '%s' "$offenders" | sed '/^$/d'
}

# ---------------------------------------------------------------------------
# Self-test mode: synthesize a tree covering compliant, violating, renamed and
# annotated shapes, and assert EXACTLY the violating ones are flagged.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  mkdir -p "$tmp/test/routing" "$tmp/integration_test"

  # COMPLIANT — concrete landing routes, and the blessed exact-equality escape
  # hatch for the one role that really does land on `/`. None may be flagged.
  cat > "$tmp/test/routing/compliant_test.dart" <<'EOF'
    AppHarness.expectLocation(router, RouteNames.clientHome);
    AppHarness.expectLocation(router, RouteNames.masterProfile);
    AppHarness.expectShellLocation(router, RouteNames.salonBookingConfirm);
    expect(AppHarness.location(router), equals(RouteNames.home));
    AppHarness.expectLocation(router, RouteNames.homeFeed);
EOF

  # VIOLATING — the shipped shape, plus the literal-'/' spelling of the same
  # defect, plus a hand-rolled UNQUALIFIED local copy of the helper.
  cat > "$tmp/integration_test/violating_flow_test.dart" <<'EOF'
    AppHarness.expectLocation(router, RouteNames.home);
    AppHarness.expectLocation(router, '/');
    expectLocation(router, RouteNames.home);
EOF

  # RENAMED — the shell-resolver variant of the helper. A rename/fork of the
  # helper must not become an escape hatch.
  cat > "$tmp/integration_test/renamed_flow_test.dart" <<'EOF'
    AppHarness.expectShellLocation(router, RouteNames.home);
EOF

  # EXEMPT — commented-out code, prose referencing the banned shape (this gate's
  # own doc comments do exactly that), and the annotated deliberate exception.
  cat > "$tmp/test/routing/exempt_test.dart" <<'EOF'
    // AppHarness.expectLocation(router, RouteNames.home);
    /// `expectLocation(router, RouteNames.home)` reduces to startsWith('/').
    // expectlocation-home-ok: pins that the runtime guard rejects '/'
    expect(failureFrom(() => AppHarness.expectLocation(router, '/')), isNotNull);
    AppHarness.expectLocation(router, RouteNames.home); // expectlocation-home-ok: same-line form
EOF

  out="$(run_scan "$tmp")"
  flagged="$(printf '%s\n' "$out" | grep -c . || true)"

  ok=1
  [ "$flagged" -eq 4 ] || ok=0
  printf '%s' "$out" | grep -q 'violating_flow_test.dart:1' || ok=0
  printf '%s' "$out" | grep -q 'violating_flow_test.dart:2' || ok=0
  printf '%s' "$out" | grep -q 'violating_flow_test.dart:3' || ok=0
  printf '%s' "$out" | grep -q 'renamed_flow_test.dart:1'   || ok=0
  printf '%s' "$out" | grep -q 'compliant_test.dart'        && ok=0
  printf '%s' "$out" | grep -q 'exempt_test.dart'           && ok=0

  if [ "$ok" -ne 1 ]; then
    echo "SELF-TEST FAIL: expected exactly the 3 violating + 1 renamed sites"
    echo "                flagged (compliant/commented/annotated clean), got"
    echo "                $flagged hit(s):"
    printf '%s\n' "$out"
    exit 1
  fi
  echo "SELF-TEST PASS: 4 vacuous route assertions flagged (RouteNames.home,"
  echo "                literal '/', unqualified local copy, renamed shell"
  echo "                variant); compliant / commented / annotated lines clean"
  echo "SELF-TEST OK: forbid_expectlocation_home.sh"
  exit 0
fi

# ---------------------------------------------------------------------------
# Live scan.
# ---------------------------------------------------------------------------
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"

offenders="$(run_scan "$root")"

if [ -n "$offenders" ]; then
  echo "Vacuous route assertion found (expectLocation against '/' / RouteNames.home):"
  echo "$offenders"
  echo
  echo "RouteNames.home is '/', which every location in the app starts with —"
  echo "such an assertion can never fail. Assert the concrete landing route:"
  echo "    AppHarness.expectLocation(router, RouteNames.clientHome);"
  echo "If you really do mean the literal '/' placeholder, assert it exactly:"
  echo "    expect(AppHarness.location(router), equals(RouteNames.home));"
  echo "A deliberate exception is annotated:"
  echo "    // expectlocation-home-ok: <why '/' is the right expectation here>"
  exit 1
fi

exit 0

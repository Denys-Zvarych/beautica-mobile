#!/usr/bin/env bash
# Naive router-location-read gate (2026-07-19 push-location safeguard).
#
# THE FRAGILITY THIS GUARDS
# -------------------------
# `router.routerDelegate.currentConfiguration.uri` / `.fullPath` are
# DOCUMENTED by go_router to exclude any `ImperativeRouteMatch` — the match
# kind `context.push`/`GoRouter.push` produces (see go_router's `match.dart`,
# `RouteMatchList.uri` doc comment + `_generateFullPath`'s
# `match is! ImperativeRouteMatch` filter). So a test that pushes a route and
# then reads either property directly keeps reporting the PRE-push location
# FOREVER, even though the push succeeded and the new screen mounted — every
# `startsWith`/equality assertion built on that read is checking the wrong
# thing and either false-fails (flags a working push as broken) or, worse,
# false-passes (the assertion happens to still hold on the stale value).
#
# This is not hypothetical: it has shipped THREE times —
#   1. `ab34c0a` — nav-bar-hide shipped broken (production code this time).
#   2. `integration_test/logout_flow_test.dart` — the true root cause of the
#      long-open "btn-menu-master not navigating" backlog MEDIUM; the push
#      worked the whole time, the test read it wrong.
#   3. `integration_test/master_bookings_flow_test.dart` — same anti-pattern,
#      caught before merge this time.
# `integration_test/support/app_harness.dart` now exposes the canonical
# push-safe resolver (`AppHarness.location` / `AppHarness.expectLocation`);
# route through it instead of reading `currentConfiguration.uri`/`.fullPath`
# directly.
#
# THE RULE
# --------
# A direct `currentConfiguration.uri` or `currentConfiguration.fullPath` read
# is forbidden in `test/**` and `integration_test/**`, OUTSIDE
# `integration_test/support/app_harness.dart` itself (the shared helper's own
# declaring file — it has to read the raw properties to implement the
# fallback branch). A legitimate exception (e.g. a regression test that
# deliberately PINS the raw-read trap itself, as
# `test/features/booking/presentation/master_bookings_routing_test.dart` does)
# is unblocked with a `// router-location-ok: <reason>` comment on the same
# line or the line directly above.
#
# LEGACY BASELINE (ratchet, not a big-bang rewrite)
# -------------------------------------------------
# Most existing flow files read `currentConfiguration.uri`/`.fullPath`
# directly and are CORRECT as written — they never push on top of the read
# location (only `.go`/redirects), so the exclusion this gate guards against
# never bites them. Auditing and migrating every one of them to the shared
# helper in one PR is out of scope and risky. So this gate is a RATCHET: the
# file list in `scripts/.naive_router_location_allow` GRANDFATHERS the
# existing occurrences; the gate enforces on every OTHER file (all freshly
# authored tests, and the two files this gate exists because of, which are
# no longer in the list). When a grandfathered file is next meaningfully
# touched AND it actually pushes on top of the read location, migrate it to
# `AppHarness.location`/`AppHarness.expectLocation` and drop it from the
# allow-list — the baseline only ever shrinks.
#
# KNOWN LIMITATION: this is a textual gate (`currentConfiguration.uri` /
# `currentConfiguration.fullPath` as adjacent tokens). It does not catch the
# same read performed through an intermediate local variable (e.g.
# `final cfg = router.routerDelegate.currentConfiguration; cfg.uri`) — no
# occurrence of that indirection exists in the corpus as of this gate's
# introduction (verified by grep); if one is added, it evades this gate the
# same way `forbid_fixed_wait.sh`/`forbid_cyrillic_finder.sh` can be evaded by
# sufficiently indirect code. Textual gates catch the common case, not every
# case.
#
# CI hard-gate (run from `.github/workflows/pr-validate.yml`); also runnable
# locally before pushing.
# Self-test:  ./scripts/forbid_naive_router_location.sh --self-test

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
allow_file="$here/.naive_router_location_allow"
helper_file="integration_test/support/app_harness.dart"

# Match: currentConfiguration.uri  OR  currentConfiguration.fullPath — as
# adjacent tokens (the direct-property-access shape every real offender uses).
pattern='currentConfiguration\.(uri|fullPath)'
# Annotation: `// router-location-ok:` (any leading whitespace before the `//`).
annotation='//[[:space:]]*router-location-ok:'

# ---------------------------------------------------------------------------
# scan_file <path>
#   Emits "<path>:<line>:<text>" for each un-annotated direct read. A line is
#   skipped when it is a genuine `//` comment line (first non-space token is
#   `//`), when a `//` precedes the match in string-stripped text, or when the
#   `// router-location-ok:` annotation is on the line itself or the line
#   directly above.
# ---------------------------------------------------------------------------
scan_file() {
  local f="$1"
  local hits
  hits="$(grep -nE "$pattern" "$f" 2>/dev/null | cut -d: -f1 | tr '\n' ' ')"
  [ -z "$hits" ] && return 0
  awk -v file="$f" -v ann="$annotation" -v hits=" $hits " '
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
        # (1a) Genuine comment line? First non-space token is `//`.
        firsttok = $0
        sub(/^[[:space:]]+/, "", firsttok)
        if (firsttok ~ /^[/][/]/) { prev = $0; next }
        # (1b) `//` comment after CODE masking the match?
        codeonly = strip_strings($0)
        if (codeonly !~ /currentConfiguration\.(uri|fullPath)/) { prev = $0; next }
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
# Self-test mode.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' EXIT
  printf '%s\n' \
    '    final s = router.routerDelegate.currentConfiguration.uri.toString();' \
    '    // router-location-ok: pinning the go_router push-drop trap itself' \
    '    expect(router.routerDelegate.currentConfiguration.fullPath, parent);' \
    '    final loc = AppHarness.location(router);' \
    '    // final s = router.routerDelegate.currentConfiguration.uri.toString();' \
    '    // See currentConfiguration.uri doc comment for why this is unsafe.' \
    > "$tmp"
  out="$(scan_file "$tmp")"
  flagged="$(printf '%s\n' "$out" | grep -c . || true)"
  if [ "$flagged" -ne 1 ]; then
    echo "SELF-TEST FAIL: expected 1 offender, got $flagged"
    printf '%s\n' "$out"
    exit 1
  fi
  echo "SELF-TEST PASS: 1 raw currentConfiguration.uri/fullPath read flagged; annotated / AppHarness.location / commented lines clean"
  echo "SELF-TEST OK: forbid_naive_router_location.sh"
  exit 0
fi

# Load the grandfathered file allow-list (one repo-relative path per line; `#`
# comments and blank lines ignored). Missing file → empty allow-list.
declare -A GRANDFATHERED=()
if [ -f "$allow_file" ]; then
  while IFS= read -r raw; do
    line="${raw%%#*}"
    line="$(printf '%s' "$line" | tr -d '[:space:]')"
    [ -n "$line" ] && GRANDFATHERED["$line"]=1
  done < "$allow_file"
fi

# All test + integration_test Dart files, minus the shared helper's own
# declaring file (it legitimately implements the raw-read fallback branch).
mapfile -t files < <(
  {
    find test -type f -name '*.dart' 2>/dev/null || true
    find integration_test -type f -name '*.dart' 2>/dev/null || true
  } | sort -u
)

[ "${#files[@]}" -eq 0 ] && exit 0

offenders=""
for f in "${files[@]}"; do
  [ "$f" = "$helper_file" ] && continue          # the shared helper itself
  [ -n "${GRANDFATHERED[$f]:-}" ] && continue    # grandfathered legacy file
  hit="$(scan_file "$f")"
  [ -n "$hit" ] && offenders+="$hit"$'\n'
done
offenders="$(printf '%s' "$offenders" | sed '/^$/d')"

if [ -n "$offenders" ]; then
  echo "Direct currentConfiguration.uri/.fullPath read found in a non-grandfathered test file:"
  echo "$offenders"
  echo
  echo "go_router excludes ImperativeRouteMatch (the match kind context.push"
  echo "produces) from both properties, so a direct read after a push keeps"
  echo "reporting the PRE-push location forever. Use the push-safe helper:"
  echo "    AppHarness.location(router)          // raw String"
  echo "    AppHarness.expectLocation(router, x)  // startsWith assertion"
  echo "(integration_test/support/app_harness.dart). If this read is a"
  echo "deliberate regression pin of the raw-read trap itself, annotate it:"
  echo "    // router-location-ok: <why the raw read is intentional here>"
  echo
  echo "Legacy files predating this gate are grandfathered in"
  echo "scripts/.naive_router_location_allow — the baseline only shrinks, never grows."
  exit 1
fi

exit 0

#!/usr/bin/env bash
# Fixed-wait test gate (2026-06-24 flaky-sleep safeguard).
#
# THE FRAGILITY THIS GUARDS
# -------------------------
# `await tester.pump(const Duration(milliseconds: 600))` /
# `await tester.pumpAndSettle(const Duration(seconds: 2))` advance the test
# clock by a HARD-CODED amount, then assert. That is a guess: too short and the
# async under test hasn't completed (flaky red on a slow CI runner); too long
# and the suite is needlessly slow. The deterministic alternative is
# PUMP-UNTIL-CONDITION — pump in a loop until the awaited widget/state appears
# (e.g. a `pumpUntilFound` helper) — so the test waits exactly as long as the
# work takes and no longer. THIS gate stops new fixed sleeps from entering the
# corpus so the suite stays deterministic.
#
# THE RULE
# --------
# A `pump(const Duration(…))` or `pumpAndSettle(const Duration(…))` is
# forbidden in `test/**` and `integration_test/**`. A legitimate fixed wait
# (e.g. asserting a debounce window is NOT yet elapsed, advancing past a known
# TTL, or driving a real-async integration step where pump-until is impossible)
# is unblocked with a `// fixed-wait-ok: <reason>` comment on the same line or
# the line directly above.
#
# LEGACY BASELINE (ratchet, not a big-bang rewrite)
# -------------------------------------------------
# The corpus predates this gate and carries a large body of fixed waits written
# before the rule existed. Rewriting them all at once is out of scope and risky,
# and per-line annotating ~200 occurrences would be pure noise. So this gate is
# a RATCHET: the file list in `scripts/.fixed_wait_allow` GRANDFATHERS the
# existing offending files; the gate enforces on every OTHER test file. When a
# grandfathered file is next meaningfully touched, drop it from the allow-list
# and convert its sleeps to pump-until-condition. New files are gated from line
# one; the baseline only ever shrinks.
#
# CI hard-gate (run from `.github/workflows/pr-validate.yml`); also runnable
# locally before pushing.
# Self-test:  ./scripts/forbid_fixed_wait.sh --self-test

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
allow_file="$here/.fixed_wait_allow"

# Match: pump(const Duration(  OR  pumpAndSettle(const Duration(  — the leading
# `const` is the tell of a fixed, compile-time wait. `[[:space:]]*` absorbs the
# spacing variants. POSIX ERE: literal `(` is `[(]`.
pattern='pump(AndSettle)?[(][[:space:]]*const[[:space:]]+Duration[(]'
# Annotation: `// fixed-wait-ok:` (any leading whitespace before the `//`).
annotation='[/][/][[:space:]]*fixed-wait-ok:'

# ---------------------------------------------------------------------------
# scan_file <path>
#   Emits "<path>:<line>:<text>" for each un-annotated fixed wait. A line is
#   skipped when it is a genuine `//` comment line (first non-space token is
#   `//`), when a `//` precedes the match in string-stripped text (a `//`
#   inside a string can't mask a real call), or when the `// fixed-wait-ok:`
#   annotation is on the line itself or the line directly above. Single awk
#   pass over the whole file so the "annotation above" check sees the real
#   previous line.
# ---------------------------------------------------------------------------
scan_file() {
  awk -v file="$1" -v pat="$pattern" -v ann="$annotation" '
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
      if ($0 ~ pat) {
        # (1a) Genuine comment line? First non-space token is `//`.
        firsttok = $0
        sub(/^[[:space:]]+/, "", firsttok)
        if (firsttok ~ /^[/][/]/) { prev = $0; next }
        # (1b) `//` comment after CODE masking the call? Test string-free text.
        codeonly = strip_strings($0)
        where = match(codeonly, pat)
        if (where > 0) {
          before = substr(codeonly, 1, where - 1)
          if (before ~ /[/][/]/) { prev = $0; next }
        }
        # (2) Annotated fixed-wait-ok on this line or the line directly above.
        if ($0 ~ ann)   { prev = $0; next }
        if (prev ~ ann) { prev = $0; next }
        printf "%s:%d:%s\n", file, NR, $0
      }
      prev = $0
    }
  ' "$1"
}

# ---------------------------------------------------------------------------
# Self-test mode.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' EXIT
  printf '%s\n' \
    "      await tester.pump(const Duration(milliseconds: 600));" \
    "      // fixed-wait-ok: > 500ms debounce window must elapse" \
    "      await tester.pumpAndSettle(const Duration(seconds: 2));" \
    "      await tester.pumpUntilFound(find.byKey(k));" \
    "      // await tester.pump(const Duration(seconds: 1));" \
    > "$tmp"
  out="$(scan_file "$tmp")"
  flagged="$(printf '%s\n' "$out" | grep -c . || true)"
  if [ "$flagged" -ne 1 ]; then
    echo "SELF-TEST FAIL: expected 1 offender, got $flagged"
    printf '%s\n' "$out"
    exit 1
  fi
  echo "SELF-TEST PASS: 1 raw fixed wait flagged; annotated / pumpUntil / commented lines clean"
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

# All test + integration_test Dart files.
mapfile -t files < <(
  {
    find test -type f -name '*.dart' 2>/dev/null || true
    find integration_test -type f -name '*.dart' 2>/dev/null || true
  } | sort -u
)

[ "${#files[@]}" -eq 0 ] && exit 0

offenders=""
for f in "${files[@]}"; do
  [ -n "${GRANDFATHERED[$f]:-}" ] && continue   # grandfathered legacy file
  hit="$(scan_file "$f")"
  [ -n "$hit" ] && offenders+="$hit"$'\n'
done
offenders="$(printf '%s' "$offenders" | sed '/^$/d')"

if [ -n "$offenders" ]; then
  echo "Fixed-wait pump(const Duration(...)) found in a non-grandfathered test file:"
  echo "$offenders"
  echo
  echo "A hard-coded pump/pumpAndSettle Duration is a guess: too short → flaky red"
  echo "on slow CI, too long → slow suite. Pump UNTIL the awaited state appears"
  echo "(pump-until-condition / pumpUntilFound) so the test waits exactly as long"
  echo "as the work takes. If a fixed wait is genuinely required (debounce-not-yet,"
  echo "TTL crossing, real-async integration step), annotate it:"
  echo "    // fixed-wait-ok: <why a fixed wait is correct here>"
  echo "    await tester.pump(const Duration(milliseconds: 600));"
  echo
  echo "Legacy files predating this gate are grandfathered in"
  echo "scripts/.fixed_wait_allow — the baseline only shrinks, never grows."
  exit 1
fi

exit 0

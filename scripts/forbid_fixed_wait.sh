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
# is unblocked with a `// fixed-wait-ok: <reason>` comment on the same line, or
# anywhere in the unbroken run of `//` comment lines immediately above it (a
# long reason may wrap across several comment lines — the annotation can be on
# any of them). The walk upward stops at the first line that is not a bare
# `//` comment line, so an annotation separated from the call by real code
# does NOT count — it would otherwise become a blanket file-level opt-out.
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
#   annotation is on the line itself or anywhere in the unbroken run of `//`
#   comment lines immediately above it. Single awk pass: `comment_run_annotated`
#   tracks whether the contiguous block of comment lines seen so far contains
#   the annotation; it is set on an annotated comment line, left untouched on
#   any other comment line (so a wrapped, multi-line reason still counts), and
#   cleared the moment a non-comment (real code) line is seen — so the walk
#   never crosses into code above the block.
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
      trimmed = $0
      sub(/^[[:space:]]+/, "", trimmed)
      is_comment_line = (trimmed ~ /^[/][/]/)

      if ($0 ~ pat) {
        # (1a) Genuine comment line (commented-out code)? Not a real call —
        # still track it as part of the comment run, then move on.
        if (is_comment_line) {
          if (trimmed ~ ann) comment_run_annotated = 1
          next
        }
        # (1b) `//` comment after CODE masking the call? Test string-free text.
        codeonly = strip_strings($0)
        where = match(codeonly, pat)
        if (where > 0) {
          before = substr(codeonly, 1, where - 1)
          if (before ~ /[/][/]/) {
            comment_run_annotated = 0   # real code line — breaks the run
            next
          }
        }
        # (2) Annotated fixed-wait-ok on this line, or anywhere in the
        # contiguous `//` comment block immediately above.
        if ($0 ~ ann || comment_run_annotated) {
          comment_run_annotated = 0
          next
        }
        printf "%s:%d:%s\n", file, NR, $0
        comment_run_annotated = 0
        next
      }

      # Not a fixed-wait line: track the contiguous comment run for lines
      # that follow. A comment line extends the run (and sets the flag if it
      # carries the annotation); any other line breaks it.
      if (is_comment_line) {
        if (trimmed ~ ann) comment_run_annotated = 1
      } else {
        comment_run_annotated = 0
      }
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
    "      // fixed-wait-ok: advancing the pointer-sample clock in lockstep with the" \
    "      // synthetic move timestamps, not waiting on a condition." \
    "      await tester.pump(const Duration(milliseconds: 40));" \
    "      // fixed-wait-ok: advancing past the screen's 220 ms day-tap debounce, so a" \
    "      // selection a paging regression had queued would have FIRED by the time the" \
    '      // "no request" assertions below run. Without it those assertions would only' \
    "      // prove the debounce timer had not expired yet." \
    "      await tester.pump(const Duration(milliseconds: 300));" \
    "      // fixed-wait-ok: this annotation is orphaned by a real code line below" \
    "      someRealCodeLine();" \
    "      await tester.pump(const Duration(milliseconds: 50));" \
    > "$tmp"
  out="$(scan_file "$tmp")"
  flagged="$(printf '%s\n' "$out" | grep -c . || true)"
  if [ "$flagged" -ne 2 ]; then
    echo "SELF-TEST FAIL: expected 2 offenders, got $flagged"
    printf '%s\n' "$out"
    exit 1
  fi
  if ! printf '%s\n' "$out" | grep -q ':1:'; then
    echo "SELF-TEST FAIL: expected the raw unannotated pump (line 1) to be flagged"
    printf '%s\n' "$out"
    exit 1
  fi
  if ! printf '%s\n' "$out" | grep -q ':16:'; then
    echo "SELF-TEST FAIL: expected the pump separated from its annotation by real code (line 16) to be flagged"
    printf '%s\n' "$out"
    exit 1
  fi
  echo "SELF-TEST PASS: 2 offenders flagged (raw fixed wait; annotation orphaned by real code)."
  echo "Clean: same-line-above annotation, 2-line and 4-line wrapped annotations, pumpUntil, commented-out line."
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

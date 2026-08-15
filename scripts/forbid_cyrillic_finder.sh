#!/usr/bin/env bash
# Cyrillic test-finder gate (2026-06-24 i18n-drift safeguard).
#
# THE FRAGILITY THIS GUARDS
# -------------------------
# A test that locates a widget by its Cyrillic copy — `find.text('Головна')` —
# is silently coupled to the UA locale being active. The day an EN locale ships
# (the app is built EN-ready: app_uk.arb primary, app_en.arb stub) every such
# finder becomes a real `findsNothing` failure, because the rendered string is
# now 'Home', not 'Головна'. Tests should locate widgets by `Key`, by
# `find.bySemanticsLabel`, or by a localized string pulled from
# `AppLocalizations` — never by a hard-coded Cyrillic literal. THIS gate stops
# new Cyrillic finders from entering the corpus so the EN switch is a copy
# change, not a test rewrite.
#
# THE RULE
# --------
# A `find.text('…')` whose argument contains a Cyrillic code point
# (U+0400–U+04FF) is forbidden in `test/**` and `integration_test/**`. A
# legitimate exception (e.g. asserting a value that is data, not UI copy, and
# is identical in every locale) is unblocked with a `// i18n-finder-ok: <reason>`
# comment on the same line, or anywhere in the unbroken run of `//` comment
# lines immediately above it (a long reason may wrap across several comment
# lines — the annotation can be on any of them). The walk upward stops at the
# first line that is not a bare `//` comment line, so an annotation separated
# from the hit by real code does NOT count — it would otherwise become a
# blanket file-level opt-out.
#
# LEGACY BASELINE (ratchet, not a big-bang rewrite)
# -------------------------------------------------
# The corpus predates this gate and carries a large body of Cyrillic finders
# written before the rule existed. Rewriting them all at once is out of scope
# and risky, and per-line annotating ~120 occurrences would be pure noise. So
# this gate is a RATCHET: the file list in `scripts/.cyrillic_finder_allow`
# GRANDFATHERS the existing offending files; the gate enforces on every OTHER
# test file (all freshly-authored tests, which were written to comply). When a
# grandfathered file is next meaningfully touched, drop it from the allow-list
# and convert its finders to keys/semantics. New files are gated from line one;
# the baseline only ever shrinks.
#
# CI hard-gate (run from `.github/workflows/pr-validate.yml`); also runnable
# locally before pushing.
# Self-test:  ./scripts/forbid_cyrillic_finder.sh --self-test

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
allow_file="$here/.cyrillic_finder_allow"

# Cyrillic block U+0400–U+04FF inside a find.text('…') / find.text("…") arg.
# grep -P (PCRE) is required for \x{…} code-point classes. The `[^)]*` keeps
# the match on the same find.text(...) call.
pattern="find\\.text\\([^)]*[\\x{0400}-\\x{04FF}]"
# Annotation: `// i18n-finder-ok:` (any leading whitespace before the `//`).
annotation='//[[:space:]]*i18n-finder-ok:'

# ---------------------------------------------------------------------------
# scan_file <path>
#   Emits "<path>:<line>:<text>" for each un-annotated Cyrillic find.text.
#   A line is skipped when it is a genuine `//` comment line (first non-space
#   token is `//`) or carries the `// i18n-finder-ok:` annotation on itself,
#   or anywhere in the unbroken run of `//` comment lines immediately above it.
#
#   Two-pass design: `grep -nP` (PCRE, for the \x{…} code-point class) yields
#   the set of OFFENDING line numbers; a single awk pass over the WHOLE file
#   then applies the comment/annotation filter — awk sees every line so the
#   "annotation anywhere in the comment run above" check can walk back through
#   the real preceding lines (a grep-prefiltered stream would skip the
#   annotation lines and break it). `comment_run_annotated` tracks whether the
#   contiguous block of comment lines seen so far contains the annotation; it
#   is set on an annotated comment line, left untouched on any other comment
#   line (so a wrapped, multi-line reason still counts), and cleared the
#   moment a non-comment (real code) line is seen — so the walk never crosses
#   into code above the block.
# ---------------------------------------------------------------------------
scan_file() {
  local f="$1"
  local hits
  hits="$(grep -nP "$pattern" "$f" 2>/dev/null | cut -d: -f1 | tr '\n' ' ')"
  [ -z "$hits" ] && return 0
  awk -v file="$f" -v ann="$annotation" -v hits=" $hits " '
    {
      trimmed = $0
      sub(/^[[:space:]]+/, "", trimmed)
      is_comment_line = (trimmed ~ /^[/][/]/)
      key = " " NR " "

      if (index(hits, key) > 0) {           # this line is a Cyrillic-finder hit
        # (1) Genuine comment line (commented-out code)? Not a real hit —
        # still track it as part of the comment run, then move on.
        if (is_comment_line) {
          if (trimmed ~ ann) comment_run_annotated = 1
          next
        }
        # (2) Annotated on this line, or anywhere in the contiguous `//`
        # comment block immediately above.
        if ($0 ~ ann || comment_run_annotated) {
          comment_run_annotated = 0
          next
        }
        printf "%s:%d:%s\n", file, NR, $0
        comment_run_annotated = 0
        next
      }

      # Not a hit line: track the contiguous comment run for lines that
      # follow. A comment line extends the run (and sets the flag if it
      # carries the annotation); any other line breaks it.
      if (is_comment_line) {
        if (trimmed ~ ann) comment_run_annotated = 1
      } else {
        comment_run_annotated = 0
      }
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
    "    expect(find.text('Головна'), findsOneWidget);" \
    "    // i18n-finder-ok: data value, locale-invariant" \
    "    expect(find.text('Манікюр'), findsOneWidget);" \
    "    expect(find.text('Home'), findsOneWidget);" \
    "    // expect(find.text('Профіль'), findsOneWidget);" \
    "    // i18n-finder-ok: this label is a fixed brand mark rendered" \
    "    // identically in every locale, not translated UI copy" \
    "    expect(find.text('Позначка'), findsOneWidget);" \
    "    // i18n-finder-ok: annotation orphaned by real code below" \
    "    someRealCodeLine();" \
    "    expect(find.text('Кошик'), findsOneWidget);" \
    "    // i18n-finder-ok: covers only the FIRST of this group" \
    "    expect(find.text('Перший'), findsOneWidget);" \
    "    expect(find.text('Другий'), findsOneWidget);" \
    > "$tmp"
  out="$(scan_file "$tmp")"
  flagged="$(printf '%s\n' "$out" | grep -c . || true)"
  if [ "$flagged" -ne 3 ]; then
    echo "SELF-TEST FAIL: expected 3 offenders, got $flagged"
    printf '%s\n' "$out"
    exit 1
  fi
  if ! printf '%s\n' "$out" | grep -q ':1:'; then
    echo "SELF-TEST FAIL: expected the raw unannotated finder (line 1) to be flagged"
    printf '%s\n' "$out"
    exit 1
  fi
  if ! printf '%s\n' "$out" | grep -q ':11:'; then
    echo "SELF-TEST FAIL: expected the finder separated from its annotation by real code (line 11) to be flagged"
    printf '%s\n' "$out"
    exit 1
  fi
  if ! printf '%s\n' "$out" | grep -q ':14:'; then
    echo "SELF-TEST FAIL: expected the SECOND finder in an annotated group (line 14), not covered by the annotation above the first, to be flagged"
    printf '%s\n' "$out"
    exit 1
  fi
  echo "SELF-TEST PASS: 3 offenders flagged (raw finder; annotation orphaned by real code;"
  echo "second hit in a group not itself annotated)."
  echo "Clean: same-line-above annotation, 2-line wrapped annotation, ASCII, commented-out line."
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

offenders="$(printf '%s' "$offenders" | grep -c . >/dev/null 2>&1 && printf '%s' "$offenders" || printf '%s' "$offenders")"
offenders="$(printf '%s' "$offenders" | sed '/^$/d')"

if [ -n "$offenders" ]; then
  echo "Cyrillic find.text(...) finder(s) found in a non-grandfathered test file:"
  echo "$offenders"
  echo
  echo "A find.text('<Cyrillic>') couples the test to the UA locale; it becomes a"
  echo "findsNothing failure the day EN ships. Locate widgets by Key, by"
  echo "find.bySemanticsLabel, or by a string pulled from AppLocalizations. If the"
  echo "argument is locale-invariant data (not UI copy), annotate it:"
  echo "    // i18n-finder-ok: <why this literal is locale-invariant>"
  echo "    expect(find.text('500 грн'), findsOneWidget);"
  echo
  echo "Legacy files predating this gate are grandfathered in"
  echo "scripts/.cyrillic_finder_allow — the baseline only shrinks, never grows."
  exit 1
fi

exit 0

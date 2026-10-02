#!/usr/bin/env bash
# Layer-opacity classification gate (Phase 300).
#
# THE FRAGILITY THIS GUARDS
# -------------------------
# CI goldens (alchemist, CI tier) DISCARD layer opacity: an `Opacity` /
# `AnimatedOpacity` dim renders at full strength in a golden, so a golden for
# a "disabled" state goes green while the dim was never observed (Phase 299).
# The failure is silent and green. Nothing stops the next author writing
# `AnimatedOpacity(opacity: enabled ? 1 : 0.6, ...)`, adding a golden, and
# believing it covers the dim.
#
# THE RULE — CLASSIFY, not FORBID
# -------------------------------
# Every `Opacity(`, `AnimatedOpacity(`, `SliverOpacity(`,
# `SliverAnimatedOpacity(` and `FadeTransition(` (also with a space before the
# paren, and the `.new` tear-off) under `lib/` must carry ONE classification comment, on the site's own line
# or anywhere in the UNBROKEN run of `//` comment lines directly above it
# (the walk upward stops at the first non-comment line):
#
#     // dim-gated: test/path/to_test.dart     a dim_probe assertion observes
#                                              this dim (the file must exist)
#     // dim-decorative: <why>                 transient: value at rest is 0
#                                              or 1; nothing durable encoded
#
# LEGACY BASELINE (ratchet)
# -------------------------
# `scripts/.layer_dim_allow` lists `path:count` — the number of UNCLASSIFIED
# sites that file may still carry. Path+count (not path-only) so a new
# unclassified site cannot hide inside an already-listed file: raising the
# count is a GROW and fails like a brand-new path. The count must match
# EXACTLY: a count above the real number is a STALE entry and fails too, so
# the ratchet cannot silently loosen as code is deleted. Classifying a site
# means decrementing its count (delete the line at zero). The list ONLY
# SHRINKS; adding a line is never the fix.
#
# Known limits: `Opacity` and `(` split across LINES is not detected (`dart
# format`, CI-enforced, joins them). Strings: raw (r'...') and multi-line
# triple-quoted strings are not tracked; a `${...}` interpolation is skipped by
# brace counting only, so a nested string holding a `}` inside it ends the
# interpolation early and can expose a fake `//` tail. The PR diff reviewer is
# the backstop for a deliberately malicious author.
#
# Scope: `lib/` only (tests/previews may use Opacity freely). Generated
# `*.g.dart` / `*.freezed.dart` and `lib/api/**` are exempt.
#
# Usage:
#   ./scripts/forbid_unclassified_layer_dim.sh               gate
#   ./scripts/forbid_unclassified_layer_dim.sh --census      print path:count
#                                                            (baseline reset only)
#   ./scripts/forbid_unclassified_layer_dim.sh --self-test

set -euo pipefail

if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
  echo "forbid_unclassified_layer_dim: bash >= 4 required (associative arrays); found ${BASH_VERSION:-unknown}. On macOS: brew install bash." >&2
  exit 2
fi

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"

# STRIP_AWK: the ONE comment/string-aware stripper, shared by scan_sites and
# uses_probe (no second parser). strip(s) returns s with `//` tails and
# `/* */` blocks (multi-line, state in `inb`) removed; string literals are
# tracked ('...' / "...", `\` escapes, and a `${ ... }` interpolation span is
# opaque so quotes nested inside it cannot end the string). With dropstr=1 the
# string CONTENTS are dropped too (probe detection); otherwise kept (site
# detection: a site inside a string is still reported - conservative).
STRIP_AWK='
function strip(s,   out, i, n, c, d, q, dep, ch) {
  out = ""; n = length(s); q = ""; i = 1; tail = ""
  while (i <= n) {
    c = substr(s, i, 1); d = substr(s, i, 2)
    if (inb) { if (d == "*/") { inb = 0; i += 2 } else i++; continue }
    if (q != "") {
      if (!dropstr) out = out c
      if (c == "\\" && i < n) { if (!dropstr) out = out substr(s, i + 1, 1); i += 2; continue }
      if (d == "${") {
        if (!dropstr) out = out "{"
        dep = 1; i += 2
        while (i <= n && dep > 0) {
          ch = substr(s, i, 1)
          if (ch == "{") dep++; else if (ch == "}") dep--
          if (!dropstr) out = out ch
          i++
        }
        continue
      }
      if (c == q) q = ""
      i++; continue
    }
    if (c == "\047" || c == "\"") { q = c; out = out c; i++; continue }
    if (d == "//") { tail = substr(s, i); break }
    if (d == "/*") { inb = 1; i += 2; continue }
    out = out c; i++
  }
  return out
}
'

# uses_probe <file> : true iff the file CALLS expectDimRatio( in REAL code: line
# and block comments and string literals are stripped first (same strip() as the
# site scan), so a comment, string or bare import does not count. awk reads to
# EOF (no early-exit SIGPIPE under pipefail).
uses_probe() {
  LC_ALL=C awk -v dropstr=1 "$STRIP_AWK"'
    { gsub(/\r/, ""); code = (inb || index($0, "/") || index($0, "\047") || index($0, "\"")) ? strip($0) : $0 }
    code ~ /expectDimRatio\(/ { f = 1 }
    END { exit !f }' "$1"
}

# scan_sites <root>
#   Prints "relpath:line" for every UNCLASSIFIED layer-opacity site under
#   <root>/lib. A `// dim-gated: <target>` marker counts as classified only if
#   <target> is a safe, existing test file that uses `expectDimRatio`; an
#   invalid target makes the site unclassified.
#
#   SECURITY: file content is never handed to a shell. awk only EMITS the
#   target (tab-separated record); bash validates it against a strict regex
#   and tests it with `[[ -f ]]` / `grep -aq`. No system(), no eval.
#
#   One awk process covers every file (FILENAME/FNR; per-file state resets on
#   FNR==1). Trailing `//` comments and `/* */` blocks are stripped before
#   site matching, string-literal aware for single-line '...' / "..." strings.
#   Residual limitations: see the header ("Known limits").
scan_sites() {
  local root="$1"
  (
    cd "$root"
    [ -d lib ] || exit 0
    local raw rec rest loc tgt
    local -A tcache=()
    raw="$(find lib -type f -name '*.dart' ! -name '*.g.dart' ! -name '*.freezed.dart' \
        ! -path 'lib/api/*' -print0 | LC_ALL=C sort -z | LC_ALL=C xargs -0 -r awk "$STRIP_AWK"'
        function classified(s) { return s ~ /\/\/ *dim-(gated|decorative): *[^ ]/ }
        function target(s,   t) {
          if (s !~ /\/\/ *dim-gated:/) return ""
          t = s; sub(/.*\/\/ *dim-gated: */, "", t); sub(/[ \t].*/, "", t)
          return t
        }
        FNR == 1 { run = 0; marker = ""; inb = 0 }
        {
          gsub(/\r/, "")
          line = $0
          if (!inb && line ~ /^[ \t]*\/\//) {
            if (!run) { run = 1; marker = "" }
            if (classified(line)) marker = line
            next
          }
          tail = ""
          code = (inb || index(line, "/")) ? strip(line) : line
          n = gsub(/(^|[^A-Za-z0-9_.])(Opacity|AnimatedOpacity|SliverOpacity|SliverAnimatedOpacity|FadeTransition)[ \t]*(\(|\.new([^A-Za-z0-9_]|$))/, "&", code)
          if (n > 0) {
            src = ""
            if (classified(tail)) src = tail
            else if (run && marker != "") src = marker
            t = (src == "") ? "" : target(src)
            for (i = 0; i < n; i++) {
              if (src == "") print "U\t" FILENAME ":" FNR
              else if (t == "") { }
              else print "G\t" FILENAME ":" FNR "\t" t
            }
          }
          run = 0; marker = ""
        }')"
    [ -n "$raw" ] || exit 0
    while IFS= read -r rec; do
      case "$rec" in
        U$'\t'*) printf '%s\n' "${rec#U$'\t'}" ;;
        G$'\t'*)
          rest="${rec#G$'\t'}"; loc="${rest%%$'\t'*}"; tgt="${rest#*$'\t'}"
          if [ -z "${tcache[$tgt]:-}" ]; then
            tcache["$tgt"]=bad
            if [[ "$tgt" =~ ^test/[A-Za-z0-9_./-]+_test\.dart$ && "$tgt" != *..* \
                  && -f "$tgt" && ! -L "$tgt" ]] && uses_probe "$tgt"; then
              tcache["$tgt"]=ok
            fi
          fi
          [ "${tcache[$tgt]}" = ok ] || printf '%s\n' "$loc"
          ;;
      esac
    done <<< "$raw"
  )
}

# counts_from_sites : stdin "path:line" lines -> "path:count" lines (sorted)
counts_from_sites() {
  LC_ALL=C awk 'i = match($0, /:[0-9]+$/) {c[substr($0, 1, i - 1)]++} END {for (p in c) print p ":" c[p]}' | LC_ALL=C sort
}

# gate <root> <allowfile>   returns 0/1, prints findings
gate() {
  local root="$1" allow="$2" sites actual rc=0
  sites="$(scan_sites "$root")"
  actual="$(counts_from_sites <<< "$sites")"
  declare -A allowed=() have=()
  local line p c
  if [ -f "$allow" ]; then
    while IFS= read -r line; do
      line="${line%%#*}"; line="${line//[[:space:]]/}"
      [ -z "$line" ] && continue
      p="${line%:*}"; c="${line##*:}"
      case "$c" in '' | *[!0-9]*) echo "BAD allow-list line: $line" >&2; rc=1; continue ;; esac
      allowed["$p"]="$c"
    done < "$allow"
  fi
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    have["${line%:*}"]="${line##*:}"
  done <<< "$actual"

  for p in "${!have[@]}"; do
    c="${allowed[$p]:-0}"
    if [ "${have[$p]}" -gt "$c" ]; then
      echo "UNCLASSIFIED layer opacity in $p: ${have[$p]} unclassified site(s), allow-list permits $c. Sites:"
      P="$p:" awk 'index($0, ENVIRON["P"]) == 1' <<< "$sites" | sed 's/^/  /'
      echo "  Fix: add '// dim-gated: <test path>' or '// dim-decorative: <why>' directly above each site."
      echo "  Adding to scripts/.layer_dim_allow is never the fix."
      rc=1
    fi
  done
  for p in "${!allowed[@]}"; do
    c="${have[$p]:-0}"
    if [ "$c" -lt "${allowed[$p]}" ]; then
      echo "STALE allow-list entry: $p:${allowed[$p]} but only $c unclassified site(s) remain."
      echo "  Shrink the entry to $p:$c (delete the line at 0) in scripts/.layer_dim_allow."
      rc=1
    fi
  done
  return $rc
}

if [ "${1:-}" = "--census" ]; then
  scan_sites "$repo" | counts_from_sites
  exit 0
fi

if [ "${1:-}" = "--self-test" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  fails=()
  mk() { # mk <name> : fresh tree $tmp/<name> with lib/ and an empty allow file
    mkdir -p "$tmp/$1/lib/f" "$tmp/$1/test"
    : > "$tmp/$1/allow"
    printf 'expectDimRatio(t, f, 0.6);\n' > "$tmp/$1/test/foo_test.dart"
  }
  expect() { # expect <case> <want_rc> <root> [grep-pattern]
    local name="$1" want="$2" r="$3" pat="${4:-}" out rc=0
    out="$(gate "$r" "$r/allow" 2>&1)" || rc=$?
    if [ "$rc" -ne "$want" ]; then fails+=("$name: exit $rc, wanted $want"); return; fi
    if [ -n "$pat" ] && ! grep -q -- "$pat" <<< "$out"; then
      fails+=("$name: output lacks '$pat'"); fi
  }
  site='    child: Opacity(opacity: 0.5, child: SizedBox()),'

  # 1 ADD trips, naming file and line
  mk c1; printf 'x\n%s\n' "$site" > "$tmp/c1/lib/f/a.dart"
  expect "case1 ADD trips" 1 "$tmp/c1" "lib/f/a.dart:2"
  # 2 dim-gated passes (target exists) ...
  mk c2; printf '// dim-gated: test/foo_test.dart\n%s\n' "$site" > "$tmp/c2/lib/f/a.dart"
  expect "case2 dim-gated passes" 0 "$tmp/c2"
  #   ... but a gated marker with a missing target does not
  mk c2b; printf '// dim-gated: test/nope_test.dart\n%s\n' "$site" > "$tmp/c2b/lib/f/a.dart"
  expect "case2b dim-gated missing target trips" 1 "$tmp/c2b" "lib/f/a.dart:2"
  # 3 dim-decorative passes; comment separated by code does NOT count
  mk c3; printf '// dim-decorative: entrance fade\n%s\n' "$site" > "$tmp/c3/lib/f/a.dart"
  expect "case3 dim-decorative passes" 0 "$tmp/c3"
  mk c3b; printf '// dim-decorative: entrance fade\nfinal x = 1;\n%s\n' "$site" > "$tmp/c3b/lib/f/a.dart"
  expect "case3b separated comment trips" 1 "$tmp/c3b" "lib/f/a.dart:3"
  # detection covers the other widget names, and not look-alikes
  mk c3c; printf 'a(FadeTransition(opacity: o));\nAnimatedOpacity(opacity: 1);\nSliverOpacity(opacity: 1);\n' > "$tmp/c3c/lib/f/a.dart"
  expect "case3c all four names trip" 1 "$tmp/c3c" "lib/f/a.dart:3"
  mk c3d; printf 'StaggeredFadeTransition(x);\n/// Opacity( in a doc\nfinal opacity = 1;\n' > "$tmp/c3d/lib/f/a.dart"
  expect "case3d look-alikes/comments ignored" 0 "$tmp/c3d"
  # 2c injection payload must not execute and the site stays unclassified
  mk c2c; printf '// dim-gated: $(touch${IFS}PWNED)\n%s\n' "$site" > "$tmp/c2c/lib/f/a.dart"
  expect "case2c injection payload rejected" 1 "$tmp/c2c" "lib/f/a.dart:2"
  [ -e "$tmp/c2c/PWNED" ] || [ -e "$tmp/c2c/lib/PWNED" ] && fails+=("case2c: injection payload EXECUTED")
  #   `..` traversal rejected even though the file exists
  mk c2d; printf '// dim-gated: test/../test/foo_test.dart\n%s\n' "$site" > "$tmp/c2d/lib/f/a.dart"
  expect "case2d '..' path rejected" 1 "$tmp/c2d" "lib/f/a.dart:2"
  #   target without expectDimRatio rejected
  mk c2e; : > "$tmp/c2e/test/foo_test.dart"; printf '// dim-gated: test/foo_test.dart\n%s\n' "$site" > "$tmp/c2e/lib/f/a.dart"
  expect "case2e target lacking expectDimRatio rejected" 1 "$tmp/c2e" "lib/f/a.dart:2"
  #   CRLF file: gated site still accepted
  mk c2f; printf '// dim-gated: test/foo_test.dart\r\n%s\r\n' "$site" > "$tmp/c2f/lib/f/a.dart"
  expect "case2f CRLF gated accepted" 0 "$tmp/c2f"
  #   Opacity( in a trailing comment / block comment is not a site
  mk c3e; printf 'final x = 1; // Opacity(foo)\n/* Opacity(\n  AnimatedOpacity( */\nfinal y = 2;\n' > "$tmp/c3e/lib/f/a.dart"
  expect "case3e comment-only mentions ignored" 0 "$tmp/c3e"
  # 4 GROW rejected: listed at 1, file now has 2
  mk c4; printf '%s\n%s\n' "$site" "$site" > "$tmp/c4/lib/f/a.dart"; echo 'lib/f/a.dart:1' > "$tmp/c4/allow"
  expect "case4 grow rejected" 1 "$tmp/c4" "UNCLASSIFIED"
  # 4b exact match passes
  mk c4b; printf '%s\n' "$site" > "$tmp/c4b/lib/f/a.dart"; echo 'lib/f/a.dart:1' > "$tmp/c4b/allow"
  expect "case4b exact baseline passes" 0 "$tmp/c4b"
  # 5 SHRINK accepted: classify one of two, decrement 2 -> 1; and 1 -> deleted
  mk c5; printf '// dim-decorative: x\n%s\n%s\n' "$site" "$site" > "$tmp/c5/lib/f/a.dart"; echo 'lib/f/a.dart:1' > "$tmp/c5/allow"
  expect "case5 shrink accepted" 0 "$tmp/c5"
  mk c5b; printf '// dim-decorative: x\n%s\n' "$site" > "$tmp/c5b/lib/f/a.dart"
  expect "case5b shrink to zero (line deleted)" 0 "$tmp/c5b"
  # 6 STALE entry surfaced
  mk c6; printf '// dim-decorative: x\n%s\n' "$site" > "$tmp/c6/lib/f/a.dart"; echo 'lib/f/a.dart:1' > "$tmp/c6/allow"
  expect "case6 stale entry surfaced" 1 "$tmp/c6" "STALE"
  mk c6b; echo 'lib/f/gone.dart:2' > "$tmp/c6b/allow"
  expect "case6b entry for vanished file is stale" 1 "$tmp/c6b" "STALE"

  if [ "${#fails[@]}" -gt 0 ]; then
    echo "SELF-TEST FAIL: forbid_unclassified_layer_dim"
    printf '  - %s\n' "${fails[@]}"
    exit 1
  fi
  echo "SELF-TEST OK: forbid_unclassified_layer_dim.sh"
  exit 0
fi

out=""; rc=0
out="$(gate "$repo" "$here/.layer_dim_allow" 2>&1)" || rc=$?
if [ "$rc" -ne 0 ]; then
  printf '%s\n' "$out"
  exit 1
fi
echo "forbid_unclassified_layer_dim: OK (allow-listed files: $(grep -c -v -E '^[[:space:]]*(#|$)' "$here/.layer_dim_allow"))"

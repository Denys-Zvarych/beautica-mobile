#!/usr/bin/env bash
# Raw-clock-read gate (Kyiv-day derivation regression guard, 2026-08-02).
#
# THE BUG CLASS THIS GUARDS
# --------------------------
# The locked principle (ARCHITECTURE-mobile.md § 0.9, `shared/time/kyiv_day
# .dart`): the device clock supplies the current INSTANT; Europe/Kyiv decides
# which calendar DAY that instant falls on. The backend already enforces
# exactly this on every date param it accepts
# (`atStartOfDay(TimeZones.KYIV)` throughout `BookingService`,
# `SlotCalculationService`, `MasterService`,
# `ScheduleOverrideConflictService`, `DashboardService`) — so a mobile call
# site that derives "today" from a bare `DateTime.now()` (or a bare tear-off
# default, `DateTime Function() now = DateTime.now`) silently reads the
# DEVICE's own calendar day instead, which disagrees with the Kyiv day for
# roughly a third of every 24h window on a device sitting outside Europe/Kyiv
# (Phase 225 audit cycles 4 and 5, and again on 2026-08-02).
#
# THE RULE — A DECLARATION GATE, NOT A CLASSIFYING ONE
# ------------------------------------------------------
# A gate that only flags the BUGGY uses of `DateTime.now()` would need
# dataflow analysis: `endAt.isBefore(DateTime.now())` (an absolute-instant
# comparison — correct) and `dateOnly(DateTime.now())` (a calendar-day
# derivation — the bug) are syntactically identical at the call site; they
# differ only in what the RESULT flows into. That is not something a grep-
# shaped gate can decide. So this gate does not attempt to classify — it
# flags EVERY live-code occurrence of `DateTime.now`, both the call form
# (`DateTime.now()`) and the bare tear-off (`DateTime Function() now =
# DateTime.now,` — `working_hours_repository.dart`'s own constructor default
# carries exactly this shape, which every earlier ad-hoc grep for
# `DateTime\.now\(\)` missed because it never calls `DateTime.now()`, it only
# ever TEARS IT OFF), and requires every one of them to be either:
#   (a) routed through the injected clock seam and immediately passed to
#       [kyivDayOf] / [kyivToday] (see `shared/time/kyiv_day.dart`) rather
#       than hand-rolled into a `DateTime(y, m, d)` date token, or
#   (b) annotated `// instant-ok: <reason>` explaining why THIS read is a
#       genuine absolute-instant use (a duration measurement, an instant
#       ordering comparison, or a value fallback) that Kyiv-anchoring would
#       not change.
# Nothing here statically verifies (a) — that a `DateTime.now()` reached
# through the seam is actually fed to `kyivDayOf`/`kyivToday` rather than
# stripped by hand into a date token some other way. That gap is a review
# responsibility; see `shared/time/kyiv_day.dart`'s own header for the
# legal/illegal operations on its date-token return value.
#
# ONE HARD-CODED EXEMPTION — NOT AN ALLOW-LIST
# -----------------------------------------------
# `lib/core/time/clock_provider.dart`'s own `DateTime Function() clock(Ref
# ref) => DateTime.now;` is the clock SEAM's definition — the one place in
# the codebase that is SUPPOSED to read the raw device clock, because it is
# what every other call site routes through instead of reading it directly.
# It cannot annotate its way out generically (a same-file allow-list would
# invite every future addition to that file to inherit the exemption without
# review), so this ONE line, identified by file path AND shape together, is
# hard-coded here — exactly how `forbid_host_local_instant_anchor.sh` hard-
# codes "no allow-list, full stop" as a documented decision rather than a
# configurable one. No other file gets this treatment; every other
# legitimate site is unblocked with `// instant-ok: <reason>` instead.
#
# ACCEPTED FIXES
# ---------------
#     final DateTime today = kyivToday(ref.read(clockProvider));   // routes through the seam
#     final DateTime day = kyivDayOf(someInstant);                 // derives a Kyiv day directly
#     final bool isPast = endAt.isBefore(DateTime.now());          // instant-ok: absolute-instant comparison, endAt is canonical UTC
#
# CI hard-gate (run from `.github/workflows/pr-validate.yml`); also runnable
# locally before pushing.
# Self-test:  ./scripts/forbid_raw_clock_read.sh --self-test

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"

# Scan root: `lib/` ONLY. `test/` and `integration_test/` are already covered
# by `scripts/forbid_host_local_instant_anchor.sh` (a DIFFERENT, narrower
# rule scoped to zone-critical fixtures) — the two gates compose without
# overlap: that one polices TEST anchors, this one polices PRODUCTION reads.
scan_dirs=(
  "lib"
)

# `// instant-ok:` (any leading whitespace before the `//`) — mirrors the
# `host-tz-ok:` / `future-date-ok:` convention used by this codebase's other
# drift gates.
annotation='[/][/][[:space:]]*instant-ok:'

# The clock seam's own definition — the ONE hard-coded exemption. Identified
# by file path (below) AND line shape together (the shape is embedded as a
# regex literal directly in scan_file's awk program, not here — see its
# comment for why).
exempt_file='lib/core/time/clock_provider.dart'

# ---------------------------------------------------------------------------
# scan_file <path> <relpath>
#   Emits "<path>:<line>:<text>" for each un-annotated, live-code
#   `DateTime.now` reference in <path> (repo-relative path <relpath>, used
#   only to test the hard-coded clock-seam exemption).
# ---------------------------------------------------------------------------
scan_file() {
  awk -v file="$1" -v relpath="$2" -v ann="$annotation" \
      -v exempt_file="$exempt_file" '
    # Reused verbatim from scripts/forbid_host_local_instant_anchor.sh.
    # Erases quoted content entirely (does not preserve length/position) —
    # every match this script makes is found and positioned INSIDE this
    # stripped buffer, so internal positions stay self-consistent even though
    # they no longer line up with the raw line.
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
    # Reused verbatim from scripts/forbid_host_local_instant_anchor.sh.
    # Index of the `//` that starts a line comment, ignoring `//` inside a
    # string literal; 0 if none. Run here over the ALREADY string-stripped
    # buffer, where it degenerates to "index of the first literal `//`".
    function comment_start(s,   i, c, q, esc) {
      q = ""; esc = 0
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (q != "") {
          if (esc) { esc = 0; continue }
          if (c == "\\") { esc = 1; continue }
          if (c == q) { q = "" }
          continue
        }
        if (c == "\"" || c == "'"'"'") { q = c; continue }
        if (c == "/" && substr(s, i + 1, 1) == "/") { return i }
      }
      return 0
    }
    BEGIN { is_exempt_file = (relpath == exempt_file) }
    {
      # Whole-comment-line skip: first non-space token is `//`.
      firsttok = $0
      sub(/^[[:space:]]+/, "", firsttok)
      if (firsttok ~ /^[/][/]/) { prev = $0; next }

      # The hard-coded clock-seam exemption — file AND shape together.
      # Embedded as a regex literal (not passed via -v) so the backslash-dot
      # escape is interpreted by the AWK regex parser directly, avoiding
      # -v assignment C-style string-escape processing entirely.
      if (is_exempt_file && $0 ~ /=>[[:space:]]*DateTime\.now;/) { prev = $0; next }

      codeonly = strip_strings($0)
      cs = comment_start(codeonly)

      is_offender = 0
      pos = 1
      needle = "DateTime.now"
      needle_len = length(needle)
      while (1) {
        idx = index(substr(codeonly, pos), needle)
        if (idx == 0) { break }
        abs = pos + idx - 1

        # Match sits at/after a trailing comment in the stripped buffer.
        if (cs > 0 && abs >= cs) { pos = abs + 1; continue }

        # Exclude a longer identifier merely ENDING in "DateTime.now" (e.g. a
        # hypothetical `TZDateTime.now(...)` — the character immediately
        # before the match must not be a word character.
        if (abs > 1) {
          prevc = substr(codeonly, abs - 1, 1)
          if (prevc ~ /[A-Za-z0-9_]/) { pos = abs + 1; continue }
        }

        is_offender = 1
        pos = abs + needle_len
      }

      if (is_offender) {
        if ($0 ~ ann)   { prev = $0; next }
        if (prev ~ ann) { prev = $0; next }
        printf "%s:%d:%s\n", file, NR, $0
      }
      prev = $0
    }
  ' "$1"
}

# ---------------------------------------------------------------------------
# run_scan <tree_root>
#   Emits offenders across every *.dart file under each of ${scan_dirs[@]},
#   resolved relative to <tree_root>.
#
# Stage-1 pre-filter (mobile-perf LOW, 2026-08-02): `scan_file`'s awk program
# does a per-character scan of EVERY line (`strip_strings` + `comment_start`
# + a linear `index()` walk) — real cost across all of `lib/**/*.dart`, most
# of which never mentions `DateTime.now` at all. Mirrors the two-stage trick
# `forbid_host_local_instant_anchor.sh` already uses (Stage 1 there:
# `grep -qE "$zone_critical_pattern"`): a cheap, DELIBERATELY OVER-INCLUSIVE
# `grep` gate decides whether the expensive awk pass runs at all.
#
# ONE `grep -rlZF` process per scan dir produces the whole candidate list —
# not a `find` walk plus one `grep` PROCESS per file (553 process spawns was
# itself a large share of the original cost; a single grep doing its own
# recursive walk removes both the `find` traversal and the per-file spawn
# overhead). `-F` (fixed string, not `-E`) is safe here — the needle has no
# regex metacharacters — and faster than a regex engine for a plain substring
# scan. `-Z`/`-z` (GNU grep) null-delimit so a path containing whitespace
# still round-trips correctly, matching the `-print0`/`read -d ''` convention
# used elsewhere in this repo's guard scripts.
#
# Over-inclusive on purpose: this must never produce a FALSE NEGATIVE. A file
# only reaches Stage 2 when its raw text contains the literal substring
# `DateTime.now` in ANY form or context — inside a string, a comment, or as
# a substring of a longer identifier (`TZDateTime.now` contains it) — every
# one of which `scan_file` already has its own logic to correctly exclude.
# Skipping Stage 2 entirely is only safe for files where the substring is
# ABSENT altogether, since no shape `scan_file` flags can exist without it.
# ---------------------------------------------------------------------------
run_scan() {
  local tree_root="$1"
  local d f relpath
  for d in "${scan_dirs[@]}"; do
    [ -d "$tree_root/$d" ] || continue
    while IFS= read -r -d '' f; do
      [ -z "$f" ] && continue
      relpath="${f#"$tree_root"/}"
      scan_file "$f" "$relpath"
    done < <(grep -rlZF --include='*.dart' 'DateTime.now' "$tree_root/$d" 2>/dev/null | sort -z)
  done
}

# ---------------------------------------------------------------------------
# Self-test mode.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  probe_path="lib/core/time/raw_clock_read_probe.dart"
  exempt_probe_path="lib/core/time/clock_provider.dart"

  offender_lines=(5 8 33 41)
  offenders_per_probe=${#offender_lines[@]}

  mkdir -p "$tmp/$(dirname "$probe_path")"
  cat > "$tmp/$probe_path" <<'EOF'
// Probe for scripts/forbid_raw_clock_read.sh — exercises the gate row by
// row. Not real production code.

// (1) call form, live code — MUST be flagged.
final DateTime a = DateTime.now();

// (2) bare tear-off default, live code — MUST be flagged.
DateTime Function() clock = DateTime.now;

// (3) whole-line comment — not flagged.
// final DateTime x = DateTime.now();

// (4) trailing comment hides the call — not flagged.
final DateTime b = c; // DateTime.now()

// (5) inside a string literal — not flagged (strip_strings).
const String s = "DateTime.now()";

// (6) same-line instant-ok marker — not flagged.
final DateTime d = DateTime.now(); // instant-ok: absolute-instant comparison

// (7) marker on the line directly above — not flagged.
// instant-ok: absolute-instant duration
final DateTime e = DateTime.now();

// (8) a longer identifier merely ENDING in "DateTime.now" (qualified-call
// exclusion, mirrors forbid_host_local_instant_anchor.sh's preceding-char
// rule for "DateTime(") — not flagged.
final DateTime f = tz.TZDateTime.now(loc);

// (9) call form, live code — MUST be flagged (second independent hit, not
// merely counted once per file).
final DateTime g = DateTime.now();

// (10) instant-ok marker at the TOP of a multi-line rationale block (not the
// line directly above the code) — MUST still be flagged. Per the documented
// gotcha shared with host-tz-ok / future-date-ok, the marker only unblocks
// when it is the LAST comment line before the code.
// instant-ok: reason stated first, on the TOP line of a 2-line block
// second line of rationale — THIS line, not the one above, is "directly
final DateTime h = DateTime.now();
EOF

  mkdir -p "$tmp/$(dirname "$exempt_probe_path")"
  cat > "$tmp/$exempt_probe_path" <<'EOF'
// Mirrors the REAL lib/core/time/clock_provider.dart shape closely enough to
// exercise the hard-coded exemption without importing riverpod_annotation.
// This exact file path + line shape must NOT be flagged.
DateTime Function() clock(Ref ref) => DateTime.now;

// A DIFFERENT DateTime.now() elsewhere in the SAME exempt file is NOT
// covered by the exemption — only the one line shape is hard-coded. MUST
// still be flagged.
final DateTime notExempt = DateTime.now();
EOF

  out="$(run_scan "$tmp")"
  flagged="$(printf '%s\n' "$out" | grep -c . || true)"
  expected=$((offenders_per_probe + 1))
  if [ "$flagged" -ne "$expected" ]; then
    echo "SELF-TEST FAIL: expected exactly $expected offenders"
    echo "                ($offenders_per_probe from the main probe + 1 from"
    echo "                the non-exempt line in the clock_provider.dart-"
    echo "                shaped probe), got $flagged:"
    printf '%s\n' "$out"
    exit 1
  fi
  for ln in "${offender_lines[@]}"; do
    if ! printf '%s\n' "$out" | grep -q "^$tmp/$probe_path:$ln:"; then
      echo "SELF-TEST FAIL: expected an offender at $probe_path:$ln, none found."
      echo "                Is 'lib' listed in scan_dirs AND actually walked"
      echo "                by run_scan?"
      printf '%s\n' "$out"
      exit 1
    fi
  done
  if ! printf '%s\n' "$out" | grep -q "^$tmp/$exempt_probe_path:9:"; then
    echo "SELF-TEST FAIL: expected the non-exempt DateTime.now() at"
    echo "                $exempt_probe_path:9 to be flagged — the hard-coded"
    echo "                exemption must be scoped to its exact line shape,"
    echo "                not the whole file:"
    printf '%s\n' "$out"
    exit 1
  fi
  if printf '%s\n' "$out" | grep -q "^$tmp/$exempt_probe_path:4:"; then
    echo "SELF-TEST FAIL: the hard-coded clock-seam exemption line"
    echo "                ($exempt_probe_path:4) was flagged — the exemption"
    echo "                is not matching its own reference shape:"
    printf '%s\n' "$out"
    exit 1
  fi

  echo "SELF-TEST PASS: call form and bare tear-off are both flagged; whole-"
  echo "                line comments, trailing comments, string-literal"
  echo "                contents, a qualified TZDateTime.now(...) call, and"
  echo "                both instant-ok annotation placements all stay"
  echo "                clean; a multi-line block whose marker sits on the"
  echo "                TOP line (not directly above the code) does NOT"
  echo "                unblock; the hard-coded clock_provider.dart exemption"
  echo "                matches its own exact line shape and does not leak"
  echo "                to a different DateTime.now() elsewhere in the same"
  echo "                file."
  exit 0
fi

# ---------------------------------------------------------------------------
# Real run over the working tree.
# ---------------------------------------------------------------------------
offenders="$(run_scan "$root")"

if [ -n "$offenders" ]; then
  echo "Un-annotated DateTime.now reference found under ${scan_dirs[*]}:"
  echo "$offenders"
  echo
  echo "The device clock supplies the current INSTANT; Europe/Kyiv decides"
  echo "which calendar DAY that instant falls on (ARCHITECTURE-mobile.md § 0.9,"
  echo "shared/time/kyiv_day.dart). A bare DateTime.now() — call form or a bare"
  echo "tear-off default — silently reads the DEVICE's own calendar day"
  echo "instead, which disagrees with the Kyiv day for roughly a third of"
  echo "every 24h window on a device outside Europe/Kyiv. This gate cannot"
  echo "tell a genuine absolute-instant read from a mis-derived calendar day"
  echo "by grep alone (see the script header) — it flags every raw read and"
  echo "asks a human to say which one this is."
  echo
  echo "Route it through the injected clock seam and derive the day via"
  echo "kyivToday / kyivDayOf:"
  echo "    final DateTime today = kyivToday(ref.read(clockProvider));"
  echo
  echo "If this read is genuinely a value fallback or an absolute-instant"
  echo "comparison/duration that Kyiv-anchoring would not change, annotate it:"
  echo "    // instant-ok: <why this read is not a calendar-day derivation>"
  echo
  echo "There is no allow-list for this gate beyond the ONE hard-coded"
  echo "clock_provider.dart line — see the script header."
  exit 1
fi

exit 0

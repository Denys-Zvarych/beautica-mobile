#!/usr/bin/env bash
# Host-local-instant-anchor gate (dev-VM-zone-equals-business-zone trap).
#
# THE FRAGILITY THIS GUARDS
# --------------------------
# The dev VM this project is built on runs `TZ=Europe/Kyiv` — and
# `Europe/Kyiv` (`lib/shared/time/time_zones.dart`'s `kBeauticaTimeZoneName`)
# is ALSO the business timezone. A bare local constructor,
# `DateTime(2026, 6, 14, 12)`, resolves its underlying instant through the
# HOST PROCESS's own `TZ` — so on the dev VM that instant IS already Kyiv
# wall-clock, on CI (`TZ=UTC`) it is a DIFFERENT instant three hours earlier,
# and on any other machine it is whatever that machine's `TZ` happens to be.
# A test anchored this way is therefore either:
#   (a) accidentally correct on the dev VM and silently non-discriminating —
#       it can never fail there no matter what the zone-conversion code does,
#       because "device local" and "Kyiv local" are the same value by
#       construction, or
#   (b) correct on CI and wrong on the dev VM (or vice versa), which reads as
#       unrelated flake and gets re-run rather than fixed.
# Either way the fixture stops being a test of the zone-conversion logic it
# was written to pin. This has shipped THREE times: Phase 225 audit cycles 4
# and 5, and again on 2026-08-02. The root cause the architect traced it to:
# `lib/core/time/clock_provider.dart`'s own doc comment taught the bad pattern
# as the canonical override example — fixed alongside this gate.
#
# THE RULE
# --------
# Under EITHER scan root — `test/` or `integration_test/` — inside a file
# whose RAW text (including comments — deliberately over-inclusive) matches
#     toBeauticaTime|clockProvider|TZDateTime|beauticaZone|kBeauticaTimeZoneName
# (i.e. the file is "zone-critical": it exercises the Kyiv-anchored clock seam
# in some way), flag every `DateTime(` call where ALL of the following hold:
#
#   1. NOT A QUALIFIED CONSTRUCTOR. The character immediately before the
#      literal substring `DateTime(` is neither `.` nor a word character
#      (`[A-Za-z0-9_]`). This is what the literal-substring search alone does
#      NOT already exclude: `DateTime.utc(`, `.now(`, `.parse(`, and
#      `.fromMillisecondsSinceEpoch(` never produce the substring `DateTime(`
#      at all (the character right after `DateTime` is `.`, not `(`), but
#      `TZDateTime(` / `tz.TZDateTime(` DO contain `DateTime(` as a substring
#      — preceded by `Z`, a word character — so rule 1 is what excludes those.
#   2. LITERAL-YEAR FIRST ARG. Skipping whitespace after the opening `(`, the
#      first character is a digit. Excludes derived forms like
#      `DateTime(day.year, day.month, day.day, hour, minute)`, which read a
#      real calendar day rather than pinning an arbitrary host-resolved one.
#   3. ARITY >= 4 (i.e. at least 3 top-level commas between `DateTime(` and
#      its matching `)`). A 3-arg call (`DateTime(y, m, d)`, no time-of-day
#      component) can never disagree with its UTC twin on which SIDE of a
#      day-boundary it falls, so it isn't the bug class this gate exists for.
#      Depth is tracked forward (`(`/`[`/`{` increment, `)`/`]`/`}` decrement,
#      commas counted only at depth 1, stop the instant depth returns to 0) —
#      NOT a `[^)]*` regex, which would silently truncate at the first `)` of
#      any NESTED call and either over- or under-count the arg list.
#   4. LIVE CODE. Survives `strip_strings($0)` (not inside a string literal);
#      the line's first non-space token is not `//` (not a whole-comment
#      line); the match sits before any `//` that starts a real trailing
#      comment (found via `comment_start`, run over the already
#      string-stripped buffer — with no quotes left in that buffer, any `//`
#      remaining in it is, by construction, a real comment marker rather than
#      one hiding inside a string, so this composition needs no separate
#      raw-vs-stripped position mapping).
#   5. NOT ANNOTATED. Neither the matching line nor the line directly above
#      matches `// host-tz-ok: <reason>` (case-sensitive marker, any leading
#      whitespace, same convention as `future-date-ok` / `fixed-wait-ok`).
#      GOTCHA (same one those two gates already document): "the line directly
#      above" means the LAST comment line before the code. A marker sitting on
#      the FIRST line of a multi-line rationale block does NOT unblock the
#      code below it — the marker has to be the closing line of the block.
#
# ACCEPTED FIXES
# --------------
#     DateTime.utc(2026, 8, 1, 23, 30)                               // a fixed instant
#     tz.TZDateTime(tz.getLocation('Asia/Tokyo'), 2026, 8, 2, 5, 0)  // a specific DEVICE zone
# Both fix the underlying instant independently of whichever `TZ` the process
# happens to run under. Worked reference:
# test/features/home/application/next_appointment_provider_test.dart:596-717
# (the "Kyiv-day boundary" group — one case anchored `.utc`, the other to an
# explicit `Asia/Tokyo` TZDateTime, precisely so the divergence each test
# exercises is a property of the FIXTURE, not of the host running it).
#
# NO LEGACY BASELINE — AND NONE SHOULD EVER BE ADDED
# ---------------------------------------------------
# Unlike `forbid_stale_future_date_fixture.sh`'s `.stale_future_date_allow`
# ratchet, this gate carries NO allow-list. At the moment it was introduced
# the two known offenders were `test/core/time/clock_provider_test.dart`'s
# three bare `DateTime(...)` fixtures, converted to `DateTime.utc(...)` in the
# same change that added this gate — so the baseline is empty from line one.
# Do NOT add a `.host_local_instant_allow` file to make a future offender
# "pass": every legitimate case is expressible either as `DateTime.utc(...)`
# or a `TZDateTime(...)` pinned to a named device zone, so there is never a
# reason to grandfather one in. If this ever feels necessary, the fix belongs
# in the flagged test, not in this script.
#
# CI hard-gate (run from `.github/workflows/pr-validate.yml`); also runnable
# locally before pushing.
# Self-test:  ./scripts/forbid_host_local_instant_anchor.sh --self-test

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"

# Repo-relative directories scanned — the WHOLE widget/unit tier and the WHOLE
# E2E tier, not a narrower subset. Unlike the stale-future-date gate (whose
# blind spot was a missing ROOT), this gate's risk is a missing FILE within an
# already-scanned root, so there is no narrower defensible scope: any test
# file anywhere under either tier can hand-roll a zone-critical fixture.
scan_dirs=(
  "test"
  "integration_test"
)

# Stage 1 classification: a file only enters Stage 2 scanning when its RAW
# text (comments included — deliberately over-inclusive, see header) touches
# the Kyiv-anchored clock seam in some way. This keeps the gate silent on the
# ~overwhelming majority of the suite that never reads a clock at all, while
# still catching every file that does — including one whose ONLY reference is
# in a comment, since a comment can just as easily reference the wrong
# pattern as code can.
zone_critical_pattern='toBeauticaTime|clockProvider|TZDateTime|beauticaZone|kBeauticaTimeZoneName'

# `// host-tz-ok:` (any leading whitespace before the `//`) — same convention
# as `future-date-ok` / `fixed-wait-ok`.
annotation='[/][/][[:space:]]*host-tz-ok:'

# ---------------------------------------------------------------------------
# scan_file <path>
#   Emits "<path>:<line>:<text>" for each un-annotated, live-code, bare
#   `DateTime(<digit>, ...)` call of arity >= 4 in <path>. Assumes <path> has
#   already passed Stage 1 classification (run_scan's job, not this
#   function's) — this function does not re-check zone-criticality.
# ---------------------------------------------------------------------------
scan_file() {
  awk -v file="$1" -v ann="$annotation" '
    # Reused verbatim from scripts/forbid_stale_future_date_fixture.sh.
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
    # Reused verbatim from scripts/forbid_stale_future_date_fixture.sh.
    # Index of the `//` that starts a line comment, ignoring `//` inside a
    # string literal; 0 if none. Run here over the ALREADY string-stripped
    # buffer (see rule 4 above), where it degenerates to "index of the first
    # literal `//`" — its quote-tracking never engages because no quotes
    # survive stripping, which is exactly what makes this composition sound
    # without a raw-to-stripped position map.
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
    # Counts top-level commas between s[start] (the "(" of a DateTime( call)
    # and its matching ")", tracking bracket depth forward. Stops the INSTANT
    # depth returns to 0 — i.e. at DateTime'"'"'s OWN closing paren, never a
    # later one belonging to an enclosing call. Deliberately not a `[^)]*`
    # regex (see header, rule 3).
    function count_top_commas(s, start,   i, c, depth, commas, n) {
      n = length(s)
      depth = 0
      commas = 0
      for (i = start; i <= n; i++) {
        c = substr(s, i, 1)
        if (c == "(" || c == "[" || c == "{") {
          depth++
        } else if (c == ")" || c == "]" || c == "}") {
          depth--
          if (depth == 0) { return commas }
        } else if (c == "," && depth == 1) {
          commas++
        }
      }
      return commas
    }
    {
      # (4a) Genuine whole-comment line? First non-space token is `//`.
      firsttok = $0
      sub(/^[[:space:]]+/, "", firsttok)
      if (firsttok ~ /^[/][/]/) { prev = $0; next }

      codeonly = strip_strings($0)
      cs = comment_start(codeonly)

      is_offender = 0
      pos = 1
      while (1) {
        idx = index(substr(codeonly, pos), "DateTime(")
        if (idx == 0) { break }
        abs = pos + idx - 1
        parenidx = abs + 8   # index, in codeonly, of the "(" itself

        # (4c) Match sits at/after a trailing comment in the stripped buffer.
        if (cs > 0 && abs >= cs) { pos = abs + 1; continue }

        # (1) Qualified-constructor exclusion (TZDateTime(, tz.TZDateTime(, …).
        if (abs > 1) {
          prevc = substr(codeonly, abs - 1, 1)
          if (prevc == "." || prevc ~ /[A-Za-z0-9_]/) { pos = abs + 1; continue }
        }

        # (2) First arg, skipping whitespace, must open on a digit.
        rest = substr(codeonly, parenidx + 1)
        sub(/^[[:space:]]*/, "", rest)
        firstc = substr(rest, 1, 1)
        if (firstc !~ /[0-9]/) { pos = abs + 1; continue }

        # (3) Arity >= 4, i.e. >= 3 top-level commas, depth-tracked.
        if (count_top_commas(codeonly, parenidx) >= 3) {
          is_offender = 1
        }
        pos = abs + 1
      }

      if (is_offender) {
        # (5) Annotated on this line or the line directly above.
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
#   resolved relative to <tree_root>, restricted to files that pass Stage 1
#   classification. A scan dir that does not exist under <tree_root>
#   contributes nothing (lets the self-test synthesize one root at a time).
# ---------------------------------------------------------------------------
run_scan() {
  local tree_root="$1"
  local d f
  for d in "${scan_dirs[@]}"; do
    while IFS= read -r -d '' f; do
      [ -z "$f" ] && continue
      if grep -qE "$zone_critical_pattern" "$f" 2>/dev/null; then
        scan_file "$f"
      fi
    done < <(find "$tree_root/$d" -type f -name '*.dart' -print0 2>/dev/null | sort -z)
  done
}

# ---------------------------------------------------------------------------
# Self-test mode: synthesize ONE zone-critical probe PER SCAN ROOT (proves
# `integration_test/` is genuinely walked, not merely listed in `scan_dirs` —
# the same lesson `forbid_stale_future_date_fixture.sh` learned the hard way
# on 2026-07-21) plus ONE non-zone-critical probe carrying the exact flagged
# shape, to pin Stage 1 classification independently of Stage 2 matching.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  probe_paths=(
    "test/core/time/host_local_instant_probe_test.dart"
    "integration_test/support/host_local_instant_probe.dart"
  )
  noncritical_path="test/core/time/host_local_instant_probe_control_test.dart"

  # Lines each rule must flag, and the total per zone-critical probe file.
  offender_lines=(16 19 44 60)
  offenders_per_probe=${#offender_lines[@]}

  for probe in "${probe_paths[@]}"; do
    mkdir -p "$tmp/$(dirname "$probe")"
    cat > "$tmp/$probe" <<'EOF'
// Zone-critical marker for the self-test probe (mentions toBeauticaTime,
// clockProvider, TZDateTime, beauticaZone, kBeauticaTimeZoneName so Stage 1
// classification picks this file up under EITHER scan root).
// Exercises scripts/forbid_host_local_instant_anchor.sh row-by-row.

// (1) arity 3 — not flagged.
final DateTime a = DateTime(2026, 8, 1);

// (2) DateTime.utc — qualified constructor, not flagged.
final DateTime b = DateTime.utc(2026, 8, 1, 23, 30);

// (3) TZDateTime — qualified constructor (device-zone form), not flagged.
final DateTime c = tz.TZDateTime(loc, 2026, 8, 2, 5, 0);

// (4) bare DateTime(, arity 4 — MUST be flagged.
final DateTime d = DateTime(2026, 8, 1, 23, 30);

// (5) bare DateTime(, arity 7 — MUST be flagged.
final DateTime e = DateTime(2026, 8, 1, 23, 30, 0, 0);

// (6) derived first arg (day.year, ...) — not flagged, rule 2.
final DateTime f = DateTime(day.year, day.month, day.day, 9, 0);

// (7) whole-line comment — not flagged.
// final DateTime g = DateTime(2026, 8, 1, 23, 30);

// (8) trailing comment hides the call — not flagged.
final DateTime h = x; // DateTime(2026, 8, 1, 23, 30)

// (9) inside a string literal — not flagged (strip_strings).
const String s = "DateTime(2026, 8, 1, 23, 30)";

// (10) same-line host-tz-ok marker — not flagged.
final DateTime i = DateTime(2026, 8, 1, 23, 30); // host-tz-ok: pinned instant, see group header

// (11) marker on the line directly above — not flagged.
// host-tz-ok: pinned instant, see group header
final DateTime j = DateTime(2026, 8, 1, 23, 30);

// (12) nested, arity 3 — not flagged; pins the depth counter.
final k = f(DateTime(2026, 8, 1), 3);

// (13) nested, arity 4 — MUST be flagged; same pin, other direction.
final l = f(DateTime(2026, 8, 1, 9), 3);

// (14) arity 3 with a nested-bracket comma INSIDE DateTime's own arg list —
// not flagged; pins the depth-RESTRICTED comma count (only depth==1 commas
// count) distinctly from (12)/(13), which pin only where counting STOPS. A
// counter that summed every comma regardless of depth would misread this as
// arity 4 (2 top-level + 1 nested) and flag it — a real false positive a
// naive `[^)]*`-style or depth-blind counter would produce.
final DateTime m = DateTime(2026, 8, sumOf(1, 2));

// (15) host-tz-ok marker at the TOP of a multi-line rationale block (not the
// line directly above the code) — MUST still be flagged. Per the documented
// gotcha (header rule 5, shared with future-date-ok / fixed-wait-ok), the
// marker only unblocks when it is the LAST comment line before the code.
// host-tz-ok: reason stated first, on the TOP line of a 2-line block
// second line of rationale — THIS line, not the one above, is "directly
final DateTime n = DateTime(2026, 8, 1, 23, 30);
EOF
  done

  mkdir -p "$tmp/$(dirname "$noncritical_path")"
  cat > "$tmp/$noncritical_path" <<'EOF'
// A file with NO zone-critical marker — Stage 1 classification must skip it
// even though it carries the exact flagged shape below (pins Stage 1
// independently of Stage 2's own matching logic).
final DateTime d = DateTime(2026, 8, 1, 23, 30);
EOF

  out="$(run_scan "$tmp")"
  flagged="$(printf '%s\n' "$out" | grep -c . || true)"
  expected=$((${#probe_paths[@]} * offenders_per_probe))
  if [ "$flagged" -ne "$expected" ]; then
    echo "SELF-TEST FAIL: expected exactly $expected offenders"
    echo "                ($offenders_per_probe per zone-critical probe ×"
    echo "                ${#probe_paths[@]} scan roots; the non-zone-critical"
    echo "                probe must contribute zero), got $flagged:"
    printf '%s\n' "$out"
    exit 1
  fi
  for probe in "${probe_paths[@]}"; do
    for ln in "${offender_lines[@]}"; do
      if ! printf '%s\n' "$out" | grep -q "^$tmp/$probe:$ln:"; then
        echo "SELF-TEST FAIL: expected an offender at $probe:$ln, none found."
        echo "                Is '$(dirname "$(dirname "$probe")")' listed in"
        echo "                scan_dirs AND actually walked by run_scan?"
        printf '%s\n' "$out"
        exit 1
      fi
    done
  done
  if printf '%s\n' "$out" | grep -q "$noncritical_path"; then
    echo "SELF-TEST FAIL: the non-zone-critical probe was flagged — Stage 1"
    echo "                classification is not gating the scan at all:"
    printf '%s\n' "$out"
    exit 1
  fi

  echo "SELF-TEST PASS: qualified constructors (DateTime.utc, TZDateTime),"
  echo "                derived first args, comments (whole-line and"
  echo "                trailing), string-literal contents, and both"
  echo "                host-tz-ok annotation placements all stay clean;"
  echo "                bare arity>=4 DateTime(<digit>, ...) is flagged in"
  echo "                BOTH scan roots (${scan_dirs[*]}), including nested"
  echo "                inside another call (pinning the depth counter in"
  echo "                both directions) and nested INSIDE DateTime's own arg"
  echo "                list (pinning depth-RESTRICTED comma counting, not"
  echo "                merely where counting stops); a file with no"
  echo "                zone-critical marker is skipped entirely even"
  echo "                carrying the same shape; and a host-tz-ok marker"
  echo "                sitting on the TOP line of a multi-line block (not"
  echo "                directly above the code) does NOT unblock."
  exit 0
fi

# ---------------------------------------------------------------------------
# Real run over the working tree. No allow-list — see header.
# ---------------------------------------------------------------------------
offenders="$(run_scan "$root")"

if [ -n "$offenders" ]; then
  echo "Host-local DateTime(...) instant anchor found in a zone-critical file"
  echo "under ${scan_dirs[*]}:"
  echo "$offenders"
  echo
  echo "A bare local DateTime(y, m, d, h, ...) resolves its underlying instant"
  echo "through the HOST PROCESS's own TZ. The dev VM this project is built on"
  echo "runs TZ=Europe/Kyiv — the SAME zone as the business timezone — so such"
  echo "a fixture is indistinguishable from a correctly-pinned one there and"
  echo "silently stops discriminating anything, while CI (TZ=UTC) or any other"
  echo "machine resolves it to a DIFFERENT instant. This exact defect class has"
  echo "shipped THREE times: Phase 225 audit cycles 4 and 5, and again on"
  echo "2026-08-02."
  echo
  echo "Pin the instant instead of the host clock:"
  echo "    DateTime.utc(2026, 8, 1, 23, 30)                               // a fixed instant"
  echo "    tz.TZDateTime(tz.getLocation('Asia/Tokyo'), 2026, 8, 2, 5, 0)  // a specific DEVICE zone"
  echo
  echo "Worked reference:"
  echo "    test/features/home/application/next_appointment_provider_test.dart:596-717"
  echo
  echo "If a bare local instant is genuinely correct here (rare — it means the"
  echo "test deliberately wants THIS PROCESS's own local clock, not a pinned"
  echo "one), annotate it:"
  echo "    // host-tz-ok: <why the host's own local clock is correct here>"
  echo
  echo "There is no allow-list for this gate and none should be added — every"
  echo "legitimate case is expressible as DateTime.utc(...) or a TZDateTime(...)"
  echo "pinned to a named device zone."
  exit 1
fi

exit 0

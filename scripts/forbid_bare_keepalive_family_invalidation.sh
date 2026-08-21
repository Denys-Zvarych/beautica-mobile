#!/usr/bin/env bash
# Keepalive-family cross-invalidation gate (this track's `ProviderSubscription`-
# closed crash class, mobile-debugger).
#
# THE BUG CLASS
# -------------
# `Bad state: called ProviderSubscription.read on a subscription that was
# closed`. The precondition: a keepAlive family member drops to ZERO listeners
# not because its screen was popped, but because the SAME still-mounted screen
# swapped which family key it watches via LOCAL mutable state (a rail tap, a
# sort toggle, a week/month page). `invalidateSelf()` then severs the keepAlive
# link and `mayNeedDispose()` queues disposal on a zero-duration Timer, which
# races the next frame's `ref.watch` re-subscribing to the SAME key — e.g. a
# rail-tap back to a day the master already viewed. Confirmed and fixed for
# `bookingsDayProvider` (`booking_calendar_invalidation.dart`'s FIX A/B),
# `masterReviewsProvider`/`salonReviewsProvider` (`review_surface_invalidation
# .dart`'s FIX C), and `effectiveScheduleProvider` (`weekly_schedule_notifier
# .dart`'s FIX D, backed by `effective_schedule_notifier.dart`'s
# `EffectiveScheduleRangeTracker`).
#
# A screen merely COVERED by another route is SAFE — Riverpod 3 pauses a
# covered consumer, its listener count stays > 0, and `mayNeedDispose` never
# queues disposal. This gate does not, and must not, flag that shape — it only
# ever looks at TEXT shape (a family watched via local state, invalidated from
# another file), never at runtime listener state, so there is nothing for it
# to get wrong here: covered-screen safety is a property of WHERE a screen
# sits in the nav stack at runtime, not of any line this gate can see.
#
# THE PROVEN REMEDY (do not invent a second mechanism)
# ------------------------------------------------------
# Gate on "was this key pinned?" (`DayKeepAliveLru.contains` /
# `WidgetRef.exists` / `EffectiveScheduleRangeTracker` — three spellings of the
# same "does an element already exist for this key" question), THEN
# `ref.invalidate`, THEN — only when the key was pinned — an eager
# `ref.read`/`ref.watch(...).future` so `element.flush()` re-touches the
# keepAlive link before the scheduler's queued disposal task ever fires,
# cancelling it deterministically.
#
# THE RULE THIS GATE ENFORCES
# ----------------------------
# Two passes, geared to catch the SHAPE of the bug rather than re-deriving the
# fix logic itself (that is unverifiable by grep — this is defense-in-depth
# requiring human review + annotation, exactly like
# `forbid_provider_self_invalidation.sh`):
#
#   PASS 1 — discover every family watched through a LOCAL/PRIVATE (`_`-
#   prefixed) variable key, e.g. `ref.watch(bookingsDayProvider(_liveQuery))`
#   or `ref.watch(masterReviewsProvider(masterId, _sort))`. A `widget.<field>`
#   key is NOT flagged here — that reads the immutable widget config, not
#   State's own mutable field, so it cannot swap keys on an otherwise
#   still-mounted screen the way a bare `_field` can. On today's tree this
#   discovers exactly `{bookingsDayProvider, masterReviewsProvider,
#   salonReviewsProvider, effectiveScheduleProvider}` — the four confirmed
#   sites — but the pass is genuinely computed, not a hardcoded list, so a
#   FIFTH family watched the same way is caught automatically.
#
#   PASS 2 — for every family PASS 1 found, flag every `ref.invalidate(
#   <family>Provider` / `ref.refresh(<family>Provider` occurrence (bare OR
#   keyed) OUTSIDE the family's OWNING file (the file that actually defines
#   the `@riverpod`/`@Riverpod` provider — resolved automatically via the
#   generated `.g.dart`'s `name: r'<family>Provider'` + its `part of
#   '<source>.dart'` directive, never hardcoded), unless the site is:
#     (a) annotated `// keepalive-safe: <reason>` on the same (collapsed) line
#         or anywhere in the unbroken run of `//` comment lines immediately
#         above it (mirrors `forbid_provider_self_invalidation.sh`'s
#         `// cycle-safe:` walk-upward exactly), or
#     (b) listed in `scripts/.keepalive_family_invalidation_allow` as
#         `<repo-relative-path>:<line>   # reason` (mirrors
#         `forbid_inline_fontsize.sh`'s line-level allow-list format exactly).
#
# Self-invalidation FROM the owning file is excluded by construction (that
# shape is `forbid_provider_self_invalidation.sh`'s own job) — this gate is
# deliberately about the CROSS-file case, where the caller does not obviously
# see the local-state-driven watcher it might race.
#
# MULTILINE COLLAPSE IS LOAD-BEARING
# ------------------------------------
# A naive single-line grep MISSED the confirmed bug's exact shape:
# `bookings_discovery_view.dart:876`'s
#     ref.watch(
#       bookingsDayProvider(_liveQuery),
#     )
# Both passes collapse a `ref.watch(`/`ref.invalidate(`/`ref.refresh(`
# opener's unbalanced parens across physical lines into one logical line
# before testing — same balanced-paren `awk` technique
# `forbid_provider_self_invalidation.sh` uses, generalised to run as ONE awk
# process PER PASS over every file (positional file arguments, `FNR`/
# `FILENAME` bookkeeping) rather than the N-forked-processes-for-N-files shape
# named as this repo's slowest gates' anti-pattern — `find lib -name '*.dart'`
# is ~500+ files, and forking `awk` once per file (as
# `forbid_provider_self_invalidation.sh`'s own `scan_file`-per-notifier-file
# loop does, safely, because that loop is bounded to the much smaller
# `*notifier*.dart` set) would reintroduce exactly that cost here. A dedicated
# self-test fixture pins that the multiline case is actually seen.
#
# CI hard-gate (run from `.github/workflows/pr-validate.yml`); also runnable
# locally before pushing, and auto-discovered by `scripts/verify_guards.sh`.
# Self-test:  ./scripts/forbid_bare_keepalive_family_invalidation.sh --self-test

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
default_allow="$here/.keepalive_family_invalidation_allow"

# ---------------------------------------------------------------------------
# pass1_scan <file...>
#   ONE awk process over every file given (positional args — `FNR`/`FILENAME`
#   track per-file line numbers natively; no per-file loop). Emits
#   "<file>:<line>:<FamilyProviderName>" for every `ref.watch(<Family>Provider
#   (...))` call — collapsed across lines when the opener's parens are not
#   balanced on one line — whose argument list contains a bare `_identifier`
#   token not immediately preceded by `.` or a word character (i.e. NOT a
#   `widget.<field>` access).
# ---------------------------------------------------------------------------
pass1_scan() {
  awk '
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
    function paren_delta(s,   code, i, c, d) {
      code = strip_strings(s); d = 0
      for (i = 1; i <= length(code); i++) {
        c = substr(code, i, 1)
        if (c == "(") d++
        else if (c == ")") d--
      }
      return d
    }
    FNR == 1 { file = FILENAME }
    {
      trimmed = $0
      sub(/^[[:space:]]+/, "", trimmed)
      is_comment_line = (trimmed ~ /^[/][/]/)
      if (is_comment_line) next

      line = $0
      openerNR = FNR
      stripped = strip_strings(line)
      if (stripped ~ /ref[.]watch[(]/ && paren_delta(line) > 0) {
        depth = paren_delta(line)
        collapsed = line
        while (depth > 0 && (getline nxt) > 0) {
          collapsed = collapsed " " nxt
          depth += paren_delta(nxt)
        }
        line = collapsed
      }

      codeonly = strip_strings(line)
      if (codeonly !~ /ref[.]watch[(]/) next

      famwhere = match(codeonly, /[A-Za-z_][A-Za-z0-9_]*Provider[(]/)
      if (famwhere == 0) next
      before = substr(codeonly, 1, famwhere - 1)
      if (before ~ /[/][/]/) next

      famtext = substr(codeonly, famwhere, RLENGTH)
      famname = famtext
      sub(/[(]$/, "", famname)
      argtail = substr(codeonly, famwhere + RLENGTH)

      if (argtail ~ /(^|[^A-Za-z0-9_.])_[A-Za-z][A-Za-z0-9_]*/) {
        printf "%s:%d:%s\n", file, openerNR, famname
      }
    }
  ' "$@"
}

# ---------------------------------------------------------------------------
# pass2_scan <fams-csv> <owners-csv> <file...>
#   <fams-csv>   comma-joined family PROVIDER names, e.g.
#                "bookingsDayProvider,masterReviewsProvider"
#   <owners-csv> comma-joined owning-file paths, SAME ORDER/LENGTH as
#                <fams-csv> (parallel arrays, split in BEGIN)
#   ONE awk process over every <file> given. Emits "<file>:<line>:<text>" for
#   every un-annotated `ref.invalidate(<family>` / `ref.refresh(<family>`
#   occurrence (bare OR keyed, collapsed across lines) whose family is one of
#   <fams-csv>, EXCLUDING occurrences inside that family's own owning file.
# ---------------------------------------------------------------------------
pass2_scan() {
  local fams_csv="$1" owners_csv="$2"
  shift 2
  awk -v fams="$fams_csv" -v owners="$owners_csv" '
    BEGIN {
      n = split(fams, famname, ",")
      split(owners, owningfile, ",")
    }
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
    function paren_delta(s,   code, i, c, d) {
      code = strip_strings(s); d = 0
      for (i = 1; i <= length(code); i++) {
        c = substr(code, i, 1)
        if (c == "(") d++
        else if (c == ")") d--
      }
      return d
    }
    # Which (if any) discovered family this collapsed logical LINE invokes
    # ref.invalidate/refresh on, honouring the owning-file exclusion. Returns
    # "" when none match or the only match is inside the owning file of that
    # family.
    function matching_family(codeonly,   fi, fp, pat) {
      for (fi = 1; fi <= n; fi++) {
        fp = famname[fi]
        pat = "(^|[^A-Za-z0-9_])" fp "([^A-Za-z0-9_]|$)"
        if (codeonly ~ pat) {
          if (file == owningfile[fi]) continue
          return famname[fi]
        }
      }
      return ""
    }
    FNR == 1 { file = FILENAME; comment_run_annotated = 0 }
    {
      trimmed = $0
      sub(/^[[:space:]]+/, "", trimmed)
      is_comment_line = (trimmed ~ /^[/][/]/)

      line = $0
      openerNR = FNR
      stripped = strip_strings(line)
      if (!is_comment_line && stripped ~ /ref[.](invalidate|refresh)[(]/ && paren_delta(line) > 0) {
        depth = paren_delta(line)
        collapsed = line
        while (depth > 0 && (getline nxt) > 0) {
          collapsed = collapsed " " nxt
          depth += paren_delta(nxt)
        }
        line = collapsed
      }

      if (line ~ /ref[.](invalidate|refresh)[(]/) {
        if (is_comment_line) {
          if (trimmed ~ /^[/][/][[:space:]]*keepalive-safe:/) comment_run_annotated = 1
          next
        }
        codeonly = strip_strings(line)
        where = match(codeonly, /ref[.](invalidate|refresh)[(]/)
        if (where > 0) {
          before = substr(codeonly, 1, where - 1)
          if (before ~ /[/][/]/) { comment_run_annotated = 0; next }
        }

        hit = matching_family(codeonly)
        if (hit == "") { comment_run_annotated = 0; next }

        if (line ~ /[/][/][[:space:]]*keepalive-safe:/ || comment_run_annotated) {
          comment_run_annotated = 0
          next
        }
        printf "%s:%d:%s\n", file, openerNR, line
        comment_run_annotated = 0
        next
      }

      if (is_comment_line) {
        if (trimmed ~ /^[/][/][[:space:]]*keepalive-safe:/) comment_run_annotated = 1
      } else {
        comment_run_annotated = 0
      }
    }
  ' "$@"
}

# ---------------------------------------------------------------------------
# owning_file_for <tree_root> <FamilyProviderName>
#   Resolves the repo-relative source file that DEFINES <FamilyProviderName>,
#   via the generated `.g.dart`'s `name: r'<FamilyProviderName>'` (unique per
#   provider) and its `part of '<source>.dart';` directive. Empty output if
#   unresolvable (e.g. codegen hasn't run) — pass2_scan then simply never
#   matches that family against an owning file, which only makes the gate
#   MORE strict (a false owning-file miss cannot hide a real offender; it can
#   only over-flag the true owning file's own harmless self-reference, which
#   would then need — and deserve — its own allow-list entry).
# ---------------------------------------------------------------------------
owning_file_for() {
  local tree_root="$1" fam="$2"
  local gdart partof
  gdart="$(grep -rl "name: r'${fam}'" "$tree_root/lib" --include='*.g.dart' 2>/dev/null | head -1)"
  [ -z "$gdart" ] && return 0
  partof="$(grep -m1 "^part of '" "$gdart" 2>/dev/null | sed -E "s/^part of '([^']+)';/\1/")"
  [ -z "$partof" ] && return 0
  printf '%s/%s\n' "$(dirname "$gdart")" "$partof"
}

# ---------------------------------------------------------------------------
# is_keepalive_owner <owning-file>
#   True iff <owning-file> contains a genuine `ref.keepAlive(` CALL on a
#   non-comment line (a `@Riverpod(keepAlive: true)` provider — e.g.
#   `dayKeepAliveLruProvider` itself — has no per-element `ref.keepAlive()`
#   call to find and is a container-scoped SINGLETON anyway, not a per-key
#   family this bug class touches).
#
#   WHY THIS FILTER EXISTS — PASS 1's local-var-key pattern alone is not
#   sufficient: `masterArchiveProvider(_query)`, `workingDaysProvider
#   (_workingDaysQuery(...))` and `salonMasterDaySlotsProvider(...)` are ALL
#   watched through local mutable state too (same textual shape as the four
#   real sites), but their owning notifiers are PLAIN `@riverpod` autoDispose
#   with no manual `ref.keepAlive()` — a zero-listener member there is
#   disposed OUTRIGHT, immediately, with no `KeepAliveLink` for
#   `invalidateSelf()`'s `mayNeedDispose()` to find still attached, so there is
#   nothing for a later `ref.watch` to race: the element is just gone and
#   rebuilds fresh, every time. Without this filter PASS 1 over-discovers, and
#   every one of those genuinely-safe retry buttons would need a
#   `// keepalive-safe:` annotation it does not need — noise that would drown
#   the gate's real signal.
# ---------------------------------------------------------------------------
is_keepalive_owner() {
  local owner="$1"
  [ -z "$owner" ] && return 1
  [ -f "$owner" ] || return 1
  grep -Ev '^[[:space:]]*//' "$owner" 2>/dev/null | grep -q 'ref[.]keepAlive[(]'
}

# ---------------------------------------------------------------------------
# run_gate <tree_root>
#   Full two-pass run over <tree_root>. Emits offenders (pass 2, minus
#   annotations, minus the allow-list) on stdout; nothing on a clean tree.
# ---------------------------------------------------------------------------
run_gate() {
  local tree_root="$1"
  local allow_file="${2:-$default_allow}"

  local -a files=()
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    files+=("$f")
  done < <(find "$tree_root/lib" -type f -name '*.dart' ! -name '*.g.dart' 2>/dev/null | sort)

  if [ "${#files[@]}" -eq 0 ]; then
    return 0
  fi

  local p1
  p1="$(pass1_scan "${files[@]}")"

  # Deduplicate discovered family names (column 3, ":"-delimited) into a CSV,
  # preserving first-seen order (irrelevant to correctness, stable for
  # reproducible self-test output).
  local fams_csv=""
  local -a fam_list=()
  local line fam seen
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    fam="${line##*:}"
    seen=0
    for f in "${fam_list[@]:-}"; do
      [ "$f" = "$fam" ] && seen=1 && break
    done
    if [ "$seen" -eq 0 ]; then
      fam_list+=("$fam")
    fi
  done <<< "$p1"

  if [ "${#fam_list[@]}" -eq 0 ]; then
    return 0
  fi

  local owners_csv=""
  local owner
  for fam in "${fam_list[@]}"; do
    owner="$(owning_file_for "$tree_root" "$fam")"
    # See is_keepalive_owner's doc: PASS 1's textual pattern alone over-
    # discovers plain-autoDispose families with no keepAlive precondition —
    # this bug class cannot reach them, so they are dropped here rather than
    # forwarded to PASS 2 for noisy, unnecessary allow-listing.
    is_keepalive_owner "$owner" || continue
    fams_csv="${fams_csv:+$fams_csv,}$fam"
    owners_csv="${owners_csv:+$owners_csv,}$owner"
  done

  if [ -z "$fams_csv" ]; then
    return 0
  fi

  local p2
  p2="$(pass2_scan "$fams_csv" "$owners_csv" "${files[@]}")"

  # Load the allow-list (repo-relative path:line, "#" reason stripped, all
  # whitespace stripped before keying) — same convention as
  # `forbid_inline_fontsize.sh`'s `.inline_fontsize_allow`.
  local -A allow=()
  if [ -f "$allow_file" ]; then
    local raw stripped key
    while IFS= read -r raw; do
      stripped="${raw%%#*}"
      key="$(printf '%s' "$stripped" | tr -d '[:space:]')"
      [ -n "$key" ] && allow["$key"]=1
    done < "$allow_file"
  fi

  local h loc rest lineno relloc
  while IFS= read -r h; do
    [ -z "$h" ] && continue
    loc="${h%%:*}"
    rest="${h#*:}"
    lineno="${rest%%:*}"
    relloc="${loc#"$tree_root"/}"
    [ -n "${allow["$relloc:$lineno"]:-}" ] && continue
    printf '%s\n' "$h"
  done <<< "$p2"
}

# ---------------------------------------------------------------------------
# Self-test mode.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  mkdir -p "$tmp/lib/features/probe/application" "$tmp/lib/features/probe/presentation"

  # The OWNING file — defines `probeThingProvider`, mirrors a real
  # `@riverpod` family + its generated companion closely enough for
  # `owning_file_for` to resolve it the same way it resolves the real ones. A
  # genuine `ref.keepAlive(` CALL (not just the word in prose) is what makes
  # this family a candidate at all — see `is_keepalive_owner`'s doc.
  cat > "$tmp/lib/features/probe/application/probe_thing_notifier.dart" <<'EOF'
// probe fixture — mentions keepAlive in prose here, which must NOT count:
// this comment alone does not make the family below keepAlive.
class ProbeThingNotifier {
  void build(Ref ref) {
    ref.keepAlive();
  }
}
EOF
  cat > "$tmp/lib/features/probe/application/probe_thing_notifier.g.dart" <<'EOF'
// GENERATED CODE - DO NOT MODIFY BY HAND
part of 'probe_thing_notifier.dart';
final probeThingProvider = 1;
// name: r'probeThingProvider'
EOF

  # A SECOND family, textually identical in shape (local-var-keyed watch,
  # cross-file bare invalidate) but PLAIN autoDispose — no `ref.keepAlive(`
  # anywhere in its owning file. Mirrors the real `masterArchiveProvider` /
  # `workingDaysProvider` / `salonMasterDaySlotsProvider` false-positive shape
  # `is_keepalive_owner` exists to filter out: this bug class cannot reach a
  # plain-autoDispose member (zero listeners disposes it outright, nothing for
  # a later watch to race), so it must never even reach PASS 2, let alone
  # require an allow-list entry.
  cat > "$tmp/lib/features/probe/application/probe_plain_notifier.dart" <<'EOF'
class ProbePlainNotifier {}
EOF
  cat > "$tmp/lib/features/probe/application/probe_plain_notifier.g.dart" <<'EOF'
// GENERATED CODE - DO NOT MODIFY BY HAND
part of 'probe_plain_notifier.dart';
final probePlainProvider = 1;
// name: r'probePlainProvider'
EOF

  # The WATCHING screen — probe 1: single-line local-var watch (`_key`).
  # probe 2: `widget.key` watch — MUST NOT be discovered by pass 1.
  # probe 3: the confirmed bug's exact MULTILINE shape (`ref.watch(\n
  #   probeThingProvider(_liveKey),\n)`) — the self-test's load-bearing case.
  # probe 4: the plain-autoDispose family, same local-var shape.
  cat > "$tmp/lib/features/probe/presentation/probe_screen.dart" <<'EOF'
class _ProbeScreenState {
  String _key = 'a';

  Widget buildOne(WidgetRef ref) {
    final a = ref.watch(probeThingProvider(_key));
    return a;
  }

  Widget buildTwo(WidgetRef ref) {
    final b = ref.watch(otherThingProvider(widget.key));
    return b;
  }

  Widget buildThree(WidgetRef ref) {
    final AsyncValue<int> c = ref.watch(
      probeThingProvider(_liveKey),
    );
    return c;
  }

  Widget buildFour(WidgetRef ref) {
    final d = ref.watch(probePlainProvider(_plainKey));
    return d;
  }
}
EOF

  # A DIFFERENT file, cross-file bare-family invalidate of the discovered
  # family — the exact shape this gate exists to flag. One un-annotated
  # offender, one `// keepalive-safe:`-annotated line that must NOT be
  # flagged, one bare (no-args) invalidate that must ALSO be flagged (the
  # ORIGINAL bug shape, before any of the four real fixes scoped it).
  mkdir -p "$tmp/lib/features/probe/other"
  cat > "$tmp/lib/features/probe/other/probe_writer.dart" <<'EOF'
class ProbeWriter {
  void unsafe(Ref ref) {
    ref.invalidate(probeThingProvider(_someKey));
  }

  void bareUnsafe(Ref ref) {
    ref.invalidate(probeThingProvider);
  }

  void safe(Ref ref) {
    // keepalive-safe: pinned target eager-read back immediately after, see doc
    ref.invalidate(probeThingProvider(_otherKey));
  }

  void plainFamilyBareInvalidate(Ref ref) {
    // No keepAlive precondition — must NEVER be flagged, annotated or not.
    ref.invalidate(probePlainProvider);
  }
}
EOF

  # A THIRD file, allow-listed by path:line instead of by inline annotation.
  mkdir -p "$tmp/lib/features/probe/allowlisted"
  cat > "$tmp/lib/features/probe/allowlisted/probe_legacy_writer.dart" <<'EOF'
class ProbeLegacyWriter {
  void legacy(Ref ref) {
    ref.invalidate(probeThingProvider(_legacyKey));
  }
}
EOF
  allow="$tmp/allow"
  cat > "$allow" <<EOF
lib/features/probe/allowlisted/probe_legacy_writer.dart:3   # legacy, reviewed
EOF

  out="$(run_gate "$tmp" "$allow")"
  flagged="$(printf '%s\n' "$out" | grep -c . || true)"

  # Expect exactly 2 offenders: probe_writer.dart's `unsafe` (keyed) AND
  # `bareUnsafe` (bare-family) lines. Everything else must be silent:
  # probe_thing_notifier.dart (owning file), the `keepalive-safe`-annotated
  # `safe()`, and the path:line-allow-listed legacy writer.
  if [ "$flagged" -ne 2 ]; then
    echo "SELF-TEST FAIL: expected exactly 2 offenders (probe_writer.dart's"
    echo "                unsafe() + bareUnsafe()), got $flagged:"
    printf '%s\n' "$out"
    exit 1
  fi
  if ! printf '%s\n' "$out" | grep -q "probe_writer.dart:3:"; then
    echo "SELF-TEST FAIL: the KEYED cross-file invalidate (probe_writer.dart"
    echo "                line 3, unsafe()) was not flagged:"
    printf '%s\n' "$out"
    exit 1
  fi
  if ! printf '%s\n' "$out" | grep -q "probe_writer.dart:7:"; then
    echo "SELF-TEST FAIL: the BARE-FAMILY cross-file invalidate"
    echo "                (probe_writer.dart line 7, bareUnsafe()) was not"
    echo "                flagged — a bare family invalidate is the ORIGINAL"
    echo "                shape of this bug class and must still be caught:"
    printf '%s\n' "$out"
    exit 1
  fi
  if printf '%s\n' "$out" | grep -q "probe_writer.dart:12:"; then
    echo "SELF-TEST FAIL: the // keepalive-safe: annotated line was flagged"
    echo "                anyway:"
    printf '%s\n' "$out"
    exit 1
  fi
  if printf '%s\n' "$out" | grep -q "probePlainProvider\|probe_writer.dart:17:"; then
    echo "SELF-TEST FAIL: the PLAIN-autoDispose family's bare invalidate"
    echo "                (probe_writer.dart:17, plainFamilyBareInvalidate)"
    echo "                was flagged — is_keepalive_owner must exclude a"
    echo "                family with no ref.keepAlive( call in its owning"
    echo "                file BEFORE pass 2 ever sees it (this bug class"
    echo "                cannot reach a plain-autoDispose member: zero"
    echo "                listeners disposes it outright, nothing left for a"
    echo "                later watch to race):"
    printf '%s\n' "$out"
    exit 1
  fi
  if printf '%s\n' "$out" | grep -q "probe_legacy_writer.dart"; then
    echo "SELF-TEST FAIL: the path:line-allow-listed legacy writer was"
    echo "                flagged anyway:"
    printf '%s\n' "$out"
    exit 1
  fi
  if printf '%s\n' "$out" | grep -q "probe_thing_notifier.dart"; then
    echo "SELF-TEST FAIL: the OWNING file was flagged — self-invalidation"
    echo "                from the defining file must be excluded (that shape"
    echo "                belongs to forbid_provider_self_invalidation.sh):"
    printf '%s\n' "$out"
    exit 1
  fi

  # Pass-1 discovery precision, checked directly: `_key` (single-line) and
  # `_liveKey` (MULTILINE — the confirmed bug's exact shape) both discover
  # `probeThingProvider`; `widget.key` must NOT (that is the immutable-config
  # case this gate must not chase).
  p1_files=()
  while IFS= read -r f; do [ -n "$f" ] && p1_files+=("$f"); done < <(
    find "$tmp/lib" -type f -name '*.dart' ! -name '*.g.dart' | sort
  )
  p1_out="$(pass1_scan "${p1_files[@]}")"
  if ! printf '%s\n' "$p1_out" | grep -q "probe_screen.dart:5:probeThingProvider"; then
    echo "SELF-TEST FAIL: pass 1 did not discover the SINGLE-LINE local-var"
    echo "                watch (probe_screen.dart:5, buildOne):"
    printf '%s\n' "$p1_out"
    exit 1
  fi
  if ! printf '%s\n' "$p1_out" | grep -q "probe_screen.dart:15:probeThingProvider"; then
    echo "SELF-TEST FAIL: pass 1 did not discover the MULTILINE local-var"
    echo "                watch (probe_screen.dart:15, buildThree) — this is"
    echo "                the confirmed bug's exact"
    echo "                'ref.watch(\\n  fooProvider(_x),\\n)' shape; a gate"
    echo "                that cannot see it is broken by the same hole that"
    echo "                let the real bug through:"
    printf '%s\n' "$p1_out"
    exit 1
  fi
  if printf '%s\n' "$p1_out" | grep -q "otherThingProvider"; then
    echo "SELF-TEST FAIL: pass 1 discovered the widget.key-keyed watch"
    echo "                (buildTwo) — that reads the immutable widget"
    echo "                config, not local mutable State, and must NOT be"
    echo "                treated as at-risk:"
    printf '%s\n' "$p1_out"
    exit 1
  fi

  echo "SELF-TEST PASS: local/private-var family watches are discovered"
  echo "                (single-line AND multiline), widget.field watches are"
  echo "                not; cross-file bare AND keyed invalidates of a"
  echo "                discovered family are flagged; the owning file,"
  echo "                // keepalive-safe: annotated lines, and path:line"
  echo "                allow-list entries are all silent."
  echo "SELF-TEST OK: forbid_bare_keepalive_family_invalidation.sh"
  exit 0
fi

# ---------------------------------------------------------------------------
# Real run over the working tree.
# ---------------------------------------------------------------------------
offenders="$(run_gate "$root")"

if [ -n "$offenders" ]; then
  echo "Cross-file invalidation of a locally-keyed keepAlive family found:"
  echo "$offenders"
  echo
  echo "This is the shape of the ProviderSubscription-closed crash class (see"
  echo "this script's header): a family watched via LOCAL mutable state on one"
  echo "screen, invalidated bare-or-keyed from a DIFFERENT file, can race"
  echo "Riverpod's queued disposal of a pinned-but-unwatched element."
  echo
  echo "Fix it with the proven idiom (gate on WidgetRef.exists /"
  echo "DayKeepAliveLru.contains / an equivalent tracker, THEN invalidate,"
  echo "THEN — only if it was pinned — an eager ref.read so element.flush()"
  echo "cancels the queued disposal). See booking_calendar_invalidation.dart's"
  echo "FIX A/B, review_surface_invalidation.dart's FIX C, or"
  echo "weekly_schedule_notifier.dart's FIX D for worked examples."
  echo
  echo "If this site is ALREADY protected by that idiom (or is provably safe"
  echo "for another reason), annotate it in place:"
  echo "    // keepalive-safe: <why this specific invalidate cannot race>"
  echo "or add it to scripts/.keepalive_family_invalidation_allow as"
  echo "    <repo-relative-path>:<line>   # reason"
  exit 1
fi

exit 0

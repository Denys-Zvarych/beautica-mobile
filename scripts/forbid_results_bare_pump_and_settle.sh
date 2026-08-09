#!/usr/bin/env bash
# Bare-pumpAndSettle-on-the-results-screen gate (2026-07-31 harness-repair safeguard).
#
# THE FRAGILITY THIS GUARDS
# -------------------------
# `SearchResultsScreen` mounts a trailing `_LoadMoreSpinner`
# (search_results_screen.dart) whenever `data.hasMore` is true. That spinner is
# an INDETERMINATE `CircularProgressIndicator` — no `value:`, so its
# `AnimationController` `repeat()`s forever and keeps a frame permanently
# scheduled. `FakeBackend` seeds `totalPages: 2`, so every integration flow that
# lands on the results screen has it mounted from the instant page 0 arrives.
#
# A bare `await tester.pumpAndSettle()` while that spinner is up can therefore
# NEVER observe quiescence. It does not fail politely: it pumps until the test's
# own 90 s timeout fires MID-PUMP, which trips `!_expectingFrame` in
# `LiveTestWidgetsFlutterBinding.postTest` and takes down every LATER test in the
# file with a bare `!inTest` assertion. When this last bit
# `integration_test/client_search_flow_test.dart`, tests 5–11 died without
# executing a single line — which is why seven tests had never once been
# observed running. The blast radius is the whole file, and the error names
# neither the real cause nor the offending line.
#
# The deterministic alternative is to wait for the thing you actually want:
#   AppHarness.pumpUntilFound(tester, find.byKey(const Key('...')))
#   AppHarness.pumpUntilCondition(tester, () => <predicate>)
# both of which are bounded and return the moment the awaited state exists.
#
# This hazard was DOCUMENTED in comments six separate times in that one file and
# still recurred on the seventh new flow. Prose does not gate; this does.
#
# THE RULE
# --------
# Inside `integration_test/**`, a bare `tester.pumpAndSettle()` (no arguments) is
# forbidden when it directly follows a TAP on a results-screen control:
#   search_show_masters_cta | results_sort_button | results_list
# "Directly follows" = within a short line window after the tap, with no
# `pumpUntilFound` / `pumpUntilCondition` in between (either of those is the
# correct fix and clears the window). The trigger key may sit on the tap line
# itself (`tester.tap(find.byKey(const Key('results_sort_button')))`) or a few
# lines above it, bound to a local (`final sortBtn = find.byKey(...); ...
# tester.tap(sortBtn);`) — both shapes occur in the corpus, so the window looks
# BOTH ways.
#
# A legitimate case — most importantly tapping a DELIBERATELY INERT control,
# where no navigation and no spinner follow — is unblocked with a
# `// results-settle-ok: <reason>` comment on the same line, or anywhere in the
# contiguous comment block directly above (so a multi-line justification, which
# is the comment worth writing, is not penalised).
#
# KNOWN BLIND SPOTS (stated honestly — this is a grep, not a type system)
# ----------------------------------------------------------------------
# 1. THE REAL HAZARD CONDITION IS RUNTIME, NOT TEXTUAL. What actually hangs is
#    "spinner mounted", i.e. `hasMore == true` — not "results screen present".
#    `client_search_flow_test.dart:612` is a bare `pumpAndSettle()` executed ON
#    the results screen that is CORRECT and green, because by then the last page
#    had loaded and the spinner was gone. No grep can tell those apart. So this
#    gate deliberately does NOT flag every `pumpAndSettle` under a mounted
#    results screen — an earlier draft of this gate did exactly that and
#    produced 10 false positives against a fully-green corpus, which is how a
#    guard earns itself an `# noqa` and stops protecting anything. It gates the
#    narrow, local, purely syntactic shape that the real defect actually took.
# 2. No brace balancing. The window is a fixed line count, not a scope.
# 3. Only `tester.tap` arms it. A drag / `enterText` / `ensureVisible` on the
#    results screen followed by a bare settle is not caught.
# 4. Helper indirection evades it: a helper that taps the CTA and is called from
#    another file arms nothing at the call site.
# Items 2–4 are the same class of evasion `forbid_fixed_wait.sh` and
# `forbid_naive_router_location.sh` accept. Textual gates catch the common case.
#
# CI hard-gate (run from `.github/workflows/pr-validate.yml`); also runnable
# locally before pushing.
# Self-test:  ./scripts/forbid_results_bare_pump_and_settle.sh --self-test

set -euo pipefail

# Results-screen controls whose tap puts the (spinner-bearing) results screen on
# screen or re-keys its data.
triggers='search_show_masters_cta|results_sort_button|results_list'
# Bare, ARGUMENT-LESS settle. `pumpAndSettle(const Duration(...))` is a
# different idiom, already owned by scripts/forbid_fixed_wait.sh.
bare_settle='tester[.]pumpAndSettle[(][)]'
# The correct fix — either clears the window.
pump_until='pumpUntilFound|pumpUntilCondition'
annotation='[/][/][[:space:]]*results-settle-ok:'

# How many lines after the tap still count as "directly follows", and how many
# lines before the tap a trigger-bound local still counts as the tap's target.
window_after=6
window_before=5

# ---------------------------------------------------------------------------
# scan_file <path>
#   Emits "<path>:<line>:<text>" for each offending bare settle.
#
#   Genuine `//` comment lines are inert for every purpose (this corpus carries
#   long prose blocks that name these very keys and call out `pumpAndSettle()`
#   by name — treating those as code would flag the documentation explaining the
#   bug).
# ---------------------------------------------------------------------------
scan_file() {
  awk -v file="$1" -v trig="$triggers" -v settle="$bare_settle" \
      -v until_re="$pump_until" -v ann="$annotation" \
      -v wa="$window_after" -v wb="$window_before" '
    {
      line = $0

      # Genuine comment line? Inert as code. But an annotation anywhere in the
      # CONTIGUOUS comment block directly above a call still unblocks it — a
      # one-line cap would punish writing a proper multi-line justification,
      # which is exactly the comment we want people to write.
      firsttok = line
      sub(/^[[:space:]]+/, "", firsttok)
      if (firsttok ~ /^[/][/]/) {
        if (line ~ ann) annblock = 1
        prev = line
        next
      }

      # Strip any trailing // comment so prose after code cannot arm the gate.
      ci = index(line, "//")
      code = (ci > 0) ? substr(line, 1, ci - 1) : line

      # A trigger token seen on a code line stays "recent" for wb lines, so a
      # local bound to the finder still associates with a later tester.tap.
      if (code ~ trig) recent = wb + 1

      # Arm when a tap coincides with a recent OR same-line trigger.
      if (code ~ /tester\.tap\(/ && (recent > 0 || code ~ trig)) win = wa + 1

      if (win > 0) {
        if (code ~ until_re) {
          win = 0                      # correct wait — window closed
        } else if (code ~ settle) {
          if (line !~ ann && !annblock) printf "%s:%d:%s\n", file, NR, line
          win = 0
        }
      }

      if (recent > 0) recent--
      if (win > 0) win--
      annblock = 0          # a code line ends the preceding comment block
      prev = line
    }
  ' "$1"
}

# ---------------------------------------------------------------------------
# Self-test mode: pinned snippets, asserted verdicts.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  # (1) inline CTA tap + bare settle → OFFENDER (the original defect shape)
  cat > "$tmp/bad_inline.dart" <<'EOF'
    await tester.tap(find.byKey(const Key('search_show_masters_cta')));
    await tester.pumpAndSettle();
EOF

  # (2) trigger bound to a local, tapped 2 lines later → OFFENDER
  cat > "$tmp/bad_local.dart" <<'EOF'
    final Finder sortBtn = find.byKey(const Key('results_sort_button'));
    await tester.ensureVisible(sortBtn);
    await tester.tap(sortBtn);
    await tester.pumpAndSettle();
EOF

  # (3) tap + pumpUntilFound → OK (the correct fix)
  cat > "$tmp/good_until.dart" <<'EOF'
    await tester.tap(find.byKey(const Key('search_show_masters_cta')));
    await AppHarness.pumpUntilFound(
      tester,
      find.byKey(const Key('results_list')),
    );
EOF

  # (4) tap + bare settle BUT annotated → OK
  cat > "$tmp/good_ann.dart" <<'EOF'
    await tester.tap(find.byKey(const Key('search_show_masters_cta')));
    // results-settle-ok: the CTA is disabled here; the tap is inert by design
    await tester.pumpAndSettle();
EOF

  # (4b) annotation inside a MULTI-LINE justification block → OK
  cat > "$tmp/good_ann_block.dart" <<'EOF'
    await tester.tap(find.byKey(const Key('search_show_masters_cta')));
    // results-settle-ok: the CTA is DISABLED here (onPressed == null), so
    // this tap pushes nothing — the results screen never mounts and there is
    // no _LoadMoreSpinner to keep a frame scheduled.
    await tester.pumpAndSettle();
EOF

  # (5) bare settle far from any results tap → OK (unrelated screen)
  cat > "$tmp/good_far.dart" <<'EOF'
    await tester.tap(find.byKey(const Key('salon-tab-1')));
    await tester.pumpAndSettle();
EOF

  # (6) prose naming the keys AND pumpAndSettle() → OK (comments are inert)
  cat > "$tmp/good_prose.dart" <<'EOF'
    // NOT `pumpAndSettle()` — tapping results_sort_button leaves the
    // results_list spinner mounted, so tester.pumpAndSettle() would hang.
    await AppHarness.pumpUntilFound(tester, sortBtn);
EOF

  # (7) bare settle BEFORE the tap → OK (window looks forward, not backward)
  cat > "$tmp/good_before.dart" <<'EOF'
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('search_show_masters_cta')));
    await AppHarness.pumpUntilFound(tester, find.byKey(const Key('results_list')));
EOF

  flagged=""
  for snip in bad_inline bad_local good_until good_ann good_ann_block good_far good_prose good_before; do
    out="$(scan_file "$tmp/$snip.dart")"
    [ -n "$out" ] && flagged="$flagged $snip"
  done
  flagged="$(printf '%s' "$flagged" | sed 's/^ //')"

  if [ "$flagged" != "bad_inline bad_local" ]; then
    echo "SELF-TEST FAIL: expected 'bad_inline bad_local', got: '$flagged'"
    exit 1
  fi
  echo "SELF-TEST PASS: both offending tap→bare-settle shapes (inline finder and"
  echo "                trigger-bound local) flagged; pumpUntilFound / annotated"
  echo "                (single- AND multi-line) / unrelated / prose-only /"
  echo "                settle-before-tap files clean."
  exit 0
fi

# integration_test only — the widget tier has no live binding and no FakeBackend
# pagination, so the hang mode this gates does not exist there.
mapfile -t files < <(find integration_test -type f -name '*.dart' 2>/dev/null | sort -u)

[ "${#files[@]}" -eq 0 ] && exit 0

offenders=""
for f in "${files[@]}"; do
  hit="$(scan_file "$f")"
  [ -n "$hit" ] && offenders+="$hit"$'\n'
done
offenders="$(printf '%s' "$offenders" | sed '/^$/d')"

if [ -n "$offenders" ]; then
  echo "Bare tester.pumpAndSettle() directly after a results-screen tap:"
  echo "$offenders"
  echo
  echo "SearchResultsScreen mounts an INDETERMINATE _LoadMoreSpinner whenever"
  echo "data.hasMore is true (FakeBackend seeds totalPages: 2), so its repeating"
  echo "AnimationController keeps a frame scheduled forever and pumpAndSettle()"
  echo "can never reach quiescence. It then times out MID-PUMP, tripping"
  echo "!_expectingFrame in LiveTestWidgetsFlutterBinding.postTest — which kills"
  echo "every LATER test in the file with '!inTest', before they run a line."
  echo "Wait for what you actually want instead:"
  echo "    await AppHarness.pumpUntilFound(tester, find.byKey(const Key('...')));"
  echo "    await AppHarness.pumpUntilCondition(tester, () => <predicate>);"
  echo "If the tapped control is deliberately INERT (no navigation, no spinner),"
  echo "annotate it:"
  echo "    // results-settle-ok: <why a plain settle is correct here>"
  exit 1
fi

exit 0

#!/usr/bin/env bash
# Self-test harness for the Riverpod cycle-guard grep gates (finding 5,
# 2026-06-18). The gates' regex/awk correctness is load-bearing — a silent
# false-negative re-opens the exact CircularDependencyError class they exist to
# block. This harness pins their behaviour against fixture snippets, including
# every former known hole from findings 1, 2 and 4, so a regression in the awk
# is caught the moment this runs.
#
# HOW IT WORKS
# ------------
# Both gates scan relative roots (`lib/` for self-invalidation; `test/` +
# `integration_test/` for cycle-stub) via `find`. So for each fixture we build a
# throwaway temp tree containing just that one snippet at the right path, run the
# REAL gate script from inside the temp dir, and assert its exit code (1 =
# FLAGGED, 0 = PASS). No mocking of the gate logic — we exercise the shipped
# scripts end-to-end.
#
# USAGE
#   ./scripts/test/test_cycle_gates.sh                 # run all gates
#   ./scripts/test/test_cycle_gates.sh self-invalidation
#   ./scripts/test/test_cycle_gates.sh cycle-stub
# Pure bash + awk + find — no new dependency. Fast (a few temp dirs).

set -euo pipefail

# Resolve absolute paths to the two gate scripts (this file lives in scripts/test).
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$(dirname "$HERE")"
SELF_INVAL="$SCRIPTS_DIR/forbid_provider_self_invalidation.sh"
CYCLE_STUB="$SCRIPTS_DIR/forbid_cycle_stub_in_tests.sh"

PASS_COUNT=0
FAIL_COUNT=0

# run_case <gate-script> <rel-path-under-tmp> <expected-exit:0|1> <name> <body...>
# Builds a temp tree with the fixture at <rel-path>, runs <gate-script> from the
# temp dir, and asserts the exit code. <body> lines are the fixture file content.
run_case() {
  local gate="$1" relpath="$2" expected="$3" name="$4"
  shift 4
  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/$(dirname "$relpath")"
  printf '%s\n' "$@" > "$tmp/$relpath"

  local out rc
  set +e
  out="$( cd "$tmp" && "$gate" 2>&1 )"
  rc=$?
  set -e
  rm -rf "$tmp"

  if [ "$rc" -eq "$expected" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    printf '  PASS  %s (exit %d)\n' "$name" "$rc"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    printf '  FAIL  %s — expected exit %d, got %d\n' "$name" "$expected" "$rc"
    printf '        gate output: %s\n' "$out"
  fi
}

# ===========================================================================
# Gate 1 — forbid_provider_self_invalidation.sh
# Fixtures live at lib/x_notifier.dart (the gate's scan glob).
# expected: 1 = FLAGGED (offender), 0 = PASS (clean / annotated).
# ===========================================================================
test_self_invalidation() {
  local g="$SELF_INVAL" p='lib/x_notifier.dart'
  echo "forbid_provider_self_invalidation.sh"

  # (a) plain offender → FLAGGED
  run_case "$g" "$p" 1 "plain offender flagged" \
    'class XNotifier {' \
    '  void boom() {' \
    '    ref.invalidate(masterProfileProvider);' \
    '  }' \
    '}'

  # (b) annotated offender (same line) → PASS
  run_case "$g" "$p" 0 "same-line annotation passes" \
    'class XNotifier {' \
    '  void ok() {' \
    '    ref.invalidate(masterProfileProvider); // cycle-safe: no back-edge' \
    '  }' \
    '}'

  # (b2) annotated offender (line above) → PASS
  run_case "$g" "$p" 0 "line-above annotation passes" \
    'class XNotifier {' \
    '  void ok() {' \
    '    // cycle-safe: target does not watch this provider' \
    '    ref.invalidate(masterProfileProvider);' \
    '  }' \
    '}'

  # (c-finding1) call AFTER a //-bearing STRING literal → now FLAGGED
  run_case "$g" "$p" 1 "finding 1: //-in-string no longer masks call" \
    'class XNotifier {' \
    '  void sneaky() {' \
    "    final u = 'http://x'; ref.invalidate(xProvider);" \
    '  }' \
    '}'

  # (c2) genuine comment line is still skipped → PASS
  run_case "$g" "$p" 0 "genuine // comment line ignored" \
    'class XNotifier {' \
    '  // ref.invalidate(xProvider); is just documentation here' \
    '  void noop() {}' \
    '}'

  # (d-finding2) multiline call (arg on continuation line) → now FLAGGED
  run_case "$g" "$p" 1 "finding 2: multiline call flagged" \
    'class XNotifier {' \
    '  void multi() {' \
    '    ref.invalidate(' \
    '      someProvider,' \
    '    );' \
    '  }' \
    '}'

  # (d2-finding2) multiline call with line-above annotation → PASS
  run_case "$g" "$p" 0 "finding 2: annotated multiline call passes" \
    'class XNotifier {' \
    '  void multiOk() {' \
    '    // cycle-safe: someProvider never watches this notifier' \
    '    ref.invalidate(' \
    '      someProvider,' \
    '    );' \
    '  }' \
    '}'

  # (e) clean notifier (no invalidation) → PASS
  run_case "$g" "$p" 0 "clean notifier passes" \
    'class XNotifier {' \
    '  void build() {}' \
    '}'
}

# ===========================================================================
# Gate 2 — forbid_cycle_stub_in_tests.sh
# Fixtures live at test/x_notifier_test.dart (the gate's scan glob).
# ===========================================================================
test_cycle_stub() {
  local g="$CYCLE_STUB" p='test/x_notifier_test.dart'
  echo "forbid_cycle_stub_in_tests.sh"

  # (a) plain stub → FLAGGED
  run_case "$g" "$p" 1 "plain cycle-closing stub flagged" \
    'void main() {' \
    '  ProviderContainer(overrides: [' \
    '    masterProfileProvider.overrideWithValue(m),' \
    '  ]);' \
    '}'

  # (b) annotated stub (same line) → PASS
  run_case "$g" "$p" 0 "same-line annotation passes" \
    'void main() {' \
    '  ProviderContainer(overrides: [' \
    '    servicesListProvider.overrideWithValue(s), // cycle-stub-ok: leaf here' \
    '  ]);' \
    '}'

  # (b2) annotated stub (line above) → PASS
  run_case "$g" "$p" 0 "line-above annotation passes" \
    'void main() {' \
    '  // cycle-stub-ok: this test never invokes a cyclic teardown entrypoint' \
    '  serviceRepositoryProvider.overrideWith((_) => repo);' \
    '}'

  # (c-finding4) stub AFTER a //-bearing STRING literal → now FLAGGED
  run_case "$g" "$p" 1 "finding 4: //-in-string no longer masks stub" \
    'void main() {' \
    "  final note = 'see http://x'; masterProfileProvider.overrideWithValue(m);" \
    '}'

  # (c2) genuine comment line is still skipped → PASS
  run_case "$g" "$p" 0 "genuine // comment line ignored" \
    'void main() {' \
    '  // masterProfileProvider.overrideWithValue(m); is just a note' \
    '}'

  # (d) clean test (only leaf deps stubbed) → PASS
  run_case "$g" "$p" 0 "clean leaf-only test passes" \
    'void main() {' \
    '  ProviderContainer(overrides: [' \
    '    authRepositoryProvider.overrideWithValue(repo),' \
    '  ]);' \
    '}'
}

main() {
  local which="${1:-all}"
  case "$which" in
    self-invalidation) test_self_invalidation ;;
    cycle-stub)        test_cycle_stub ;;
    all)               test_self_invalidation; echo; test_cycle_stub ;;
    *) echo "unknown gate: $which (use self-invalidation | cycle-stub | all)" >&2; exit 2 ;;
  esac

  echo
  echo "cycle-gate self-test: $PASS_COUNT passed, $FAIL_COUNT failed"
  [ "$FAIL_COUNT" -eq 0 ]
}

main "$@"

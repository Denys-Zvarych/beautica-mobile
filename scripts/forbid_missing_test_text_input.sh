#!/usr/bin/env bash
# Shared-E2E-boot-policy gate (2026-07-22 profile-drive safeguard;
# 2026-07-31 extended to the single-source refactor).
#
# THE BUG THIS GUARDS
# -------------------
# `WidgetTester.enterText` is a SILENT NO-OP in any non-debug build unless the
# harness registers the test text-input mock. Mechanism:
#
#   1. `enterText` ultimately posts a `TextInputClient.updateEditingState`
#      platform message carrying the connection id `TestTextInput._client ?? -1`.
#   2. `IntegrationTestWidgetsFlutterBinding` (and `PatrolBinding`, patrol 4.6.1
#      `lib/src/binding.dart` line 136) both override
#      `registerTestTextInput => false`, so the mock handler is never installed,
#      `_client` is never assigned, and the id posted is ALWAYS `-1`.
#   3. In `TextInput._handleTextInputInvocation`, the escape hatch that accepts
#      `-1` ("the framework is in a test") lives INSIDE an `assert(() {...}())`
#      block.
#   4. `flutter drive --profile` / `--release` STRIPS asserts. The `-1` message
#      falls through and the injected value is DISCARDED WITHOUT ERROR.
#
# Consequence: every credential/form field stays empty, the screen's own
# "required field" validation correctly bails, no request is ever made, and the
# failure surfaces far downstream as a misleading tap/navigation assertion. The
# `integration-profile` job carried exactly this defect from its introduction
# (2026-06-18) until 2026-07-22 — a separate YAML break masked it the whole
# time — and the misleading "the button was absorbed by an in-flight
# overlay/route transition" message cost a full investigation before the real
# cause was found. 16 integration flows call `enterText`; ALL of them route
# through `AppHarness.boot`, so that single line is what makes the profile job
# meaningful at all.
#
# THE SECOND BUG THIS GUARDS (2026-07-31)
# ---------------------------------------
# The registration call, and the rest of the E2E boot rules, used to be
# hand-copied into BOTH harnesses, kept in sync only by a "Mirrors
# app_harness.dart" comment. That mirror drifted:
# `WidgetController.hitTestWarningShouldBeFatal` (the off-screen-tap guard)
# reached the flutter_test harness only, so the whole patrol tier kept booting
# unguarded. The rules now live in ONE function — `applyE2eBootPolicy` in
# `integration_test/support/e2e_boot_policy.dart` — and every E2E entry point
# calls it.
#
# THE RULE
# --------
# Two linked obligations, each structurally checked below:
#
#   (1) `applyE2eBootPolicy` MUST still call `testTextInput.register()`.
#       This is the one definition; if it goes, every tier loses it at once.
#   (2) Every E2E entry point MUST call `applyE2eBootPolicy`:
#         • `AppHarness.boot(...)`        — flutter_test tier
#         • `PatrolHarness.boot(...)`     — patrol fake-backend tier
#         • `deep_link_patrol_test.dart`  — patrol native tier, which builds its
#           own tree and so has no harness to inherit from
#       An entry point that stops calling it silently re-opens the mirror.
#
# Commented-out calls do not count. None of this is visible to
# `flutter analyze`, to a lint, or to a green debug run — the call looks
# redundant in debug (`enterText` works there because the assert survives),
# which is precisely why it has to be a structural gate.
#
# If a checked file is renamed or its entry point restructured, this gate FAILS
# rather than silently passing on something it can no longer find. Update the
# `CHECKS` table in the same commit.
#
# CI hard-gate (run from `.github/workflows/pr-validate.yml`); also runnable
# locally before pushing.
# Self-test:  ./scripts/forbid_missing_test_text_input.sh --self-test

set -euo pipefail

# ---------------------------------------------------------------------------
# CHECKS — one `path|decl|body_end|required|hint` row per obligation.
#
#   decl      ERE opening the region the call must live in. EMPTY = whole file.
#   body_end  ERE closing that region (ignored when decl is empty).
#   required  ERE the region must contain on a non-comment line.
#   hint      what to write if it is missing.
#
# NOTE: bracket expressions, not backslash escapes — awk's ERE engine rejects
# `\(` / `\}` ("invalid regexp: Unmatched (") and the gate then silently finds
# no body at all. Caught by --self-test; keep it this way.
#
# Both harnesses declare `boot` as a static class member and the tree is
# `dart format`-clean, so those method bodies always terminate at a `}` indented
# by exactly two spaces. `applyE2eBootPolicy` is a top-level function, so its
# body terminates at a `}` in column 0.
# ---------------------------------------------------------------------------
CHECKS=(
  "integration_test/support/e2e_boot_policy.dart|^void applyE2eBootPolicy[(]|^[}]$|testTextInput[.]register[(][)]|tester.binding.testTextInput.register();"
  "integration_test/support/app_harness.dart|static Future<GoRouter> boot[(]|^  [}]$|applyE2eBootPolicy[(]|applyE2eBootPolicy(tester);"
  "integration_test/patrol/support/patrol_harness.dart|static Future<GoRouter> boot[(]|^  [}]$|applyE2eBootPolicy[(]|applyE2eBootPolicy(\$.tester);"
  "integration_test/patrol/deep_link_patrol_test.dart||-|applyE2eBootPolicy[(]|applyE2eBootPolicy(\$.tester);"
)

# ---------------------------------------------------------------------------
# scan_file <path> <decl> <body_end> <required>
#   Prints a diagnosis line if <path> does not contain <required> on a
#   non-comment line inside the region opened by <decl> and closed by
#   <body_end> (or anywhere in the file when <decl> is empty). Silent when
#   compliant. A line is treated as a comment when its first non-space token
#   is `//`.
# ---------------------------------------------------------------------------
scan_file() {
  local f="$1" decl="$2" endpat="$3" required="$4"

  if [ ! -f "$f" ]; then
    echo "$f: MISSING — the gate cannot verify a file it cannot find."
    return 0
  fi

  local body
  if [ -z "$decl" ]; then
    body="$(cat "$f")"
  else
    body="$(
      awk -v decl="$decl" -v endpat="$endpat" '
        $0 ~ decl { inbody = 1 }
        inbody     { print }
        inbody && $0 ~ endpat { inbody = 0 }
      ' "$f"
    )"
    if [ -z "$body" ]; then
      echo "$f: no body found (expected a line matching /$decl/)."
      return 0
    fi
  fi

  # Strip genuine comment lines (first non-space token is `//`) before looking
  # for the required call, so a commented-out call cannot satisfy it.
  local hits
  hits="$(
    printf '%s\n' "$body" \
      | grep -vE '^[[:space:]]*//' \
      | grep -cE "$required" || true
  )"

  if [ "$hits" -eq 0 ]; then
    if [ -z "$decl" ]; then
      echo "$f: does not call ${required}."
    else
      echo "$f: the body opened by /$decl/ does not call ${required}."
    fi
  fi
}

# ---------------------------------------------------------------------------
# Self-test mode: run scan_file against pinned fixtures and assert verdicts.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  fail=0

  emit() { printf '%s\n' "$@" > "$tmp/$FIXTURE"; }

  boot_decl='static Future<GoRouter> boot[(]'
  boot_end='^  [}]$'
  register='testTextInput[.]register[(][)]'
  policy='applyE2eBootPolicy[(]'

  # (1) compliant — the policy call inside the boot body.
  FIXTURE=ok.dart emit \
    'abstract final class H {' \
    '  static Future<GoRouter> boot(WidgetTester tester) async {' \
    '    applyE2eBootPolicy(tester);' \
    '    await tester.pumpWidget(const App());' \
    '  }' \
    '}'

  # (2) missing entirely.
  FIXTURE=missing.dart emit \
    'abstract final class H {' \
    '  static Future<GoRouter> boot(WidgetTester tester) async {' \
    '    await tester.pumpWidget(const App());' \
    '  }' \
    '}'

  # (3) present but COMMENTED OUT — must not satisfy the gate.
  FIXTURE=commented.dart emit \
    'abstract final class H {' \
    '  static Future<GoRouter> boot(WidgetTester tester) async {' \
    '    // applyE2eBootPolicy(tester);' \
    '    await tester.pumpWidget(const App());' \
    '  }' \
    '}'

  # (4) present in the file but OUTSIDE the boot body — must not satisfy it.
  FIXTURE=outside.dart emit \
    'abstract final class H {' \
    '  static Future<GoRouter> boot(WidgetTester tester) async {' \
    '    await tester.pumpWidget(const App());' \
    '  }' \
    '' \
    '  static void other(WidgetTester tester) {' \
    '    applyE2eBootPolicy(tester);' \
    '  }' \
    '}'

  # (5) the shared policy itself — top-level function, register() inside.
  FIXTURE=policy_ok.dart emit \
    'void applyE2eBootPolicy(WidgetTester tester) {' \
    '  installOverflowGuard();' \
    '  tester.binding.testTextInput.register();' \
    '}'

  # (6) the shared policy with the registration REMOVED — the single-source
  #     regression this gate exists to catch (every tier loses it at once).
  FIXTURE=policy_missing.dart emit \
    'void applyE2eBootPolicy(WidgetTester tester) {' \
    '  installOverflowGuard();' \
    '}'

  # (7) whole-file mode (no decl) — an entry point that builds its own tree.
  FIXTURE=wholefile_ok.dart emit \
    'void main() {' \
    '  patrolTest("x", ($) async {' \
    '    applyE2eBootPolicy($.tester);' \
    '  });' \
    '}'

  # (8) whole-file mode, call absent.
  FIXTURE=wholefile_missing.dart emit \
    'void main() {' \
    '  patrolTest("x", ($) async {' \
    '    await $.pumpWidgetAndSettle(const App());' \
    '  });' \
    '}'

  expect_verdict() { # <fixture> <decl> <end> <required> <clean|flagged>
    local out
    out="$(scan_file "$tmp/$1" "$2" "$3" "$4")"
    if [ "$5" = "clean" ] && [ -n "$out" ]; then
      echo "SELF-TEST FAIL: $1 expected clean, got: $out"; fail=1
    elif [ "$5" = "flagged" ] && [ -z "$out" ]; then
      echo "SELF-TEST FAIL: $1 expected flagged, got clean"; fail=1
    fi
  }

  expect_verdict ok.dart               "$boot_decl" "$boot_end" "$policy"   clean
  expect_verdict missing.dart          "$boot_decl" "$boot_end" "$policy"   flagged
  expect_verdict commented.dart        "$boot_decl" "$boot_end" "$policy"   flagged
  expect_verdict outside.dart          "$boot_decl" "$boot_end" "$policy"   flagged
  expect_verdict policy_ok.dart        '^void applyE2eBootPolicy[(]' '^[}]$' "$register" clean
  expect_verdict policy_missing.dart   '^void applyE2eBootPolicy[(]' '^[}]$' "$register" flagged
  expect_verdict wholefile_ok.dart     ""           "-"         "$policy"   clean
  expect_verdict wholefile_missing.dart ""          "-"         "$policy"   flagged
  expect_verdict does_not_exist.dart   "$boot_decl" "$boot_end" "$policy"   flagged

  if [ "$fail" -ne 0 ]; then
    exit 1
  fi
  echo "SELF-TEST PASS: missing / commented-out / outside-body / absent-file calls flagged, in both scoped and whole-file mode; compliant boot + compliant shared policy clean"
  echo "SELF-TEST OK: forbid_missing_test_text_input.sh"
  exit 0
fi

offenders=""
for row in "${CHECKS[@]}"; do
  IFS='|' read -r path decl endpat required _hint <<< "$row"
  hit="$(scan_file "$path" "$decl" "$endpat" "$required")"
  [ -n "$hit" ] && offenders+="$hit"$'\n'
done
offenders="$(printf '%s' "$offenders" | sed '/^$/d')"

if [ -n "$offenders" ]; then
  echo "The shared E2E boot policy is not wired up:"
  echo "$offenders"
  echo
  echo "Every E2E entry point must call applyE2eBootPolicy(...), and that one"
  echo "function must call tester.binding.testTextInput.register()."
  echo
  echo "Without the registration, tester.enterText() is a SILENT NO-OP in"
  echo "profile/release: the editing state is posted with client id -1, and the"
  echo "-1 escape hatch in TextInput._handleTextInputInvocation sits inside an"
  echo "assert(() {...}()) block that non-debug builds strip. Every form field"
  echo "stays empty and the flow fails downstream with a misleading"
  echo "tap/navigation error."
  echo
  echo "Without the applyE2eBootPolicy call, that entry point also boots with"
  echo "the overflow guard and the off-screen-tap guard"
  echo "(WidgetController.hitTestWarningShouldBeFatal) OFF — the exact drift"
  echo "that left the whole patrol tier unguarded until 2026-07-31."
  echo
  echo "Restore the call (idempotent; keep it unconditional so debug and"
  echo "profile share one code path):"
  for row in "${CHECKS[@]}"; do
    IFS='|' read -r path _decl _endpat _required hint <<< "$row"
    printf '    %-52s %s\n' "$path" "$hint"
  done
  echo
  echo "It looks redundant in a debug run — that is exactly why this gate exists."
  exit 1
fi

exit 0

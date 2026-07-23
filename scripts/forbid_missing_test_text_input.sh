#!/usr/bin/env bash
# Text-input-mock registration gate (2026-07-22 profile-drive safeguard).
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
# THE RULE
# --------
# Every harness listed in `harnesses` below MUST call `testTextInput.register()`
# INSIDE its `boot(...)` function body — not merely somewhere in the file, and
# not commented out. The call looks redundant in a debug `flutter test` run
# (debug keeps the assert, so `enterText` works without it), which is precisely
# why a refactor can delete it without any test going red. Nothing about the
# breakage is visible to `flutter analyze`, to a lint, or to the debug suite —
# so it has to be a structural gate.
#
# If a harness is renamed or its boot entrypoint is restructured, this gate
# FAILS rather than silently passing on a file it can no longer find. Update the
# `harnesses` / `boot_decl` values in the same commit.
#
# CI hard-gate (run from `.github/workflows/pr-validate.yml`); also runnable
# locally before pushing.
# Self-test:  ./scripts/forbid_missing_test_text_input.sh --self-test

set -euo pipefail

# Harness files that must register the mock, and the `boot` declaration that
# opens the function body the call has to live in.
harnesses=(
  "integration_test/support/app_harness.dart"
  "integration_test/patrol/support/patrol_harness.dart"
)
# NOTE: bracket expressions, not backslash escapes — awk's ERE engine rejects
# `\(` / `\}` ("invalid regexp: Unmatched (") and the gate then silently finds
# no boot body at all. Caught by --self-test on this gate's first run; keep it
# this way.
boot_decl='static Future<GoRouter> boot[(]'
# Both harnesses declare `boot` as a static member of a class, and the tree is
# `dart format`-clean, so the method body always terminates at a `}` indented by
# exactly two spaces.
body_end='^  [}]$'
required='testTextInput[.]register[(][)]'

# ---------------------------------------------------------------------------
# scan_file <path>
#   Prints a diagnosis line if <path> does not call `testTextInput.register()`
#   on a non-comment line inside its `boot(...)` body. Silent when compliant.
#   A line is treated as a comment when its first non-space token is `//`.
# ---------------------------------------------------------------------------
scan_file() {
  local f="$1"

  if [ ! -f "$f" ]; then
    echo "$f: MISSING — the gate cannot verify a harness it cannot find."
    return 0
  fi

  local body
  body="$(
    awk -v decl="$boot_decl" -v endpat="$body_end" '
      $0 ~ decl { inbody = 1 }
      inbody     { print }
      inbody && $0 ~ endpat { inbody = 0 }
    ' "$f"
  )"

  if [ -z "$body" ]; then
    echo "$f: no boot(...) body found (expected a line matching /$boot_decl/)."
    return 0
  fi

  # Strip genuine comment lines (first non-space token is `//`) before looking
  # for the required call, so a commented-out registration cannot satisfy it.
  local hits
  hits="$(
    printf '%s\n' "$body" \
      | grep -vE '^[[:space:]]*//' \
      | grep -cE "$required" || true
  )"

  if [ "$hits" -eq 0 ]; then
    echo "$f: boot(...) does not call testTextInput.register()."
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

  # (1) compliant — register() inside the boot body.
  FIXTURE=ok.dart emit \
    'abstract final class H {' \
    '  static Future<GoRouter> boot(WidgetTester tester) async {' \
    '    installOverflowGuard();' \
    '    tester.binding.testTextInput.register();' \
    '    await tester.pumpWidget(const App());' \
    '  }' \
    '}'

  # (2) missing entirely.
  FIXTURE=missing.dart emit \
    'abstract final class H {' \
    '  static Future<GoRouter> boot(WidgetTester tester) async {' \
    '    installOverflowGuard();' \
    '    await tester.pumpWidget(const App());' \
    '  }' \
    '}'

  # (3) present but COMMENTED OUT — must not satisfy the gate.
  FIXTURE=commented.dart emit \
    'abstract final class H {' \
    '  static Future<GoRouter> boot(WidgetTester tester) async {' \
    '    // tester.binding.testTextInput.register();' \
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
    '    tester.binding.testTextInput.register();' \
    '  }' \
    '}'

  # (5) renamed away — the gate must fail loudly, never silently pass.
  expect_verdict() { # <fixture> <clean|flagged>
    local out
    out="$(scan_file "$tmp/$1")"
    if [ "$2" = "clean" ] && [ -n "$out" ]; then
      echo "SELF-TEST FAIL: $1 expected clean, got: $out"; fail=1
    elif [ "$2" = "flagged" ] && [ -z "$out" ]; then
      echo "SELF-TEST FAIL: $1 expected flagged, got clean"; fail=1
    fi
  }

  expect_verdict ok.dart clean
  expect_verdict missing.dart flagged
  expect_verdict commented.dart flagged
  expect_verdict outside.dart flagged
  expect_verdict does_not_exist.dart flagged

  if [ "$fail" -ne 0 ]; then
    exit 1
  fi
  echo "SELF-TEST PASS: missing / commented-out / outside-boot / absent-file registrations flagged; compliant boot clean"
  exit 0
fi

offenders=""
for f in "${harnesses[@]}"; do
  hit="$(scan_file "$f")"
  [ -n "$hit" ] && offenders+="$hit"$'\n'
done
offenders="$(printf '%s' "$offenders" | sed '/^$/d')"

if [ -n "$offenders" ]; then
  echo "Integration harness is missing its test text-input mock registration:"
  echo "$offenders"
  echo
  echo "Without it, tester.enterText() is a SILENT NO-OP in profile/release:"
  echo "the editing state is posted with client id -1, and the -1 escape hatch"
  echo "in TextInput._handleTextInputInvocation sits inside an assert(() {...}())"
  echo "block that non-debug builds strip. Every form field stays empty and the"
  echo "flow fails downstream with a misleading tap/navigation error."
  echo
  echo "Add it to the harness's boot(...) body (idempotent, keep it"
  echo "unconditional so debug and profile share one code path):"
  echo "    tester.binding.testTextInput.register();"
  echo
  echo "It looks redundant in a debug run — that is exactly why this gate exists."
  exit 1
fi

exit 0

#!/usr/bin/env bash
# Anti-stub test-convention gate (2026-06-18 circular-dependency safeguard).
#
# THE ROOT CAUSE THIS GUARDS
# --------------------------
# The 2026-06-18 logout CircularDependencyError shipped because the NOTIFIER and
# INTEGRATION tests that should have caught it instead STUBBED the cycle-closing
# providers (masterProfileProvider / servicesListProvider /
# serviceRepositoryProvider) with mocks that broke their `ref.watch(authProvider)`
# edge. With that edge gone there was no back-edge for Riverpod's debug
# `_debugAssertCanDependOn` to fire on — the tests engineered the very bug away.
#
# THE RULE
# --------
# Notifier tests and integration tests must exercise the REAL provider graph and
# override ONLY leaf data deps (repo/storage/dio). Overriding an INTERMEDIATE
# provider that closes a watch cycle hides exactly this class of bug. So this
# gate FAILS the build when a notifier-test or integration-test file
# `overrideWith` / `overrideWithValue`s one of the known cycle-closing providers
# UNLESS the override is explicitly justified with a `// cycle-stub-ok: <reason>`
# comment (same line, or the line immediately above). The reason should state
# why stubbing this provider here does NOT hide the cycle (e.g. the test targets
# the notifier in isolation and the provider IS its leaf data dep, or the test
# does not exercise the cyclic teardown entrypoint at all).
#
# SCOPE (deliberately narrow — this is the bug-relevant surface)
# --------------------------------------------------------------
#   • test/**/*notifier*_test.dart  — notifier unit tests
#   • integration_test/**/*.dart    — end-to-end flows on the real graph
# Ordinary widget / golden / screen tests legitimately stub these providers to
# drive UI state and never invoke a cyclic teardown entrypoint, so they are NOT
# gated — gating them would be pure noise. The cycle assert only has teeth on
# the notifier/integration tier, which is what this gate protects.
#
# The list of cycle-closing providers lives in `closers` below — extend it as
# new watch cycles appear (any intermediate provider that transitively
# `ref.watch`es a Notifier which can mutate it). `*.g.dart` is never a test file,
# so no generated-file exclusion is needed.
#
# COMMENT DETECTION (finding 4, 2026-06-18)
# -----------------------------------------
# A stub mention is only "commented out" when the line's FIRST non-space token
# is `//` (a genuine comment line) — NOT merely when `//` appears somewhere
# earlier on the line. The previous heuristic ("`//` anywhere before the match")
# false-PASSED a real stub that follows a `//`-bearing STRING LITERAL, e.g.
# `final note = 'see http://x'; masterProfileProvider.overrideWithValue(m);`. We
# now STRIP string literals before the comment test, so a `//` inside a string
# can never mask a real stub. The `// cycle-stub-ok:` allow-list still works
# because the annotation test runs on the ORIGINAL (un-stripped) text.
#
# CI hard-gate (run from `.github/workflows/pr-validate.yml`); also runnable
# locally before pushing. Documented in `ARCHITECTURE-mobile.md` § 14.
# Self-test:  ./scripts/forbid_cycle_stub_in_tests.sh --self-test
#   (or run the shared harness: ./scripts/test/test_cycle_gates.sh)

set -euo pipefail

# ---------------------------------------------------------------------------
# Self-test mode (finding 5): run the gate logic against pinned fixture
# snippets and assert the verdicts, then exit. Delegates to the shared harness.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
  "$(dirname "$0")/test/test_cycle_gates.sh" cycle-stub
  st_rc=$?
  if [ "$st_rc" -eq 0 ]; then
    echo "SELF-TEST OK: forbid_cycle_stub_in_tests.sh"
  fi
  exit "$st_rc"
fi

# Cycle-closing providers — the intermediate providers that transitively
# ref.watch(authProvider) and thus close the logout cascade cycle.
closers='masterProfileProvider|servicesListProvider|serviceRepositoryProvider'

# Notifier-test + integration-test files only.
mapfile -t files < <(
  {
    find test -type f -name '*notifier*_test.dart' 2>/dev/null || true
    find integration_test -type f -name '*.dart' 2>/dev/null || true
  } | sort -u
)

if [ "${#files[@]}" -eq 0 ]; then
  exit 0
fi

# Match: `<closer>.overrideWith(` or `<closer>.overrideWithValue(`.
pattern="(${closers})[.]overrideWith(Value)?[(]"
# Annotation: `// cycle-stub-ok:` (any leading whitespace before the `//`).
annotation='[/][/][[:space:]]*cycle-stub-ok:'

# ---------------------------------------------------------------------------
# scan_file <path>
#   Emits "<path>:<line>:<text>" for each un-annotated stub of a cycle-closing
#   provider. Comment detection mirrors forbid_provider_self_invalidation.sh
#   (finding 4): genuine-comment = first non-space token is `//`, plus a
#   string-stripped re-test so a `//` inside a string literal cannot mask a real
#   stub. The `// cycle-stub-ok:` allow-list runs on the ORIGINAL text.
# ---------------------------------------------------------------------------
scan_file() {
  awk -v file="$1" -v pat="$pattern" -v ann="$annotation" '
    # Remove Dart string literals (single-/double-quoted, with escapes) so any
    # `//` they contain cannot be mistaken for a comment.
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
      if ($0 ~ pat) {
        # (1a) Genuine comment line? First non-space token is `//`.
        firsttok = $0
        sub(/^[[:space:]]+/, "", firsttok)
        if (firsttok ~ /^[/][/]/) { prev = $0; next }
        # (1b) `//` comment after CODE masking the stub? Test string-free text.
        codeonly = strip_strings($0)
        where = match(codeonly, pat)
        if (where > 0) {
          before = substr(codeonly, 1, where - 1)
          if (before ~ /[/][/]/) { prev = $0; next }
        }
        # (2) Annotated cycle-stub-ok on this line or the line directly above.
        if ($0 ~ ann) { prev = $0; next }
        if (prev ~ ann) { prev = $0; next }
        printf "%s:%d:%s\n", file, NR, $0
      }
      prev = $0
    }
  ' "$1"
}

offenders="$(
  for f in "${files[@]}"; do
    scan_file "$f"
  done
)"

if [ -n "$offenders" ]; then
  echo "Un-annotated cycle-closing-provider stub found in a notifier/integration test:"
  echo "$offenders"
  echo
  echo "Notifier & integration tests must drive the REAL provider graph and"
  echo "override ONLY leaf data deps (repo/storage/dio) — stubbing an intermediate"
  echo "provider that closes a watch cycle hides the debug-only"
  echo "CircularDependencyError class of bug (it cannot fire without the real edge)."
  echo "If this stub provably does NOT hide the cycle (e.g. the test targets the"
  echo "notifier in isolation and this IS its leaf data dep, or the flow never"
  echo "invokes a cyclic teardown entrypoint), annotate it:"
  echo "    // cycle-stub-ok: <why this stub does not hide the cycle>"
  echo "    serviceRepositoryProvider.overrideWithValue(repo),"
  exit 1
fi

exit 0

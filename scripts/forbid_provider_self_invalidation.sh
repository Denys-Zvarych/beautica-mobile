#!/usr/bin/env bash
# Provider self-invalidation gate (2026-06-18 circular-dependency safeguard).
#
# THE FOOTGUN
# -----------
# A Riverpod Notifier that `ref.invalidate(otherProvider)` /
# `ref.refresh(otherProvider)` from inside one of its methods can close a
# dependency cycle when `otherProvider` (directly or transitively)
# `ref.watch`es the notifier's own provider. Riverpod's
# `_debugAssertCanDependOn` then throws `CircularDependencyError` — but ONLY
# under `kDebugMode`. Release/AOT strips the assert, so the bug is invisible in
# release and only surfaces in debug / `flutter test`. This is exactly the
# regression we hit in `auth_notifier.dart` `logout()` (it invalidated
# masterProfile / serviceRepository / servicesList, all of which transitively
# watch authProvider → cycle → "Вихід не вдався").
#
# THE RULE
# --------
# Cross-provider invalidation from inside a Notifier must be a CONSCIOUS,
# REVIEWED decision — never a silent default. So this gate FAILS the build the
# moment a `ref.invalidate(...)` or `ref.refresh(...)` appears inside a notifier
# source file UNLESS the call is explicitly justified with a
# `// cycle-safe: <reason>` comment (on the same line, or the line immediately
# above). The reason should state why the target provider does NOT watch this
# notifier's provider (no back-edge → no cycle).
#
# Self-invalidation that re-runs the notifier's OWN build is NOT the footgun;
# the gate only targets the cross-provider form (`ref.invalidate(somethingProvider)`),
# and any legitimate cross-provider case is unblocked by the annotation rather
# than by weakening the regex.
#
# GATE BOUNDARY — THIS IS NOT THE COMPLETE CYCLE NET (finding 3, 2026-06-18)
# -------------------------------------------------------------------------
# This grep gate is DEFENSE-IN-DEPTH for the single MOST COMMON footgun only:
# `ref.invalidate(...Provider)` / `ref.refresh(...Provider)` self-targeting from
# inside a notifier. It DELIBERATELY does NOT flag the third cycle-closer shape,
# `ref.read(someProvider.notifier).<mutator>()` — that call is extremely common
# and almost always safe, so gating every occurrence would be pure noise and
# would drown the gate's signal.
#
# The AUTHORITATIVE net for ALL cycle-closer shapes — including
# `ref.read(x.notifier).mutate()` — is the RUNTIME guard
# `test/core/provider_cycle_guard_test.dart`. It wires the REAL provider graph
# (only leaf deps faked) so Riverpod's debug `CircularDependencyError` actually
# fires on a real back-edge. That is why EVERY teardown / cross-provider-mutation
# entrypoint MUST be added as a registry row there. Do NOT assume a green run of
# THIS grep gate means a flow is cycle-safe — only the registry row proves it.
#
# SCOPE
# -----
#   • Files: lib/**/*notifier*.dart (covers `*_notifier.dart` and any file with
#     "notifier" in its name). Generated `*.g.dart` is excluded — codegen never
#     contains hand-written invalidation.
#   • Match: a `ref.invalidate(` or `ref.refresh(` call whose argument is an
#     IDENTIFIER ending in `Provider` (i.e. another provider) — `ref.invalidate(
#     state)` style self-calls without a `Provider` arg are not flagged. The call
#     may span multiple lines: `ref.invalidate(\n  someProvider,\n)` is matched
#     by collapsing logical continuation lines before the test (finding 2,
#     2026-06-18). Calls annotated `// cycle-safe:` on the same line or the line
#     directly above are filtered out before the offender check.
#
# COMMENT DETECTION (finding 1, 2026-06-18)
# -----------------------------------------
# A `ref.invalidate(...)` mention is only "commented out" when the line's FIRST
# non-space token is `//` (a genuine comment line) — NOT merely when `//` appears
# somewhere earlier on the line. The previous heuristic ("`//` anywhere before
# the call") false-PASSED real calls that follow a `//`-bearing STRING LITERAL,
# e.g. `final u = 'http://x'; ref.invalidate(someProvider);`. We now STRIP string
# literals before the comment test, so a `//` inside a string can never mask a
# real call. The `// cycle-safe:` allow-list still works because the annotation
# test runs on the ORIGINAL (un-stripped) text.
#
# This is the CI hard-gate (run from `.github/workflows/pr-validate.yml`); it can
# also be run locally before pushing. Documented in `analysis_options.yaml`.
# Self-test:  ./scripts/forbid_provider_self_invalidation.sh --self-test
#   (or run the shared harness: ./scripts/test/test_cycle_gates.sh)

set -euo pipefail

# ---------------------------------------------------------------------------
# Self-test mode (finding 5): run the gate logic against pinned fixture
# snippets and assert the verdicts, then exit. Delegates to the shared harness
# so all gate fixtures live in one place.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
  exec "$(dirname "$0")/test/test_cycle_gates.sh" self-invalidation
fi

# The matcher (awk POSIX ERE): `ref.invalidate(<provider>` or
# `ref.refresh(<provider>` where the argument is an identifier ending in
# `Provider`. Note for awk ERE: `.` is `[.]`, the literal call-paren is `[(]`,
# and whitespace is `[[:space:]]*`. The arg may carry a leading namespace
# (e.g. `someProvider` or `someProvider(arg)` — `Provider` followed by a non-word
# char or call-paren catches the base name in both forms). Because continuation
# lines are collapsed before matching, the `[[:space:]]*` between `(` and the
# provider arg also absorbs the newline-turned-space of a multiline call.
pattern='ref[.](invalidate|refresh)[(][[:space:]]*[A-Za-z_][A-Za-z0-9_]*Provider([^A-Za-z0-9_]|$)'

# The call-OPENER matcher: a `ref.invalidate(` / `ref.refresh(` whose argument
# is NOT yet closed on the same line (no provider+`)` before EOL). Used to
# decide whether to splice the next physical line(s) onto this one so a
# multiline call (`ref.invalidate(\n  someProvider,\n)`) becomes one logical
# line for the offender test.
opener='ref[.](invalidate|refresh)[(]'

# The annotation matcher: a `// cycle-safe:` comment (any leading whitespace
# before the `//`). `[/][/]` avoids escaping the slash.
annotation='[/][/][[:space:]]*cycle-safe:'

# ---------------------------------------------------------------------------
# scan_file <path>
#   Emits "<path>:<line>:<text>" for each un-annotated offender. The awk:
#     • Collapses a multiline `ref.invalidate(`/`ref.refresh(` call into ONE
#       logical line before testing (finding 2). It buffers from the opener
#       until the call's parens balance, joining physical lines with a space.
#     • Detects genuine comments by FIRST non-space token == `//`, AND by
#       stripping string literals before re-testing — so a `//` inside a string
#       (`'http://x'`) can never mask a real call (finding 1).
#     • Honours the `// cycle-safe:` allow-list on the (collapsed) line and on
#       the physical line directly above the call's opener.
#   The reported line number is the opener's physical line.
# ---------------------------------------------------------------------------
scan_file() {
  awk -v file="$1" -v pat="$pattern" -v opener="$opener" -v ann="$annotation" '
    # Remove Dart string literials (single- and double-quoted, with escapes) so
    # any `//` they contain cannot be mistaken for a comment. Approximate but
    # sufficient: replaces "..." / '"'"'...'"'"' runs with empty strings.
    function strip_strings(s,   out, c, i, q, esc) {
      out = ""; q = ""; esc = 0
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (q != "") {                       # inside a string literal
          if (esc) { esc = 0; continue }
          if (c == "\\") { esc = 1; continue }
          if (c == q) { q = "" }             # closing quote
          continue                           # drop string chars
        }
        if (c == "\"" || c == "'"'"'") { q = c; continue }
        out = out c
      }
      return out
    }
    # Count unescaped parens OUTSIDE string literals so multiline collapse stops
    # exactly when the call closes.
    function paren_delta(s,   code, i, c, d) {
      code = strip_strings(s); d = 0
      for (i = 1; i <= length(code); i++) {
        c = substr(code, i, 1)
        if (c == "(") d++
        else if (c == ")") d--
      }
      return d
    }
    {
      line = $0
      openerNR = NR          # physical line to report (opener line)
      # ----- multiline collapse: if THIS line opens a ref.invalidate/refresh
      #       call whose parens are not yet balanced, splice following lines. ---
      stripped = strip_strings(line)
      if (stripped ~ opener && paren_delta(line) > 0) {
        depth = paren_delta(line)
        collapsed = line
        while (depth > 0 && (getline nxt) > 0) {
          collapsed = collapsed " " nxt
          depth += paren_delta(nxt)
        }
        line = collapsed
      }

      # ----- offender test on the (possibly collapsed) logical line -----------
      if (line ~ pat) {
        # (1a) Genuine comment line? First non-space token is `//`.
        firsttok = line
        sub(/^[[:space:]]+/, "", firsttok)
        if (firsttok ~ /^[/][/]/) { prev = $0; next }
        # (1b) Match inside a comment after CODE? Strip strings, then if `//`
        #      precedes the matched call in the string-free text it is a real
        #      `//` comment masking the call → prose, skip.
        codeonly = strip_strings(line)
        where = match(codeonly, pat)
        if (where > 0) {
          before = substr(codeonly, 1, where - 1)
          if (before ~ /[/][/]/) { prev = $0; next }
        }
        # (2) Annotated cycle-safe on the collapsed line, or on the physical
        #     line directly above the opener (prev = the line before this one).
        if (line ~ ann) { prev = $0; next }
        if (prev ~ ann) { prev = $0; next }
        printf "%s:%d:%s\n", file, openerNR, line
      }
      prev = $0
    }
  ' "$1"
}

# Notifier source files, excluding generated output.
mapfile -t files < <(find lib -type f -name '*notifier*.dart' ! -name '*.g.dart' | sort)

# No notifier files (e.g. a fresh checkout) → nothing to check, pass.
if [ "${#files[@]}" -eq 0 ]; then
  exit 0
fi

offenders="$(
  for f in "${files[@]}"; do
    scan_file "$f"
  done
)"

if [ -n "$offenders" ]; then
  echo "Un-annotated cross-provider self-invalidation found inside notifier(s):"
  echo "$offenders"
  echo
  echo "Cross-provider ref.invalidate()/ref.refresh() from inside a Notifier can"
  echo "close a watch cycle (CircularDependencyError, debug-only). Either remove"
  echo "the call (let the watch cascade handle teardown) or, if the target"
  echo "provably does NOT watch this notifier's provider, annotate it:"
  echo "    // cycle-safe: <why no back-edge exists>"
  echo "    ref.invalidate(someOtherProvider);"
  exit 1
fi

exit 0

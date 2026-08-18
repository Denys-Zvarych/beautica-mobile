#!/usr/bin/env bash
# Raw user-visible string gate (2026-08-18 — the gate that never ran).
#
# THE FRAGILITY THIS GUARDS
# -------------------------
# Ukrainian is the PRODUCT language, not a translation. That inverts the usual
# i18n failure mode: a raw `Text('Записатись')` under `lib/` looks perfect in
# every screenshot, every emulator run, and every review, because UA is what a
# developer sees anyway. It is only wrong in a locale nobody exercises yet. The
# app is built EN-ready (app_uk.arb primary, app_en.arb mirrored, parity
# CI-checked), so every literal that never reached an ARB file is a string that
# will render Ukrainian inside an English build — and it is invisible until the
# day EN ships, at which point it is not one bug but a sweep.
#
# WHY A SHELL GUARD AND NOT A LINT
# --------------------------------
# It WAS a lint. `no_raw_ui_strings` was authored in Phase 1.3 as a
# `custom_lint` plugin — a pure AST checker plus a `DartLintRule` adapter,
# exported from `lib/beautica_mobile.dart` via `createPlugin()` — and promoted
# to `error` severity in Phase 1.5. It never ran once, in either phase.
# `custom_lint` discovers plugins by scanning the ANALYZED package's
# dependencies for packages depending on `custom_lint_builder`, then loading
# `package:<dep>/<dep>.dart`. A package is never a plugin of itself, so
# `lib/beautica_mobile.dart` — not a dependency of `beautica_mobile` — was
# never loaded. `dart run custom_lint` returned exit 0 across ~1200 files in
# 0.949s, and a planted `Text('Raw untranslated probe string')` under `lib/`
# went undetected. The plugin's own header comment asserted the discovery
# convention incorrectly; that comment was the entire bug.
#
# Nothing else covered it. `forbid_cyrillic_finder.sh` guards the OPPOSITE
# direction (Cyrillic inside `find.text('…')`) and only ever looks at `test/`
# and `integration_test/`. ARB parity compares `app_uk.arb` against
# `app_en.arb` — a string that never reached ARB is absent from BOTH and so
# parity is trivially satisfied.
#
# The AST checker was never the problem and is kept verbatim
# (`lib/core/lints/no_raw_ui_strings_checker.dart`, 19 unit tests). Only the
# host changed: `tool/lints/no_raw_ui_strings.dart` drives it as a plain Dart
# CLI, and this script is the house-pattern gate around it. A grep would have
# been a downgrade — the rule is about which ARGUMENT of which WIDGET a literal
# sits in (`AppBar(title: Text('…'))` fires; `Key('slot-card')`,
# `context.go('/bookings')`, `Text('$name')` do not), which is an AST question.
#
# THE RULE
# --------
# A non-empty raw string literal in a user-visible argument slot of a Material
# widget is forbidden anywhere under `lib/`. The widget/argument surface lives
# in `kRawUiStringTargets` in the checker (Text, AppBar.title,
# InputDecoration.{label,hint,error,helper}Text, the Button `child` family,
# Tooltip.message, Semantics.label, SnackBar.content, AlertDialog.{title,
# content}, FAB/IconButton.tooltip, Chip.label, ListTile.{title,subtitle},
# Badge.label). Generated output (`*.g.dart`, `*.freezed.dart`, `lib/api/**`),
# `test/**`, `**/dev/**` and `_debug_*.dart` are exempt by path.
#
# ESCAPE COMMENTS — two accepted spellings, both permanent:
#
#     // raw-ui-string-ok: <why this literal is not translatable UI copy>
#     Text('₴'),
#
#     // ignore: no_raw_ui_strings
#     Text('SMS'),
#
#     // ignore_for_file: no_raw_ui_strings        (whole file, anywhere in it)
#
# `raw-ui-string-ok:` is the spelling for new code and matches every other
# guard here (`i18n-finder-ok:`, `future-date-ok:`, `cycle-safe:`,
# `instant-ok:`). `ignore:` is accepted because suppressions were written
# across the corpus on the assumption the plugin was live; re-flagging all of
# them at once would bury the real signal. Either marker works on the
# offending line itself, or anywhere in the UNBROKEN run of `//` comment lines
# directly above it — the walk upward stops at the first non-comment line, so
# an annotation separated from its literal by real code does NOT count (same
# semantics as `forbid_cyrillic_finder.sh`; otherwise any escape comment near
# the top of a file becomes a blanket file-level opt-out).
#
# A bare `// raw-ui-string-ok:` with NO reason parses fine — the gate should
# never block a merge over comment prose — but it is a REVIEW SMELL. The
# reason is the only part of the annotation a human can check.
#
# LEGACY BASELINE (ratchet, not a big-bang rewrite)
# -------------------------------------------------
# The corpus accumulated violations for two full phases while the lint was
# decorative, so `scripts/.raw_ui_strings_allow` GRANDFATHERS the files that
# already offend, one repo-relative path per line (`#` comments and blanks
# ignored) — same shape as `.cyrillic_finder_allow` / `.stale_future_date_allow`.
# Every OTHER file under `lib/` is gated from line one. The baseline ONLY
# SHRINKS: adding a path is never the fix for a new violation. Every normal run
# prints `allow-listed files: N` so the number sits in CI output and a baseline
# that stops shrinking is visible rather than inferred.
#
# COST NOTE: this is the FIRST guard that invokes the Dart VM rather than
# grep/awk, so `verify_guards.sh` gains a one-off compile — roughly 10-20s on
# the first invocation, a few seconds afterwards from the kernel snapshot
# cache. Every other guard finishes in milliseconds. No `verify_guards.sh`
# wiring is needed: it discovers guards with
# `find -maxdepth 1 -name 'forbid_*.sh'`, so this file joins the suite by
# existing.
#
# CI hard-gate (run from `.github/workflows/pr-validate.yml`); also runnable
# locally before pushing.
# Self-test:  ./scripts/forbid_raw_ui_strings.sh --self-test

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
cli="tool/lints/no_raw_ui_strings.dart"

# INVOKED AS `dart <file>`, NOT `dart run <file>` — deliberately.
#
# `dart run` drives the native-assets build-hook pipeline, which prints
# "Running build hooks..." to STDOUT, once per hook, WITHOUT a trailing
# newline. That chatter is therefore glued onto the front of the CLI's first
# real output line, which (a) breaks any anchored `^` match against the
# sentinel and (b) would corrupt the first `path:line:text` offender row into
# something no editor or CI annotator can parse. Bare `dart <file>` skips the
# hook pipeline entirely and yields a clean stream. Verified: `dart run` ->
# "Running build hooks...Running build hooks...SELF-TEST OK: …"; `dart` ->
# "SELF-TEST OK: …". Do not "simplify" this back to `dart run`.
#
# stderr is captured separately (never merged with `2>&1`) so toolchain
# warnings can never be mistaken for offender rows either; it is surfaced only
# when something actually went wrong.
errfile="$(mktemp)"
trap 'rm -f "$errfile"' EXIT

# ---------------------------------------------------------------------------
# Self-test mode.
#
# Delegates to the CLI's synthetic probe matrix, then verifies BOTH that it
# exited 0 AND that it printed its sentinel. The sentinel check is not
# ceremony: a `dart run` that dies on a missing package, a stale
# `.dart_tool/package_config.json`, or a compile error can still be coaxed
# into a 0 by an intermediate pipe, and "green because nothing ran" is the
# exact failure this whole gate exists to stop repeating.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
  out="$(cd "$root" && dart "$cli" --self-test 2>"$errfile")" || {
    echo "SELF-TEST FAIL: the CLI self-test exited non-zero."
    printf '%s\n' "$out"
    cat "$errfile"
    exit 1
  }
  printf '%s\n' "$out"
  if ! printf '%s\n' "$out" | grep -q '^SELF-TEST OK: no_raw_ui_strings'; then
    echo "SELF-TEST FAIL: the CLI exited 0 but never printed its sentinel."
    echo "                An exit 0 with no output means the checker did not"
    echo "                run — which is indistinguishable from 'no probes"
    echo "                were violated', and is precisely how the original"
    echo "                custom_lint gate passed unconditionally."
    exit 1
  fi
  echo "SELF-TEST OK: forbid_raw_ui_strings.sh"
  exit 0
fi

# ---------------------------------------------------------------------------
# Real run over the working tree.
# ---------------------------------------------------------------------------
set +e
offenders="$(cd "$root" && dart "$cli" --root="$root" 2>"$errfile")"
rc=$?
set -e

printf '%s\n' "$offenders"

# Exit 2 is the CLI's "I could not run meaningfully" code (e.g. a checkout
# path that would make every file vacuously exempt). Surface its stderr —
# that failure must never be mistaken for "no offenders".
if [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ]; then
  echo
  echo "The no_raw_ui_strings CLI failed to run (exit $rc):"
  cat "$errfile"
  exit "$rc"
fi

if [ "$rc" -ne 0 ]; then
  echo
  echo "Raw user-visible string literal(s) found under lib/."
  echo
  echo "Ukrainian is the product language, so these render UA in EVERY locale"
  echo "— including the English build the app is wired for (app_uk.arb primary,"
  echo "app_en.arb mirrored). They are invisible until EN ships, at which point"
  echo "they are a sweep, not a bug."
  echo
  echo "Localize it:"
  echo "    1. add the key to lib/l10n/app_uk.arb  (UA, primary)"
  echo "    2. mirror the key in lib/l10n/app_en.arb (EN, or an EN placeholder"
  echo "       if the copy is not approved yet — never leave the key absent)"
  echo "    3. flutter gen-l10n"
  echo "    4. reference AppLocalizations.of(context).<key>"
  echo
  echo "If the literal is genuinely NOT translatable UI copy (a currency glyph,"
  echo "a brand mark, a protocol token), annotate the line:"
  echo "    // raw-ui-string-ok: <why this literal is locale-invariant>"
  echo "    Text('₴'),"
  echo "(// ignore: no_raw_ui_strings is accepted too — same claim, older"
  echo "spelling. Either marker also works on the line itself, or anywhere in"
  echo "the unbroken run of // comment lines directly above it.)"
  echo
  echo "Legacy files predating this gate are grandfathered in"
  echo "scripts/.raw_ui_strings_allow — the baseline only shrinks, never grows."
  echo "Adding a path there is NOT the fix for a new violation."
  exit 1
fi

exit 0

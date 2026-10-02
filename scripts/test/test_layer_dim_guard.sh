#!/usr/bin/env bash
# End-to-end regression harness for scripts/forbid_unclassified_layer_dim.sh
# (Phase 300). Complements the guard's own --self-test (cases 1-6): this one
# copies the SHIPPED script into a throwaway repo tree and runs it as a
# subprocess, so security, path-confinement, CRLF, exemption and allow-list
# parsing behaviour is exercised exactly as CI runs it.
#
# Tags: [GREEN] passes on the current guard (a regression pin).
#
# USAGE: ./scripts/test/test_layer_dim_guard.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
GATE_SRC="$(dirname "$HERE")/forbid_unclassified_layer_dim.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
SITE='    child: Opacity(opacity: 0.5, child: SizedBox()),'
PROBE_BODY='await expectDimRatio(tester, find.byKey(const Key("k")), 0.6);'

# mk <case> : tree with scripts/<gate>, empty allow-list, lib/f, a probe-using
# test/foo_test.dart. Prints the root.
mk() {
  local r="$TMP/$1"
  mkdir -p "$r/scripts" "$r/lib/f" "$r/test"
  cp "$GATE_SRC" "$r/scripts/forbid_unclassified_layer_dim.sh"
  : > "$r/scripts/.layer_dim_allow"
  printf '%s\n' "$PROBE_BODY" > "$r/test/foo_test.dart"
  printf '%s' "$r"
}

# check <name> <want_rc> <root> [grep-pattern] : run the copied gate.
check() {
  local name="$1" want="$2" r="$3" pat="${4:-}" out rc
  out="$(cd "$r" && bash scripts/forbid_unclassified_layer_dim.sh 2>&1)"; rc=$?
  if [ "$rc" -ne "$want" ]; then
    FAIL=$((FAIL + 1)); printf '  FAIL  %s - exit %d, wanted %d\n' "$name" "$rc" "$want"; return
  fi
  if [ -n "$pat" ] && ! grep -aq -- "$pat" <<< "$out"; then
    FAIL=$((FAIL + 1)); printf '  FAIL  %s - output lacks %s\n' "$name" "$pat"; return
  fi
  PASS=$((PASS + 1)); printf '  PASS  %s\n' "$name"
}

echo "== security: dim-gated payloads (HIGH finding) =="
r="$(mk inj1)"
printf '// dim-gated: $(touch${IFS}PWNED)\n%s\n' "$SITE" > "$r/lib/f/a.dart"
bash -c "cd '$r' && bash scripts/forbid_unclassified_layer_dim.sh" >/dev/null 2>&1
if [ -e "$r/PWNED" ] || [ -e "$r/lib/PWNED" ]; then
  FAIL=$((FAIL + 1)); echo "  FAIL  [GREEN] \$(...) in dim-gated EXECUTED (PWNED created)"
else PASS=$((PASS + 1)); echo "  PASS  [GREEN] \$(...) in dim-gated not executed"; fi
check "[GREEN] \$(...) payload is unclassified, not accepted" 1 "$r" "a.dart:2"

r="$(mk inj2)"
printf '// dim-gated: `touch${IFS}PWNED`\n%s\n' "$SITE" > "$r/lib/f/a.dart"
bash -c "cd '$r' && bash scripts/forbid_unclassified_layer_dim.sh" >/dev/null 2>&1
if [ -e "$r/PWNED" ]; then
  FAIL=$((FAIL + 1)); echo "  FAIL  [GREEN] backtick in dim-gated EXECUTED"
else PASS=$((PASS + 1)); echo "  PASS  [GREEN] backtick in dim-gated not executed"; fi

r="$(mk inj3)"
printf '// dim-gated: test/foo_test.dart"; touch${IFS}PWNED; echo "\n%s\n' "$SITE" > "$r/lib/f/a.dart"
bash -c "cd '$r' && bash scripts/forbid_unclassified_layer_dim.sh" >/dev/null 2>&1
if [ -e "$r/PWNED" ]; then
  FAIL=$((FAIL + 1)); echo "  FAIL  [GREEN] quote-breakout in dim-gated EXECUTED"
else PASS=$((PASS + 1)); echo "  PASS  [GREEN] quote-breakout not executed"; fi

echo "== path confinement (LOW finding) =="
r="$(mk esc1)"; : > "$TMP/outside_test.dart"
printf '// dim-gated: ../outside_test.dart\n%s\n' "$SITE" > "$r/lib/f/a.dart"
check "[GREEN] '..' escape rejected" 1 "$r" "a.dart:2"
r="$(mk esc2)"
printf '// dim-gated: test/../test/foo_test.dart\n%s\n' "$SITE" > "$r/lib/f/a.dart"
check "[GREEN] embedded '..' rejected" 1 "$r" "a.dart:2"
r="$(mk esc3)"
printf '// dim-gated: /etc/passwd\n%s\n' "$SITE" > "$r/lib/f/a.dart"
check "[GREEN] absolute path rejected" 1 "$r" "a.dart:2"
r="$(mk esc4)"
cp "$r/test/foo_test.dart" "$r/lib/f/helper.dart"
printf '// dim-gated: lib/f/helper.dart\n%s\n' "$SITE" > "$r/lib/f/a.dart"
check "[GREEN] target outside test/ or not *_test.dart rejected" 1 "$r" "a.dart:2"

echo "== probe usage (LOW finding) =="
r="$(mk probe_ok)"
printf '// dim-gated: test/foo_test.dart\n%s\n' "$SITE" > "$r/lib/f/a.dart"
check "[GREEN] gated target that uses expectDimRatio passes (positive control)" 0 "$r"
r="$(mk probe_no)"; echo 'void main() {}' > "$r/test/foo_test.dart"
printf '// dim-gated: test/foo_test.dart\n%s\n' "$SITE" > "$r/lib/f/a.dart"
check "[GREEN] gated target that never uses the probe rejected" 1 "$r" "a.dart:2"

echo "== detection gaps in cases 1-6 =="
r="$(mk ml)"
printf 'x = Opacity(\n  opacity: 0.5,\n  child: SizedBox(),\n);\n' > "$r/lib/f/a.dart"
check "[GREEN] multi-line Opacity( constructor trips on its first line" 1 "$r" "a.dart:1"
r="$(mk ml_ok)"
printf '// dim-decorative: fade\nx = Opacity(\n  opacity: 0.5,\n);\n' > "$r/lib/f/a.dart"
check "[GREEN] multi-line Opacity( classified passes" 0 "$r"
r="$(mk tern)"
printf 'w = on\n    ? AnimatedOpacity(opacity: 1, child: a)\n    : Opacity(opacity: .5, child: b);\n' > "$r/lib/f/a.dart"
check "[GREEN] AnimatedOpacity + Opacity inside a ternary both trip (2 sites)" 1 "$r" "a.dart:2"
r="$(mk two_above)"
printf '// dim-decorative: x\n// more prose\n%s\n' "$SITE" > "$r/lib/f/a.dart"
check "[GREEN] marker two comment-lines above passes (unbroken run)" 0 "$r"
r="$(mk blank_gap)"
printf '// dim-decorative: x\n\n%s\n' "$SITE" > "$r/lib/f/a.dart"
check "[GREEN] blank line between marker and site trips" 1 "$r" "a.dart:3"
r="$(mk below)"
printf '%s\n// dim-decorative: x\n' "$SITE" > "$r/lib/f/a.dart"
check "[GREEN] marker BELOW the site does not classify it" 1 "$r" "a.dart:1"
r="$(mk consume)"
printf '// dim-decorative: x\n%s\n%s\n' "$SITE" "$SITE" > "$r/lib/f/a.dart"
check "[GREEN] one marker does not cover the next adjacent site" 1 "$r" "a.dart:3"
r="$(mk trailing)"
printf '%s // dim-decorative: x\n' "$SITE" > "$r/lib/f/a.dart"
check "[GREEN] same-line trailing marker passes" 0 "$r"
r="$(mk emptyreason)"
printf '// dim-decorative:\n%s\n' "$SITE" > "$r/lib/f/a.dart"
check "[GREEN] marker with empty reason trips" 1 "$r" "a.dart:2"
r="$(mk crlf_dec)"
printf '// dim-decorative: x\r\n%s\r\n' "$SITE" > "$r/lib/f/a.dart"
check "[GREEN] CRLF dim-decorative passes" 0 "$r"
r="$(mk crlf_gated)"
printf '// dim-gated: test/foo_test.dart\r\n%s\r\n' "$SITE" > "$r/lib/f/a.dart"
check "[GREEN] CRLF dim-gated passes (\\r must not poison the path)" 0 "$r"
r="$(mk codecomment)"
printf 'final a = 1; // wraps Opacity( elsewhere\n' > "$r/lib/f/a.dart"
check "[GREEN] 'Opacity(' in a trailing code comment is not a site" 0 "$r"
r="$(mk blockcomment)"
printf '/*\n * Opacity(x) is avoided here\n */\n' > "$r/lib/f/a.dart"
check "[GREEN] 'Opacity(' inside a block comment is not a site" 0 "$r"

echo "== exemptions + allow-list parsing =="
r="$(mk exempt)"; mkdir -p "$r/lib/api"
printf '%s\n' "$SITE" > "$r/lib/api/x.dart"; printf '%s\n' "$SITE" > "$r/lib/f/a.g.dart"
printf '%s\n' "$SITE" > "$r/lib/f/a.freezed.dart"
check "[GREEN] lib/api, *.g.dart, *.freezed.dart exempt" 0 "$r"
r="$(mk notdart)"; printf '%s\n' "$SITE" > "$r/lib/f/a.txt"
check "[GREEN] non-.dart file ignored" 0 "$r"
r="$(mk nolib)"; rm -rf "$r/lib"
check "[GREEN] missing lib/ passes" 0 "$r"
r="$(mk badallow)"; echo 'lib/f/a.dart:x' > "$r/scripts/.layer_dim_allow"
check "[GREEN] malformed allow-list count fails" 1 "$r" "BAD allow-list"
r="$(mk allow_cmt)"; printf '# header\n\nlib/f/a.dart:1  # why\n' > "$r/scripts/.layer_dim_allow"
printf '%s\n' "$SITE" > "$r/lib/f/a.dart"
check "[GREEN] allow-list comments/blank lines/trailing comment parsed" 0 "$r"
r="$(mk allow_new)"; printf 'lib/f/a.dart:1\n' > "$r/scripts/.layer_dim_allow"
printf '%s\n' "$SITE" > "$r/lib/f/a.dart"; printf '%s\n' "$SITE" > "$r/lib/f/b.dart"
check "[GREEN] new unlisted file trips though another file is listed" 1 "$r" "b.dart"
r="$(mk census)"; printf '%s\n%s\n' "$SITE" "$SITE" > "$r/lib/f/a.dart"
out="$(cd "$r" && bash scripts/forbid_unclassified_layer_dim.sh --census 2>&1)"
if [ "$out" = "lib/f/a.dart:2" ]; then PASS=$((PASS + 1)); echo "  PASS  [GREEN] --census prints path:count"
else FAIL=$((FAIL + 1)); echo "  FAIL  --census output: $out"; fi

echo "== marker-in-string / probe-in-comment (cycle-2 LOW findings) =="
r="$(mk str_marker)"
printf "x = '// dim-decorative: y'; Opacity(opacity: 0.5);\n" > "$r/lib/f/a.dart"
check "[GREEN] marker inside a string literal does not classify" 1 "$r" "a.dart:1"
r="$(mk str_marker_gated)"
printf "x = '// dim-gated: test/foo_test.dart'; Opacity(opacity: 0.5);\n" > "$r/lib/f/a.dart"
check "[GREEN] dim-gated marker inside a string literal does not classify" 1 "$r" "a.dart:1"
r="$(mk probe_comment)"; printf '// expectDimRatio(t, f, 0.6);\n' > "$r/test/foo_test.dart"
printf '// dim-gated: test/foo_test.dart\n%s\n' "$SITE" > "$r/lib/f/a.dart"
check "[GREEN] gated target mentioning expectDimRatio only in a comment rejected" 1 "$r" "a.dart:2"
r="$(mk probe_import)"; printf "import 'package:x/dim_probe.dart';\nvoid main() {}\n" > "$r/test/foo_test.dart"
printf '// dim-gated: test/foo_test.dart\n%s\n' "$SITE" > "$r/lib/f/a.dart"
check "[GREEN] gated target with only the dim_probe import rejected" 1 "$r" "a.dart:2"
r="$(mk probe_real)"; printf 'void main() {\n    await expectDimRatio(\n      t, f, 0.6);\n}\n' > "$r/test/foo_test.dart"
printf '// dim-gated: test/foo_test.dart\n%s\n' "$SITE" > "$r/lib/f/a.dart"
check "[GREEN] gated target with a real await expectDimRatio( call passes" 0 "$r"
r="$(mk str_marker_gated_valid)"
printf "x = '// dim-gated: test/foo_test.dart ok'; Opacity(opacity: 0.5);\n" > "$r/lib/f/a.dart"
check "[GREEN] dim-gated marker in a string with a VALID target does not classify" 1 "$r" "a.dart:1"
r="$(mk probe_after_comment)"; printf '// note\nawait expectDimRatio(t, f, 0.6); // trailing note\n' > "$r/test/foo_test.dart"
printf '// dim-gated: test/foo_test.dart\n%s\n' "$SITE" > "$r/lib/f/a.dart"
check "[GREEN] probe call after a comment line / with trailing // note passes" 0 "$r"
r="$(mk colon_name)"; printf '%s\n' "$SITE" > "$r/lib/f/we:ird.dart"
check "[GREEN] filename containing ':' keyed by full path" 1 "$r" "we:ird.dart:1"

echo "== probe detection only in real code (cycle-3 LOW) =="
gated() { # gated <case> <test-file body> : gated site whose target has <body>
  local g; g="$(mk "$1")"; printf '%s\n' "$2" > "$g/test/foo_test.dart"
  printf '// dim-gated: test/foo_test.dart\n%s\n' "$SITE" > "$g/lib/f/a.dart"; printf '%s' "$g"
}
r="$(gated pr_block '/* expectDimRatio( */')"
check "[GREEN] probe only in a one-line block comment rejected" 1 "$r" "a.dart:2"
r="$(gated pr_mblock $'/*\n  await expectDimRatio(t, f, 0.6);\n*/')"
check "[GREEN] probe only inside a multi-line block comment rejected" 1 "$r" "a.dart:2"
r="$(gated pr_str "final s = 'expectDimRatio(';")"
check "[GREEN] probe only inside a string literal rejected" 1 "$r" "a.dart:2"
r="$(gated pr_dstr 'final s = "x expectDimRatio(";')"
check "[GREEN] probe only inside a double-quoted string rejected" 1 "$r" "a.dart:2"
r="$(gated pr_after_block $'/* note */ await expectDimRatio(t, f, 0.6);')"
check "[GREEN] probe call after a closed block comment passes" 0 "$r"
r="$(gated pr_after_mblock $'/*\n note\n*/\nawait expectDimRatio(t, f, 0.6);')"
check "[GREEN] probe call after a multi-line block comment passes" 0 "$r"
r="$(gated pr_plain 'await expectDimRatio(t, f, 0.6);')"
check "[GREEN] plain await expectDimRatio( call passes" 0 "$r"
r="$(gated pr_split $'await expectDimRatio(\n  t,\n  f,\n  0.6,\n);')"
check "[GREEN] probe call split across lines passes" 0 "$r"
r="$(gated pr_str_then_call $'final s = \'a\'; await expectDimRatio(t, f, 0.6);')"
check "[GREEN] real call after a string on the same line passes" 0 "$r"

echo "== nested quotes in interpolation (cycle-3 LOW) =="
r="$(mk interp)"
printf "x = '\${a ? '//' : ''} // dim-decorative: x'; Opacity(opacity: 0.5);\n" > "$r/lib/f/a.dart"
check "[GREEN] marker inside a string with nested-quote interpolation does not classify" 1 "$r" "a.dart:1"
r="$(mk interp_limit)"
printf "Opacity(opacity: 0.5); x = '\${a ? '}' : ''} // dim-decorative: x';\n" > "$r/lib/f/a.dart"
check "[GREEN] KNOWN LIMIT: a nested string holding } ends the interpolation early and fakes a marker (documented; flip when fixed)" 0 "$r"

echo "== widened detection (cycle-3 INFO) =="
r="$(mk sp)"; printf 'x = Opacity (opacity: 0.5);\n' > "$r/lib/f/a.dart"
check "[GREEN] 'Opacity (' with a space trips" 1 "$r" "a.dart:1"
r="$(mk tearoff)"; printf 'final f = Opacity.new;\n' > "$r/lib/f/a.dart"
check "[GREEN] Opacity.new tear-off trips" 1 "$r" "a.dart:1"
r="$(mk tearoff_eol)"; printf 'final f = AnimatedOpacity.new(opacity: 1);\n' > "$r/lib/f/a.dart"
check "[GREEN] AnimatedOpacity.new( trips" 1 "$r" "a.dart:1"
r="$(mk sliver_anim)"; printf 'x = SliverAnimatedOpacity(opacity: 0.5);\n' > "$r/lib/f/a.dart"
check "[GREEN] SliverAnimatedOpacity( trips" 1 "$r" "a.dart:1"
r="$(mk fade_sp)"; printf 'x = FadeTransition (opacity: o);\n' > "$r/lib/f/a.dart"
check "[GREEN] 'FadeTransition (' with a space trips" 1 "$r" "a.dart:1"
r="$(mk lookalike)"; printf 'StaggeredFadeTransition(x);\nStaggeredFadeTransition (x);\nfoo.Opacity(x);\nOpacityBuilder(x);\nOpacity.newer;\n' > "$r/lib/f/a.dart"
check "[GREEN] look-alikes (StaggeredFadeTransition, .Opacity, OpacityBuilder, .newer) do not trip" 0 "$r"
r="$(mk sp_ok)"; printf '// dim-decorative: fade\nx = Opacity (opacity: 0.5);\n' > "$r/lib/f/a.dart"
check "[GREEN] classified 'Opacity (' passes" 0 "$r"

echo
echo "layer-dim guard harness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

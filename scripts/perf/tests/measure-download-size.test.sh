#!/usr/bin/env bash
# Phase 366 — hermetic behavioural test for scripts/perf/measure_download_size.sh (MP7 download-size gate).
#
# No real flutter build, no network, no real bundletool: `flutter`, `java`, `curl`, `git` are stubs on a
# per-case PATH; HOME, AAB_PATH, BUNDLETOOL_JAR and the symbols dir all live in a temp dir. The script
# under test is COPIED into a fake repo root (it derives MOBILE_DIR from its own location), so the real
# repo, real ~/.cache and real ~/.beautica-symbols are never touched. Runs in a few seconds.
#
# Run:   ./scripts/perf/tests/measure-download-size.test.sh
#        MEASURE_SCRIPT=/path/to/mutant.sh ./scripts/perf/tests/measure-download-size.test.sh   (mutation probes)
#        PENDING_STRICT=1 ./scripts/perf/tests/measure-download-size.test.sh  (XFAIL counts as failure)
#
# Exit 0 = no FAIL.  Mechanism: a case marked `pending` (instead of `ok`) records a not-yet-fixed
# audit finding: it prints XFAIL while RED (exit unaffected unless PENDING_STRICT=1) and XPASS once
# the fix lands, which is the cue to promote it to `ok`.  Currently every case is `ok`.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${MEASURE_SCRIPT:-$SCRIPT_DIR/../measure_download_size.sh}"
[ -f "$TARGET" ] || { echo "FAIL: script under test not found: $TARGET"; exit 2; }
bash -n "$TARGET" || { echo "FAIL: bash -n"; exit 2; }

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
PASS=0; FAIL=0; XFAIL=0; XPASS=0; N=0

# check <ok|pending> <label> <shell-expr evaluated in this scope>
check() {
    if eval "$3"; then
        if [ "$1" = pending ]; then XPASS=$((XPASS+1)); echo "  XPASS  - $2   (fix landed: promote to ok)"
        else PASS=$((PASS+1)); echo "  ok     - $2"; fi
    else
        if [ "$1" = pending ]; then XFAIL=$((XFAIL+1)); echo "  XFAIL  - $2   [known gap]"
        else FAIL=$((FAIL+1)); echo "  FAIL   - $2"; echo "           rc=$RC out: $(printf %s "$OUT" | tail -n 4 | tr '\n' '|')"; fi
    fi
}

SIZES_OK='SDK,ABI,MIN,MAX
26-28,ARM64_V8A,10000000,10849936
29-,ARM64_V8A,10000000,10852693
26-28,ARMEABI_V7A,9000000,9500000
29-,ARMEABI_V7A,9000000,9600000
29-,X86_64,12000000,12500000'
ARM64_MAX=10852693

# new_case <name> : fresh isolated world (fake repo + stubs + HOME)
new_case() {
    N=$((N+1)); echo "[$N] $1"
    W="$ROOT/c$N"; MONO="$W/mono"; FAKE="$MONO/beautica-mobile"; H="$W/home"; BIN="$W/bin"; LOGD="$W/log"
    mkdir -p "$FAKE/scripts/perf" "$H" "$BIN" "$LOGD" "$W/aab" "$W/out"
    cp "$TARGET" "$FAKE/scripts/perf/measure_download_size.sh"
    printf 'name: x\nversion: 1.2.3+45\n' >"$FAKE/pubspec.yaml"
    SIZES_F="$W/sizes.csv"; printf '%s\n' "$SIZES_OK" >"$SIZES_F"
    JARSRC="$W/jarsrc.bin"; printf 'FAKE-BUNDLETOOL-JAR' >"$JARSRC"
    printf 'FAKE-BUNDLETOOL-JAR' >"$W/fake.jar"
    SYMDIR="$W/out/sym"; JAROVR="$W/fake.jar"; BUDGET_ENV=""; GIT_TOP=""; CWD="$FAKE"; AABP="$W/aab/app.aab"
    DEFAULT_AAB="$FAKE/build/app/outputs/bundle/release/app-release.aab"; HIST="$H/.cache/beautica-history/download-size-history.csv"
    EXTRA_ENV=(); UMASK=022; FORCE_AABPATH=""
    cat >"$BIN/flutter" <<'EOF'
#!/usr/bin/env bash
echo "flutter $* (cwd=$PWD)" >>"$STUB_LOG/flutter.log"
for a in "$@"; do case "$a" in --split-debug-info=*) d="${a#*=}"; [ -d "$d" ] && stat -c %a "$d" >"$STUB_LOG/symbols.mode";; esac; done
[ -n "${STUB_SWAP_JAR:-}" ] && printf 'EVIL' >"$STUB_SWAP_JAR"
# the real script builds into the default location, relative to beautica-mobile (cwd)
d=build/app/outputs/bundle/release; mkdir -p "$d"; : >"$d/app-release.aab"
[ -n "${STUB_RO_AABDIR:-}" ] && chmod a-w "$d"
exit 0
EOF
    cat >"$BIN/java" <<'EOF'
#!/usr/bin/env bash
echo "java $*" >>"$STUB_LOG/java.log"
sha256sum "$2" | cut -d' ' -f1 >>"$STUB_LOG/java.jarsha"
[ -n "${STUB_JAVA_FAIL:-}" ] && { echo "bundletool boom" >&2; exit 1; }
case "$3" in
  build-apks) for a in "$@"; do case "$a" in --output=*) : >"${a#--output=}";; esac; done ;;
  get-size) cat "$FAKE_SIZES" ;;
esac
EOF
    cat >"$BIN/curl" <<'EOF'
#!/usr/bin/env bash
echo "curl $*" >>"$STUB_LOG/curl.log"
out=""; prev=""; for a in "$@"; do [ "$prev" = -o ] && out="$a"; prev="$a"; done
[ -n "${STUB_CURL_FAIL:-}" ] && exit 22
[ -n "$out" ] && cat "$FAKE_JAR" >"$out"
if [ -n "${STUB_CURL_KILL_PARENT:-}" ]; then kill -TERM "$PPID"; sleep 0.4; fi
EOF
    cat >"$BIN/git" <<'EOF'
#!/usr/bin/env bash
echo "git $*" >>"$STUB_LOG/git.log"
case "$*" in
  *--show-toplevel*) [ -n "${FAKE_GIT_TOP:-}" ] && { echo "$FAKE_GIT_TOP"; exit 0; }; exit 128 ;;
  *"rev-parse --short HEAD"*) [ -n "${FAKE_HEAD_SHORT:-}" ] && { echo "$FAKE_HEAD_SHORT"; exit 0; }; exit 128 ;;
  *"rev-parse HEAD"*) [ -n "${FAKE_HEAD_FULL:-}" ] && { echo "$FAKE_HEAD_FULL"; exit 0; }; exit 128 ;;
  *"status --porcelain"*) [ -n "${FAKE_DIRTY:-}" ] && echo " M lib/x.dart"; exit 0 ;;
esac
exit 128
EOF
    chmod +x "$BIN"/*
}

pin_sha() { # make the script copy trust JARSRC's hash (a "valid pinned jar")
    local s; s="$(sha256sum "$JARSRC" | cut -d' ' -f1)"; PINNED="$s"
    sed -i "s/^BUNDLETOOL_SHA256=.*/BUNDLETOOL_SHA256=\"$s\"/" "$FAKE/scripts/perf/measure_download_size.sh"
}

run() { # run [script args...]  -> OUT (stdout+stderr), RC
    local e=(HOME="$H" PATH="$BIN:$PATH" STUB_LOG="$LOGD" FAKE_SIZES="$SIZES_F" FAKE_JAR="$JARSRC"
             FAKE_GIT_TOP="$GIT_TOP" BEAUTICA_SYMBOLS_DIR="$SYMDIR")
    # AAB_PATH is only legal with --skip-build; pass it only then (or when a case forces it)
    local a; for a in "$@"; do [ "$a" = --skip-build ] && e+=(AAB_PATH="$AABP"); done
    [ -n "$FORCE_AABPATH" ] && e+=(AAB_PATH="$AABP")
    [ -n "$JAROVR" ] && e+=(BUNDLETOOL_JAR="$JAROVR")
    [ -n "$BUDGET_ENV" ] && e+=(MP7_DOWNLOAD_BUDGET_BYTES="$BUDGET_ENV")
    OUT="$(cd "$CWD" && umask "$UMASK" && env -u CI -u BUNDLETOOL_JAR -u MP7_DOWNLOAD_BUDGET_BYTES -u BEAUTICA_SYMBOLS_DIR -u AAB_PATH \
        -u FAKE_HEAD_SHORT -u FAKE_HEAD_FULL -u FAKE_DIRTY -u STUB_RO_AABDIR \
        "${e[@]}" ${EXTRA_ENV[@]+"${EXTRA_ENV[@]}"} bash "$FAKE/scripts/perf/measure_download_size.sh" "$@" 2>&1)"
    RC=$?
}
flutter_calls() { [ -f "$LOGD/flutter.log" ] && wc -l <"$LOGD/flutter.log" || echo 0; }

# ───────────── budget gate ─────────────
new_case "default budget, healthy sizes -> exit 0, size line printed, build invoked with obfuscation"
run
check ok "exit 0" '[ $RC -eq 0 ]'
check ok "arm64 size line printed" 'grep -q "arm64-v8a download size (MAX): $ARM64_MAX bytes" <<<"$OUT"'
check ok "PASS line" 'grep -q "PASS: within MP7 budget" <<<"$OUT"'
check ok "flutter built appbundle --release --obfuscate --split-debug-info=<symdir>" \
    'grep -q "build appbundle --release --obfuscate --split-debug-info=$SYMDIR" "$LOGD/flutter.log"'
check ok "x86_64 / armeabi rows ignored for the gate value" '! grep -q "download size (MAX): 12500000" <<<"$OUT"'

new_case "budget 1000 -> exit 1 with measured size and overage printed"
BUDGET_ENV=1000; run
check ok "exit 1" '[ $RC -eq 1 ]'
check ok "measured size printed" 'grep -q "$ARM64_MAX bytes  (budget 1000)" <<<"$OUT"'
check ok "FAIL overage line" 'grep -q "FAIL: over MP7 budget by $((ARM64_MAX-1000)) bytes" <<<"$OUT"'

new_case "budget boundary: == size passes, size-1 fails"
BUDGET_ENV=$ARM64_MAX; run; r1=$RC
BUDGET_ENV=$((ARM64_MAX-1)); run; r2=$RC
check ok "== budget -> 0" '[ $r1 -eq 0 ]'
check ok "budget-1 -> 1" '[ $r2 -eq 1 ]'

new_case "x86_64 over budget but arm64 under -> still 0"
printf 'SDK,ABI,MIN,MAX\n29-,ARM64_V8A,1,100\n29-,X86_64,1,99999999\n' >"$SIZES_F"; BUDGET_ENV=1000; run
check ok "exit 0" '[ $RC -eq 0 ]'

new_case "highest arm64 SDK-range MAX wins; CRLF CSV tolerated"
printf 'SDK,ABI,MIN,MAX\r\n26-28,ARM64_V8A,1,500\r\n29-,ARM64_V8A,1,900\r\n' >"$SIZES_F"; run
check ok "picks 900" 'grep -q "download size (MAX): 900 bytes" <<<"$OUT"'

new_case "bad budget / unknown arg -> exit 64, nothing built"
BUDGET_ENV=abc; run; r1=$RC; f1=$(flutter_calls)
BUDGET_ENV=""; run --bogus; r2=$RC
check ok "non-integer budget -> 64" '[ $r1 -eq 64 ]'
check ok "unknown arg -> 64" '[ $r2 -eq 64 ]'
check ok "no flutter call" '[ "$f1" = 0 ]'

# ───────────── parse failures ─────────────
new_case "no arm64 row -> exit 1, clear message"
printf 'SDK,ABI,MIN,MAX\n29-,X86_64,1,100\n' >"$SIZES_F"; run
check ok "exit 1" '[ $RC -eq 1 ]'
check ok "message names arm64-v8a" 'grep -qi "no arm64-v8a row" <<<"$OUT"'

new_case "empty get-size output -> non-zero"
: >"$SIZES_F"; run
check ok "non-zero" '[ $RC -ne 0 ]'

new_case "header lacks MAX column -> must fail with a column message (today silently reads \$0)"
printf 'SDK,ABI,MIN\n29,ARM64_V8A,10852693\n' >"$SIZES_F"; run
check ok "non-zero" '[ $RC -ne 0 ]'
check ok "message mentions the missing column" 'grep -qi "column" <<<"$OUT"'

new_case "bundletool failure propagates, no PASS"
EXTRA_ENV=(STUB_JAVA_FAIL=1); run
check ok "non-zero" '[ $RC -ne 0 ]'
check ok "no PASS line" '! grep -q "PASS:" <<<"$OUT"'

new_case "--skip-build with missing AAB -> exit 1, flutter never invoked"
rm -f "$AABP"; run --skip-build
check ok "exit 1 AAB not found" '[ $RC -eq 1 ] && grep -q "AAB not found" <<<"$OUT"'
check ok "no flutter" '[ "$(flutter_calls)" = 0 ]'

new_case "--skip-build measures existing AAB without building"
: >"$AABP"; run --skip-build
check ok "exit 0, no flutter" '[ $RC -eq 0 ] && [ "$(flutter_calls)" = 0 ]'

# ───────────── in-repo symbols refusal (exit 2, nothing built) ─────────────
refused() { # label ; expects the case already configured
    run; check ok "$1 -> exit 2" '[ $RC -eq 2 ]'
    check ok "$1 -> REFUSED message" 'grep -q "REFUSED" <<<"$OUT"'
    check ok "$1 -> flutter NEVER invoked" '[ ! -e "$LOGD/flutter.log" ]'
    check ok "$1 -> no download / no bundletool exec" '[ ! -e "$LOGD/curl.log" ] && [ ! -e "$LOGD/java.log" ]'
    check ok "$1 -> symbols dir not created" '[ ! -e "$SYMDIR" ] || [ -n "${SYM_PREEXISTS:-}" ]'
}
new_case "refuse: relative ./build/symbols from inside beautica-mobile"
CWD="$FAKE"; SYMDIR="./build/symbols"; refused "relative"
new_case "refuse: absolute path inside beautica-mobile"
SYMDIR="$FAKE/build/symbols"; refused "absolute"
new_case "refuse: absolute path directly under the repo root (outside build/)"
SYMDIR="$FAKE/symbols"; refused "root-level"
new_case "refuse: symbols dir == repo root itself"
SYMDIR="$FAKE"; SYM_PREEXISTS=1; refused "root itself"; unset SYM_PREEXISTS
new_case "refuse: symlink pointing into the repo"
mkdir -p "$FAKE/build"; ln -s "$FAKE/build" "$W/out/lnk"; SYMDIR="$W/out/lnk/symbols"; refused "symlink"
new_case "refuse: '..' traversal back into the repo"
SYMDIR="$W/out/../mono/beautica-mobile/x"; refused "dotdot"
new_case "refuse: repo-relative '..' escape that lands back inside (scripts/../x)"
SYMDIR="$FAKE/scripts/../x"; refused "scripts/.."
new_case "refuse: enclosing git toplevel (git -C reports a parent of the fake root)"
GIT_TOP="$MONO"; SYMDIR="$MONO/other-sibling/sym"; refused "git toplevel parent"
new_case "refuse also under --skip-build (refusal precedes everything)"
SYMDIR="$FAKE/s"; : >"$AABP"; run --skip-build
check ok "exit 2" '[ $RC -eq 2 ]'
check ok "no bundletool exec" '[ ! -e "$LOGD/java.log" ]'

# ───────────── out-of-repo symbols accepted ─────────────
new_case "accept: out-of-repo explicit symbols dir"
SYMDIR="$W/out/keep/sym"; run
check ok "exit 0" '[ $RC -eq 0 ]'
check ok "dir created" '[ -d "$SYMDIR" ]'
check ok "flutter got that dir" 'grep -q "split-debug-info=$SYMDIR" "$LOGD/flutter.log"'
new_case "accept: symlink that points OUT of the repo"
mkdir -p "$W/real"; ln -s "$W/real" "$W/out/lnk2"; SYMDIR="$W/out/lnk2/s"; run
check ok "exit 0, created through the link" '[ $RC -eq 0 ] && [ -d "$W/real/s" ]'
new_case "default symbols dir = \$HOME/.beautica-symbols/<versionName>+<versionCode>"
SYMDIR=""; run
check ok "exit 0" '[ $RC -eq 0 ]'
check ok "flutter got default 1.2.3+45 dir" 'grep -q "split-debug-info=$H/.beautica-symbols/1.2.3+45" "$LOGD/flutter.log"'
new_case "pubspec without versionCode -> exit 1, nothing built"
printf 'name: x\nversion: 1.2.3\n' >"$FAKE/pubspec.yaml"; run
check ok "exit 1" '[ $RC -eq 1 ] && [ ! -e "$LOGD/flutter.log" ]'

# ───────────── bundletool jar provenance ─────────────
new_case "download: wrong SHA on a freshly downloaded jar -> fail closed, jar removed, never executed"
JAROVR=""; printf 'EVIL-JAR' >"$JARSRC"; run
CJAR="$H/.cache/beautica/bundletool-1.18.1.jar"
check ok "exit 1" '[ $RC -eq 1 ]'
check ok "mismatch message" 'grep -q "SHA-256 mismatch" <<<"$OUT"'
check ok "jar deleted from cache" '[ ! -e "$CJAR" ]'
check ok "java (bundletool) NEVER executed" '[ ! -e "$LOGD/java.log" ]'
check ok "flutter never built after a bad jar" '[ ! -e "$LOGD/flutter.log" ]'
check ok "pinned release URL fetched" 'grep -q "github.com/google/bundletool/releases/download/1.18.1/bundletool-all-1.18.1.jar" "$LOGD/curl.log"'

new_case "download: correct SHA -> cached, executed, PASS"
JAROVR=""; pin_sha; run
check ok "exit 0" '[ $RC -eq 0 ]'
check ok "cached jar exists" '[ -f "$H/.cache/beautica/bundletool-1.18.1.jar" ]'
check ok "bundletool executed from cache" 'grep -q "java -jar .*/bundletool-1.18.1.jar" "$LOGD/java.log"'
check ok "executed jar bytes == pinned SHA (private copy is the verified one)" '[ "$(sort -u "$LOGD/java.jarsha")" = "$PINNED" ]'
check ok "no stray temp jar files in cache" '[ "$(ls "$H/.cache/beautica" | wc -l)" = 1 ]'

new_case "cached valid jar -> no re-download"
JAROVR=""; pin_sha; mkdir -p "$H/.cache/beautica"; cp "$JARSRC" "$H/.cache/beautica/bundletool-1.18.1.jar"; run
check ok "exit 0, curl not called" '[ $RC -eq 0 ] && [ ! -e "$LOGD/curl.log" ]'

new_case "cached TAMPERED jar -> fail closed, removed, not executed"
JAROVR=""; mkdir -p "$H/.cache/beautica"; printf 'EVIL' >"$H/.cache/beautica/bundletool-1.18.1.jar"; run
check ok "exit 1, not executed, removed" '[ $RC -eq 1 ] && [ ! -e "$LOGD/java.log" ] && [ ! -e "$H/.cache/beautica/bundletool-1.18.1.jar" ]'

new_case "curl failure -> exit 1, no jar, no temp leftovers"
JAROVR=""; EXTRA_ENV=(STUB_CURL_FAIL=1); run
check ok "exit 1 + message" '[ $RC -eq 1 ] && grep -q "download failed" <<<"$OUT"'
check ok "cache dir has no leftovers" '[ "$(ls -A "$H/.cache/beautica" | wc -l)" = 0 ]'

new_case "BUNDLETOOL_JAR pointing at a missing file -> exit 1"
JAROVR="$W/nope.jar"; run
check ok "exit 1 + message" '[ $RC -eq 1 ] && grep -q "BUNDLETOOL_JAR not found" <<<"$OUT"'

# ───────────── known gaps from the other auditors (expected RED until the fix batch) ─────────────
new_case "[gap] armeabi-v7a larger than arm64 must fail the gate (gate = max of arm64/armeabi-v7a)"
printf 'SDK,ABI,MIN,MAX\n29-,ARM64_V8A,1,10852693\n29-,ARMEABI_V7A,1,16000000\n' >"$SIZES_F"; run
check ok "exit 1 (v7a 16 MB > 15 MB budget)" '[ $RC -eq 1 ]'
new_case "[guard] armeabi-v7a smaller than arm64 stays PASS (keeps the gap fix honest)"
run; check ok "exit 0" '[ $RC -eq 0 ]'

new_case "[gap] --skip-build on a stale AAB must warn (not current for HEAD / not built with --obfuscate)"
: >"$AABP"; touch -d '30 days ago' "$AABP"; run --skip-build
check ok "stale/unverified AAB warning printed" 'grep -Eqi "stale|older than|not current|outdated|may not be obfuscated" <<<"$OUT"'

new_case "[gap] symbols dir must be created mode 700 (umask 022)"
UMASK=022; run
check ok "mode 700" '[ "$(cat "$LOGD/symbols.mode" 2>/dev/null)" = 700 ]'

new_case "[gap] bundletool cache dir must not be group/other-writable (umask 002)"
JAROVR=""; pin_sha; UMASK=002; run
check ok "cache dir mode & 022 == 0" '[ $(( 8#$(stat -c %a "$H/.cache/beautica") & 8#022 )) -eq 0 ]'

new_case "[gap] TOCTOU: jar swapped between SHA check and execution must not be executed"
JAROVR=""; pin_sha; EXTRA_ENV=(STUB_SWAP_JAR="$H/.cache/beautica/bundletool-1.18.1.jar"); run
check ok "every executed jar has the pinned SHA (or none executed)" \
    '[ ! -e "$LOGD/java.jarsha" ] || ! grep -qv "^$PINNED\$" "$LOGD/java.jarsha"'

new_case "[gap] BUNDLETOOL_JAR override must print an unverified-jar warning"
run
check ok "warning present" 'grep -Eqi "unverified|not verified|not hash|without verif|unchecked" <<<"$OUT"'

new_case "[gap] curl must pin https + TLS1.2"
JAROVR=""; pin_sha; run
check ok "--proto =https and --tlsv1.2" 'grep -q -- "--proto =https" "$LOGD/curl.log" && grep -q -- "--tlsv1.2" "$LOGD/curl.log"'

new_case "[gap] temp jar cleaned when interrupted mid-download"
JAROVR=""; pin_sha; EXTRA_ENV=(STUB_CURL_KILL_PARENT=1); run; sleep 0.5
check ok "no leftover bundletool*.XXXXXX in cache" '[ "$(ls -A "$H/.cache/beautica" 2>/dev/null | wc -l)" = 0 ]'

new_case "BUNDLETOOL_JAR + CI set -> REFUSED, nothing executed or built"
EXTRA_ENV=(CI=true); run
check ok "exit 1 + REFUSED" '[ $RC -eq 1 ] && grep -q "^REFUSED" <<<"$OUT"'
check ok "no java/flutter ran" '[ ! -e "$LOGD/java.log" ] && [ ! -e "$LOGD/flutter.log" ]'
new_case "CI set without override -> pinned flow still works"
JAROVR=""; pin_sha; EXTRA_ENV=(CI=true); run
check ok "exit 0" '[ $RC -eq 0 ]'

# ───────────── audit-fix cycle 2 (stamp / history / AAB_PATH / cp) ─────────────
VER_ENV=(FAKE_HEAD_SHORT=abc1234 FAKE_HEAD_FULL=abc1234deadbeef)
EMPTY_SHA="$(: | sha256sum | cut -d' ' -f1)"
fresh_aab() { : >"$AABP"; touch -d '+1 minute' "$AABP"; } # newer than HEAD/pubspec, so only stamp checks can warn

new_case "AAB_PATH without --skip-build -> exit 64, no build, nothing measured"
FORCE_AABPATH=1; : >"$AABP"; run
check ok "exit 64" '[ $RC -eq 64 ]'
check ok "usage message names --skip-build" 'grep -q "only valid with --skip-build" <<<"$OUT"'
check ok "no flutter / no java" '[ ! -e "$LOGD/flutter.log" ] && [ ! -e "$LOGD/java.log" ]'
check ok "AAB_PATH with --skip-build still accepted" 'FORCE_AABPATH=""; run --skip-build; [ $RC -eq 0 ]'

new_case "full build writes a stamp: short+full sha, dirty=0, aabsha, obfuscate"
EXTRA_ENV=("${VER_ENV[@]}"); run
check ok "exit 0" '[ $RC -eq 0 ]'
check ok "stamp content" 'S="$DEFAULT_AAB.measure-stamp"; grep -qx "sha=abc1234" "$S" && grep -qx "full=abc1234deadbeef" "$S" && grep -qx "dirty=0" "$S" && grep -qx "aabsha=$EMPTY_SHA" "$S" && grep -qx "obfuscate=1" "$S"'
new_case "full build on a dirty tree -> stamp dirty=1 + warning"
EXTRA_ENV=("${VER_ENV[@]}" FAKE_DIRTY=1); run
check ok "dirty=1 in stamp" 'grep -qx "dirty=1" "$DEFAULT_AAB.measure-stamp"'
check ok "dirty warning, still exit 0" '[ $RC -eq 0 ] && grep -q "working tree is dirty" <<<"$OUT"'

new_case "stamp write failure (read-only AAB dir) -> explicit warning, exit 0, measured"
if [ "$(id -u)" = 0 ]; then echo "  (skipped: root ignores directory modes)"; else
EXTRA_ENV=("${VER_ENV[@]}" STUB_RO_AABDIR=1); run
chmod u+w "$(dirname "$DEFAULT_AAB")"
check ok "exit 0" '[ $RC -eq 0 ]'
check ok "explicit warning" 'grep -q "could not write build stamp .* next --skip-build will report unverified" <<<"$OUT"'
check ok "measurement still printed + PASS" 'grep -q "PASS: within MP7 budget" <<<"$OUT"'
fi

stamp_run() { # stamp_run <stamp-body-printf-args...> ; skip-build against an up-to-date AAB with a hand-made stamp
    fresh_aab; printf "$@" >"$AABP.measure-stamp"; EXTRA_ENV=("${VER_ENV[@]}"); run --skip-build
}
new_case "skip-build: consistent stamp -> no warnings"
JAROVR=""; pin_sha
stamp_run 'sha=abc1234
full=abc1234deadbeef
dirty=0
aabsha=%s
obfuscate=1
' "$EMPTY_SHA"
check ok "exit 0, no WARNING" '[ $RC -eq 0 ] && ! grep -q "^WARNING:.*\(stale\|DIRTY\|sha256\|obfuscated\)" <<<"$OUT"'
check ok "positive control: consistent stamp + pinned jar -> row verified=1" 'grep -q ",abc1234,$ARM64_MAX,9600000,1$" "$HIST"'
new_case "skip-build: stamp full sha != HEAD -> stale warning"
JAROVR=""; pin_sha
stamp_run 'sha=abc1234
full=ffffffffffff
dirty=0
aabsha=%s
obfuscate=1
' "$EMPTY_SHA"
check ok "stale warning" 'grep -q "AAB is stale: built at .ffffffffffff" <<<"$OUT"'
check ok "history row recorded verified=0 (pinned jar, so only the stamp can cause it)" 'grep -q ",abc1234,$ARM64_MAX,9600000,0$" "$HIST"'
new_case "skip-build: stamp short sha != HEAD (no full in stamp) -> stale warning"
JAROVR=""; pin_sha
stamp_run 'sha=zzz9999
dirty=0
aabsha=%s
obfuscate=1
' "$EMPTY_SHA"
check ok "stale warning" 'grep -q "AAB is stale: built at .zzz9999" <<<"$OUT"'
check ok "history row recorded verified=0 (pinned jar, so only the stamp can cause it)" 'grep -q ",abc1234,$ARM64_MAX,9600000,0$" "$HIST"'
new_case "skip-build: dirty stamp -> warning"
JAROVR=""; pin_sha
stamp_run 'sha=abc1234
full=abc1234deadbeef
dirty=1
aabsha=%s
obfuscate=1
' "$EMPTY_SHA"
check ok "DIRTY warning" 'grep -q "built from a DIRTY" <<<"$OUT"'
check ok "history row recorded verified=0 (pinned jar, so only the stamp can cause it)" 'grep -q ",abc1234,$ARM64_MAX,9600000,0$" "$HIST"'
new_case "skip-build: AAB sha256 != stamp -> warning"
JAROVR=""; pin_sha
stamp_run 'sha=abc1234
full=abc1234deadbeef
dirty=0
aabsha=%s
obfuscate=1
' "$(printf x | sha256sum | cut -d' ' -f1)"
check ok "sha256 mismatch warning, exit 0" '[ $RC -eq 0 ] && grep -q "AAB sha256 does not match the build stamp" <<<"$OUT"'
check ok "history row recorded verified=0 (pinned jar, so only the stamp can cause it)" 'grep -q ",abc1234,$ARM64_MAX,9600000,0$" "$HIST"'
new_case "skip-build: stamp is data, never executed (command substitution in a field)"
stamp_run 'sha=abc1234
full=$(touch %s/PWNED)
dirty=0
aabsha=%s
obfuscate=1
' "$W" "$EMPTY_SHA"
check ok "no side effect" '[ ! -e "$W/PWNED" ]'

new_case "history: first run creates header + row (verified=1), no delta line"
JAROVR=""; pin_sha; EXTRA_ENV=("${VER_ENV[@]}"); run
check ok "header + row" '[ "$(sed -n 1p "$HIST")" = "date,sha,arm64,v7a,verified" ] && grep -q ",abc1234,$ARM64_MAX,9600000,1$" "$HIST"'
check ok "no delta on first row" '! grep -q "^delta vs previous" <<<"$OUT"'
check ok "file 600, dir 700" '[ "$(stat -c %a "$HIST")" = 600 ] && [ "$(stat -c %a "$(dirname "$HIST")")" = 700 ]'
check ok "no temp leftovers" '[ "$(ls -A "$(dirname "$HIST")" | wc -l)" = 1 ]'
new_case "history: same sha + sizes rerun does NOT add a row"
JAROVR=""; pin_sha; EXTRA_ENV=("${VER_ENV[@]}"); run; run
check ok "one data row (+header)" '[ "$(wc -l <"$HIST")" = 2 ]'
check ok "says not appended" 'grep -q "not appended" <<<"$OUT"'
new_case "history: new sha appends and prints delta vs previous different-sha row"
JAROVR=""; pin_sha; EXTRA_ENV=("${VER_ENV[@]}"); run
printf '%s
' "$SIZES_OK" | sed 's/10852693/10852700/' >"$SIZES_F"; EXTRA_ENV=(FAKE_HEAD_SHORT=bbb2222 FAKE_HEAD_FULL=bbb2222f); run
check ok "delta line vs abc1234: +7 / 0" 'grep -q "delta vs previous (abc1234): arm64 7 bytes, v7a 0 bytes" <<<"$OUT"'
check ok "two data rows" '[ "$(wc -l <"$HIST")" = 3 ]'
new_case "history: delta skips same-sha rows and unverified rows (baseline = last verified different sha)"
mkdir -p "$(dirname "$HIST")"
printf 'date,sha,arm64,v7a,verified
2026-01-01,old0001,10000000,9000000,1
2026-01-02,junk999,1,1,0
2026-01-03,abc1234,10852000,9600000,1
' >"$HIST"
JAROVR=""; pin_sha; EXTRA_ENV=("${VER_ENV[@]}"); run
check ok "baseline is old0001" 'grep -q "delta vs previous (old0001): arm64 852693 bytes, v7a 600000 bytes" <<<"$OUT"'
new_case "history: leading-zero legacy row -> decimal delta, no arithmetic error"
mkdir -p "$(dirname "$HIST")"; printf '2026-01-01,old0001,010000000,009600000
' >"$HIST"
JAROVR=""; pin_sha; EXTRA_ENV=("${VER_ENV[@]}"); run
check ok "exit 0, correct delta" '[ $RC -eq 0 ] && grep -q "delta vs previous (old0001): arm64 852693 bytes, v7a 0 bytes" <<<"$OUT" && ! grep -qi "value too great\|syntax error" <<<"$OUT"'
check ok "legacy row preserved, new row appended" '[ "$(wc -l <"$HIST")" = 2 ]'
new_case "history: override-jar run is recorded verified=0"
EXTRA_ENV=("${VER_ENV[@]}"); run
check ok "row ends ,0" 'grep -q ",abc1234,$ARM64_MAX,9600000,0$" "$HIST"'
new_case "history: stale skip-build run is recorded verified=0"
JAROVR=""; pin_sha; : >"$AABP"; touch -d '30 days ago' "$AABP"; EXTRA_ENV=("${VER_ENV[@]}"); run --skip-build
check ok "row ends ,0" 'grep -q ",abc1234,$ARM64_MAX,9600000,0$" "$HIST"'
new_case "history: HIST is a symlink -> skipped with warning, target untouched, exit 0"
mkdir -p "$(dirname "$HIST")" "$W/victim"; printf 'KEEP
' >"$W/victim/target"; ln -s "$W/victim/target" "$HIST"; chmod 644 "$W/victim/target"
run
check ok "exit 0" '[ $RC -eq 0 ]'
check ok "symlink warning" 'grep -q "history path is a symlink" <<<"$OUT"'
check ok "target not written or chmodded" '[ "$(cat "$W/victim/target")" = KEEP ] && [ "$(stat -c %a "$W/victim/target")" = 644 ] && [ -L "$HIST" ]'
new_case "history: pre-existing loose dir is tightened to 700 with a warning"
mkdir -p "$(dirname "$HIST")"; chmod 755 "$(dirname "$HIST")"; run
check ok "dir 700 + warning" '[ "$(stat -c %a "$(dirname "$HIST")")" = 700 ] && grep -q "history dir .* tightening to 700" <<<"$OUT"'

# ───────────── audit-fix cycle 3 ─────────────
CLEAN_STAMP='sha=abc1234
full=abc1234deadbeef
dirty=0
aabsha=%s
obfuscate=1
'
new_case "skip-build: clean stamp but CURRENT tree dirty -> warning + verified=0"
JAROVR=""; pin_sha; fresh_aab; printf "$CLEAN_STAMP" "$EMPTY_SHA" >"$AABP.measure-stamp"
EXTRA_ENV=("${VER_ENV[@]}" FAKE_DIRTY=1); run --skip-build
check ok "exit 0 + uncommitted-changes warning" '[ $RC -eq 0 ] && grep -q "working tree has uncommitted changes since the AAB was built" <<<"$OUT"'
check ok "row recorded verified=0" 'grep -q ",abc1234,$ARM64_MAX,9600000,0$" "$HIST"'
new_case "skip-build: clean stamp + clean current tree -> no uncommitted-changes warning"
JAROVR=""; pin_sha; fresh_aab; printf "$CLEAN_STAMP" "$EMPTY_SHA" >"$AABP.measure-stamp"
EXTRA_ENV=("${VER_ENV[@]}"); run --skip-build
check ok "no warning" '! grep -q "uncommitted changes since the AAB" <<<"$OUT"'

new_case "full build: dirty state is recomputed AFTER the build (tree dirtied during build -> stamp dirty=1)"
JAROVR=""; pin_sha
# git stub reports clean until flutter has run, then dirty
sed -i 's|\*"status --porcelain"\*) \[ -n "${FAKE_DIRTY:-}" \]|*"status --porcelain"*) [ -n "${FAKE_DIRTY:-}" ] \|\| [ -e "$STUB_LOG/flutter.log" ]|' "$BIN/git"
EXTRA_ENV=("${VER_ENV[@]}"); run
check ok "stamp dirty=1" 'grep -qx "dirty=1" "$DEFAULT_AAB.measure-stamp"'
check ok "dirty warning + verified=0 row" 'grep -q "working tree is dirty" <<<"$OUT" && grep -q ",abc1234,$ARM64_MAX,9600000,0$" "$HIST"'

new_case "stamp values are sanitised before being echoed in warnings"
JAROVR=""; pin_sha; fresh_aab
printf 'sha=abc1234\nfull=ev\033[31mil;$(x)`y`\ndirty=0\naabsha=%s\nobfuscate=1\n' "$EMPTY_SHA" >"$AABP.measure-stamp"
EXTRA_ENV=("${VER_ENV[@]}"); run --skip-build
check ok "stale warning shown, sanitised" 'grep -q "AAB is stale: built at .ev31milxy.," <<<"$OUT"'
check ok "no ESC, backtick, \$( or ; in output" '! grep -q $'"'"'\033'"'"' <<<"$OUT" && ! grep -q "[;\`]" <<<"$OUT" && ! grep -qF "\$(x)" <<<"$OUT"'

new_case "history: malformed ver column counts as UNVERIFIED (not a delta baseline)"
mkdir -p "$(dirname "$HIST")"
printf 'date,sha,arm64,v7a,verified
2026-01-01,old0001,10000000,9000000,1
2026-01-02,bad0002,1,1,2
2026-01-03,bad0003,2,2,yes
' >"$HIST"
JAROVR=""; pin_sha; EXTRA_ENV=("${VER_ENV[@]}"); run
check ok "baseline skips the malformed rows -> old0001" 'grep -q "delta vs previous (old0001): arm64 852693 bytes, v7a 600000 bytes" <<<"$OUT"'

new_case "build stamp: pre-planted symlink at the stamp path -> target untouched, stamp is a regular file"
JAROVR=""; pin_sha
mkdir -p "$(dirname "$DEFAULT_AAB")" "$W/victim"; printf 'KEEP\n' >"$W/victim/target"
ln -s "$W/victim/target" "$DEFAULT_AAB.measure-stamp"
EXTRA_ENV=("${VER_ENV[@]}"); run
check ok "exit 0" '[ $RC -eq 0 ]'
check ok "symlink target untouched" '[ "$(cat "$W/victim/target")" = KEEP ]'
check ok "stamp now a regular file with content" '[ ! -L "$DEFAULT_AAB.measure-stamp" ] && grep -qx "obfuscate=1" "$DEFAULT_AAB.measure-stamp"'
check ok "no stamp temp leftovers" '[ -z "$(ls -A "$(dirname "$DEFAULT_AAB")" | grep "^\.stamp\.")" ]'

new_case "build stamp: pre-planted symlink-to-DIRECTORY at the stamp path -> nothing lands in that dir, stamp is a regular file"
JAROVR=""; pin_sha
mkdir -p "$(dirname "$DEFAULT_AAB")" "$W/victimdir"
ln -s "$W/victimdir" "$DEFAULT_AAB.measure-stamp"
EXTRA_ENV=("${VER_ENV[@]}"); run
check ok "exit 0" '[ $RC -eq 0 ]'
check ok "victim dir stayed empty (no .stamp.* moved into it)" '[ -z "$(ls -A "$W/victimdir")" ]'
check ok "stamp is now a regular file with content" '[ ! -L "$DEFAULT_AAB.measure-stamp" ] && [ -f "$DEFAULT_AAB.measure-stamp" ] && grep -qx "obfuscate=1" "$DEFAULT_AAB.measure-stamp"'

new_case "history temp is registered in the cleanup trap (no .history.XXXXXX after a kill mid-write)"
grep -q 'HIST_TMP="\$tmp"' "$FAKE/scripts/perf/measure_download_size.sh" && grep -q '\$HIST_TMP' "$FAKE/scripts/perf/measure_download_size.sh"
check ok "trap removes HIST_TMP + STAMP_TMP" 'grep -q "rm -f \"\$HIST_TMP\"" "$FAKE/scripts/perf/measure_download_size.sh" && grep -q "rm -f \"\$STAMP_TMP\"" "$FAKE/scripts/perf/measure_download_size.sh"'
# behavioural: kill the script while it is inside the history write (slow `cat` stub)
JAROVR=""; pin_sha; mkdir -p "$(dirname "$HIST")"; printf 'date,sha,arm64,v7a,verified\n' >"$HIST"
printf '#!/usr/bin/env bash\nkill -TERM "$PPID"; sleep 0.4; exec /bin/cat "$@"\n' >"$BIN/cat"; chmod +x "$BIN/cat"
EXTRA_ENV=("${VER_ENV[@]}"); run; sleep 0.5
check ok "no leftover .history.* temp" '[ -z "$(ls -A "$(dirname "$HIST")" | grep "^\.history\.")" ]'

new_case "full-build run leaves nothing inside the fake repo (symbols, jar, history live outside)"
JAROVR=""; pin_sha
mkdir -p "$W/shadow"; cp -a "$FAKE" "$W/shadow/before"
EXTRA_ENV=("${VER_ENV[@]}"); run
# the only allowed new paths: beautica-mobile/build/** (the AAB + its stamp, which flutter itself writes)
NEWF="$(cd "$FAKE" && find . -type f -o -type l | sort | grep -v '^./build/')"
OLDF="$(cd "$W/shadow/before" && find . -type f -o -type l | sort)"
check ok "exit 0" '[ $RC -eq 0 ]'
check ok "no new file in the repo outside beautica-mobile/build/" '[ "$NEWF" = "$OLDF" ]'
check ok "no symbols / jar / history file inside the fake repo" '[ -z "$(find "$FAKE" \( -name "*.jar" -o -name "*.symbols" -o -name "download-size-history*" -o -name ".history.*" \) | head -n1)" ]'
check ok "symbols, jar cache and history all landed outside the repo" '[ -d "$SYMDIR" ] && [ -f "$HIST" ] && [ -f "$H/.cache/beautica/bundletool-1.18.1.jar" ]'
check ok "git status stub sees no tracked change from the script" 'grep -q "status --porcelain" "$LOGD/git.log" && ! grep -Eq "^git (add|commit|checkout|stash)" "$LOGD/git.log"'

new_case "cp of the bundletool jar fails -> non-zero, jar never executed"
printf '#!/usr/bin/env bash
exit 1
' >"$BIN/cp"; chmod +x "$BIN/cp"; run
check ok "non-zero + message" '[ $RC -ne 0 ] && grep -q "could not copy bundletool jar" <<<"$OUT"'
check ok "java never ran, no PASS" '[ ! -e "$LOGD/java.log" ] && ! grep -q "PASS:" <<<"$OUT"'

echo
echo "RESULT: pass=$PASS fail=$FAIL xfail(known gaps)=$XFAIL xpass=$XPASS"
[ "$FAIL" -eq 0 ] || exit 1
[ "${PENDING_STRICT:-0}" = 1 ] && [ "$XFAIL" -gt 0 ] && exit 1
exit 0

#!/usr/bin/env bash
# Release AAB verification — phase 409 D7 / D9. A HARD gate: `.github/workflows/release-aab.yml`
# runs it after the build, and it is the local acceptance check for a release AAB.
#
#   ./scripts/verify_release_aab.sh <app-prod-release.aab>      all 8 rules
#
# Single-rule modes (used by scripts/test/test_verify_release_aab.sh to prove each rule
# can FAIL on crafted input; same code paths as the full run):
#   --check-manifest <manifest.xml>   rules 1-6 on a `bundletool dump manifest` XML
#   --check-zipalign <file.apk>       rule 7b
#   --check-elf <lib.so>...           rule 7c
#   --check-nsc <file.apk>            rule 5 network-security-config sub-check (binary APK)
#   --check-cert <signed .aab/.jar>   rule 8
#
# Rules (any FAIL => exit 1; a rule that produced no result also FAILs — fail closed):
#   1  package == com.beautica.app
#   2  versionName / versionCode == pubspec X.Y.Z / B (parsed by check_release_version.sh)
#   3  targetSdkVersion >= 36 (D2, phase 422) and minSdkVersion == 26
#   4  merged <uses-permission> set == android/release-permissions.allow, both directions
#   5  no android:debuggable / android:usesCleartextTraffic / android:testOnly set true, AND the
#      packaged network security config (manifest android:networkSecurityConfig, every config
#      variant, read from the universal APK with `aapt2 dump xmltree`; bundletool 1.18.3 has
#      no XML-file dump) has <base-config cleartextTrafficPermitted="false"> and no element
#      with cleartextTrafficPermitted="true". Unreadable => FAIL
#   6  every autoVerify intent-filter (at least one) claims only host beautica.app
#   7  16 KB pages (D9): 7a bundle config PAGE_ALIGNMENT_16K; 7b `zipalign -c -P 16 4` on
#      the universal APK; 7c every LOAD segment of lib/{arm64-v8a,x86_64}/*.so aligned >= 2**14
#   8  `jarsigner -verify -strict` passes (only the self-signed / no-PKIX-chain errors every
#      upload key produces are tolerated; unsigned or tampered entries fail), AND exactly one
#      signer with exactly one certificate, whose SHA-256 == $BEAUTICA_UPLOAD_CERT_SHA256
#      (repo variable; colon form)
#
# Env: BEAUTICA_UPLOAD_CERT_SHA256 (rule 8; unset => FAIL), PUBSPEC, RELEASE_PERMISSIONS_ALLOW,
# REPORT (default build/release-verify.txt), MANIFEST_OUT (default build/release-manifest.xml),
# BUNDLETOOL_JAR (optional pre-fetched jar; its sha256 is still verified), ZIPALIGN, AAPT2,
# LLVM_OBJDUMP, ANDROID_HOME / ANDROID_SDK_ROOT, DRY_RUN (true => the report's FIRST line is
# DRY_RUN_MARKER; release-aab.yml dispatch dry runs). Needs java, keytool, jarsigner,
# python3, curl.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

BUNDLETOOL_VERSION='1.18.3'
# sha256 of bundletool-all-1.18.3.jar, equal to the GitHub release asset digest.
BUNDLETOOL_SHA256='a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29'
BUNDLETOOL_URL="https://github.com/google/bundletool/releases/download/${BUNDLETOOL_VERSION}/bundletool-all-${BUNDLETOOL_VERSION}.jar"

EXPECTED_PACKAGE='com.beautica.app'
EXPECTED_MIN_SDK='26'
MIN_TARGET_SDK='36'
EXPECTED_APPLINK_HOST='beautica.app'
ELF_MIN_ALIGN_LOG2='14'
DRY_RUN_MARKER='DRY-RUN — DO NOT UPLOAD'

PUBSPEC="${PUBSPEC:-$ROOT/pubspec.yaml}"
ALLOW="${RELEASE_PERMISSIONS_ALLOW:-$ROOT/android/release-permissions.allow}"
REPORT="${REPORT:-$ROOT/build/release-verify.txt}"
MANIFEST_OUT="${MANIFEST_OUT:-$ROOT/build/release-manifest.xml}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

declare -A STATUS=()
mkdir -p "$(dirname "$REPORT")"
if [ "${DRY_RUN:-false}" = "true" ]; then
  printf '%s\n' "$DRY_RUN_MARKER" > "$REPORT"
  echo "::warning::$DRY_RUN_MARKER (dry-run build from non-release code)"
else
  : > "$REPORT"
fi

# result <PASS|FAIL> <rule-number> <text>: print + append to the report; a FAIL for a
# rule sticks even if a later sub-check of the same rule passes.
result() {
  local st="$1" rule="$2" text="$3"
  printf '%s rule %s: %s\n' "$st" "$rule" "$text" | tee -a "$REPORT"
  if [ "$st" = "FAIL" ] || [ "${STATUS[$rule]:-}" = "FAIL" ]; then
    STATUS[$rule]=FAIL
  else
    STATUS[$rule]=PASS
  fi
}

# finish <rule>...: every listed rule must have a result and none may be FAIL.
finish() {
  local r bad=0
  for r in "$@"; do
    if [ -z "${STATUS[$r]:-}" ]; then
      result FAIL "$r" "not evaluated (no result produced)"
    fi
    [ "${STATUS[$r]}" = "PASS" ] || bad=1
  done
  if [ "$bad" -eq 0 ]; then
    echo "RESULT: PASS (rules $*)" | tee -a "$REPORT"
  else
    echo "::error::release AAB verification FAILED, see $REPORT"
    echo "RESULT: FAIL" | tee -a "$REPORT"
  fi
  return "$bad"
}

sdk_root() {
  local d
  for d in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$HOME/Android/Sdk"; do
    if [ -n "$d" ] && [ -d "$d" ]; then printf '%s' "$d"; return 0; fi
  done
  return 1
}

find_zipalign() {
  if [ -n "${ZIPALIGN:-}" ]; then printf '%s' "$ZIPALIGN"; return 0; fi
  local sdk z
  sdk="$(sdk_root)" || return 1
  z="$(ls -d "$sdk"/build-tools/*/zipalign 2>/dev/null | sort -V | tail -1)"
  [ -n "$z" ] && printf '%s' "$z"
}

find_aapt2() {
  if [ -n "${AAPT2:-}" ]; then printf '%s' "$AAPT2"; return 0; fi
  local sdk a
  sdk="$(sdk_root)" || return 1
  a="$(ls -d "$sdk"/build-tools/*/aapt2 2>/dev/null | sort -V | tail -1)"
  [ -n "$a" ] && printf '%s' "$a"
}

find_objdump() {
  if [ -n "${LLVM_OBJDUMP:-}" ]; then printf '%s' "$LLVM_OBJDUMP"; return 0; fi
  local sdk o
  if sdk="$(sdk_root)"; then
    o="$(ls -d "$sdk"/ndk/*/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-objdump 2>/dev/null \
      | sort -V | tail -1)"
    if [ -n "$o" ]; then printf '%s' "$o"; return 0; fi
  fi
  # GNU objdump prints the same "LOAD ... align 2**N" lines; a foreign-arch .so it
  # cannot read yields no LOAD lines, which check_elf turns into a FAIL.
  command -v llvm-objdump || command -v objdump
}

bundletool_jar() {
  local jar="${BUNDLETOOL_JAR:-$ROOT/build/tools/bundletool-all-${BUNDLETOOL_VERSION}.jar}"
  if [ ! -f "$jar" ]; then
    mkdir -p "$(dirname "$jar")"
    curl -fsSL --retry 3 -o "$jar.part" "$BUNDLETOOL_URL" >&2
    mv "$jar.part" "$jar"
  fi
  local got
  got="$(sha256sum "$jar" | cut -d' ' -f1)"
  if [ "$got" != "$BUNDLETOOL_SHA256" ]; then
    echo "::error::bundletool checksum mismatch ($got), refusing to run it" >&2
    [ -n "${BUNDLETOOL_JAR:-}" ] || rm -f "$jar"
    return 1
  fi
  printf '%s' "$jar"
}

# ---------------------------------------------------------------------------
# Rules 1-6 — one python pass over the decoded manifest. It prints exactly one
# "PASS|FAIL<TAB>rule<TAB>text" line per finding; any crash leaves rules unreported,
# which finish() turns into FAIL.
# ---------------------------------------------------------------------------
check_manifest() {
  local xml="$1" version vout st rule text
  if vout="$(PUBSPEC="$PUBSPEC" "$ROOT/scripts/check_release_version.sh" version 2>&1)"; then
    version="$vout"
  else
    result FAIL 2 "pubspec version unreadable: $vout"
    version=''
  fi
  while IFS=$'\t' read -r st rule text; do
    case "$st" in PASS | FAIL) result "$st" "$rule" "$text" ;; esac
  done < <(python3 -I - "$xml" "$version" "$ALLOW" "$EXPECTED_PACKAGE" "$MIN_TARGET_SDK" \
    "$EXPECTED_MIN_SDK" "$EXPECTED_APPLINK_HOST" <<'PY' || true
import sys
import xml.etree.ElementTree as ET

xml_path, version, allow_path, pkg, min_target, want_min, host = sys.argv[1:8]
A = '{http://schemas.android.com/apk/res/android}'

def out(ok, rule, text):
    print(('PASS' if ok else 'FAIL') + '\t' + str(rule) + '\t' + text.replace('\t', ' '))

def truthy(v):
    # Absent or an explicit false is fine; anything else (true, 0xffffffff, junk) fails.
    return v is not None and v.strip().lower() not in ('false', '0', '0x0', '0x00000000')

try:
    root = ET.parse(xml_path).getroot()
except Exception as e:  # noqa: BLE001 - every parse failure fails every rule
    for r in range(1, 7):
        out(False, r, 'manifest unparseable: %s' % e)
    sys.exit(0)

# 1 package
got = root.get('package')
out(got == pkg, 1, 'package %r (want %r)' % (got, pkg))

# 2 version
if version:
    name, _, code = version.partition('+')
    vn, vc = root.get(A + 'versionName'), root.get(A + 'versionCode')
    out(vn == name and vc == code, 2,
        'versionName %r / versionCode %r (pubspec %s)' % (vn, vc, version))

# 3 sdk levels
sdk = root.find('uses-sdk')
tgt = sdk.get(A + 'targetSdkVersion') if sdk is not None else None
mn = sdk.get(A + 'minSdkVersion') if sdk is not None else None
try:
    ok3 = int(tgt) >= int(min_target) and mn == want_min
except (TypeError, ValueError):
    ok3 = False
out(ok3, 3, 'targetSdkVersion %r (want >= %s), minSdkVersion %r (want %s)'
    % (tgt, min_target, mn, want_min))

# 4 permission allow-list, exact match
try:
    allowed = set()
    with open(allow_path, encoding='utf-8') as f:
        for line in f:
            line = line.split('#', 1)[0].strip()
            if line:
                allowed.add(line.split()[0])
except OSError as e:
    allowed = None
    out(False, 4, 'allow-list unreadable: %s' % e)
if allowed is not None:
    declared = {e.get(A + 'name') for tag in ('uses-permission', 'uses-permission-sdk-23')
                for e in root.findall(tag)}
    extra, gone = sorted(declared - allowed), sorted(allowed - declared)
    if not allowed:
        out(False, 4, 'allow-list is empty')
    elif extra or gone:
        out(False, 4, 'not in allow-list: %s; allowed but missing: %s'
            % (', '.join(map(str, extra)) or '-', ', '.join(gone) or '-'))
    else:
        out(True, 4, '%d permissions match %s exactly' % (len(declared), allow_path.split('/')[-1]))

# 5 debuggable / cleartext / testOnly
app = root.find('application')
if app is None:
    out(False, 5, 'no <application> element')
else:
    dbg, clr = app.get(A + 'debuggable'), app.get(A + 'usesCleartextTraffic')
    tst = app.get(A + 'testOnly')
    out(not truthy(dbg) and not truthy(clr) and not truthy(tst), 5,
        'debuggable=%r usesCleartextTraffic=%r testOnly=%r' % (dbg, clr, tst))

# 6 App Link autoVerify hosts
filters = [f for f in root.iter('intent-filter') if truthy(f.get(A + 'autoVerify'))]
if not filters:
    out(False, 6, 'no autoVerify intent-filter found')
else:
    bad = []
    for f in filters:
        hosts = {d.get(A + 'host') for d in f.findall('data') if d.get(A + 'host') is not None}
        if hosts != {host}:
            bad.append(sorted(hosts) or ['<none>'])
    out(not bad, 6, ('%d autoVerify filter(s), all host %s' % (len(filters), host)) if not bad
        else 'autoVerify filter(s) with hosts %s (want only %s)' % (bad, host))
PY
  )
}

# Rule 7b
check_zipalign() {
  local apk="$1" za
  if ! za="$(find_zipalign)"; then
    result FAIL 7 "7b zipalign not found (set ZIPALIGN or ANDROID_HOME)"; return
  fi
  if "$za" -c -P 16 4 "$apk" > "$WORK/zipalign.log" 2>&1; then
    result PASS 7 "7b zipalign -c -P 16 4 OK on $(basename "$apk")"
  else
    grep -a -v '(OK' "$WORK/zipalign.log" | head -20 | tee -a "$REPORT" || true
    result FAIL 7 "7b zipalign -c -P 16 4 failed on $(basename "$apk")"
  fi
}

# Rule 7c: every LOAD segment of every given .so aligned >= 2**14.
check_elf() {
  local od so bad=0 n=0 aligns
  if ! od="$(find_objdump)"; then
    result FAIL 7 "7c llvm-objdump not found (set LLVM_OBJDUMP or install the NDK)"; return
  fi
  for so in "$@"; do
    n=$((n + 1))
    local name="${so#"$WORK"/so/}"
    if ! aligns="$("$od" -p "$so" 2>&1 | awk '$1 == "LOAD" { for (i = 1; i <= NF; i++) if ($i == "align") print $(i + 1) }')" \
      || [ -z "$aligns" ]; then
      result FAIL 7 "7c no LOAD segments readable in $name"; bad=1; continue
    fi
    local lib_ok=1 min=99
    while read -r a; do
      if [[ ! "$a" =~ ^2\*\*([0-9]+)$ ]] || [ "${BASH_REMATCH[1]}" -lt "$ELF_MIN_ALIGN_LOG2" ]; then
        result FAIL 7 "7c $name LOAD segment align $a (< 2**$ELF_MIN_ALIGN_LOG2)"; bad=1; lib_ok=0; break
      fi
      [ "${BASH_REMATCH[1]}" -ge "$min" ] || min="${BASH_REMATCH[1]}"
    done <<< "$aligns"
    [ "$lib_ok" -eq 0 ] || printf '  ok %s (min LOAD align 2**%s)\n' "$name" "$min" | tee -a "$REPORT"
  done
  if [ "$n" -eq 0 ]; then
    result FAIL 7 "7c no native libraries to check"
  elif [ "$bad" -eq 0 ]; then
    result PASS 7 "7c $n native libraries, every LOAD segment >= 2**$ELF_MIN_ALIGN_LOG2"
  fi
}

# Rule 5, network-security-config sub-check, on a BINARY (APK) build of the bundle.
# Resolves manifest android:networkSecurityConfig -> resource id -> every file variant, then
# requires <base-config cleartextTrafficPermitted="false"> and no cleartext=true anywhere.
check_nsc() {
  local apk="$1" a st rule text n=0
  if ! a="$(find_aapt2)"; then
    result FAIL 5 "network security config: aapt2 not found (set AAPT2 or ANDROID_HOME)"; return
  fi
  while IFS=$'\t' read -r st rule text; do
    case "$st" in PASS | FAIL) result "$st" "$rule" "$text"; n=$((n + 1)) ;; esac
  done < <(python3 -I - "$a" "$apk" <<'PY' || true
import re, subprocess, sys

aapt2, apk = sys.argv[1:3]

def out(ok, text):
    print(('PASS' if ok else 'FAIL') + '\t5\tnetwork security config: ' + text.replace('\t', ' '))

def run(*args):
    p = subprocess.run([aapt2, 'dump', *args, apk], capture_output=True, text=True)
    if p.returncode != 0:
        msg = (p.stderr or p.stdout).strip().replace('\n', ' ')[:200]
        raise RuntimeError('aapt2 dump %s failed: %s' % (args[0], msg))
    return p.stdout

def value(raw):
    return re.sub(r'\s*\(Raw: .*\)$', '', raw.strip()).strip('"').lower()

FALSE = ('false', '0', '0x0', '0x00000000')
try:
    man = run('xmltree', '--file', 'AndroidManifest.xml')
    m = re.search(r'android:networkSecurityConfig\(0x[0-9a-f]+\)=@(0x[0-9a-f]+)', man)
    if not m:
        out(False, 'manifest has no android:networkSecurityConfig resource reference')
        sys.exit(0)
    rid = int(m.group(1), 16)
    paths, cur = [], False
    for line in run('resources').splitlines():
        hdr = re.match(r'\s*resource (0x[0-9a-f]+) ', line)
        if hdr:
            cur = int(hdr.group(1), 16) == rid
            continue
        f = re.search(r'\(file\) (\S+)', line) if cur else None
        if f:
            paths.append(f.group(1))
    if not paths:
        out(False, 'resource 0x%08x has no file in the resource table' % rid)
        sys.exit(0)
    for path in paths:
        tree = run('xmltree', '--file', path)
        bad, base_ok, base_seen, elem = [], False, False, None
        for line in tree.splitlines():
            e = re.match(r'\s*E: (\S+)', line)
            if e:
                elem = e.group(1)
                base_seen = base_seen or elem == 'base-config'
                continue
            at = re.match(r'\s*A: (?:\S*:)?cleartextTrafficPermitted(?:\(0x[0-9a-f]+\))?=(.*)$', line)
            if at:
                v = value(at.group(1))
                if v not in FALSE:
                    bad.append('%s cleartextTrafficPermitted=%s' % (elem, v))
                elif elem == 'base-config':
                    base_ok = True
        if not re.search(r'^\s*E: network-security-config\b', tree, re.M):
            out(False, '%s is not a <network-security-config>' % path)
        elif bad:
            out(False, '%s permits cleartext: %s' % (path, '; '.join(bad)))
        elif not base_ok:
            out(False, '%s has no <base-config cleartextTrafficPermitted="false">%s'
                % (path, '' if base_seen else ' (no base-config at all)'))
        else:
            out(True, '%s base-config cleartextTrafficPermitted=false, no cleartext anywhere' % path)
except Exception as ex:  # noqa: BLE001 - an unreadable config fails closed
    out(False, 'unreadable: %s' % ex)
PY
  )
  [ "$n" -gt 0 ] || result FAIL 5 "network security config: no result produced"
}

# Rule 8. jarsigner -strict exit bit 4 also covers expired / disabled-algorithm certs, so it
# is tolerated only when every "Error:" line is one of the two lines a self-signed upload key
# always produces.
JARSIGNER_TOLERATED='entries whose certificate chain is invalid\. Reason: PKIX path building failed|entries whose signer certificate is self-signed\.'
check_cert() {
  local file="$1" want got owner rc=0 errs unexpected signers shas why
  want="$(printf '%s' "${BEAUTICA_UPLOAD_CERT_SHA256:-}" | tr -d ' :\n' | tr 'a-f' 'A-F')"
  jarsigner -verify -strict "$file" > "$WORK/jarsigner.txt" 2>&1 || rc=$?
  if grep -aq 'jar is unsigned' "$WORK/jarsigner.txt"; then
    result FAIL 8 "no signing certificate in $(basename "$file") (jarsigner: jar is unsigned)"; return
  fi
  errs="$(awk '/^Error:/ { e = 1; next } e && /^[[:space:]]*$/ { e = 0 } e' "$WORK/jarsigner.txt")"
  unexpected="$(printf '%s\n' "$errs" | grep -a -v -E "$JARSIGNER_TOLERATED" | grep -a -v '^[[:space:]]*$' || true)"
  why=''
  if [ $((rc & ~4)) -ne 0 ]; then why="exit $rc"
  elif grep -aqi 'unsigned entries' "$WORK/jarsigner.txt"; then why='unsigned entries'
  elif ! grep -aq '^jar verified' "$WORK/jarsigner.txt"; then why='no "jar verified"'
  elif [ "$rc" -eq 4 ] && [ -n "$unexpected" ]; then why="error: $(head -1 <<< "$unexpected")"
  elif [ "$rc" -eq 4 ] && [ -z "$errs" ]; then why='exit 4 with no Error: lines'
  fi
  if [ -n "$why" ]; then
    grep -a -v 'is signed in JarFile but is not signed in JarInputStream' "$WORK/jarsigner.txt" \
      | head -12 | tee -a "$REPORT" || true
    result FAIL 8 "jarsigner -verify -strict failed on $(basename "$file") ($why)"; return
  fi
  keytool -printcert -jarfile "$file" > "$WORK/cert.txt" 2>&1 || true
  signers="$(grep -a -c -E '^Signer #[0-9]+:' "$WORK/cert.txt" || true)"
  shas="$(grep -a -c -E '^[[:space:]]*SHA256:' "$WORK/cert.txt" || true)"
  got="$(grep -a -m1 -E '^[[:space:]]*SHA256:' "$WORK/cert.txt" | sed -E 's/^[[:space:]]*SHA256:[[:space:]]*//' \
    | tr -d ' :\r' | tr 'a-f' 'A-F' || true)"
  owner="$(grep -a -m1 -E '^Owner:' "$WORK/cert.txt" || true)"
  if [ -z "$got" ]; then
    result FAIL 8 "no signing certificate in $(basename "$file") ($(head -1 "$WORK/cert.txt"))"
  elif [ "$signers" -ne 1 ] || [ "$shas" -ne 1 ]; then
    result FAIL 8 "expected exactly one signer with one certificate, found $signers signer(s) / $shas certificate(s)"
  elif [ -z "$want" ]; then
    result FAIL 8 "BEAUTICA_UPLOAD_CERT_SHA256 is not set (signed by: $owner)"
  elif [[ ! "$want" =~ ^[0-9A-F]{64}$ ]]; then
    result FAIL 8 "BEAUTICA_UPLOAD_CERT_SHA256 is not a SHA-256 fingerprint"
  elif [ "$got" != "$want" ]; then
    result FAIL 8 "signing cert SHA-256 $got is not the upload key ($owner)"
  else
    result PASS 8 "signing cert SHA-256 matches the upload key ($owner)"
  fi
}

verify_aab() {
  local aab="$1" bt
  [ -f "$aab" ] || { echo "::error::AAB not found: $aab"; exit 1; }
  echo "verify_release_aab.sh — $(basename "$aab") — $(date -u +%FT%TZ)" | tee -a "$REPORT"

  if ! bt="$(bundletool_jar)"; then
    finish 1 2 3 4 5 6 7 8 || exit 1
  fi

  if java -jar "$bt" dump manifest --bundle "$aab" > "$WORK/manifest.xml" 2> "$WORK/bt.err"; then
    mkdir -p "$(dirname "$MANIFEST_OUT")"
    cp "$WORK/manifest.xml" "$MANIFEST_OUT"
    check_manifest "$WORK/manifest.xml"
  else
    result FAIL 1 "bundletool dump manifest failed: $(head -1 "$WORK/bt.err")"
  fi

  # 7a
  if java -jar "$bt" dump config --bundle "$aab" 2> "$WORK/bt.err" \
    | grep -aqE '"alignment"[[:space:]]*:[[:space:]]*"PAGE_ALIGNMENT_16K"'; then
    result PASS 7 "7a bundle config alignment PAGE_ALIGNMENT_16K"
  else
    result FAIL 7 "7a bundle config is not PAGE_ALIGNMENT_16K"
  fi

  # 7b + 7c on the universal APK. Signed with a throwaway key made here: alignment does
  # not depend on the signer, and the upload keystore never reaches this script.
  if keytool -genkeypair -keystore "$WORK/verify.jks" -storepass verify-only -keypass verify-only \
      -alias v -keyalg RSA -keysize 2048 -validity 1 -dname 'CN=verify-only' > /dev/null 2>&1 \
    && java -jar "$bt" build-apks --bundle "$aab" --output "$WORK/u.apks" --mode=universal \
      --ks "$WORK/verify.jks" --ks-pass pass:verify-only --ks-key-alias v --key-pass pass:verify-only \
      > "$WORK/bt.log" 2>&1 \
    && python3 -I -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extract("universal.apk", sys.argv[2])' \
      "$WORK/u.apks" "$WORK"; then
    check_zipalign "$WORK/universal.apk"
    mkdir -p "$WORK/so"
    python3 -I - "$WORK/universal.apk" "$WORK/so" <<'PY'
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
for n in z.namelist():
    if n.endswith('.so') and n.startswith(('lib/arm64-v8a/', 'lib/x86_64/')):
        z.extract(n, sys.argv[2])
PY
    local libs=()
    mapfile -t libs < <(find "$WORK/so" -name '*.so' | sort)
    if [ ! -d "$WORK/so/lib/arm64-v8a" ]; then
      result FAIL 7 "7c universal APK has no lib/arm64-v8a"
    fi
    check_elf "${libs[@]}"
    check_nsc "$WORK/universal.apk"
  else
    result FAIL 7 "7b/7c bundletool build-apks --mode=universal failed: $(tail -1 "$WORK/bt.log" 2>/dev/null)"
    result FAIL 5 "network security config not read: universal APK build failed"
  fi

  check_cert "$aab"
  finish 1 2 3 4 5 6 7 8
}

case "${1:-}" in
  --check-manifest) shift; check_manifest "${1:?manifest.xml}"; finish 1 2 3 4 5 6 ;;
  --check-zipalign) shift; check_zipalign "${1:?file.apk}"; finish 7 ;;
  --check-elf) shift; check_elf "$@"; finish 7 ;;
  --check-nsc) shift; check_nsc "${1:?file.apk}"; finish 5 ;;
  --check-cert) shift; check_cert "${1:?signed file}"; finish 8 ;;
  -* | '') echo "usage: $0 <app.aab> | --check-manifest|--check-zipalign|--check-elf|--check-nsc|--check-cert <file>" >&2; exit 2 ;;
  *) verify_aab "$1" ;;
esac

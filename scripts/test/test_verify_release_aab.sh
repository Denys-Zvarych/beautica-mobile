#!/usr/bin/env bash
# Falsification harness for scripts/verify_release_aab.sh (phase 409 D7 / T3).
# Every rule is driven through the script's own single-rule modes with crafted input
# and must FAIL on the bad variant and PASS on the good one — proof that no rule is
# vacuous. No AAB, device or network needed:
#   rules 1-6  crafted `bundletool dump manifest` XML      (--check-manifest)
#   rule 7b    crafted zips, misaligned vs zipaligned      (--check-zipalign; needs zipalign)
#   rule 7c    gcc-built .so with 4 KB vs 16 KB LOAD align  (--check-elf; needs gcc + objdump)
#   rule 5 NSC aapt2-linked APKs with crafted network security configs
#              (--check-nsc; needs aapt2 + a platforms/*/android.jar)
#   rule 8     jarsigner-signed zips with throwaway keys: wrong key, two signers, an entry
#              tampered or added after signing (--check-cert; needs a JDK)
#   DRY_RUN    the report's first line is the DO-NOT-UPLOAD marker
# Rules 7a and the full-AAB wiring are covered by running the script on a real AAB
# (release-aab.yml, and the phase 409 local acceptance run).
#
# A missing tool SKIPs its cases locally; with CI=true any SKIP fails the run (exit 1),
# so a runner image change can never silently drop a falsification case.
#
# USAGE: ./scripts/test/test_verify_release_aab.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$(dirname "$HERE")/verify_release_aab.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0; SKIP=0; SKIPPED=()

printf 'name: x\nversion: 1.1.0+2\n' > "$TMP/pubspec.yaml"
printf 'android.permission.INTERNET  # why\n# comment\n\nandroid.permission.WAKE_LOCK  # why\n' \
  > "$TMP/allow"

GOOD='<manifest xmlns:android="http://schemas.android.com/apk/res/android" android:versionCode="2" android:versionName="1.1.0" package="com.beautica.app">
  <uses-sdk android:minSdkVersion="26" android:targetSdkVersion="36"/>
  <uses-permission android:name="android.permission.INTERNET"/>
  <uses-permission android:name="android.permission.WAKE_LOCK"/>
  <application android:name="x">
    <activity android:name="a">
      <intent-filter><action android:name="android.intent.action.MAIN"/></intent-filter>
      <intent-filter android:autoVerify="true">
        <data android:scheme="https" android:host="beautica.app" android:pathPrefix="/invite/accept"/>
      </intent-filter>
    </activity>
  </application>
</manifest>'

# run <name> <want_rc> <pattern> <mode> <file...> [-- VAR=value ...]
run() {
  local name="$1" want="$2" pat="$3" mode="$4"; shift 4
  local files=() envs=() out rc
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do files+=("$1"); shift; done
  [ "${1:-}" = "--" ] && shift
  envs=("$@")
  out="$(env PUBSPEC="$TMP/pubspec.yaml" RELEASE_PERMISSIONS_ALLOW="$TMP/allow" \
    REPORT="$TMP/report.txt" MANIFEST_OUT="$TMP/m.xml" BEAUTICA_UPLOAD_CERT_SHA256= \
    "${envs[@]}" bash "$SCRIPT" "$mode" "${files[@]}" 2>&1)"; rc=$?
  if [ "$rc" -ne "$want" ]; then
    FAIL=$((FAIL + 1)); printf '  FAIL  %s - exit %d, wanted %d\n%s\n' "$name" "$rc" "$want" "$out"; return
  fi
  if ! grep -aqF -- "$pat" <<< "$out"; then
    FAIL=$((FAIL + 1)); printf '  FAIL  %s - output lacks [%s]\n%s\n' "$name" "$pat" "$out"; return
  fi
  if [ "$want" -ne 2 ] && ! grep -aqF -- "$pat" "$TMP/report.txt"; then
    FAIL=$((FAIL + 1)); printf '  FAIL  %s - report lacks [%s]\n' "$name" "$pat"; return
  fi
  PASS=$((PASS + 1)); printf '  PASS  %s\n' "$name"
}

# man <case> <sed-expr>: GOOD manifest with one edit; prints the file path.
man() {
  local f="$TMP/$1.xml"
  printf '%s\n' "$GOOD" | sed -E "$2" > "$f"
  printf '%s' "$f"
}

skip() { SKIP=$((SKIP + 1)); SKIPPED+=("$1"); printf '  SKIP  %s\n' "$1"; }

echo "== rules 1-6: --check-manifest =="
run "good manifest passes 1-6" 0 "RESULT: PASS (rules 1 2 3 4 5 6)" --check-manifest "$(man good 's/x/x/')"
run "rule 1: staging package" 1 "FAIL rule 1" --check-manifest \
  "$(man pkg 's/package="com.beautica.app"/package="com.beautica.app.staging"/')"
run "rule 1: package missing" 1 "FAIL rule 1" --check-manifest "$(man nopkg 's/ package="[^"]*"//')"
run "rule 2: versionCode differs" 1 "FAIL rule 2" --check-manifest \
  "$(man vc 's/versionCode="2"/versionCode="3"/')"
run "rule 2: versionName differs" 1 "FAIL rule 2" --check-manifest \
  "$(man vn 's/versionName="1.1.0"/versionName="1.1.1"/')"
printf 'version: 1.1.0\n' > "$TMP/badpub.yaml"
run "rule 2: malformed pubspec" 1 "FAIL rule 2: pubspec version unreadable" --check-manifest \
  "$(man good2 's/x/x/')" -- PUBSPEC="$TMP/badpub.yaml"
run "rule 3: targetSdk 35" 1 "FAIL rule 3" --check-manifest \
  "$(man t35 's/targetSdkVersion="36"/targetSdkVersion="35"/')"
run "rule 3: targetSdk 37 is fine" 0 "PASS rule 3" --check-manifest \
  "$(man t37 's/targetSdkVersion="36"/targetSdkVersion="37"/')"
run "rule 3: minSdk 24" 1 "FAIL rule 3" --check-manifest \
  "$(man m24 's/minSdkVersion="26"/minSdkVersion="24"/')"
run "rule 3: no uses-sdk" 1 "FAIL rule 3" --check-manifest "$(man nosdk '/uses-sdk/d')"
run "rule 4: permission outside the allow-list" 1 "not in allow-list: android.permission.READ_CONTACTS" \
  --check-manifest "$(man extra 's#(<application)#<uses-permission android:name="android.permission.READ_CONTACTS"/>\1#')"
run "rule 4: AD_ID back in the manifest" 1 "com.google.android.gms.permission.AD_ID" --check-manifest \
  "$(man adid 's#(<application)#<uses-permission android:name="com.google.android.gms.permission.AD_ID"/>\1#')"
run "rule 4: uses-permission-sdk-23 counted" 1 "FAIL rule 4" --check-manifest \
  "$(man sdk23 's#(<application)#<uses-permission-sdk-23 android:name="android.permission.CAMERA"/>\1#')"
run "rule 4: allowed permission disappeared" 1 "allowed but missing: android.permission.WAKE_LOCK" \
  --check-manifest "$(man gone '/WAKE_LOCK/d')"
: > "$TMP/empty.allow"
run "rule 4: empty allow-list" 1 "FAIL rule 4" --check-manifest "$(man good3 's/x/x/')" \
  -- RELEASE_PERMISSIONS_ALLOW="$TMP/empty.allow"
run "rule 4: missing allow-list" 1 "allow-list unreadable" --check-manifest "$(man good4 's/x/x/')" \
  -- RELEASE_PERMISSIONS_ALLOW="$TMP/nope.allow"
run "rule 5: debuggable=true" 1 "FAIL rule 5" --check-manifest \
  "$(man dbg 's/<application /<application android:debuggable="true" /')"
run "rule 5: debuggable as 0xffffffff" 1 "FAIL rule 5" --check-manifest \
  "$(man dbghex 's/<application /<application android:debuggable="0xffffffff" /')"
run "rule 5: usesCleartextTraffic=true" 1 "FAIL rule 5" --check-manifest \
  "$(man clr 's/<application /<application android:usesCleartextTraffic="true" /')"
run "rule 5: testOnly=true" 1 "testOnly='true'" --check-manifest \
  "$(man tst 's/<application /<application android:testOnly="true" /')"
run "rule 5: explicit false is fine" 0 "PASS rule 5" --check-manifest \
  "$(man dbgf 's/<application /<application android:debuggable="false" android:usesCleartextTraffic="false" android:testOnly="false" /')"
run "rule 5: no <application>" 1 "FAIL rule 5: no <application>" --check-manifest \
  "$(man noapp 's/<(\/?)application[^>]*>/<\1x>/')"
run "rule 6: staging App Link host" 1 "FAIL rule 6" --check-manifest \
  "$(man host 's/android:host="beautica.app"/android:host="staging.beautica.app"/')"
run "rule 6: second host in the filter" 1 "FAIL rule 6" --check-manifest \
  "$(man host2 's#(android:pathPrefix="/invite/accept"/>)#\1<data android:host="evil.example"/>#')"
run "rule 6: second autoVerify filter elsewhere" 1 "FAIL rule 6" --check-manifest \
  "$(man filt2 's#(</activity>)#<intent-filter android:autoVerify="true"><data android:host="evil.example"/></intent-filter>\1#')"
run "rule 6: autoVerify filter without host" 1 "FAIL rule 6" --check-manifest \
  "$(man nohost 's/ android:host="beautica.app"//')"
run "rule 6: no autoVerify filter" 1 "FAIL rule 6: no autoVerify" --check-manifest \
  "$(man noav 's/ android:autoVerify="true"//')"
printf '<manifest' > "$TMP/broken.xml"
run "unparseable manifest fails every rule" 1 "FAIL rule 6: manifest unparseable" --check-manifest "$TMP/broken.xml"

echo "== rule 7b: --check-zipalign =="
ZA="${ZIPALIGN:-$(ls -d "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"/build-tools/*/zipalign 2>/dev/null | sort -V | tail -1)}"
if [ -n "$ZA" ] && [ -x "$ZA" ]; then
  python3 -I - "$TMP/bad.apk" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], 'w') as z:
    z.writestr('AndroidManifest.xml', b'x' * 37, compress_type=zipfile.ZIP_DEFLATED)
    z.writestr('lib/arm64-v8a/libx.so', b'\x7fELF' + b'\0' * 5000, compress_type=zipfile.ZIP_STORED)
PY
  "$ZA" -P 16 -f 4 "$TMP/bad.apk" "$TMP/good.apk" > /dev/null
  run "rule 7b: stored .so not 16 KB aligned" 1 "FAIL rule 7: 7b" --check-zipalign "$TMP/bad.apk" -- ZIPALIGN="$ZA"
  run "rule 7b: zipalign -P 16 output passes" 0 "PASS rule 7: 7b" --check-zipalign "$TMP/good.apk" -- ZIPALIGN="$ZA"
else
  skip "rule 7b (no zipalign under ANDROID_HOME/build-tools)"
fi
run "rule 7b: zipalign missing fails closed" 1 "zipalign not found" --check-zipalign "$TMP/allow" \
  -- ZIPALIGN= ANDROID_HOME="$TMP/nosdk" ANDROID_SDK_ROOT="$TMP/nosdk" HOME="$TMP"

echo "== rule 7c: --check-elf =="
if command -v gcc > /dev/null; then
  printf 'int f(void){return 1;}\n' > "$TMP/f.c"
  gcc -shared -fPIC -Wl,-z,max-page-size=4096 -Wl,-z,common-page-size=4096 -o "$TMP/lib4k.so" "$TMP/f.c"
  gcc -shared -fPIC -Wl,-z,max-page-size=16384 -o "$TMP/lib16k.so" "$TMP/f.c"
  run "rule 7c: 4 KB-aligned .so" 1 "LOAD segment align 2**12" --check-elf "$TMP/lib16k.so" "$TMP/lib4k.so"
  run "rule 7c: 16 KB-aligned .so" 0 "PASS rule 7: 7c 1 native libraries" --check-elf "$TMP/lib16k.so"
else
  skip "rule 7c 4K/16K (no gcc)"
fi
run "rule 7c: non-ELF file fails closed" 1 "no LOAD segments readable" --check-elf "$TMP/allow"
run "rule 7c: no libraries fails closed" 1 "no native libraries" --check-elf

echo "== rule 5: --check-nsc (network security config) =="
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
AAPT2_BIN="${AAPT2:-$(ls -d "$SDK"/build-tools/*/aapt2 2>/dev/null | sort -V | tail -1)}"
ANDROID_JAR="$(ls -d "$SDK"/platforms/android-*/android.jar 2>/dev/null | sort -V | tail -1)"
# apk <case> <manifest-application-attrs> [network_security_config.xml body]: aapt2-linked APK.
apk() {
  local d="$TMP/nsc-$1"
  mkdir -p "$d/res/xml"
  printf '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.beautica.app"><application %s/></manifest>\n' \
    "$2" > "$d/M.xml"
  printf '%s\n' "${3:-<network-security-config/>}" > "$d/res/xml/network_security_config.xml"
  "$AAPT2_BIN" compile -o "$d/c.zip" --dir "$d/res" \
    && "$AAPT2_BIN" link -o "$d/a.apk" -I "$ANDROID_JAR" --manifest "$d/M.xml" "$d/c.zip" \
    || { echo "aapt2 failed for $1" >&2; return 1; }
  printf '%s' "$d/a.apk"
}
if [ -n "$AAPT2_BIN" ] && [ -x "$AAPT2_BIN" ] && [ -n "$ANDROID_JAR" ]; then
  REF='android:networkSecurityConfig="@xml/network_security_config"'
  BASE_F='<base-config cleartextTrafficPermitted="false"><trust-anchors><certificates src="system"/></trust-anchors></base-config>'
  NSC_GOOD="<network-security-config>$BASE_F<domain-config cleartextTrafficPermitted=\"false\"><domain>api.beautica.app</domain></domain-config></network-security-config>"
  run "rule 5 NSC: base-config false, domain false passes" 0 "PASS rule 5: network security config" \
    --check-nsc "$(apk good "$REF" "$NSC_GOOD")" -- AAPT2="$AAPT2_BIN"
  run "rule 5 NSC: base-config permits cleartext" 1 "base-config cleartextTrafficPermitted=true" \
    --check-nsc "$(apk basetrue "$REF" '<network-security-config><base-config cleartextTrafficPermitted="true"/></network-security-config>')" \
    -- AAPT2="$AAPT2_BIN"
  run "rule 5 NSC: domain-config permits cleartext" 1 "domain-config cleartextTrafficPermitted=true" \
    --check-nsc "$(apk domtrue "$REF" "<network-security-config>$BASE_F<domain-config cleartextTrafficPermitted=\"true\"><domain>10.0.2.2</domain></domain-config></network-security-config>")" \
    -- AAPT2="$AAPT2_BIN"
  run "rule 5 NSC: base-config without the attribute" 1 'has no <base-config cleartextTrafficPermitted="false">' \
    --check-nsc "$(apk baseimplicit "$REF" '<network-security-config><base-config/></network-security-config>')" \
    -- AAPT2="$AAPT2_BIN"
  run "rule 5 NSC: no base-config at all" 1 "(no base-config at all)" \
    --check-nsc "$(apk nobase "$REF" '<network-security-config><domain-config cleartextTrafficPermitted="false"><domain>a.b</domain></domain-config></network-security-config>')" \
    -- AAPT2="$AAPT2_BIN"
  run "rule 5 NSC: manifest does not reference a config" 1 "no android:networkSecurityConfig" \
    --check-nsc "$(apk noref 'android:label="x"' "$NSC_GOOD")" -- AAPT2="$AAPT2_BIN"
  run "rule 5 NSC: not an APK fails closed" 1 "network security config: unreadable" \
    --check-nsc "$TMP/allow" -- AAPT2="$AAPT2_BIN"
else
  skip "rule 5 NSC (no aapt2 under build-tools or no platforms/*/android.jar)"
fi
run "rule 5 NSC: aapt2 missing fails closed" 1 "aapt2 not found" --check-nsc "$TMP/allow" \
  -- AAPT2= ANDROID_HOME="$TMP/nosdk" ANDROID_SDK_ROOT="$TMP/nosdk" HOME="$TMP"

echo "== rule 8: --check-cert =="
if command -v jarsigner > /dev/null && command -v keytool > /dev/null; then
  for k in a b; do
    keytool -genkeypair -keystore "$TMP/$k.jks" -storepass pw123456 -keypass pw123456 -alias "$k" \
      -keyalg RSA -keysize 2048 -validity 1 -dname "CN=key-$k" > /dev/null 2>&1
  done
  python3 -I -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1], "w").writestr("a.txt", "a")' "$TMP/u.zip"
  cp "$TMP/u.zip" "$TMP/s.zip"
  jarsigner -keystore "$TMP/a.jks" -storepass pw123456 "$TMP/s.zip" a > /dev/null 2>&1
  SHA_A="$(keytool -list -v -keystore "$TMP/a.jks" -storepass pw123456 -alias a | sed -nE 's/^[[:space:]]*SHA256:[[:space:]]*//p')"
  SHA_B="$(keytool -list -v -keystore "$TMP/b.jks" -storepass pw123456 -alias b | sed -nE 's/^[[:space:]]*SHA256:[[:space:]]*//p')"
  run "rule 8: matching upload cert" 0 "PASS rule 8" --check-cert "$TMP/s.zip" -- BEAUTICA_UPLOAD_CERT_SHA256="$SHA_A"
  run "rule 8: lowercase, no colons still matches" 0 "PASS rule 8" --check-cert "$TMP/s.zip" \
    -- BEAUTICA_UPLOAD_CERT_SHA256="$(printf '%s' "$SHA_A" | tr -d ':' | tr 'A-F' 'a-f')"
  run "rule 8: signed by another key" 1 "is not the upload key (Owner: CN=key-a)" --check-cert "$TMP/s.zip" \
    -- BEAUTICA_UPLOAD_CERT_SHA256="$SHA_B"
  run "rule 8: variable unset" 1 "BEAUTICA_UPLOAD_CERT_SHA256 is not set" --check-cert "$TMP/s.zip"
  run "rule 8: variable malformed" 1 "not a SHA-256 fingerprint" --check-cert "$TMP/s.zip" \
    -- BEAUTICA_UPLOAD_CERT_SHA256="AB:CD"
  run "rule 8: unsigned file" 1 "no signing certificate" --check-cert "$TMP/u.zip" \
    -- BEAUTICA_UPLOAD_CERT_SHA256="$SHA_A"
  cp "$TMP/s.zip" "$TMP/two.zip"
  jarsigner -keystore "$TMP/b.jks" -storepass pw123456 "$TMP/two.zip" b > /dev/null 2>&1
  run "rule 8: two signers (expected key is one of them)" 1 "found 2 signer(s)" --check-cert "$TMP/two.zip" \
    -- BEAUTICA_UPLOAD_CERT_SHA256="$SHA_A"
  # Same signature files, a.txt content changed after signing.
  python3 -I - "$TMP/s.zip" "$TMP/tamper.zip" add <<'PY'
import sys, zipfile
src, dst = sys.argv[1:3]
with zipfile.ZipFile(src) as zi, zipfile.ZipFile(dst, 'w') as zo:
    for i in zi.infolist():
        zo.writestr(i, b'tampered' if i.filename == 'a.txt' else zi.read(i))
with zipfile.ZipFile(src) as zi, zipfile.ZipFile(dst.replace('tamper', 'added'), 'w') as zo:
    for i in zi.infolist():
        zo.writestr(i, zi.read(i))
    zo.writestr('b.txt', 'added after signing')
PY
  # jarsigner -strict exit 4 also means "expired"; only the self-signed lines are tolerated.
  keytool -genkeypair -keystore "$TMP/x.jks" -storepass pw123456 -keypass pw123456 -alias x \
    -keyalg RSA -keysize 2048 -startdate -3d -validity 1 -dname "CN=key-x" > /dev/null 2>&1
  cp "$TMP/u.zip" "$TMP/expired.zip"
  jarsigner -keystore "$TMP/x.jks" -storepass pw123456 "$TMP/expired.zip" x > /dev/null 2>&1
  SHA_X="$(keytool -list -v -keystore "$TMP/x.jks" -storepass pw123456 -alias x | sed -nE 's/^[[:space:]]*SHA256:[[:space:]]*//p')"
  run "rule 8: expired signer cert (exit 4, not tolerated)" 1 "has expired" --check-cert "$TMP/expired.zip" \
    -- BEAUTICA_UPLOAD_CERT_SHA256="$SHA_X"
  run "rule 8: entry tampered after signing" 1 "jarsigner -verify -strict failed" --check-cert "$TMP/tamper.zip" \
    -- BEAUTICA_UPLOAD_CERT_SHA256="$SHA_A"
  run "rule 8: unsigned entry added after signing" 1 "jarsigner -verify -strict failed" --check-cert "$TMP/added.zip" \
    -- BEAUTICA_UPLOAD_CERT_SHA256="$SHA_A"
else
  skip "rule 8 (no JDK jarsigner/keytool)"
fi

echo "== DRY_RUN report marker =="
run "DRY_RUN=true: report carries the marker" 0 "DRY-RUN — DO NOT UPLOAD" --check-manifest \
  "$(man dry1 's/x/x/')" -- DRY_RUN=true
if [ "$(head -1 "$TMP/report.txt")" = "DRY-RUN — DO NOT UPLOAD" ]; then
  PASS=$((PASS + 1)); echo "  PASS  DRY_RUN=true: marker is the report's FIRST line"
else
  FAIL=$((FAIL + 1)); echo "  FAIL  DRY_RUN=true: first report line is '$(head -1 "$TMP/report.txt")'"
fi
run "DRY_RUN unset: still verifies" 0 "RESULT: PASS" --check-manifest "$(man dry2 's/x/x/')"
if ! grep -aqF "DO NOT UPLOAD" "$TMP/report.txt"; then
  PASS=$((PASS + 1)); echo "  PASS  DRY_RUN unset: no marker in the report"
else
  FAIL=$((FAIL + 1)); echo "  FAIL  DRY_RUN unset: report carries the dry-run marker"
fi

echo "== usage =="
run "no argument" 2 "usage:" ""
run "unknown flag" 2 "usage:" --bogus

printf '\n%d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
if [ "${CI:-}" = "true" ] && [ "$SKIP" -gt 0 ]; then
  printf '::error::CI=true and %d case group(s) were SKIPPED (missing tool):\n' "$SKIP"
  printf '  - %s\n' "${SKIPPED[@]}"
  exit 1
fi
[ "$FAIL" -eq 0 ]

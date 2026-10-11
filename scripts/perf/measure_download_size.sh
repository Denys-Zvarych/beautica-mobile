#!/usr/bin/env bash
# ================================================
# scripts/perf/measure_download_size.sh
#
# MP7 gate (phase 366): measure the Play per-device DOWNLOAD size of the
# release AAB for an arm64-v8a device (SDK >= 26), via bundletool, and fail if
# it exceeds the budget.  Release ships as an AAB via Play, so the number that
# matters is what bundletool computes -- not the --split-per-abi APK bytes.
#
# Usage:
#   scripts/perf/measure_download_size.sh               # build AAB, then measure
#   scripts/perf/measure_download_size.sh --skip-build  # measure the existing AAB
#
# Exit codes:
#   0  gate size <= budget (gate = max of arm64-v8a / armeabi-v7a; x86_64 excluded)
#   1  gate size  > budget (or arm64 row / ABI,MAX column not found / tool failure /
#      BUNDLETOOL_JAR override under CI)
#   2  refused: symbols dir resolves inside a git work tree (nothing built)
#  64  usage error (unknown arg, bad budget, AAB_PATH set without --skip-build)
#
# Env vars (all optional):
#   BEAUTICA_SYMBOLS_DIR       --split-debug-info output. Default:
#                              $HOME/.beautica-symbols/<versionName>+<versionCode>/
#                              (from beautica-mobile/pubspec.yaml). Symlinks and
#                              relative paths are resolved first; a path inside
#                              beautica-mobile or the monorepo root is REFUSED.
#                              Keep these files: they symbolicate Play crashes.
#   AAB_PATH                   AAB to measure. ONLY valid together with --skip-build (a build
#                              always writes the default AAB, so measuring/stamping another
#                              path after a build would be wrong: exit 64). Default:
#                              beautica-mobile/build/app/outputs/bundle/release/app-release.aab
#   BUNDLETOOL_JAR             Use this bundletool jar (NOT hash-checked; warns; refused
#                              when CI is set). Default: pinned version below, downloaded
#                              once (https, TLS1.2+) to the mode-700 ~/.cache/beautica/ and
#                              SHA-256 verified (fail closed). Either way the jar is copied
#                              into a private temp dir, re-verified there, and only that
#                              copy is executed (no check/exec race).
#   MP7_DOWNLOAD_BUDGET_BYTES  Budget in bytes. Default 15000000.
#
# --skip-build measures an EXISTING AAB: path, mtime and HEAD are printed, and a
# "stale" WARNING is raised if the AAB predates HEAD / pubspec.yaml or its
# <aab>.measure-stamp (written atomically via temp+mv, never through a symlink, by a full build: short + full HEAD sha, dirty=0|1 for
# beautica-mobile, the AAB sha256, obfuscate) is missing/mismatched, was built from a dirty
# tree, or the AAB bytes differ from the stamped sha256. The stamp is parsed with sed, never
# sourced. A failed stamp write is non-fatal (the measurement is valid) but warns.
# Each measurement appends "date,sha,arm64,v7a,verified" to
# ~/.cache/beautica-history/download-size-history.csv (private dir 700 / file 600, atomic
# write, skipped if the file or dir is a symlink) and prints the delta vs the most recent
# row with a DIFFERENT sha. verified=0 marks runs with an override jar, a stale/unstamped/
# dirty AAB; such rows are never used as a delta baseline. A repeat run with the same sha
# and sizes as the last row does not append a duplicate.
#
# Signing: bundletool needs a key only to sign the throw-away .apks set. The
# default debug keystore (~/.android/debug.keystore) is used if present; no
# keystore is created or committed. Temp .apks live in a mktemp dir removed on exit.
# ================================================
set -euo pipefail

BUNDLETOOL_VERSION="1.18.1"
BUNDLETOOL_SHA256="675786493983787ffa11550bdb7c0715679a44e1643f3ff980a529e9c822595c"
BUNDLETOOL_URL="https://github.com/google/bundletool/releases/download/${BUNDLETOOL_VERSION}/bundletool-all-${BUNDLETOOL_VERSION}.jar"

# Cleanup trap FIRST, before any temp file exists.
WORK="$(mktemp -d)"
CACHE_TMP=""
STAMP_TMP=""
HIST_TMP=""
cleanup() {
  rm -rf "$WORK"
  [[ -z "$CACHE_TMP" ]] || rm -f "$CACHE_TMP"
  [[ -z "$STAMP_TMP" ]] || rm -f "$STAMP_TMP"
  [[ -z "$HIST_TMP" ]] || rm -f "$HIST_TMP"
  return 0
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
MOBILE_REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
MOBILE_DIR="$MOBILE_REPO_DIR"
BUDGET="${MP7_DOWNLOAD_BUDGET_BYTES:-15000000}"

warn() { echo "WARNING: $*" >&2; }
# Stamp/history values are data from disk: strip everything but [:alnum:] . - before echoing.
san() { local v; v="$(LC_ALL=C; printf '%s' "${1//[^[:alnum:].-]/}")"; printf '%s' "${v:0:64}"; }

SKIP_BUILD=0
for arg in "$@"; do
  case "$arg" in
    --skip-build) SKIP_BUILD=1 ;;
    -h|--help) awk 'NR>1 && /^#/ {print; next} NR>1 {exit}' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 64 ;;
  esac
done

if [[ -n "${AAB_PATH:-}" ]] && (( ! SKIP_BUILD )); then
  echo "AAB_PATH is only valid with --skip-build (a build writes the default AAB, not AAB_PATH)." >&2
  echo "Usage: AAB_PATH=<aab> $0 --skip-build   |   $0   (build + measure)" >&2
  exit 64
fi

[[ "$BUDGET" =~ ^[0-9]+$ ]] || { echo "MP7_DOWNLOAD_BUDGET_BYTES must be an integer" >&2; exit 64; }

# --- version -> default symbols dir -----------------------------------------
version_line="$(sed -n 's/^version:[[:space:]]*\([^[:space:]]*\).*/\1/p' "$MOBILE_DIR/pubspec.yaml" | sed -n '1p')"
[[ "$version_line" == *+* ]] || { echo "cannot read versionName+versionCode from pubspec.yaml" >&2; exit 1; }

SYMBOLS_DIR="${BEAUTICA_SYMBOLS_DIR:-$HOME/.beautica-symbols/$version_line}"

# --- refuse symbols inside a git work tree (before anything else) ------------
# realpath -m resolves symlinks in existing components and relative segments
# even when the leaf does not exist yet.
SYMBOLS_ABS="$(realpath -m -- "$SYMBOLS_DIR")"
# Refuse inside this repo, and inside the parent monorepo work tree when there is one
# (the parent dir's git toplevel; absent when this repo is checked out standalone, e.g. CI).
tree_roots=("$MOBILE_DIR")
for d in "$MOBILE_DIR" "$MOBILE_DIR/.."; do
  top="$(git -C "$d" rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n "$top" ]] && tree_roots+=("$(realpath -m -- "$top")")
done
for t in "${tree_roots[@]}"; do
  t="${t%/}"
  if [[ "$SYMBOLS_ABS" == "$t" || "$SYMBOLS_ABS" == "$t"/* ]]; then
    echo "REFUSED: symbols dir '$SYMBOLS_ABS' is inside git work tree '$t'." >&2
    echo "Symbols must live outside beautica-mobile and its parent monorepo (default: \$HOME/.beautica-symbols/...)." >&2
    exit 2
  fi
done

# --- bundletool: locate + verify the SOURCE jar ------------------------------
# The jar that is finally executed is a private copy made at measurement time
# (see below); this block only decides where it comes from.
SRC_JAR=""
VERIFIED=1
if [[ -n "${BUNDLETOOL_JAR:-}" ]]; then
  if [[ -n "${CI:-}" ]]; then
    echo "REFUSED: BUNDLETOOL_JAR override is not allowed when CI is set (jar would be unverified)." >&2
    exit 1
  fi
  [[ -f "$BUNDLETOOL_JAR" ]] || { echo "BUNDLETOOL_JAR not found: $BUNDLETOOL_JAR" >&2; exit 1; }
  warn "unverified bundletool (BUNDLETOOL_JAR override)"
  SRC_JAR="$BUNDLETOOL_JAR"
  VERIFIED=0
else
  CACHE_DIR="$HOME/.cache/beautica"
  SRC_JAR="$CACHE_DIR/bundletool-${BUNDLETOOL_VERSION}.jar"
  (umask 077; mkdir -p "$CACHE_DIR")
  chmod 700 "$CACHE_DIR"
  if [[ ! -f "$SRC_JAR" ]]; then
    dl="$WORK/download.jar"
    curl --proto '=https' --tlsv1.2 -fsSL -o "$dl" "$BUNDLETOOL_URL" || { echo "bundletool download failed" >&2; exit 1; }
    actual="$(sha256sum "$dl" | cut -d' ' -f1)"
    if [[ "$actual" != "$BUNDLETOOL_SHA256" ]]; then
      echo "bundletool SHA-256 mismatch: expected $BUNDLETOOL_SHA256, got $actual" >&2
      echo "Refusing to cache or run the downloaded jar." >&2
      exit 1
    fi
    CACHE_TMP="$SRC_JAR.tmp.$$"
    install -m 600 "$dl" "$CACHE_TMP"
    mv -f "$CACHE_TMP" "$SRC_JAR"
    CACHE_TMP=""
  fi
  actual="$(sha256sum "$SRC_JAR" | cut -d' ' -f1)"
  if [[ "$actual" != "$BUNDLETOOL_SHA256" ]]; then
    echo "bundletool SHA-256 mismatch: expected $BUNDLETOOL_SHA256, got $actual" >&2
    echo "Removing $SRC_JAR; refusing to run it." >&2
    rm -f "$SRC_JAR"
    exit 1
  fi
fi

# --- build / locate AAB ------------------------------------------------------
DEFAULT_AAB="$MOBILE_DIR/build/app/outputs/bundle/release/app-release.aab"
AAB="${AAB_PATH:-$DEFAULT_AAB}"
STAMP="$AAB.measure-stamp"
head_sha="$(git -C "$MOBILE_DIR" rev-parse --short HEAD 2>/dev/null || true)"
[[ -n "$head_sha" ]] || head_sha="unknown"
head_full="$(git -C "$MOBILE_DIR" rev-parse HEAD 2>/dev/null || true)"
[[ -n "$head_full" ]] || head_full="unknown"
dirty=0
compute_dirty() {   # sets $dirty from the CURRENT beautica-mobile working tree
  local out; out="$(git -C "$MOBILE_DIR" status --porcelain 2>/dev/null || true)"
  dirty=0; [[ -z "$out" ]] || dirty=1
}
MEAS_OK=1   # 1 = measurement provenance clean (feeds the history "verified" column)
(( VERIFIED )) || MEAS_OK=0

if (( SKIP_BUILD )); then
  :
else
  # Symbols: private (700) dir, outside any repo (checked above).
  if [[ -d "$SYMBOLS_ABS" ]]; then
    pre_mode="$(stat -c %a "$SYMBOLS_ABS")"
    (( (8#$pre_mode & 8#077) == 0 )) || warn "symbols dir '$SYMBOLS_ABS' was group/world-accessible (mode $pre_mode); tightening to 700"
  else
    (umask 077; mkdir -p "$SYMBOLS_ABS")
  fi
  chmod 700 "$SYMBOLS_ABS"
  echo "==> Building release AAB (symbols -> $SYMBOLS_ABS)"
  ( cd "$MOBILE_DIR" && flutter build appbundle --release --obfuscate --split-debug-info="$SYMBOLS_ABS" )
  # Recompute AFTER the build: the tree (and HEAD) may have changed while it ran.
  compute_dirty
  head_sha="$(git -C "$MOBILE_DIR" rev-parse --short HEAD 2>/dev/null || true)"
  [[ -n "$head_sha" ]] || head_sha="unknown"
  head_full="$(git -C "$MOBILE_DIR" rev-parse HEAD 2>/dev/null || true)"
  [[ -n "$head_full" ]] || head_full="unknown"
  if [[ -f "$AAB" ]]; then
    built_sha="$(sha256sum "$AAB" | cut -d' ' -f1)"
    # temp file + atomic mv -T (GNU; the script is GNU-only anyway: stat -c, date -d, realpath -m):
    # a pre-planted symlink (even to a directory) at $STAMP is replaced, never followed.
    write_stamp() {
      STAMP_TMP="$(umask 077; mktemp "$(dirname "$STAMP")/.stamp.XXXXXX" 2>/dev/null)" || { STAMP_TMP=""; return 1; }
      printf 'sha=%s\nfull=%s\ndirty=%s\naabsha=%s\nobfuscate=1\n' "$head_sha" "$head_full" "$dirty" "$built_sha" >"$STAMP_TMP" \
        && mv -fT -- "$STAMP_TMP" "$STAMP" || { rm -f "$STAMP_TMP"; STAMP_TMP=""; return 1; }
      STAMP_TMP=""
    }
    write_stamp \
      || warn "could not write build stamp $STAMP; the measurement is still valid but the next --skip-build will report unverified."
  fi
  if (( dirty )); then
    warn "beautica-mobile working tree is dirty: HEAD $head_sha does not identify this build; history row will be marked unverified."
    MEAS_OK=0
  fi
fi
[[ -f "$AAB" ]] || { echo "AAB not found: $AAB" >&2; exit 1; }

aab_mtime="$(stat -c %Y "$AAB")"
echo "AAB:   $AAB"
echo "mtime: $(date -d "@$aab_mtime" '+%F %T') | HEAD: $head_sha"

if (( SKIP_BUILD )); then
  compute_dirty
  if (( dirty )); then
    warn "working tree has uncommitted changes since the AAB was built: HEAD $head_sha does not identify its source; measurement is unverified."
    MEAS_OK=0
  fi
  head_ct="$(git -C "$MOBILE_DIR" log -1 --format=%ct HEAD 2>/dev/null || true)"
  if [[ "$head_ct" =~ ^[0-9]+$ ]] && (( aab_mtime < head_ct )); then
    warn "AAB is stale: older than the HEAD commit ($head_sha); it may not reflect the current source."; MEAS_OK=0
  fi
  pub_mt="$(stat -c %Y "$MOBILE_DIR/pubspec.yaml" 2>/dev/null || echo 0)"
  if (( aab_mtime < pub_mt )); then
    warn "AAB is stale: older than pubspec.yaml; it may predate the current version/dependencies."; MEAS_OK=0
  fi
  if [[ ! -f "$STAMP" ]]; then
    warn "no build stamp ($STAMP): AAB may be stale or not built with --obfuscate by this script; measurement is unverified."
    MEAS_OK=0
  else
    # sed-parsed on purpose: the stamp is data, never sourced or eval'd.
    stamp_sha="$(sed -n 's/^sha=//p' "$STAMP" | sed -n '1p')"
    stamp_full="$(sed -n 's/^full=//p' "$STAMP" | sed -n '1p')"
    stamp_dirty="$(sed -n 's/^dirty=//p' "$STAMP" | sed -n '1p')"
    stamp_aabsha="$(sed -n 's/^aabsha=//p' "$STAMP" | sed -n '1p')"
    stamp_obf="$(sed -n 's/^obfuscate=//p' "$STAMP" | sed -n '1p')"
    if [[ -n "$stamp_full" && "$head_full" != "unknown" ]]; then
      [[ "$stamp_full" == "$head_full" ]] || { warn "AAB is stale: built at '$(san "$stamp_full")', HEAD is '$(san "$head_full")'."; MEAS_OK=0; }
    else
      [[ "$stamp_sha" == "$head_sha" ]] || { warn "AAB is stale: built at '$(san "${stamp_sha:-?}")', HEAD is '$(san "$head_sha")'."; MEAS_OK=0; }
    fi
    [[ "$stamp_dirty" != "1" ]] || { warn "AAB was built from a DIRTY beautica-mobile tree (stamp dirty=1); HEAD does not identify its source."; MEAS_OK=0; }
    cur_aabsha="$(sha256sum "$AAB" | cut -d' ' -f1)"
    if [[ -z "$stamp_aabsha" ]]; then
      warn "build stamp has no AAB sha256; cannot confirm the AAB is the one that was built."; MEAS_OK=0
    elif [[ "$stamp_aabsha" != "$cur_aabsha" ]]; then
      warn "AAB sha256 does not match the build stamp (stamp $(san "${stamp_aabsha:0:12}"), file ${cur_aabsha:0:12}): the AAB changed after the build."; MEAS_OK=0
    fi
    [[ "$stamp_obf" == "1" ]] || { warn "AAB may not be obfuscated (stamp obfuscate='$(san "${stamp_obf:-?}")')."; MEAS_OK=0; }
  fi
fi

# --- private copy of the jar: verify THAT copy, execute only it --------------
JAR="$WORK/bundletool-${BUNDLETOOL_VERSION}.jar"
cp -- "$SRC_JAR" "$JAR" || { echo "could not copy bundletool jar '$SRC_JAR' to a private temp dir; nothing executed." >&2; exit 1; }
chmod 400 "$JAR"
if (( VERIFIED )); then
  actual="$(sha256sum "$JAR" | cut -d' ' -f1)"
  if [[ "$actual" != "$BUNDLETOOL_SHA256" ]]; then
    echo "bundletool SHA-256 mismatch at execution time: expected $BUNDLETOOL_SHA256, got $actual" >&2
    echo "Removing $SRC_JAR; refusing to run it." >&2
    rm -f "$SRC_JAR"
    exit 1
  fi
fi

# --- bundletool: build-apks + get-size ---------------------------------------
APKS="$WORK/out.apks"

sign_args=()
if [[ -f "$HOME/.android/debug.keystore" ]]; then
  sign_args=(--ks="$HOME/.android/debug.keystore" --ks-pass=pass:android
             --ks-key-alias=androiddebugkey --key-pass=pass:android)
fi

java -jar "$JAR" build-apks --bundle="$AAB" --output="$APKS" --mode=default "${sign_args[@]}" >/dev/null
SIZES="$(java -jar "$JAR" get-size total --apks="$APKS" --dimensions=ABI,SDK)"

echo "--- bundletool get-size total (ABI,SDK) ---"
echo "$SIZES"
echo "-------------------------------------------"

# Output is CSV: header row naming columns (e.g. SDK,ABI,MIN,MAX), then rows.
# Per ABI take the highest MAX across SDK ranges. Missing ABI/MAX column is an error.
parsed="$(awk -F, '
  NR==1 { for (i=1;i<=NF;i++) { h=toupper($i); gsub(/[ \r]/,"",h); col[h]=i }
          if (!("ABI" in col) || !("MAX" in col)) {
            print "ERROR: bundletool get-size header lacks an ABI or MAX column: " $0 > "/dev/stderr"; bad=1; exit 3 }
          next }
  { abi=toupper($col["ABI"]); m=$col["MAX"]+0
    if (abi ~ /ARM64/) { if (m>a64) a64=m }
    else if (abi ~ /ARMEABI|V7A/) { if (m>v7) v7=m } }
  END { if (bad) exit 3
        if (NR==0) { print "ERROR: empty get-size output (no header column)" > "/dev/stderr"; exit 3 }
        print a64+0, v7+0 }' <<<"$SIZES")" || exit 1
read -r arm64_max v7a_max <<<"$parsed"

if (( arm64_max == 0 )); then
  echo "ERROR: no arm64-v8a row in bundletool output" >&2
  exit 1
fi

echo "arm64-v8a download size (MAX): ${arm64_max} bytes  (budget ${BUDGET})"
if (( v7a_max > 0 )); then
  echo "armeabi-v7a download size (MAX): ${v7a_max} bytes  (budget ${BUDGET})"
else
  echo "armeabi-v7a download size (MAX): no row in bundletool output (not gated)"
fi
gate=$(( arm64_max > v7a_max ? arm64_max : v7a_max ))
echo "gate value (max of arm64-v8a, armeabi-v7a): ${gate} bytes"

# --- growth history (never fails the run) ------------------------------------
HIST_DIR="$HOME/.cache/beautica-history"
HIST="$HIST_DIR/download-size-history.csv"
HIST_HEADER="date,sha,arm64,v7a,verified"
verified_col=$MEAS_OK

update_history() {
  if [[ -L "$HIST_DIR" || -L "$HIST" ]]; then
    warn "history path is a symlink ($HIST); refusing to follow it, history skipped."
    return 0
  fi
  # Rows: date,sha,arm64,v7a[,verified]. Legacy 4-column rows count as verified.
  # Delta baseline = most recent verified row with a DIFFERENT sha; the LAST row is
  # only used to skip an exact duplicate (same sha, sizes and verified flag).
  local d s a v ver rest last_s="" last_a="" last_v="" last_ver="" base_s="" base_a="" base_v=""
  if [[ -f "$HIST" ]]; then
    while IFS=, read -r d s a v ver rest || [[ -n "$d" ]]; do
      [[ "$a" =~ ^[0-9]+$ && "$v" =~ ^[0-9]+$ ]] || continue   # header / junk
      a=$((10#$a)); v=$((10#$v))
      # verified only on literal 1 (or empty = legacy 4-column row); anything else is unverified.
      case "$ver" in ""|1) ver=1 ;; *) ver=0 ;; esac
      last_s="$s"; last_a="$a"; last_v="$v"; last_ver="$ver"
      if [[ "$ver" == "1" && "$s" != "$head_sha" ]]; then base_s="$s"; base_a="$a"; base_v="$v"; fi
    done <"$HIST"
  fi
  if [[ -n "$base_s" ]]; then
    echo "delta vs previous ($(san "$base_s")): arm64 $(( arm64_max - base_a )) bytes, v7a $(( v7a_max - base_v )) bytes"
  fi
  if [[ "$last_s" == "$head_sha" && "$last_a" == "$arm64_max" && "$last_v" == "$v7a_max" && "$last_ver" == "$verified_col" ]]; then
    echo "history: same sha and sizes as the last row; not appended."
    return 0
  fi
  (umask 077; mkdir -p "$HIST_DIR") || return 1
  local dmode; dmode="$(stat -c %a "$HIST_DIR")" || return 1
  (( (8#$dmode & 8#077) == 0 )) || warn "history dir '$HIST_DIR' was group/world-accessible (mode $dmode); tightening to 700"
  chmod 700 "$HIST_DIR" || return 1
  local tmp; tmp="$(umask 077; mktemp "$HIST_DIR/.history.XXXXXX")" || return 1
  HIST_TMP="$tmp"
  { if [[ -f "$HIST" ]]; then cat -- "$HIST"; else echo "$HIST_HEADER"; fi
    printf '%s,%s,%s,%s,%s\n' "$(date +%F)" "$head_sha" "$arm64_max" "$v7a_max" "$verified_col"
  } >"$tmp" && chmod 600 "$tmp" && mv -f -- "$tmp" "$HIST" || { rm -f "$tmp"; HIST_TMP=""; return 1; }
  HIST_TMP=""
}
update_history || warn "could not update history file $HIST"

if (( gate > BUDGET )); then
  echo "FAIL: over MP7 budget by $(( gate - BUDGET )) bytes" >&2
  exit 1
fi
echo "PASS: within MP7 budget"

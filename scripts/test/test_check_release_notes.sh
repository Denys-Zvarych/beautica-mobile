#!/usr/bin/env bash
# Table-driven harness for scripts/check_release_notes.sh (phase 423 D9/D10).
# Each case copies the SHIPPED script into a throwaway git repo whose history carries
# mobile-v* tags with (or without) release-notes/whatsnew-uk, writes the working-tree
# notes file, and runs the script as CI does. A case passes only on the expected exit
# code AND the expected `::error::`/`::notice::`/`::warning::`/PASS text, so a rule that
# silently stops firing turns its row red.
#
# USAGE: ./scripts/test/test_check_release_notes.sh
set -uo pipefail
export LC_ALL=C.UTF-8

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$(dirname "$HERE")/check_release_notes.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
N=release-notes/whatsnew-uk

g() { git -c user.email=t@t -c user.name=t -c tag.gpgSign=false -c commit.gpgSign=false "$@"; }

# repo <case>: fresh repo with the script copied in and one root commit. Prints its path.
repo() {
  local r="$TMP/$1"
  mkdir -p "$r/scripts" "$r/release-notes"
  cp "$SRC" "$r/scripts/check_release_notes.sh"
  (cd "$r" && git init -q -b main . && g commit -q --allow-empty -m root)
  printf '%s' "$r"
}

# tag_with <repo> <tag> [notes]: commit (notes written with printf %b, or the file removed
# when no notes are given) and create an annotated tag on it.
tag_with() {
  local r="$1" t="$2"
  (
    cd "$r" || exit 1
    if [ "$#" -ge 3 ]; then printf '%b' "$3" > "$N"; git add "$N"; else git rm -q --ignore-unmatch "$N"; fi
    g commit -q --allow-empty -m "$t"
    g tag -a -m "$t" "$t"
  )
}

# notes <repo> <content>: working-tree notes file (printf %b).
notes() { printf '%b' "$2" > "$1/$N"; }

# check <name> <want_rc> <pattern> <repo> <mode> [VAR=value ...]
check() {
  local name="$1" want="$2" pat="$3" r="$4" mode="$5" out rc; shift 5
  out="$(cd "$r" && env -i PATH="$PATH" HOME="$HOME" "$@" \
    bash scripts/check_release_notes.sh "$mode" 2>&1)"; rc=$?
  if [ "$rc" -ne "$want" ]; then
    FAIL=$((FAIL + 1)); printf '  FAIL  %s - exit %d, wanted %d\n%s\n' "$name" "$rc" "$want" "$out"; return
  fi
  if ! grep -aqF -- "$pat" <<< "$out"; then
    FAIL=$((FAIL + 1)); printf '  FAIL  %s - output lacks %s\n%s\n' "$name" "$pat" "$out"; return
  fi
  PASS=$((PASS + 1)); printf '  PASS  %s\n' "$name"
}

# cyr <n>: n Cyrillic code points (2 bytes each in UTF-8).
cyr() { local i s=''; for ((i = 0; i < $1; i++)); do s+='ї'; done; printf '%s' "$s"; }

echo "== format rules (1)-(3) =="
r="$(repo fmt)"
rm -f "$r/$N"
check "file missing" 1 "::error::rule (1): $N not found" "$r" pr
notes "$r" ''
check "empty file" 1 "::error::rule (2)" "$r" pr
notes "$r" '  \n\t\n \n'
check "whitespace-only file" 1 "::error::rule (2)" "$r" pr
notes "$r" "$(cyr 500)\n"
check "exactly 500 Cyrillic code points (+ trailing LF) passes" 0 "500/500 characters" "$r" pr
notes "$r" "$(cyr 501)"
check "501 code points fails" 1 "::error::rule (3): $N is 501 characters" "$r" pr
notes "$r" 'Покращення стабільності.\r\nДрібні виправлення.\r\n'
check "CRLF line endings fail" 1 "::error::rule (1): $N has CR" "$r" pr
notes "$r" '\xef\xbb\xbfПокращення стабільності.\n'
check "UTF-8 BOM fails" 1 "::error::rule (1): $N starts with a UTF-8 BOM" "$r" pr
notes "$r" 'Покращення \xff стабільності.\n'
check "invalid UTF-8 fails" 1 "::error::rule (1): $N is not valid UTF-8" "$r" pr
notes "$r" 'Покращення стабільності.\n'
printf 'x\n' > "$r/release-notes/whatsnew-en-US"
check "extra whatsnew-* file beside whatsnew-uk fails" 1 "::error::rule (1): release-notes/ must contain only whatsnew-uk" "$r" pr
rm -f "$r/release-notes/whatsnew-en-US"; : > "$r/release-notes/.hidden"
check "hidden stray file fails" 1 "found release-notes/.hidden" "$r" pr
rm -f "$r/release-notes/.hidden"; mkdir -p "$r/release-notes/sub"
check "subdirectory fails" 1 "found release-notes/sub" "$r" pr
rmdir "$r/release-notes/sub"
check "no previous tag passes with a notice" 0 "::notice::rule (4): no previous mobile-v* tag" "$r" pr

echo "== rule (4): differs from the previous tag =="
r="$(repo diff)"
tag_with "$r" 'mobile-v1.1.0+2'
tag_with "$r" 'mobile-v1.2.0+3' 'Нові фільтри пошуку.\n'
notes "$r" 'Нові фільтри пошуку.\n'
check "pr: identical to the highest tag fails" 1 "::error::rule (4): $N is the same as at mobile-v1.2.0+3" "$r" pr
notes "$r" '  Нові   фільтри\nпошуку.  \n\n'
check "pr: whitespace-only diff vs the previous tag fails" 1 "::error::rule (4)" "$r" pr
notes "$r" 'Нові фільтри пошуку.\n'
check "dispatch: same as previous is only a warning" 0 "::warning::rule (4)" "$r" dispatch
notes "$r" 'Швидше завантаження календаря.\n'
check "pr: new notes pass" 0 "PASS rule (4): $N differs from mobile-v1.2.0+3" "$r" pr
check "tag: compared with the previous tag, not itself" 0 "differs from mobile-v1.2.0+3" "$r" tag \
  GITHUB_REF_NAME='mobile-v1.3.0+4'
notes "$r" 'Нові фільтри пошуку.\n'
check "tag: stale notes fail on a tag push" 1 "::error::rule (4): $N is the same as at mobile-v1.2.0+3" "$r" tag \
  GITHUB_REF_NAME='mobile-v1.3.0+4'
check "tag: previous tag without the file passes with a notice" 0 "previous tag mobile-v1.1.0+2 has no $N" "$r" tag \
  GITHUB_REF_NAME='mobile-v1.2.0+3'
check "tag: malformed ref name fails" 1 "::error::rule (4): GITHUB_REF_NAME 'dev' is not" "$r" tag \
  GITHUB_REF_NAME=dev
check "tag: unset ref name fails" 1 "::error::rule (4): GITHUB_REF_NAME ''" "$r" tag

echo "== previous tag = largest +B, not lexical order =="
r="$(repo order)"
tag_with "$r" 'mobile-v1.9.0+9' 'Старі нотатки дев'"'"'ять.\n'
tag_with "$r" 'mobile-v1.10.0+10' 'Нотатки десять.\n'
tag_with "$r" 'mobile-v1.10.1+11' 'Нотатки одинадцять.\n'
tag_with "$r" 'mobile-vbogus' 'Сміттєвий тег.\n'
notes "$r" 'Нотатки одинадцять.\n'
check "pr: highest +B (11) chosen over lexical max (+9)" 1 "same as at mobile-v1.10.1+11" "$r" pr
notes "$r" 'Нотатки десять.\n'
check "tag +12: previous is +11, notes equal to +10 pass" 0 "differs from mobile-v1.10.1+11" "$r" tag \
  GITHUB_REF_NAME='mobile-v1.11.0+12'
check "tag +11: previous is +10 (strictly lower +B)" 1 "same as at mobile-v1.10.0+10" "$r" tag \
  GITHUB_REF_NAME='mobile-v1.10.1+11'
notes "$r" 'Сміттєвий тег.\n'
check "malformed mobile-v tags are ignored" 0 "differs from mobile-v1.10.1+11" "$r" pr

echo "== +B longer than 9 digits (arithmetic overflow guard) =="
tag_with "$r" 'mobile-v9.0.0+99999999999' 'Сміттєвий тег.\n'
check "pr: 11-digit +B tag is ignored, previous stays +11" 0 "differs from mobile-v1.10.1+11" "$r" pr
check "tag: 10-digit +B ref name fails" 1 "::error::rule (4): GITHUB_REF_NAME 'mobile-v2.0.0+1000000000' is not" "$r" tag \
  GITHUB_REF_NAME='mobile-v2.0.0+1000000000'
check "tag: 9-digit +B ref name is accepted" 0 "differs from mobile-v1.10.1+11" "$r" tag \
  GITHUB_REF_NAME='mobile-v2.0.0+999999999'

echo "== usage =="
check "unknown mode" 2 "usage:" "$r" bogus
check "no mode" 2 "usage:" "$r" ''

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

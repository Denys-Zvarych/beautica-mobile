#!/usr/bin/env bash
# Release-notes check — phase 423 D9/D10 (docs/mobile-phases/phase-423-play-auto-upload.md).
#
#   ./scripts/check_release_notes.sh <tag|dispatch|pr>
#
# Checks release-notes/whatsnew-uk, the Ukrainian "What's new" text the `play-upload` job of
# .github/workflows/release-aab.yml sends to Google Play (r0adkll whatsnew-<LOCALE>, locale `uk`):
#   (1) the file exists and is the ONLY entry in release-notes/, is valid UTF-8, has no BOM
#       and no CR (LF line endings only);
#   (2) it is non-empty after trimming whitespace;
#   (3) it is at most 500 Unicode code points (Play limit), counted with `wc -m` under
#       LC_ALL=C.UTF-8 after stripping trailing newlines;
#   (4) it differs from the same file at the PREVIOUS `mobile-v*` tag. Both sides are
#       whitespace-normalised first (CR dropped, runs of whitespace collapsed, trimmed), so
#       a whitespace-only edit counts as "the same".
#       "Previous" is chosen by the NUMERIC build number +B, never lexically, among tags
#       matching ^mobile-v[0-9]+.[0-9]+.[0-9]+\+[0-9]+$:
#         tag       the largest +B strictly below the +B of GITHUB_REF_NAME (the tag being
#                   released; it must itself be a well-formed mobile-v tag);
#         dispatch  the largest +B overall; "same as previous" is only a ::warning::
#                   (workflow_dispatch dry run, nothing is uploaded);
#         pr        the largest +B overall (bump PR into main / `/git release` precheck).
#       No previous tag, or a previous tag without the file -> pass with a ::notice::
#       (the very first automated release).
#
# Inputs come only from env: GITHUB_REF_NAME (mode tag). Run from the repo root with full
# history and tags (actions/checkout fetch-depth: 0).
# Exit 0 = pass. Exit 1 = fail, with a `::error::` line naming the rule. Exit 2 = usage.
set -euo pipefail
export LC_ALL=C.UTF-8

NOTES_DIR='release-notes'
NOTES_PATH="$NOTES_DIR/whatsnew-uk"
MAX_CHARS=500
# +B is capped at 9 digits so bash arithmetic can never overflow (a 10+ digit +B is not a
# release tag: ignored when listing, a failure as GITHUB_REF_NAME).
TAG_RE='^mobile-v[0-9]+\.[0-9]+\.[0-9]+\+([0-9]{1,9})$'

fail() { printf '::error::%s\n' "$1"; exit 1; }

# normalise: stdin -> CR dropped, whitespace runs collapsed to one space, trimmed.
normalise() { tr -d '\r' | tr -s '[:space:]' ' ' | sed -E 's/^ //; s/ $//'; }

# build_number <tag>: prints +B of a well-formed mobile-v tag, nothing otherwise.
build_number() { [[ "$1" =~ $TAG_RE ]] && printf '%s' "${BASH_REMATCH[1]}"; }

# previous_tag <below|''>: prints the tag with the largest +B (strictly below <below> when
# given). Ties on +B are broken by version sort so the result is deterministic.
previous_tag() {
  local below="$1" t b best='' best_b=-1
  while IFS= read -r t; do
    b="$(build_number "$t")" || continue
    [ -n "$b" ] || continue
    if [ -n "$below" ] && [ "$((10#$b))" -ge "$((10#$below))" ]; then continue; fi
    if [ "$((10#$b))" -gt "$best_b" ]; then
      best="$t"; best_b="$((10#$b))"
    fi
  done < <(git tag -l 'mobile-v*' | sort -V)
  printf '%s' "$best"
}

check_file() {
  local f="$1" body count extra
  [ -f "$f" ] || fail "rule (1): $f not found (Play 'What's new' text, phase 423 D9)"
  # Play reads every whatsnew-* file in the uploaded dir; only $NOTES_PATH is checked, so
  # nothing else (other locales, hidden or stray files, subdirectories) may sit beside it.
  extra="$(find "$NOTES_DIR" -mindepth 1 ! -path "$NOTES_PATH" -print -quit)"
  [ -z "$extra" ] \
    || fail "rule (1): $NOTES_DIR/ must contain only whatsnew-uk, found $extra"
  if ! iconv -f UTF-8 -t UTF-8 "$f" > /dev/null 2>&1; then
    fail "rule (1): $f is not valid UTF-8"
  fi
  if [ "$(head -c 3 "$f" | od -An -tx1 | tr -d ' \n')" = "efbbbf" ]; then
    fail "rule (1): $f starts with a UTF-8 BOM (save it as UTF-8 without BOM)"
  fi
  if grep -q $'\r' "$f"; then
    fail "rule (1): $f has CR (CRLF) line endings; use LF only"
  fi
  if [ -z "$(normalise < "$f")" ]; then
    fail "rule (2): $f is empty or whitespace-only"
  fi
  # $(...) strips every trailing newline; printf adds none back.
  body="$(cat "$f")"
  count="$(printf '%s' "$body" | wc -m | tr -d ' ')"
  [ "$count" -le "$MAX_CHARS" ] \
    || fail "rule (3): $f is $count characters, Play allows at most $MAX_CHARS"
  echo "PASS rules (1)-(3): $f is UTF-8/LF, non-empty, $count/$MAX_CHARS characters"
}

check_differs() {
  local mode="$1" f="$2" below='' prev cur old
  if [ "$mode" = "tag" ]; then
    below="$(build_number "${GITHUB_REF_NAME:-}")" \
      || fail "rule (4): GITHUB_REF_NAME '${GITHUB_REF_NAME:-}' is not a mobile-vX.Y.Z+B tag"
  fi
  prev="$(previous_tag "$below")"
  if [ -z "$prev" ]; then
    echo "::notice::rule (4): no previous mobile-v* tag; nothing to compare $f against"
    return 0
  fi
  if ! git cat-file -e "$prev:$NOTES_PATH" 2>/dev/null; then
    echo "::notice::rule (4): previous tag $prev has no $NOTES_PATH; first automated release notes"
    return 0
  fi
  cur="$(normalise < "$f")"
  old="$(git show "$prev:$NOTES_PATH" | normalise)"
  if [ "$cur" = "$old" ]; then
    if [ "$mode" = "dispatch" ]; then
      echo "::warning::rule (4): $f is the same as at $prev; write new notes before tagging"
      return 0
    fi
    fail "rule (4): $f is the same as at $prev (ignoring whitespace); write the notes for this release"
  fi
  echo "PASS rule (4): $f differs from $prev"
}

case "${1:-}" in
  tag | dispatch | pr)
    check_file "$NOTES_PATH"
    check_differs "$1" "$NOTES_PATH" ;;
  *)
    echo "usage: $0 tag|dispatch|pr" >&2
    exit 2 ;;
esac

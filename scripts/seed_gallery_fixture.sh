#!/usr/bin/env bash
# Phase 073 — seed a JPEG into the device gallery (MediaStore) so the patrol
# avatar test (integration_test/patrol/avatar_pick_patrol_test.dart) has a
# photo to select in the Android Photo Picker. A device test cannot write to
# MediaStore itself, so run this from the host BEFORE `patrol test`.
#
# Usage: scripts/seed_gallery_fixture.sh [--clean] [adb args...]
#   seed : scripts/seed_gallery_fixture.sh -H 10.0.2.2 -P 5037 -s RF8R704WR6P
#   clean: scripts/seed_gallery_fixture.sh --clean -H 10.0.2.2 -P 5037 -s RF8R704WR6P
#          removes the JPEG from /sdcard/Pictures AND its MediaStore row, so the
#          fixture does not linger in the user's gallery after the run.
#
# Re-scan: the `MEDIA_SCANNER_SCAN_FILE` broadcast is deprecated and ignored on
# Android 10+ (scoped storage). The MediaProvider `scan_file` call works from
# the shell uid on 10+; the legacy broadcast stays as a fallback for older
# devices only.
set -euo pipefail
cd "$(dirname "$0")/.."

FIXTURE="integration_test/fixtures/avatar.jpg"
REMOTE="/sdcard/Pictures/beautica_avatar_fixture.jpg"
CLEAN=0
if [[ "${1:-}" == "--clean" ]]; then
  CLEAN=1
  shift
fi

scan() {
  # Android 10+: ask MediaProvider directly. Prints a Bundle on success.
  if adb "$@" shell content call --uri content://media/external_primary \
      --method scan_file --arg "$REMOTE" >/dev/null 2>&1; then
    return 0
  fi
  # Pre-10 fallback.
  adb "$@" shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE \
    -d "file://$REMOTE" >/dev/null 2>&1 || true
}

if [[ $CLEAN -eq 1 ]]; then
  adb "$@" shell rm -f "$REMOTE"
  # Drop the MediaStore row (scanning a missing file does not on every OEM).
  adb "$@" shell content delete --uri content://media/external/images/media \
    --where "_data='$REMOTE'" >/dev/null 2>&1 || true
  scan "$@"
  echo "cleaned $REMOTE"
  exit 0
fi

adb "$@" push "$FIXTURE" "$REMOTE"
scan "$@"
echo "seeded $REMOTE"

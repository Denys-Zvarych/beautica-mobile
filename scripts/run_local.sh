#!/usr/bin/env bash
# scripts/run_local.sh
#
# Boot the app on the Windows-host Android emulator over the ADB bridge,
# pointing at a local backend running on 10.0.2.2:8080 (the emulator alias
# for the Windows host loopback). If the backend runs inside the Ubuntu VM,
# override BEAUTICA_BASE_URL on the command line — see ARCHITECTURE-mobile.md
# § 0.7 (network routing note).
#
# Usage:
#   ./scripts/run_local.sh                  # default local URL
#   BEAUTICA_BASE_URL=http://192.168.56.1:8080/api/v1 ./scripts/run_local.sh
#
# Prerequisites:
#   - Windows AVD booted + start_adb_server.ps1 running on the host.
#   - ../scripts/connect_adb.sh succeeded (one-time per session).

set -euo pipefail

BASE_URL="${BEAUTICA_BASE_URL:-http://10.0.2.2:8080/api/v1}"

cd "$(dirname "$0")/.."

exec flutter run \
  --dart-define=BEAUTICA_BASE_URL="$BASE_URL"

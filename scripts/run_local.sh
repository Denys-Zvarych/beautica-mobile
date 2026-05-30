#!/usr/bin/env bash
# scripts/run_local.sh
#
# Boot the app on the Windows-host Android emulator over the ADB bridge,
# pointing at a local backend running on 10.0.2.2:8080 (the emulator alias
# for the Windows host loopback). If the backend runs inside the Ubuntu VM,
# override BEAUTICA_BASE_URL on the command line — see ARCHITECTURE-mobile.md
# § 0.7 (network routing note).
#
# NOTE: The URL must NOT include an /api/v1 suffix. The generated API client
# and all raw Dio calls already include the /api/v1/ prefix in their paths.
# Appending /api/v1 to the base URL produces double-prefix URLs that Spring
# Security blocks with 401 Unauthorized.
#
# Usage:
#   ./scripts/run_local.sh [debug|profile|release]   (default: debug)
#   ./scripts/run_local.sh                  # default local URL, debug mode
#   BEAUTICA_BASE_URL=http://192.168.56.1:8080 ./scripts/run_local.sh
#   ./scripts/run_local.sh profile          # profile mode — removes JIT overhead
#
# Prerequisites:
#   - Windows AVD booted + start_adb_server.ps1 running on the host.
#   - ../scripts/connect_adb.sh succeeded (one-time per session).

set -euo pipefail

MODE="${1:-debug}"
# Whitelist guard — prevent flag injection via an unrecognized MODE argument.
case "$MODE" in
  debug|profile|release) ;;
  *)
    echo "Usage: $0 [debug|profile|release]" >&2
    exit 1
    ;;
esac
BASE_URL="${BEAUTICA_BASE_URL:-http://10.0.2.2:8080}"

cd "$(dirname "$0")/.."

exec flutter run --$MODE \
  --dart-define=BEAUTICA_BASE_URL="$BASE_URL"

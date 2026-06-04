#!/usr/bin/env bash
# scripts/run_local.sh
#
# Boot the app on the Windows-host Android emulator over the ADB bridge,
# pointing at the local backend that runs INSIDE this Ubuntu VM on :8080.
# Topology: VirtualBox is NAT-only, so the emulator (on the Windows host)
# reaches the VM backend only via `adb reverse tcp:8080 tcp:8080` — that
# tunnels the emulator's localhost:8080 back to the VM. Hence the default
# base URL is http://localhost:8080 (NOT 10.0.2.2, which is the Windows host
# loopback and has no backend under this topology). If you instead run the
# backend ON the Windows host, override with
# BEAUTICA_BASE_URL=http://10.0.2.2:8080. See ARCHITECTURE-mobile.md § 0.7.
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
# Topology: backend lives in the VM; emulator reaches it via `adb reverse`,
# so localhost:8080 (forwarded back to the VM) is the working default. An
# explicit BEAUTICA_BASE_URL override still wins (e.g. http://10.0.2.2:8080
# when the backend runs on the Windows host).
BASE_URL="${BEAUTICA_BASE_URL:-http://localhost:8080}"

# ------------------------------------------------
# Preflight: require an online device before launching.
# Without this, the app boots, fails to reach the backend, and shows a silent
# "No internet connection" — the exact regression this guards against.
# ------------------------------------------------
if ! adb devices | grep -qE "\sdevice$"; then
  echo "ERROR: No online ADB device found." >&2
  echo "" >&2
  echo "Fix this before launching:" >&2
  echo "  1. Boot the Android emulator on Windows + start its adb server" >&2
  echo "     (start_adb_server.ps1 on the host)." >&2
  echo "  2. Bridge the VM to it:  ../scripts/connect_adb.sh" >&2
  echo "  3. Re-run this script:   $0 $MODE" >&2
  exit 1
fi

# Guarantee the VM-backend reverse forward even if connect_adb.sh wasn't
# re-run this session. Idempotent — `adb reverse` overwrites the mapping.
# Warn (don't hard-fail) on hiccup; the device is already online above.
if adb reverse tcp:8080 tcp:8080 >/dev/null 2>&1; then
  echo "✓ adb reverse tcp:8080 → VM backend"
else
  echo "WARNING: 'adb reverse tcp:8080 tcp:8080' failed — the app may not reach the backend." >&2
fi

cd "$(dirname "$0")/.."

exec flutter run --$MODE \
  --dart-define=BEAUTICA_BASE_URL="$BASE_URL"

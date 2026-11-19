#!/usr/bin/env bash
# scripts/sync_error_codes.sh
#
# Phone-first hardening M8 (AUTH-D27 contract) — keeps the app's copy of the
# backend identity error-code golden byte-identical to the source of truth.
#
#   source : ../beautica-backend/src/test/resources/contract/identity-error-codes.json
#            (written by the backend IdentityErrorCodeContractTest, B17)
#   copy   : tool/contract/identity-error-codes.json
#            (read by test/core/network/identity_error_codes_contract_test.dart,
#            which fails on any code the app does not map or explicitly ignore)
#
# Usage:
#   ./scripts/sync_error_codes.sh          copy the backend golden over the app copy
#   ./scripts/sync_error_codes.sh --check  exit 1 when the two differ (local pre-push)
#   ./scripts/sync_error_codes.sh --check --source <path|https-url>
#
# Source (first match wins): --source, then $BEAUTICA_ERROR_CODES_SOURCE, then
# the sibling checkout ($BEAUTICA_BACKEND_DIR, default ../beautica-backend).
# An https:// source is fetched with curl. CI (pr-validate.yml gates-fast)
# passes the backend `dev` raw URL; a 404 there (the backend change is not on
# `dev` yet — the backend PR merges first) WARNS and exits 0 in --check mode.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BACKEND_DIR="${BEAUTICA_BACKEND_DIR:-${PROJECT_ROOT}/../beautica-backend}"
SOURCE="${BEAUTICA_ERROR_CODES_SOURCE:-${BACKEND_DIR}/src/test/resources/contract/identity-error-codes.json}"
TARGET="${PROJECT_ROOT}/tool/contract/identity-error-codes.json"

usage() { echo "usage: $0 [--check] [--source <path|https-url>]" >&2; exit 2; }

mode="sync"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) mode="check"; shift ;;
    --source) [[ $# -ge 2 ]] || usage; SOURCE="$2"; shift 2 ;;
    *) usage ;;
  esac
done

warn() {
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then echo "::warning::$*"; else echo "WARNING: $*" >&2; fi
}

if [[ "${SOURCE}" == https://* ]]; then
  TMP="$(mktemp)"
  trap 'rm -f "${TMP}"' EXIT
  status="$(curl -sS -L --max-time 30 -o "${TMP}" -w '%{http_code}' "${SOURCE}")" || {
    echo "sync_error_codes: fetch failed: ${SOURCE}" >&2; exit 2; }
  if [[ "${status}" == "404" && "${mode}" == "check" ]]; then
    warn "sync_error_codes: backend golden not published yet (404) — skipped: ${SOURCE}"
    exit 0
  fi
  if [[ "${status}" != "200" ]]; then
    echo "sync_error_codes: HTTP ${status} fetching ${SOURCE}" >&2; exit 2
  fi
  SOURCE="${TMP}"
elif [[ "${SOURCE}" == *://* ]]; then
  echo "sync_error_codes: only https:// URLs are accepted: ${SOURCE}" >&2; exit 2
fi

if [[ ! -f "${SOURCE}" ]]; then
  echo "sync_error_codes: backend golden not found: ${SOURCE}" >&2
  echo "  (check out beautica-backend next to beautica-mobile, or set BEAUTICA_BACKEND_DIR / --source)" >&2
  exit 2
fi

if [[ "${mode}" == "check" ]]; then
  if cmp -s "${SOURCE}" "${TARGET}"; then
    echo "sync_error_codes: in sync"
    exit 0
  fi
  echo "sync_error_codes: DRIFT — ${TARGET#"${PROJECT_ROOT}/"} differs from the backend golden." >&2
  echo "  Run ./scripts/sync_error_codes.sh, then map every new code (or add it to" >&2
  echo "  kIgnoredIdentityCodes with a reason) in the contract test." >&2
  diff -u "${TARGET}" "${SOURCE}" >&2 || true
  exit 1
fi

mkdir -p "$(dirname "${TARGET}")"
cp "${SOURCE}" "${TARGET}"
echo "sync_error_codes: copied the backend golden -> ${TARGET#"${PROJECT_ROOT}/"}"

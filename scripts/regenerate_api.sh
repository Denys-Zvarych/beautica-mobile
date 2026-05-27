#!/usr/bin/env bash
# scripts/regenerate_api.sh
#
# Regenerate the OpenAPI Dart client from the committed spec snapshot.
#
# Normal usage (regenerates lib/api/ in-place):
#   ./scripts/regenerate_api.sh
#
# Check mode (CI — diffs generated output against lib/api/, exits non-zero on drift):
#   ./scripts/regenerate_api.sh --check
#
# To refresh the spec from the running local backend first, then regenerate:
#   dart run tool/openapi/fetch_spec.dart && ./scripts/regenerate_api.sh
#
# Approach: standalone openapi-generator-cli JAR via the openapi_generator_cli
# Dart pub package (dart pub global activate openapi_generator_cli).
# The pub package is NOT in pubspec.yaml dependencies — it is a global tool
# activated once per developer machine / CI runner.
# This approach avoids the irreconcilable analyzer version conflict between
# openapi_generator_annotations (<7.0.0) and riverpod_lint (^8.4.0).
#
# PINNED CLI VERSION: openapi_generator_cli 6.1.0 (wraps JAR 7.9.0).
# CI also activates this exact version — see .github/workflows/pr-validate.yml.
# Changing this version must be done in both places simultaneously.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${PROJECT_ROOT}"

CHECK_MODE=false
for arg in "$@"; do
  if [[ "$arg" == "--check" ]]; then
    CHECK_MODE=true
  fi
done

# ── Locate the openapi-generator CLI binary ────────────────────────────────────
# Prefer $HOME/.pub-cache/bin; fall back to PATH.
OPENAPI_GEN="${HOME}/.pub-cache/bin/openapi-generator"
if [[ ! -x "${OPENAPI_GEN}" ]]; then
  OPENAPI_GEN="$(command -v openapi-generator 2>/dev/null || true)"
fi
if [[ -z "${OPENAPI_GEN}" ]]; then
  echo "ERROR: openapi-generator not found."
  echo "  Install it with:"
  echo "    dart pub global activate openapi_generator_cli"
  echo "  Then re-run this script."
  exit 1
fi

SPEC_FILE="${PROJECT_ROOT}/tool/openapi/api-spec.json"
if [[ ! -f "${SPEC_FILE}" ]]; then
  echo "ERROR: Spec snapshot not found at tool/openapi/api-spec.json."
  echo "  Fetch it first: dart run tool/openapi/fetch_spec.dart"
  exit 1
fi

# ── Config file for the openapi-generator Dart wrapper ────────────────────────
# The Dart wrapper (openapi_generator_cli pub package) reads
# openapi_generator_config.json from the CWD.  We write it to a temp dir so
# we never pollute the project root.
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

# Point the cache dir at the project's .dart_tool so the JAR is shared across
# runs and not re-downloaded on every invocation.
JAR_CACHE_DIR="${PROJECT_ROOT}/.dart_tool/openapi_generator_cache"
mkdir -p "${JAR_CACHE_DIR}"

cat > "${WORK_DIR}/openapi_generator_config.json" <<EOF
{
  "openapiGeneratorVersion": "7.9.0",
  "additionalCommands": "",
  "downloadUrlOverride": null,
  "jarCacheDir": "${JAR_CACHE_DIR}",
  "customGeneratorUrls": []
}
EOF

# ── Run codegen ────────────────────────────────────────────────────────────────
run_codegen() {
  local output_dir="$1"
  # Run from WORK_DIR so the config file is in CWD.
  (
    cd "${WORK_DIR}"
    "${OPENAPI_GEN}" generate \
      -i "${SPEC_FILE}" \
      -g dart-dio \
      -o "${output_dir}" \
      --additional-properties=pubName=beautica_api,nullableFields=true,useEnumExtension=true \
      2>&1 | grep -v "^\[main\] INFO" || true
  )
}

# ── Post-codegen security patches ─────────────────────────────────────────────
# MEDIUM-1: Clear the cleartext localhost basePath so no code can accidentally
#           construct a BeauticaApi() targeting http://localhost:8080.
#           Individual API classes receive a Dio from dioProvider (which sets
#           the correct HTTPS base URL) — BeauticaApi.basePath is never used.
# MEDIUM-2: Add a @Deprecated annotation on BeauticaApi to prevent direct
#           instantiation that would bypass the app's auth interceptors and
#           cert-pinning. See lib/core/network/dio_provider.dart for usage.
apply_security_patches() {
  local api_dart="$1/lib/src/api.dart"
  if [[ ! -f "${api_dart}" ]]; then
    echo "WARNING: ${api_dart} not found — skipping security patches."
    return
  fi

  # MEDIUM-1: Replace any cleartext localhost basePath with empty string.
  # The generator emits whatever server URL is in the spec; match the whole
  # r'...' literal so future spec changes don't silently leave a bad URL.
  sed -i "s|static const String basePath = r'http://localhost[^']*';|static const String basePath = r'';|g" "${api_dart}"

  # MEDIUM-2: Add @Deprecated annotation above the BeauticaApi class declaration.
  # Guard with a check so repeated runs don't double-insert.
  if ! grep -q '@Deprecated("Never instantiate BeauticaApi' "${api_dart}"; then
    sed -i '/^class BeauticaApi {/i @Deprecated("Never instantiate BeauticaApi() directly. Use individual API class constructors with ref.watch(dioProvider) instead to ensure auth interceptors and cert-pinning apply. See lib\/core\/network\/dio_provider.dart.")\n// ignore: deprecated_member_use_from_same_package' "${api_dart}"
  fi

  echo "  Security patches applied to ${api_dart}"
}

# ── Build runner inside the generated package ──────────────────────────────────
run_build_runner() {
  local pkg_dir="$1"
  (
    cd "${pkg_dir}"
    dart pub get --no-example 2>&1 | tail -3
    dart run build_runner build --delete-conflicting-outputs 2>&1 | tail -3
    dart format lib/ test/ 2>&1 | tail -1
  )
}

if [[ "${CHECK_MODE}" == "true" ]]; then
  echo "=== regenerate_api.sh --check mode ==="
  echo "Generating into temp dir for diff …"

  TEMP_OUT="${WORK_DIR}/api_fresh"
  mkdir -p "${TEMP_OUT}"
  run_codegen "${TEMP_OUT}"
  apply_security_patches "${TEMP_OUT}"
  run_build_runner "${TEMP_OUT}"

  # Diff ignoring:
  #   pubspec.lock          — always changes with a fresh pub get in the temp dir
  #   .dart_tool            — build cache; not committed
  #   .gitattributes        — manually added linguist marker, not generated by codegen
  #   .openapi-generator/   — FILES manifest lists paths relative to output dir;
  #                           fresh temp-dir generation will always differ due to
  #                           test/ stubs the generator may or may not list. Only
  #                           the source files under lib/ matter for drift detection.
  #   test/                 — scaffolding stub tests generated by openapi-generator;
  #                           not part of the app's test suite and differ between
  #                           in-place and temp-dir runs. Excluded from drift check.
  DIFF_OUTPUT="$(diff -rq \
    --exclude="pubspec.lock" \
    --exclude=".dart_tool" \
    --exclude="*.g.dart.bak" \
    --exclude=".gitattributes" \
    --exclude=".openapi-generator" \
    --exclude=".openapi-generator-ignore" \
    "${PROJECT_ROOT}/lib/api" \
    "${TEMP_OUT}" 2>&1 || true)"

  # Strip diff lines that only mention the test/ scaffolding directory (generated
  # stub tests that differ between runs but carry no semantic content).
  DIFF_OUTPUT="$(echo "${DIFF_OUTPUT}" | grep -v "^Only in.*test/" || true)"

  if [[ -n "${DIFF_OUTPUT}" ]]; then
    echo "ERROR: lib/api/ is out of date with the committed spec."
    echo "  Run ./scripts/regenerate_api.sh and commit the result."
    echo ""
    echo "${DIFF_OUTPUT}" | head -40
    exit 1
  fi

  echo "OK: lib/api/ matches the committed spec snapshot."
  exit 0
fi

# ── Normal (in-place) regeneration ────────────────────────────────────────────
echo "=== regenerate_api.sh ==="
echo "Generating Dart client into lib/api/ …"

OUTPUT_DIR="${PROJECT_ROOT}/lib/api"
run_codegen "${OUTPUT_DIR}"
apply_security_patches "${OUTPUT_DIR}"
run_build_runner "${OUTPUT_DIR}"

echo ""
echo "Done. Review the diff, then:"
echo "  git add lib/api/ tool/openapi/api-spec.json"
echo "  git commit -m 'chore(api): regenerate Dart client from updated spec'"

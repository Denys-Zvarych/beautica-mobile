// M515 (AUTH-D14 / AUTH-54) — Firebase App Check build-time configuration.
//
// `APP_CHECK_DEBUG_TOKEN` is a uuid registered on the STAGING Firebase app
// only (never prod). It is passed with `--dart-define` for DEBUG builds only
// (`scripts/deploy_apk.sh` / `deploy_apk_device.sh` read it from the
// out-of-repo secrets dir). A debug token bypasses attestation, so
// `EnvGuard` kills a profile / release build that carries one.

/// Debug-provider token; empty when the define is absent.
const String kAppCheckDebugToken = String.fromEnvironment(
  'APP_CHECK_DEBUG_TOKEN',
);

/// Request header the backend's App Check guard reads (AUTH-54).
const String kAppCheckHeader = 'X-Firebase-AppCheck';

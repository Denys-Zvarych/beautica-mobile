/// Truly unauthenticated endpoint paths — used by [AuthInterceptor] to decide
/// whether to skip Bearer token injection.
///
/// IMPORTANT: Only add paths here when the backend endpoint is genuinely
/// public (no JWT required). Adding an authenticated endpoint to this set
/// causes [AuthInterceptor] to skip token injection → 401 → logout loop.
///
/// Paths are matched against [RequestOptions.path], which contains the raw
/// path string passed to Dio (e.g. `/api/v1/auth/login`). Since
/// [AppConfig.baseUrl] no longer carries the `/api/v1` prefix (fixed in
/// 2026-05-30 to prevent URL double-prefix), and all API clients use the full
/// `/api/v1/...` path, every entry here must include the `/api/v1/` prefix.
const Set<String> kAuthPaths = {
  '/api/v1/auth/login',
  '/api/v1/auth/logout',
  '/api/v1/auth/register',
  '/api/v1/auth/register/independent-master',
  '/api/v1/auth/refresh',
  // Phase 2.11 — OTP verification / resend are unauthenticated endpoints
  // (the user has no session yet when they reach these).
  '/api/v1/auth/verify-email',
  '/api/v1/auth/resend-verification',
  // Phase 2.13 — password-reset flow. Both endpoints are unauthenticated
  // (the user is not logged in when they reach the reset flow).
  '/api/v1/auth/forgot-password',
  '/api/v1/auth/reset-password',
  // Phase 2.20 — invite flow. Both endpoints are unauthenticated (the invitee
  // has no session; they authenticate by presenting the invite token).
  '/api/v1/auth/invite/validate',
  '/api/v1/auth/invite/accept',
};

/// Path prefixes for public endpoints whose URLs contain dynamic segments (UUIDs,
/// slugs) that prevent exact membership in [kAuthPaths].
///
/// [AuthInterceptor] checks `options.path.startsWith(prefix)` for each entry.
/// Order does not matter — first match wins.
///
/// IMPORTANT: Only add prefixes that are genuinely public (no JWT required).
/// Overly broad prefixes (e.g. `/api/v1/`) would suppress token injection for
/// every authenticated endpoint — breaking the entire auth flow.
const List<String> kPublicPathPrefixes = [
  // Phase 2.18 / security fix 2026-05-31 — location reference-data endpoints
  // are public reads. No Bearer token should be attached even when a logged-in
  // user triggers the locality picker (master edit, profile settings).
  //   GET /api/v1/locations/oblasts
  //   GET /api/v1/locations/oblasts/{oblastId}/cities
  //   GET /api/v1/locations/cities/{cityId}/districts
  '/api/v1/locations/',
  // NOTE (security/correctness fix 2026-06-25): `/api/v1/search/` was REMOVED
  // from this list. The discovery search endpoints are `permitAll` (a
  // logged-out user can still browse), BUT the backend auth-gates the
  // `street`/`buildingNo` address fields on the authenticated principal: an
  // anonymous caller gets null addresses, an authenticated one gets the full
  // address. Listing `/api/v1/search/` here forced [AuthInterceptor] to STRIP
  // the Bearer token from every search call, so the app was always anonymous
  // and full addresses were permanently dead. By NOT listing it, the
  // interceptor attaches the token WHEN PRESENT (logged-in → addresses) and
  // sends the request anonymously when absent (logged-out → still works, no
  // addresses). [AuthInterceptor] never blocks/force-refreshes a tokenless
  // request, so public browse remains functional. See `auth_interceptor.dart`.
];

/// Paths whose request bodies must be redacted in debug logs — used by
/// [LoggingInterceptor] to suppress PII / credentials from log output.
///
/// This is a superset of [kAuthPaths]:
///   • All unauthenticated auth paths (credentials, OTPs, reset tokens).
///   • Authenticated endpoints that carry precise location PII (street,
///     building number, location note) that must never appear in plain-text
///     debug logs even though they require a Bearer token.
///
/// [AuthInterceptor] does NOT reference this set — only [LoggingInterceptor]
/// does. Adding an entry here has no effect on token injection.
const Set<String> kPiiPaths = {
  // All unauthenticated auth paths are also PII paths.
  ...kAuthPaths,
  // Phase 4.2 — master/provider profile endpoints carry precise work address
  // (street, buildingNo, locationNote). Bodies must be redacted in logs even
  // though these endpoints require authentication.
  '/api/v1/independent-masters/me',
  // Phase 4.3 — profile edit endpoint carries phone number and other PII.
  // Must be a separate entry because the path differs from the locality endpoint.
  '/api/v1/independent-masters/me/profile',
  '/api/v1/masters/me',
  // Security fix 2026-06-25 — discovery search responses carry auth-gated
  // address fields (street, buildingNo) for authenticated callers. Redact the
  // response/request bodies in debug logs (the error-path logger in
  // logging_interceptor.dart logs `err.response?.data` otherwise). These are
  // exact paths (the search endpoints have no dynamic segments), so exact
  // membership in this set matches the LoggingInterceptor's `.contains` check.
  '/api/v1/search/masters',
  '/api/v1/search/salons',
};

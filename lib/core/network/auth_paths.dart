/// Truly unauthenticated endpoint paths — used by [AuthInterceptor] to decide
/// whether to skip Bearer token injection.
///
/// IMPORTANT: Only add paths here when the backend endpoint is genuinely
/// public (no JWT required). Adding an authenticated endpoint to this set
/// causes [AuthInterceptor] to skip token injection → 401 → logout loop.
///
/// Paths are matched against [RequestOptions.path], which contains only the
/// path segment (no host), as set by [BaseOptions.baseUrl].
const Set<String> kAuthPaths = {
  '/auth/login',
  '/auth/logout',
  '/auth/register',
  '/auth/register/independent-master',
  '/auth/refresh',
  // Phase 2.11 — OTP verification / resend are unauthenticated endpoints
  // (the user has no session yet when they reach these).
  '/auth/verify-email',
  '/auth/resend-verification',
  // Phase 2.13 — password-reset flow. Both endpoints are unauthenticated
  // (the user is not logged in when they reach the reset flow).
  '/auth/forgot-password',
  '/auth/reset-password',
  // Phase 2.20 — invite flow. Both endpoints are unauthenticated (the invitee
  // has no session; they authenticate by presenting the invite token).
  '/auth/invite/validate',
  '/auth/invite/accept',
};

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
  '/independent-masters/me',
  // Phase 4.3 — profile edit endpoint carries phone number and other PII.
  // Must be a separate entry because the path differs from the locality endpoint.
  '/independent-masters/me/profile',
  '/masters/me',
};

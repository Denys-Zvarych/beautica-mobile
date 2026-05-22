/// Shared set of auth endpoint paths used by interceptors.
///
/// Both [AuthInterceptor] and [LoggingInterceptor] reference this set
/// so additions only need to be made in one place.
///
/// Paths are matched against [RequestOptions.path], which contains only the
/// path segment (no host), as set by [BaseOptions.baseUrl].
const Set<String> kAuthPaths = {
  '/auth/login',
  '/auth/logout',
  '/auth/register',
  '/auth/register/independent-master',
  '/auth/refresh',
  // Phase 2.11 — OTP verification paths added pre-emptively so that
  // LoggingInterceptor never logs an OTP body in plaintext (SECURITY HIGH fix).
  // Paths may be renamed once the backend SpringDoc spec is finalised; the
  // redaction rule must be in place before the first real Dio call is made.
  '/auth/verify-email',
  '/auth/resend-verification',
  // Phase 2.13 — password-reset flow (backend Phase 11.2 / 11.3). Both are
  // UNAUTHENTICATED endpoints, so AuthInterceptor must NOT inject a bearer
  // token, and LoggingInterceptor must redact the request body (the email
  // and the single-use reset token are PII / sensitive).
  '/auth/forgot-password',
  '/auth/reset-password',
};

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
  // Phase 2.13 / Phase A3 — password-reset flow. All three endpoints are
  // unauthenticated (the user is not logged in when they reach the reset
  // flow). `/users/me/change-password/request-otp` (settings "change
  // password") is the AUTHENTICATED sibling entry point and must NOT be
  // listed here — it carries no request body (no PII to redact either).
  '/api/v1/auth/forgot-password',
  '/api/v1/auth/verify-password-reset-otp',
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
  // Phase 14.0 — CLIENT booking create endpoint. Exact match: the bare
  // `/api/v1/bookings` path (no dynamic segment) carries the free-text
  // `clientComment` field on POST. The `{bookingId}` sub-routes (list/detail/
  // cancel/reschedule) are covered by the prefix in [kPiiPathPrefixes] below.
  '/api/v1/bookings',
  // MO-1 — CLIENT appointment (multi-service visit) create endpoint. Exact
  // match: the bare `/api/v1/appointments` path (no dynamic segment) carries
  // the free-text `clientComment` field on POST. The `{id}` sub-routes
  // (detail/cancel/decline/not-complete/review) are covered by the prefix in
  // [kPiiPathPrefixes] below.
  '/api/v1/appointments',
  // Track 7.x Wave B — PROVIDER→CLIENT leave-feedback create endpoint. Exact
  // match: the bare `/api/v1/client-reviews` path (no dynamic segment)
  // carries the free-text `comment` field on POST — the provider's private
  // note about the client, never shown to the client, but still free text
  // that must not land in plain-text debug logs. Mirrors the `/api/v1/
  // bookings` and `/api/v1/appointments` exact-match precedents above.
  '/api/v1/client-reviews',
};

/// Path PREFIXES whose request/response bodies — and URL query strings — carry
/// PII or free-text user input and must be redacted in debug logs.
///
/// Unlike [kPiiPaths] (exact match), these cover routes with dynamic segments
/// (`{serviceDefId}`, `{masterId}`) or query parameters that exact membership
/// cannot match. [LoggingInterceptor] tests `basePath.startsWith(prefix)` via
/// [isPiiPath] (query string stripped first).
///
/// Security note (2026-06-28): the free-text discovery search `q` parameter can
/// carry a person's name, and service create/update bodies carry free-text
/// service names + pricing. Redacting these prevents PII from landing in logs.
const List<String> kPiiPathPrefixes = <String>[
  // Discovery search — the `q` query parameter is free-text (often a person /
  // business name). Covers /search/masters, /search/salons and any future
  // /search/* route.
  '/api/v1/search/',
  // Service create + bulk-create on the independent master's own catalogue —
  // free-text service names.
  '/api/v1/independent-masters/me/services',
  // Service update / delete / photo carry a dynamic {serviceDefId} segment and
  // free-text names, so they cannot live in the exact-match [kPiiPaths].
  '/api/v1/services/',
  // Service-type autocomplete echoes the user's typed free-text query.
  '/api/v1/service-types/suggest',
  // Phase 14.0 — CLIENT booking read/write endpoints. Covers
  // `GET /bookings/me` (paged list — enriched master name/address/price/
  // comments), `GET /bookings/{bookingId}` (same enrichment), and
  // `PATCH /bookings/{bookingId}/cancel` + `PATCH /bookings/{bookingId}
  // /reschedule` (free-text cancellation `comment`). The bare
  // `POST /bookings` create endpoint is covered separately by the exact-match
  // entry in [kPiiPaths] (no trailing dynamic segment to match a prefix).
  '/api/v1/bookings/',
  // MO-1 — CLIENT appointment (multi-service visit) read/write endpoints.
  // Covers `GET /appointments/{id}` (enriched master name/address/price +
  // notes), `PATCH /appointments/{id}/cancel` (free-text clientCancellationNote),
  // `PATCH /appointments/{id}/reschedule` (dual-actor, no note payload),
  // `PATCH /appointments/{id}/decline` + `/not-complete` (providerComment) and
  // `POST /appointments/{id}/review` (free-text review comment). The bare
  // `POST /appointments` create endpoint is covered separately by the
  // exact-match entry in [kPiiPaths] (no trailing dynamic segment to match a
  // prefix).
  '/api/v1/appointments/',
];

/// Path SEGMENTS (substring match) for dynamic routes whose `{masterId}` /
/// `{scheduleId}` segments sit BEFORE the meaningful tail, so neither exact
/// membership nor a fixed prefix can match them.
///
/// Covers e.g. `/api/v1/masters/{masterId}/working-hours` and
/// `/api/v1/masters/{masterId}/weekly-schedules/{scheduleId}` — the dynamic
/// working-hours / schedule write endpoints flagged in the 2026-06-28 audit.
const List<String> kPiiPathSegments = <String>[
  '/working-hours',
  '/weekly-schedules',
];

/// Query-parameter keys whose VALUES must be masked in debug logs on ANY route
/// (defence-in-depth over [isPiiPath]). Even if a path is not classified as
/// PII-bearing, a token / OTP / free-text term riding in one of these params
/// must never reach the log. Matched case-insensitively against the param name.
const Set<String> kSensitiveQueryKeys = <String>{
  'q', // discovery free-text — may be a typed person / business name
  'query',
  'search',
  'token', // password-reset / verify / invite links carry a token query param
  'access_token',
  'refresh_token',
  'code', // OTP / verification codes
  'otp',
  'password',
  'secret',
  'email',
  'phone',
};

/// Strips any `?query` from [path], returning just the route portion.
String _stripQuery(String path) {
  final int q = path.indexOf('?');
  return q == -1 ? path : path.substring(0, q);
}

/// Returns `true` when [path] (with any query string ignored) is a PII-bearing
/// route whose body and query string must be redacted in debug logs.
///
/// Matches in three ways, in order: exact membership in [kPiiPaths], a prefix
/// in [kPiiPathPrefixes], or a segment substring in [kPiiPathSegments]. This is
/// a strict superset of the old `kPiiPaths.contains(path)` check — it also
/// covers dynamic ({uuid}) routes and paths that carry a query string.
bool isPiiPath(String path) {
  final String base = _stripQuery(path);
  if (kPiiPaths.contains(base)) return true;
  for (final String prefix in kPiiPathPrefixes) {
    if (base.startsWith(prefix)) return true;
  }
  for (final String segment in kPiiPathSegments) {
    if (base.contains(segment)) return true;
  }
  return false;
}

/// Returns a log-safe rendering of [path].
///
/// Two layers of redaction:
///   • For PII routes ([isPiiPath]) the entire query string is masked as
///     `?[REDACTED]` — even the param NAMES can be revealing there.
///   • For every other route the value of any [kSensitiveQueryKeys] param is
///     masked as `key=***`, while harmless params (page / size / sort) stay
///     visible for debugging. This closes the gap where a token / OTP / typed
///     name rides a query param on a path not classified as PII.
String redactLogPath(String path) {
  final int q = path.indexOf('?');
  if (q == -1) return path;
  final String base = path.substring(0, q);
  if (isPiiPath(base)) return '$base?[REDACTED]';

  final String query = path.substring(q + 1);
  if (query.isEmpty) return path;
  final Iterable<String> pairs = query.split('&').map((String pair) {
    final int eq = pair.indexOf('=');
    if (eq == -1) return pair;
    final String key = pair.substring(0, eq);
    if (kSensitiveQueryKeys.contains(key.toLowerCase())) {
      return '$key=***';
    }
    return pair;
  });
  return '$base?${pairs.join('&')}';
}

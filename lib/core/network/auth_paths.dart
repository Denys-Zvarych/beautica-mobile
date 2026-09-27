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
  // Mandatory companion to the mobile-security HIGH fix 2026-09-01 —
  // [HttpMasterRepository.updateMyProfile] now PATCHes this endpoint for
  // SALON_MASTER (mirrors the sibling entry above for the
  // INDEPENDENT_MASTER endpoint one line up). Same PII shape as
  // `/independent-masters/me/profile`: phone number, bio, Instagram handle.
  // Must be a separate exact entry — `/api/v1/masters/me` above does NOT
  // cover this path (kPiiPaths is exact-match only, no prefix semantics).
  '/api/v1/masters/me/profile',
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
  // (detail/cancel/decline/not-complete) are covered by the prefix in
  // [kPiiPathPrefixes] below.
  '/api/v1/appointments',
  // Track 7.x Wave B — PROVIDER→CLIENT leave-feedback create endpoint. Exact
  // match: the bare `/api/v1/client-reviews` path (no dynamic segment)
  // carries the free-text `comment` field on POST — the provider's private
  // note about the client, never shown to the client, but still free text
  // that must not land in plain-text debug logs. Mirrors the `/api/v1/
  // bookings` and `/api/v1/appointments` exact-match precedents above.
  '/api/v1/client-reviews',
  // Phase 13.x — CLIENT wish-list toggle endpoint. Exact match: the bare
  // `/api/v1/favorites` path (no dynamic segment) is hit on POST/DELETE and
  // echoes back the saved service/master identifiers. The `/favorites/services`
  // read route is covered by the prefix in [kPiiPathPrefixes] below.
  '/api/v1/favorites',
  // mobile-security MEDIUM follow-up (2026-08-28) — Phase 21.1 SALON_OWNER
  // hub endpoint. Exact match: the bare `/api/v1/salons/mine` path (no
  // dynamic segment) returns `SalonResponse`, which carries `phone` and
  // `ownerId` — same class of gap already closed for `/clients/me` and
  // `/favorites/services` above. Without this entry, `LoggingInterceptor
  // .onError` logs `err.response?.data` unredacted to `dart:developer` on
  // any 4xx/5xx from this endpoint in debug builds.
  '/api/v1/salons/mine',
  // NOTE (mobile-security LOW, 2026-09-01): `/api/v1/users/me` was MOVED from
  // this exact-match set to [kPiiPathPrefixes] below. Its original entry
  // justified staying exact with "no other `/users/me/...` sub-route exists
  // today" — that claim was FALSE when it was written: `GET
  // /api/v1/users/me/rating` is live (`user_controller_api.dart`, reached via
  // `myRatingProvider`) and the exact entry did not cover it. The whole
  // self-scoped family is now covered by one prefix, mirroring the
  // `/api/v1/clients/me` precedent. Do NOT re-add an exact entry here.
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
  // `PATCH /appointments/{id}/reschedule` (dual-actor, no note payload) and
  // `PATCH /appointments/{id}/decline` (providerComment). The bare
  // `POST /appointments` create endpoint is covered separately by the
  // exact-match entry in [kPiiPaths] (no trailing dynamic segment to match a
  // prefix).
  '/api/v1/appointments/',
  // Phase 13.8 — CLIENT self endpoints. `GET /clients/me/passport` returns
  // BEHAVIOURAL PII (favourite procedures, favourite districts, spend/budget
  // band); the sibling `/clients/me` routes carry the client's own profile PII.
  // Without this entry `LoggingInterceptor.onError` logs `err.response?.data`
  // verbatim (debug builds), so a 4xx/5xx on the passport route would spill the
  // client's taste + spend profile into the log. Deliberately the WIDER
  // `/clients/me` prefix rather than `.../passport`: every self-scoped client
  // route under it is PII-bearing, and a prefix (not an exact [kPiiPaths]
  // entry) is what covers the `/passport` tail and any future sub-route.
  // Same rationale as `/api/v1/search/masters` above.
  '/api/v1/clients/me',
  // Finding S1 (mobile-security MEDIUM, 2026-08-31) PROMOTED to a prefix
  // (mobile-security LOW, 2026-09-01) — the shared self-profile family.
  //
  // The bare `/api/v1/users/me` path is BOTH the `GET` every role's own-profile
  // screen reads and the `PATCH` the edit forms write, and its
  // `UserProfileResponse` / `UpdateUserProfileRequest` bodies carry `email`,
  // `phoneNumber`, `firstName`/`lastName`, `bio`, `instagram` and
  // `professionalTitle`. It matched NOTHING in [kPiiPaths], this list or
  // [kPiiPathSegments] before Finding S1, so `LoggingInterceptor.onRequest`
  // wrote the whole PATCH body — and `onError` the whole error response — to
  // `dart:developer.log()` verbatim in debug builds.
  //
  // A PREFIX, not the exact [kPiiPaths] entry S1 originally added. That entry
  // justified staying exact with "no other `/users/me/...` sub-route exists
  // today", which was already FALSE: `GET /api/v1/users/me/rating` is live
  // (`api/lib/src/api/user_controller_api.dart`, `rating_repository.dart`,
  // reached via `myRatingProvider`) and an exact entry cannot match it. Its
  // `UserRatingResponse` is aggregate-only (`avgRating`, `reviewCount`,
  // `ratingDistribution`) so nothing leaked — but the exact entry was resting
  // on a false premise, and the next sub-route the backend adds would inherit
  // the same silent gap. Deliberately the WIDER `/users/me` prefix, exactly
  // like `/api/v1/clients/me` directly above: every self-scoped user route
  // under it is PII-bearing or PII-adjacent, the authenticated sibling
  // `/users/me/change-password/request-otp` (see the [kAuthPaths] header)
  // carries no body so redacting it costs nothing, and a prefix covers every
  // future tail without another ledger move.
  '/api/v1/users/me',
  // Phase 13.x — CLIENT wish-list read endpoint. `GET /favorites/services`
  // returns the client's saved service names, master names and prices —
  // booking-intent PII. Without this entry `LoggingInterceptor.onError` logs
  // `err.response?.data` verbatim on a 4xx/5xx, spilling the wish list. A
  // prefix (not the exact-match [kPiiPaths] entry above) so it also covers
  // `/favorites` itself and any future sub-path. Same class of gap already
  // fixed for `/api/v1/clients/me` above.
  '/api/v1/favorites',
  // Finding 2 (mobile-security MEDIUM, 2026-08-28) — Phase 21.10
  // SalonAddressEditScreen's `PATCH /api/v1/salons/{salonId}` carries
  // name/description/street/buildingNo/locationNote/phone/instagramUrl.
  // The dynamic {salonId} segment sits AFTER the meaningful `/salons/` tail
  // (unlike the `/masters/{masterId}/bookings` segment case below), so a
  // prefix match works — same shape as the `/api/v1/bookings/` and
  // `/api/v1/appointments/` pairs above. Deliberately the WIDER `/salons/`
  // prefix (not a `{salonId}`-specific pattern this simple prefix scheme
  // cannot express) — every owner/admin-scoped sub-route under it
  // (services, masters, invite, admins) is PII-adjacent, and this mirrors
  // the exact-match `/api/v1/salons/mine` entry already in [kPiiPaths]
  // above (kept, not superseded — that entry stays for the bare `/mine`
  // path; this prefix additionally covers every `/salons/{salonId}...`
  // route the exact-match set cannot). Without this entry
  // `LoggingInterceptor.onRequest` wrote the full PATCH body unredacted via
  // `dart:developer.log()` in debug builds.
  '/api/v1/salons/',
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
  // Per-date schedule overrides — `PUT /api/v1/masters/{masterId}/overrides/
  // {date}` (working intervals + the display-only window, same class of data as
  // /weekly-schedules) and `POST /api/v1/masters/{masterId}/overrides/conflicts`
  // (2026-07-26 booking-conflict preview, whose RESPONSE carries client display
  // names and service names). Both sit behind a dynamic {masterId}, so neither
  // exact membership nor a fixed prefix matches. Without this entry
  // `LoggingInterceptor.onError` logs `err.response?.data` verbatim, so a 4xx on
  // either route would spill a conflict payload with client identifiers.
  '/overrides',
  // Phase 246 (2026-08-19 security fix) — INDEPENDENT_MASTER walk-in booking
  // create endpoint: `POST /api/v1/masters/{masterId}/bookings`. The dynamic
  // {masterId} segment sits BEFORE the meaningful `/bookings` tail, same shape
  // as `/working-hours` above, so neither exact membership in [kPiiPaths] nor a
  // fixed prefix in [kPiiPathPrefixes] can match it (the existing
  // `/api/v1/bookings/` prefix only covers the CLIENT-side
  // `/api/v1/bookings/...` routes, a different path family). The request body
  // carries a walk-in guest's `name`, `surname` and E.164 `phone` — third-party
  // PII from a person who never installed the app — so without this entry both
  // the success-path and `onError` loggers in logging_interceptor.dart would
  // write it to `dart:developer.log()` verbatim on debug builds.
  '/bookings',
  // Phase 21.4 (mobile-security MEDIUM) — SALON_OWNER/SALON_ADMIN staff
  // invite endpoint: `POST /api/v1/salons/{salonId}/invite`. The dynamic
  // {salonId} segment sits BEFORE the meaningful `/invite` tail, same shape
  // as `/working-hours`/`/bookings` above, so neither exact membership in
  // [kPiiPaths] nor a fixed prefix in [kPiiPathPrefixes] can match it (the
  // existing `/api/v1/salons/` prefix covers PATCH /salons/{salonId} but a
  // segment match is still needed here since this route has its OWN
  // request-body PII beyond what the prefix documents). The request body
  // carries the invitee's raw email address, so without this entry both the
  // success-path and `onError` loggers in logging_interceptor.dart would
  // write it to `dart:developer.log()` verbatim on debug builds.
  '/invite',
  // Finding S2 (mobile-security LOW, 2026-08-31) — the PUBLIC per-master
  // catalogue read `GET /api/v1/masters/{masterId}/services`
  // (`ServiceRepository.getMasterServices`, `service_repository.dart:327`),
  // hit by the public master profile, the salon staff-member profile and the
  // owner's own profile. The dynamic {masterId} segment sits BEFORE the
  // meaningful `/services` tail, exactly like `/bookings` above, so neither
  // exact membership in [kPiiPaths] nor a fixed prefix in [kPiiPathPrefixes]
  // can match it — the `/api/v1/services/` prefix is a DIFFERENT path family
  // (the master's own `{serviceDefId}` write routes) and does not cover this
  // one.
  //
  // The payload is public catalogue data (service names, durations, prices),
  // so the exposure is low — this closes the path family for completeness and
  // for the query string, which `redactLogPath` masks wholesale on a PII
  // route. The substring is deliberately the bare `/services` tail: it also
  // subsumes `/api/v1/independent-masters/me/services` and
  // `/api/v1/salons/{salonId}/services` (both already covered by their own
  // prefix entries, so this adds no new breadth there), and it does NOT match
  // `/api/v1/service-types/...`.
  '/services',
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

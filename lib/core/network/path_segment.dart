import 'dart:developer';

import 'package:flutter/foundation.dart';

import '../errors/failures.dart';

/// Encodes [value] as ONE safe path segment, or throws.
///
/// PROMOTED (Phase 21.12) out of `service_repository.dart`, where it lived as
/// the private `_pathSegment`. It was already the single encoder for that
/// file's three raw paths; `booking_repository.dart`'s
/// `/api/v1/bookings/salon/$salonId` was interpolating a raw segment with no
/// hardening at all, and `salon_repository.dart` / `master_repository.dart`
/// each reached for a bare [Uri.encodeComponent]. Rather than add a fourth
/// hand-rolled variant, the strictest one moved here.
///
/// THAT PROMOTION DID NOT ACTUALLY REACH EVERY CALL SITE, and an earlier
/// revision of this paragraph claimed it did ("so a fix reaches every raw path
/// in the app at once"). It did not: four sites kept their bare
/// [Uri.encodeComponent] — `salon_repository.dart`'s `getSalonMasters` /
/// `getSalonReviews` and `master_repository.dart`'s `getMasterReviewSummary` /
/// `getMasterReviews` — and `location_repository.dart`'s two cascade reads had
/// no encoding at all. All six were swapped on 2026-09-17, and the claim is
/// now ENFORCED rather than asserted:
/// `scripts/forbid_unencoded_path_interpolation.sh` fails the build on any
/// hand-built `/api/v1/…` literal that interpolates an id the file never
/// routed through [encodePathSegment]. A promotion comment is not a gate.
///
/// The single encoder for every HAND-BUILT path in the app — an id carrying a
/// path-significant character would otherwise retarget the request on an
/// authenticated Dio that holds the bearer token.
///
/// **The generated client does NOT do this for you.** An earlier revision of
/// this doc said hand-built paths "bypass the generated client's automatic
/// encoding"; there is no such encoding. Measured, not assumed:
/// `api/lib/src/api/salon_controller_api.dart:599-603` builds its path with
/// `.replaceAll('{salonId}', encodeQueryParameter(...).toString())`, and
/// `api/lib/src/api_util.dart:44-46`'s `encodeQueryParameter` returns a
/// `String` input **verbatim** — no escaping, no dot-segment rejection. Every
/// generated path param is therefore interpolated raw, exactly like the
/// hand-built paths this helper guards.
///
/// What makes the generated call sites safe today is NOT encoding but the
/// PROVENANCE of the ids that reach them: each is a server-issued UUID that an
/// equality gate (ownership/`canManage` checks, roster membership, a route
/// guard) has already matched against a value the server returned. Nothing
/// user-typed reaches a generated path param. That is a property of the call
/// sites, not of the client — so a NEW generated path param fed from freer
/// input is not automatically safe, and must route its id through
/// [encodePathSegment] (or an equivalent gate) before the call. Do not read
/// "the generated client handles it" anywhere in this codebase; it does not.
///
/// The PROVENANCE half of that invariant is not mechanically enforceable, and
/// the guard above deliberately does not pretend to enforce it — it checks
/// hand-built literals only. A new generated path param fed from freer input
/// stays a code-review obligation; a green guard run says nothing about it.
///
/// **Encoding alone is NOT sufficient, which is why this also rejects.**
/// [Uri.encodeComponent] does not escape `.`, so a bare `..` or `.` survives
/// it verbatim. Dio then issues the request as
/// `Uri.parse(url).normalizePath()` (`dio-5.9.2/lib/src/options.dart:642`),
/// and `normalizePath` REMOVES dot-segments per RFC 3986 §5.2.4. Measured,
/// not assumed: with `masterId` and `serviceDefId` both `'..'`,
/// `DELETE /api/v1/salons/S/masters/../services/..` collapses to
/// `DELETE /api/v1/salons/S/` — one trailing slash away from the
/// delete-the-whole-salon endpoint (`SalonController.java:208`). A single
/// `'.'` deletes its own segment and shifts every later one left.
///
/// REJECT rather than sanitise: these ids are server-issued UUIDs, so a
/// dot-segment here is a PROGRAMMING error, not user input to be repaired.
/// Silently rewriting a caller's id would send a well-formed request about the
/// wrong resource, which is strictly worse than not sending one.
///
/// Composite values that merely CONTAIN dot-segments (`a/../../b`) are safe
/// and pass: the separators encode to `%2F`, and `normalizePath` splits on
/// literal `/` only. Nor can encoding manufacture a dot-segment —
/// [Uri.encodeComponent] emits `%2E` for no input (it never escapes `.`, and
/// any literal `%` becomes `%25`), so Dart's unreserved-character
/// normalization has nothing to decode back into `.`.
///
/// Throws [UnknownFailure] wrapping an [ArgumentError]: unreachable in
/// production (the ids are server-issued UUIDs), non-transient in
/// `failureRetryPolicy`, and a [Failure] rather than a raw [ArgumentError] so
/// a repository never leaks an unmapped error type past its boundary.
///
/// [name] is the caller's parameter name (for the error and the debug log);
/// [logTag] is the calling repository's own `dart:developer` log name, so the
/// diagnostic still lands under the feature that issued the request.
String encodePathSegment(String value, String name, {required String logTag}) {
  final encoded = Uri.encodeComponent(value);
  // `encoded.contains('/')` cannot fire for encodeComponent (it escapes `/`
  // to `%2F`); it is kept so a future swap onto a laxer encoder — encodeFull
  // does NOT escape `/` — trips here instead of shipping a path split.
  if (encoded.isEmpty ||
      encoded == '.' ||
      encoded == '..' ||
      encoded.contains('/')) {
    if (kDebugMode) {
      log(
        'encodePathSegment: refusing to build a path with $name="$value" — it '
        'is empty or a dot-segment that Dio\'s normalizePath() would collapse',
        name: logTag,
        level: 1000,
      );
    }
    throw UnknownFailure(
      cause: ArgumentError.value(
        value,
        name,
        'must be a single non-empty path segment (not "." or "..")',
      ),
    );
  }
  return encoded;
}

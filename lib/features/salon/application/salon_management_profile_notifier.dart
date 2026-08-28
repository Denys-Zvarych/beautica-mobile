// Phase 21.2 — Owner/admin salon profile notifier.
//
// Extends the read pattern of `public_salon_profile_notifier.dart` (loads
// the salon detail + its masters rail in parallel, same TTL-cached family
// shape) with the owner/admin write paths this screen needs:
//   • [save] — a partial `PATCH /salons/{salonId}`, built from a DIRTY-FIELD
//     diff against the currently-loaded [Salon] rather than always sending
//     every editable field. This is the Phase 21.2 gap workaround: `GET
//     /salons/{salonId}` never returns `phone` (see [Salon.phone]'s doc), so
//     the edit form always seeds that field empty. If Save always sent
//     `phone` verbatim, an owner who saves WITHOUT touching the phone field
//     would silently wipe a real phone number already on file (empty string
//     PATCHed over it). Diffing against the loaded snapshot means an
//     untouched field is simply OMITTED from the request body — the backend
//     never sees it, so it can't be cleared by accident — while a field the
//     viewer DID type into is always included, however it compares to the
//     (possibly-unknown) baseline.
//   • [deleteSalon] — `DELETE /salons/{salonId}` (soft-deactivate
//     server-side; owner-only, enforced by the backend AND the router's
//     client-side role gate — this method itself has no role check of its
//     own, matching every other repository call in this codebase).
//
// mobile-perf MEDIUM follow-up (2026-08-28) — `mySalonsProvider`
// (`my_salons_notifier.dart`) was promoted to `@Riverpod(keepAlive: true)`
// so the router's `salonManageGuard` reads an already-resolved value instead
// of re-fetching on every navigation. Nothing then invalidated that cached
// list on write, so an edited/deleted salon's name, locality, or «Основний»
// badge went stale on the «Мої салони» hub for the rest of the session —
// a regression introduced by the keepAlive promotion, not a pre-existing
// gap. Both [save] and [deleteSalon] now invalidate `mySalonsProvider` on
// their success branch so the hub refetches the next time it is watched.
//
// `UpdateSalonRequest.street`/`.buildingNo` are non-nullable/required even on
// this partial-update DTO (see `tool/openapi/api-spec.json`'s
// `UpdateSalonRequest` schema — `"required": ["buildingNo", "street"]`), so
// [save] always threads the CURRENT loaded values through for those two,
// regardless of whether the viewer edited them (this phase does not expose
// address editing at all — see the screen's own doc for why).

// Prefixed: `dart:async`'s non-generic [async.AsyncError] (carried by the
// records `.wait` [async.ParallelWaitError]) must NOT be confused with
// Riverpod's generic `AsyncError<T>`, which `riverpod_annotation` brings
// unprefixed into scope. Mirrors `public_salon_profile_notifier.dart`'s exact
// unwrap — see that file's own header note on the mis-resolution risk.
import 'dart:async' as async;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_api/beautica_api.dart' show UpdateSalonRequest;
import 'package:beautica_mobile/core/errors/failures.dart';

import '../../auth/presentation/auth_notifier.dart';
import '../data/salon_repository.dart';
import '../domain/salon.dart';
import '../domain/salon_master_summary.dart';
import 'my_salons_notifier.dart';

part 'salon_management_profile_notifier.g.dart';

/// The data the owner/admin salon management screen renders: the salon
/// detail (editable) paired with its masters rail (the «Персонал» tab).
typedef SalonManagementProfileData = (
  Salon salon,
  List<SalonMasterSummary> masters,
);

/// Loads + mutates the owner/admin salon profile for [salonId].
///
/// Generated provider name: `salonManagementProfileProvider` (a family — call
/// it with the target salon id, e.g. `salonManagementProfileProvider(salonId)`).
@riverpod
class SalonManagementProfile extends _$SalonManagementProfile {
  @override
  Future<SalonManagementProfileData> build(String salonId) async {
    // Auth-boundary eviction, mirrors `publicSalonProfileProvider` — this
    // keepAlive-free family is torn down on logout / session change so a
    // stale owner/admin salon never survives into the next signed-in user.
    ref.watch(authProvider);

    final SalonRepository repo = ref.read(salonRepositoryProvider);
    // Load both in parallel — neither read depends on the other. Unwraps
    // [async.ParallelWaitError] instead of letting it leak to the screen as
    // a generic wrapper: `SalonManagementProfileScreen`'s error branch only
    // renders the correct localized message (network/server/unauthorized)
    // when `e is Failure` — a bare `ParallelWaitError` would always fall
    // through to `UnknownFailure`, silently discarding which real endpoint
    // failed and why. Mirrors `public_salon_profile_notifier.dart`'s
    // identical unwrap (this notifier's own header doc names that file as
    // the read pattern this build() extends).
    try {
      final (Salon salon, List<SalonMasterSummary> masters) = await (
        repo.getSalonById(salonId),
        repo.getSalonMasters(salonId),
      ).wait;
      return (salon, masters);
    } on async.ParallelWaitError<
      (Salon?, List<SalonMasterSummary>?),
      (async.AsyncError?, async.AsyncError?)
    > catch (error, stackTrace) {
      final (async.AsyncError? salonError, async.AsyncError? mastersError) =
          error.errors;
      final async.AsyncError? firstError = salonError ?? mastersError;
      if (firstError != null) {
        Error.throwWithStackTrace(firstError.error, firstError.stackTrace);
      }
      // Defensive: no underlying error to unwrap (should never happen) —
      // rethrow the wrapper as-is so the failure is never silently swallowed.
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Saves the edited «Редагувати профіль» fields (name, description, phone,
  /// Instagram) via a partial `PATCH /salons/{salonId}`.
  ///
  /// [name]/[description]/[phone]/[instagramUrl] are the CURRENT text of the
  /// screen's editable fields (trimmed by the caller or here). Each is
  /// included in the request only when it differs from the loaded [Salon]'s
  /// value — see this file's header doc for why that matters for [phone]
  /// specifically. `street`/`buildingNo` are always threaded through
  /// unmodified (backend-required on every PATCH).
  ///
  /// Returns `null` on success (state is updated with the server's response,
  /// merged with the previous snapshot's read-only aggregates — see
  /// [SalonMapper.fromUpdateDto]'s doc) or the [Failure] on error, leaving
  /// state untouched so the screen can offer a retry.
  Future<Failure?> save({
    required String name,
    required String description,
    required String phone,
    required String instagramUrl,
  }) async {
    final SalonManagementProfileData? data = state.value;
    if (data == null) return null;
    final (Salon current, List<SalonMasterSummary> masters) = data;

    final String trimmedName = name.trim();
    final String trimmedDescription = description.trim();
    final String trimmedPhone = phone.trim();
    final String trimmedInstagram = instagramUrl.trim();

    final UpdateSalonRequest request = UpdateSalonRequest(
      (b) => b
        ..street = current.street ?? ''
        ..buildingNo = current.buildingNo ?? ''
        ..name = trimmedName != current.name ? trimmedName : null
        ..description = trimmedDescription != (current.description ?? '')
            ? trimmedDescription
            : null
        // Phase 21.2 gap workaround — see file header doc. `current.phone` is
        // always null unless a previous save already resolved it, so an
        // untouched field (still empty) never diffs true here.
        ..phone = trimmedPhone != (current.phone ?? '') ? trimmedPhone : null
        ..instagramUrl = trimmedInstagram != (current.instagramUrl ?? '')
            ? trimmedInstagram
            : null,
    );

    try {
      final Salon patched = await ref
          .read(salonRepositoryProvider)
          .updateSalon(salonId, request);
      // SalonResponse (the PATCH response) does not carry coverImageUrl /
      // avgRating / reviewCount — preserve those from the last known-good
      // read rather than letting them reset to null/0. See
      // SalonMapper.fromUpdateDto's doc.
      final Salon merged = patched.copyWith(
        coverImageUrl: current.coverImageUrl,
        avgRating: current.avgRating,
        reviewCount: current.reviewCount,
      );
      state = AsyncData((merged, masters));
      // cycle-safe: mySalonsProvider (MySalons.build()) only watches
      // authProvider — it never watches salonManagementProfileProvider, so
      // there is no back-edge here to close into a cycle. See this file's
      // header doc (mobile-perf MEDIUM follow-up, 2026-08-28) for why this
      // invalidation exists: keeps the «Мої салони» hub's cached list from
      // going stale after an edit.
      ref.invalidate(mySalonsProvider);
      return null;
    } on Failure catch (f) {
      return f;
    }
  }

  /// Deactivates (soft-deletes) this salon via `DELETE /salons/{salonId}`.
  ///
  /// Owner-only — enforced server-side and by the router's client-side role
  /// gate; this method issues the call unconditionally, matching every other
  /// repository call in this codebase (never re-implement authorization on
  /// the client). Returns `null` on success or the [Failure] on error.
  Future<Failure?> deleteSalon() async {
    try {
      await ref.read(salonRepositoryProvider).deleteSalon(salonId);
      // cycle-safe: mySalonsProvider (MySalons.build()) only watches
      // authProvider — it never watches salonManagementProfileProvider, so
      // there is no back-edge here to close into a cycle. See this file's
      // header doc (mobile-perf MEDIUM follow-up, 2026-08-28) for why this
      // invalidation exists: keeps the «Мої салони» hub's cached list from
      // going stale after a delete.
      ref.invalidate(mySalonsProvider);
      return null;
    } on Failure catch (f) {
      return f;
    }
  }
}

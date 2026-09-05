// Phase 21.2 — Owner/admin salon profile notifier.
//
// Extends the read pattern of `public_salon_profile_notifier.dart` (loads
// the salon detail + its masters rail in parallel, same TTL-cached family
// shape) with the owner/admin write paths this screen needs:
//   • [save] — a partial `PATCH /salons/{salonId}`, built from a DIRTY-FIELD
//     diff against the currently-loaded [Salon] rather than always sending
//     every editable field. HISTORY: this diff started life as the Phase 21.2
//     gap workaround — `GET /salons/{salonId}` returned no `phone`, so the
//     edit form always seeded that field EMPTY and an unconditional send
//     would have wiped a real number the client was never told about. That
//     gap is CLOSED (`PublicSalonResponse.phone` now ships; see
//     [Salon.phone]'s doc), so `current.phone` is a real, seeded baseline and
//     the edit forms pre-populate. The diff STAYS, and is kept correct rather
//     than unwound: it is now a plain partial-update contract — an untouched
//     field is OMITTED from the request body, a field the viewer edited is
//     always included (clearing one sends `''`, which the backend persists
//     verbatim — the `""`-vs-null wire contract [Salon.phone] documents).
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
// gap. [save] and [saveAddress] invalidate `mySalonsProvider` on their
// success branch so the hub refetches the next time it is watched;
// [deleteSalon] does NOT — that invalidation lives in the CALLER
// (`runDeleteSalonFlow`, `presentation/delete_salon_flow.dart`) instead, for
// the reasons [deleteSalon]'s own doc below explains.
//
// mobile-security MEDIUM / mobile-perf LOW follow-up (2026-09-03) — [save]
// and [saveAddress] used to gate `ref.invalidate(mySalonsProvider)` behind
// the SAME `ref.mounted` check that guards their post-await `state` write.
// `ref.mounted` DOES go false in one real case: `SalonProfileEditScreen`
// (or its address counterpart) is popped mid-await, dropping the only
// watcher, and `save()`/`saveAddress()`'s own `ref.keepAlive()` link — the
// last thing keeping this element alive — is then wiped by an unrelated
// `authProvider` identity change invalidating this element while nothing
// is watching it (element genuinely disposed; see [deleteSalon]'s doc for
// the identical mechanism). CORRECTION (investigated 2026-09-03, see
// `salon_management_profile_notifier_test.dart`'s "compound
// authProvider-mid-await race" group): `ref.mounted` can NOT go false
// while the calling screen is still mounted and watching — Riverpod only
// REBUILDS an element with an active watcher on invalidation, it never
// disposes one (`isActive` stays true for as long as a real, unpaused
// `ref.watch` is attached). A prior version of this doc claimed exactly
// that impossible case; do not re-derive it. Whichever case fires, the
// PATCH already succeeded server-side by the time `ref.mounted` matters,
// so skipping the invalidate would still leave the «Мої салони» hub
// stale for the rest of the session. Both methods therefore capture
// `ref.container` (a plain stored reference to the app's root
// [ProviderContainer] — reading it, unlike `ref.invalidate`/`ref.read`,
// does NOT assert `ref.mounted`) BEFORE the await, while this element is
// definitely alive, and invalidate through THAT handle, unconditionally, the
// moment the `PATCH` succeeds — independent of whether this element is still
// mounted by the time the await resolves. The `state` write itself stays
// behind `ref.mounted`, since unlike the container-backed invalidate it
// genuinely needs this element's own `ref` — and the guard, together with
// the `ref.keepAlive()` call below, is REQUIRED: it is the only thing
// standing between the popped-screen race above and an
// `UnmountedRefException` crash. Do not remove either on the belief that
// the mounted-while-watching case (disproven above) was their only
// justification.
//
// `UpdateSalonRequest.street`/`.buildingNo` are non-nullable/required even on
// this partial-update DTO (see `tool/openapi/api-spec.json`'s
// `UpdateSalonRequest` schema — `"required": ["buildingNo", "street"]`), so
// [save] always threads the CURRENT loaded values through for those two,
// regardless of whether the viewer edited them (this phase does not expose
// address editing at all — see the screen's own doc for why).
//
// `cityId`/`districtId` get the SAME unconditional echo (Finding, 2026-08-29)
// — the backend's `SalonService.updateSalon` calls `validateProviderLocality`
// on every PATCH regardless of which fields changed (`LocalityWriteValidator`
// throws `BusinessException: City is required` the moment `cityId` is null),
// so [save] must always send the loaded [Salon]'s current cityId/districtId
// even though this screen never edits them — never diff them against the
// snapshot like the other fields, since an untouched (identical) selection
// would fold to `null` and trip the same 400 on every save, whichever field
// the viewer actually edited. Mirrors [MasterRepository.updateLocality]'s
// `required` (non-diffable) `cityId` parameter.

// Prefixed: `dart:async`'s non-generic [async.AsyncError] (carried by the
// records `.wait` [async.ParallelWaitError]) must NOT be confused with
// Riverpod's generic `AsyncError<T>`, which `riverpod_annotation` brings
// unprefixed into scope. Mirrors `public_salon_profile_notifier.dart`'s exact
// unwrap — see that file's own header note on the mis-resolution risk.
import 'dart:async' as async;

// `KeepAliveLink` is not part of `riverpod_annotation`'s show-list — it lives
// on the dedicated advanced-API surface, `misc.dart` (mirrors
// `package:riverpod/misc.dart`; imported via `flutter_riverpod`, an existing
// direct dependency, rather than adding `riverpod` itself as one). Same
// import `bookings_day_notifier.dart` reaches for, for the same reason.
import 'package:flutter_riverpod/misc.dart';
// `ProviderListenable.select` (used below to narrow the `authProvider` watch to
// the identity-bearing slice via [authUserIdOrNull]) is not part of
// `riverpod_annotation`'s show-list — same reason `bookings_day_notifier.dart`
// reaches for the full package.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_api/beautica_api.dart' show UpdateSalonRequest;
import 'package:beautica_mobile/core/errors/failures.dart';

import '../../auth/presentation/auth_notifier.dart';
import '../data/salon_repository.dart';
import '../domain/salon.dart';
import '../domain/salon_staff_member.dart';
import 'my_salons_notifier.dart';

part 'salon_management_profile_notifier.g.dart';

/// The data the owner/admin salon management screen renders: the salon
/// detail (editable) paired with its staff roster (the «Персонал» tab).
///
/// Phase 21.5 — the roster is now the management-scoped `GET
/// /salons/{salonId}/staff` read (masters AND admins, unmasked contacts),
/// replacing the earlier public `GET /salons/{salonId}/masters` rail read —
/// see [SalonRepository.getSalonStaff]'s own doc.
typedef SalonManagementProfileData = (
  Salon salon,
  List<SalonStaffMember> staff,
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
    //
    // NARROWED to the user id (mobile-perf LOW, 2026-09-01). What this watch
    // means is "rebuild when the signed-in IDENTITY changes"; a bare
    // `ref.watch(authProvider)` also fired on every silent token refresh
    // (`AuthNotifier.setAccessToken` re-emits `Authenticated` with a new
    // accessToken), refetching BOTH `GET /salons/{id}` and `GET
    // /salons/{id}/staff` while the owner sat on the management screen.
    // Identity is the whole trigger here: neither read is role-scoped (the
    // owner and the admin fetch the same salon + the same roster — the ROLE
    // only gates which controls `SalonManagementProfileScreen` renders, and
    // that screen reads the role from `authProvider` itself), so nothing but
    // a different signed-in user can invalidate this data.
    ref.watch(authProvider.select(authUserIdOrNull));

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
      final (Salon salon, List<SalonStaffMember> staff) = await (
        repo.getSalonById(salonId),
        repo.getSalonStaff(salonId),
      ).wait;
      return (salon, staff);
    } on async.ParallelWaitError<
      (Salon?, List<SalonStaffMember>?),
      (async.AsyncError?, async.AsyncError?)
    > catch (error, stackTrace) {
      final (async.AsyncError? salonError, async.AsyncError? staffError) =
          error.errors;
      final async.AsyncError? firstError = salonError ?? staffError;
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
  /// specifically. `street`/`buildingNo`/`cityId`/`districtId` are always
  /// threaded through unmodified (backend-required locality validation runs
  /// on every PATCH — see this file's header doc's 2026-08-29 finding).
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
    final (Salon current, List<SalonStaffMember> staff) = data;

    final String trimmedName = name.trim();
    final String trimmedDescription = description.trim();
    final String trimmedPhone = phone.trim();
    final String trimmedInstagram = instagramUrl.trim();

    final UpdateSalonRequest request = UpdateSalonRequest(
      (b) => b
        ..street = current.street ?? ''
        ..buildingNo = current.buildingNo ?? ''
        ..cityId = current.cityId
        ..districtId = current.districtId
        ..name = trimmedName != current.name ? trimmedName : null
        ..description = trimmedDescription != (current.description ?? '')
            ? trimmedDescription
            : null
        // `current.phone` is now a REAL baseline on every read path (the
        // Phase 21.2 gap is closed — see file header doc), and is never a
        // blank-but-present string (`SalonMapper._blankToNull`), so
        // `current.phone ?? ''` compares exactly against the trimmed field
        // text: an untouched pre-populated field folds to `null` (omitted),
        // a cleared one sends `''`.
        ..phone = trimmedPhone != (current.phone ?? '') ? trimmedPhone : null
        ..instagramUrl = trimmedInstagram != (current.instagramUrl ?? '')
            ? trimmedInstagram
            : null,
    );

    // mobile-qa CRITICAL fix (swipe-to-delete audit, 2026-09-03) — same
    // class of autoDispose-mid-await defect as [deleteSalon] (see that
    // method's full doc). `SalonProfileEditScreen`'s own `build()` watches
    // this family for the duration of a normal save, which is the SAME
    // "incidental keep-alive via watching" every pre-existing delete caller
    // relied on — but its «Назад» button (`onBack`) is never disabled while
    // `_saving` is true, unlike its text fields, so a user CAN pop the
    // screen mid-await and drop the only watcher. `ref.keepAlive()` covers
    // that plain listener-drop case on its own (the link is closed in
    // `finally` so it never outlives this call) — UNLESS the screen has
    // ALSO already popped when an unrelated `authProvider` identity change
    // lands: that invalidates this now-unwatched element and unconditionally
    // wipes the just-added `KeepAliveLink` too ([deleteSalon]'s doc walks
    // the exact mechanism), so the scheduled disposal proceeds regardless of
    // having called `ref.keepAlive()` earlier in this method. Unlike
    // [deleteSalon], THIS method still needs `ref` after the await to
    // persist `state`, so that combined race can't be designed away by
    // moving work to the caller the way [deleteSalon] did. `ref.mounted` is
    // checked before the post-await `state` write below: on that (rare,
    // popped-then-invalidated) case this returns `null` — the PATCH itself
    // already succeeded server-side — rather than throwing
    // `UnmountedRefException`.
    //
    // CORRECTION (investigated 2026-09-03 — see
    // `salon_management_profile_notifier_test.dart`'s "compound
    // authProvider-mid-await race" group for the executable proof): a PRIOR
    // version of this doc claimed `ref.mounted` could flip false while
    // `SalonProfileEditScreen` was STILL mounted and still awaiting this
    // very call, i.e. with nothing popped. That claim is false and does not
    // reproduce — Riverpod only REBUILDS an element that still has an
    // active watcher on invalidation (`isActive` stays true for as long as
    // the screen's own `ref.watch` is attached); it never disposes one.
    // `ref.mounted` going false requires the screen to have already popped,
    // per the paragraph above — do not re-derive the "still mounted" case.
    // Because the PATCH has already succeeded server-side regardless of
    // which case applies, the `mySalonsProvider` invalidation below is
    // captured through `ref.container` (taken BEFORE the await, while this
    // element is provably alive) and fired unconditionally on success,
    // rather than being folded into the `ref.mounted` branch below — see
    // this file's header doc. Skipping the local `state` write in the
    // popped case is still fine: the caller only reads this element's
    // `state` via its OWN `ref.watch`, and since the screen that would read
    // it is gone, the next fresh read of this family self-heals from a
    // fresh `GET` rather than rendering a stale local merge. The
    // `ref.mounted` guard and the `ref.keepAlive()` call below are
    // REQUIRED for this — removing either reintroduces the
    // `UnmountedRefException` crash the mobile-qa fix above closed.
    final ProviderContainer container = ref.container;
    final KeepAliveLink keepAliveLink = ref.keepAlive();
    try {
      final Salon patched = await ref
          .read(salonRepositoryProvider)
          .updateSalon(salonId, request);
      // cycle-safe: mySalonsProvider (MySalons.build()) only watches
      // authProvider — it never watches salonManagementProfileProvider, so
      // there is no back-edge here to close into a cycle. See this file's
      // header doc (mobile-perf MEDIUM follow-up, 2026-08-28) for why this
      // invalidation exists: keeps the «Мої салони» hub's cached list from
      // going stale after an edit. UNCONDITIONAL the moment the PATCH
      // succeeds — via the captured `container`, not `ref`, so it does not
      // depend on `ref.mounted` (see the correction above).
      container.invalidate(mySalonsProvider);
      if (!ref.mounted) return null;
      // SalonResponse (the PATCH response) does not carry coverImageUrl /
      // avgRating / reviewCount — preserve those from the last known-good
      // read rather than letting them reset to null/0. See
      // SalonMapper.fromUpdateDto's doc.
      final Salon merged = patched.copyWith(
        coverImageUrl: current.coverImageUrl,
        avgRating: current.avgRating,
        reviewCount: current.reviewCount,
      );
      state = AsyncData((merged, staff));
      return null;
    } on Failure catch (f) {
      return f;
    } finally {
      // Safe even if the element is no longer mounted: `KeepAliveLink.close`
      // only mutates its own captured link list and does not touch `Ref`'s
      // mounted-guarded API, so this never throws.
      keepAliveLink.close();
    }
  }

  /// Saves the «Локація» edit form (Phase 21.10 — [SalonAddressEditScreen]):
  /// locality (cityId/districtId) + street/buildingNo/locationNote, via a
  /// partial `PATCH /salons/{salonId}`.
  ///
  /// ADDITIVE sibling of [save] — that method covers the name/description/
  /// phone/Instagram slice only (`street`/`buildingNo`/`cityId`/`districtId`
  /// are threaded through UNMODIFIED there — see this file's header doc).
  /// This method is the address counterpart: THIS screen owns locality, so
  /// [street]/[buildingNo]/[cityId] are the CURRENT (always sent, never
  /// diffed) selection/text of the screen's own fields — [cityId] is
  /// `required` and non-nullable at the Dart type level for exactly the
  /// reason [MasterRepository.updateLocality]'s `cityId` parameter is:
  /// diffing it against the loaded snapshot (Finding, 2026-08-29 — the prior
  /// `cityId != current.cityId ? cityId : null` shape) folded an UNCHANGED
  /// selection to `null`, which the backend's `LocalityWriteValidator`
  /// rejects with `BusinessException: City is required`. [districtId]
  /// remains nullable/optional (a city without districts has none to send)
  /// and [locationNote] is the only field still included conditionally
  /// (optional field, differs-from-snapshot is fine since omitting it is not
  /// a validation failure).
  ///
  /// Returns `null` on success (state updated, aggregates preserved — see
  /// [save]'s identical merge note) or the [Failure] on error.
  Future<Failure?> saveAddress({
    required String cityId,
    String? districtId,
    required String street,
    required String buildingNo,
    required String locationNote,
  }) async {
    final SalonManagementProfileData? data = state.value;
    if (data == null) return null;
    final (Salon current, List<SalonStaffMember> staff) = data;

    final String trimmedStreet = street.trim();
    final String trimmedBuildingNo = buildingNo.trim();
    final String trimmedNote = locationNote.trim();

    final UpdateSalonRequest request = UpdateSalonRequest(
      (b) => b
        ..street = trimmedStreet
        ..buildingNo = trimmedBuildingNo
        ..cityId = cityId
        ..districtId = districtId
        ..locationNote = trimmedNote != (current.locationNote ?? '')
            ? trimmedNote
            : null,
    );

    // mobile-qa CRITICAL fix (swipe-to-delete audit, 2026-09-03) — same
    // class of autoDispose-mid-await defect as [deleteSalon] and [save]
    // (identical back-button gap: `SalonAddressEditScreen`'s «Назад» is
    // never disabled while `_saving` is true). See [save]'s doc for the full
    // mechanism and its 2026-09-03 correction: `ref.keepAlive()` (covers a
    // plain listener drop) is paired with a `ref.mounted` check before the
    // post-await `state` touch (covers the popped-then-invalidated race
    // `ref.keepAlive()` alone cannot survive — NOT a race reachable while
    // the screen is still watching, disproven and not to be re-derived);
    // both are REQUIRED, removing either reintroduces
    // `UnmountedRefException`. The `mySalonsProvider` invalidation below
    // goes through a `ref.container` handle captured BEFORE the await
    // instead, unconditionally, since the PATCH has already succeeded
    // server-side by the time `ref.mounted` matters either way.
    final ProviderContainer container = ref.container;
    final KeepAliveLink keepAliveLink = ref.keepAlive();
    try {
      final Salon patched = await ref
          .read(salonRepositoryProvider)
          .updateSalon(salonId, request);
      // cycle-safe: mySalonsProvider (MySalons.build()) only watches
      // authProvider — it never watches salonManagementProfileProvider, so
      // there is no back-edge here to close into a cycle. See this file's
      // header doc (mobile-perf MEDIUM follow-up, 2026-08-28) for why this
      // invalidation exists: keeps the «Мої салони» hub's cached list from
      // going stale after an address edit. UNCONDITIONAL the moment the
      // PATCH succeeds — see [save]'s identical note.
      container.invalidate(mySalonsProvider);
      if (!ref.mounted) return null;
      final Salon merged = patched.copyWith(
        coverImageUrl: current.coverImageUrl,
        avgRating: current.avgRating,
        reviewCount: current.reviewCount,
      );
      state = AsyncData((merged, staff));
      return null;
    } on Failure catch (f) {
      return f;
    } finally {
      // Safe even if the element is no longer mounted — see [save]'s
      // identical `finally` note.
      keepAliveLink.close();
    }
  }

  /// Deactivates (soft-deletes) this salon via `DELETE /salons/{salonId}`.
  ///
  /// Owner-only — enforced server-side and by the router's client-side role
  /// gate; this method issues the call unconditionally, matching every other
  /// repository call in this codebase (never re-implement authorization on
  /// the client). Returns `null` on success or the [Failure] on error.
  ///
  /// mobile-qa CRITICAL fix (swipe-to-delete audit, 2026-09-03) — this
  /// method does NOT invalidate `mySalonsProvider` itself anymore; see
  /// `runDeleteSalonFlow`'s doc for why that moved to the caller. Two
  /// independent Riverpod gotchas made doing it here unreliable:
  ///
  /// 1. `salonManagementProfileProvider` is `@riverpod`: autoDispose, no
  ///    `ref.keepAlive()`. `MySalonsScreen`'s swipe-to-delete never watches
  ///    this family at all (unlike `SettingsScreen`/`SalonSettingsScreen`,
  ///    which incidentally keep it alive by watching it for display), so
  ///    the element can be disposed mid-await.
  /// 2. A bare `ref.keepAlive()` does NOT reliably survive that await
  ///    either: `build()` watches `authProvider.select(authUserIdOrNull)`,
  ///    and if `authProvider`'s own async resolution completes WHILE this
  ///    method is awaiting the `DELETE` call (a real, measured race — this
  ///    family is commonly first read on `/salons/mine`, the landing route
  ///    right after login, before `authProvider` has necessarily resolved
  ///    once), Riverpod's `Ref.watch` machinery calls `invalidateSelf()` on
  ///    this element — which unconditionally WIPES every `KeepAliveLink`
  ///    in `runOnDispose()` *before* re-checking whether to dispose, node
  ///    for node the same mechanism `project_riverpod_offstage_pause_
  ///    invalidate` documents for keepAlive family buckets. Since nothing
  ///    watches this element, the wipe is immediately followed by a
  ///    schedule-and-actually-dispose, regardless of the keepAlive() we
  ///    called earlier in this same method.
  ///
  /// Given (2), pinning this element harder isn't the fix — this method
  /// simply stops touching `ref` for anything but the repository call
  /// itself, so it is correct whether or not the element survives.
  /// `runDeleteSalonFlow` invalidates `mySalonsProvider` afterwards using
  /// its OWN `WidgetRef` (stable for as long as the calling screen is
  /// mounted, which it already checks) instead of this volatile
  /// per-`salonId` family member's `ref`.
  Future<Failure?> deleteSalon() async {
    try {
      await ref.read(salonRepositoryProvider).deleteSalon(salonId);
      return null;
    } on Failure catch (f) {
      return f;
    }
  }
}

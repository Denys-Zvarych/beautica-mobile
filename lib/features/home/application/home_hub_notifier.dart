// Phase 13.7 — HomeHub aggregate notifier.
//
// Exposes per-card independent AsyncValue fields so that a single failed card
// (e.g. the passport endpoint returning 404 while the profile is fine) never
// blanks the whole screen.
//
// Data-wired cards (backend already exists):
//   • profileAsync         → derived from clientEditProfileProvider (fresh GET
//     /users/me) — the same authoritative source the Settings edit screens read,
//     so the home card and Settings refresh together.
//   • nextAppointmentAsync → Phase 225 — derived from BookingRepository
//     .getMyBookings (the same endpoint the «Мої записи» Майбутні tab reads),
//     see [nextAppointment]'s doc. Returns the raw [Booking] unchanged — the
//     Home Hub renders it through the SAME `BookingCard` widget «Мої записи»
//     uses (locked decision), so there is no lossy DTO projection in between
//     any more.
//
// Empty-state-placeholder cards (backend 19.x not yet shipped):
//   • favoriteMastersAsync  — TODO(19.1) wire GET /favorites/masters
//   • timelineAsync         — TODO(19.5) wire GET /clients/me/timeline
//
// The client's aggregate rating (two-sided system: masters/salons rate clients)
// is derivable from GET /clients/me/rating but that endpoint is not yet shipped;
// the clientRating stat tile shows null (empty state) until then.

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';

import '../../../features/auth/domain/user.dart';
import '../../../features/location/state/location_providers.dart';
import '../../booking/data/booking_providers.dart';
import '../../booking/domain/booking.dart';
import '../../booking/domain/booking_partition.dart';
import '../../booking/domain/booking_sort.dart';
import '../../booking/domain/booking_tab.dart';
import '../domain/home_hub_models.dart';
import 'client_edit_profile_notifier.dart';

part 'home_hub_notifier.g.dart';

// ---------------------------------------------------------------------------
// Profile card — data-wired
// ---------------------------------------------------------------------------

/// Derives the CLIENT's [ClientProfileSummary] from the fresh `GET /users/me`
/// profile cached by [clientEditProfileProvider] — the SAME authoritative source
/// the Settings edit screens read. Sharing one source (rather than the
/// long-lived `authProvider` session [User], which only re-hydrates on cold
/// start / login / explicit `refreshUser()`) keeps the home card and Settings in
/// lock-step: every edit-screen save already calls
/// `ref.invalidate(clientEditProfileProvider)`, which now also refreshes this
/// card. The locality (city / district) therefore reflects `/users/me` without
/// waiting for a cold restart.
///
/// [clientEditProfileProvider] throws [UnauthorizedFailure] when the session is
/// unauthenticated (the router guard should have redirected already, but it is
/// defensive nonetheless), so that error propagates here as the card's
/// AsyncError.
@riverpod
Future<ClientProfileSummary> clientProfile(Ref ref) async {
  // Read the injected clock seam BEFORE the first `await`: `ref.watch` after a
  // suspension point is not safe in an async provider body (the provider may
  // have been rebuilt or disposed in the meantime). The value captured here is
  // the `DateTime Function()` ITSELF, not an instant — it is invoked below, so
  // "now" is still read at use time rather than frozen at build entry.
  final DateTime Function() clock = ref.watch(clockProvider);

  final user = await ref.watch(clientEditProfileProvider.future);
  return ClientProfileSummary(
    firstName: user.firstName ?? '',
    lastName: user.lastName ?? '',
    // phone comes from the same fresh /users/me profile; nullable because CLIENT
    // location is optional — fall back to the empty string so the profile card
    // renders its placeholder.
    city: await _resolveLocalityLabel(ref, user),
    phone: user.phoneNumber ?? '',
    // TODO(backend): GET /clients/me/rating (two-sided client rating, excludes comments)
    clientRating: null,
    // Placeholder fallback until the backend exposes a real account-creation
    // date (TODO above's sibling).
    //
    // This is a CALENDAR-FIELD read, so it goes through the Kyiv seam like
    // every other one (ARCHITECTURE-mobile.md § 0.9): the device supplies the
    // INSTANT, Europe/Kyiv decides which DAY — and therefore which YEAR — that
    // instant falls in. The divergence window is only year-granular (roughly
    // the last two-to-three Kyiv hours of 31 December, when a device behind
    // Kyiv is still in the previous year), but it is a real instance of the
    // class, and `DateTime.now().year` here was the exact shape the guards ban
    // elsewhere. `kyivToday` returns a DATE TOKEN — reading `.year` off it is
    // legal; treating it as an instant is not (see `shared/time/kyiv_day.dart`).
    memberSinceYear: kyivToday(clock).year,
  );
}

/// Resolves the human-readable locality label for the profile card.
///
/// Produces `"<city>, <district>"` when the client has a district set (e.g.
/// "Львів, Сихівський район"), or just `"<city>"` when no district is set.
/// Returns the empty string when no city is resolvable (placeholder is then
/// correct).
///
/// City and district both derive solely from fields already on [User]
/// ([User.cityId]/[User.oblastId] for the city, [User.cityId]/[User.districtId]
/// for the district) — neither lookup depends on the other's result. So both
/// futures are started before either is awaited: on the cold path (no
/// denormalized name on either) the two taxonomy round-trips overlap instead of
/// serializing. The district future is still created only when
/// [User.districtId] is set, so users without a district trigger no fetch.
///
/// A missing/failed district lookup degrades gracefully to the bare city — it
/// never throws and never blocks the card.
Future<String> _resolveLocalityLabel(Ref ref, User user) async {
  final cityFuture = _resolveCityName(ref, user);
  final districtFuture = user.districtId == null
      ? null
      : _resolveDistrictName(ref, user);

  final city = await cityFuture;
  if (city.isEmpty || districtFuture == null) {
    return city;
  }

  final district = await districtFuture;
  if (district == null || district.isEmpty) {
    return city;
  }
  return '$city, $district';
}

/// Resolves the human-readable city name for the profile card.
///
/// The denormalized [User.cityName] string can be null/empty even when the
/// authoritative [User.cityId] FK is set, in which case the card would wrongly
/// render its "add location" placeholder. To stay consistent with the Settings
/// location screen (`ClientLocationEditScreen._prePopulateLocality`), fall back
/// to resolving the display name from the location taxonomy by matching the
/// city id — exactly as Settings does.
///
/// Resolution order:
///   1. Non-empty [User.cityName] → use it (fast path, no extra fetch).
///   2. Else [User.cityId] set → look it up in the oblast's city list.
///   3. Else → empty string (genuinely no location → placeholder is correct).
Future<String> _resolveCityName(Ref ref, User user) async {
  final cityName = user.cityName;
  if (cityName != null && cityName.isNotEmpty) {
    return cityName;
  }

  final cityId = user.cityId;
  final oblastId = user.oblastId;
  if (cityId == null || oblastId == null) {
    return '';
  }

  try {
    final cities = await ref.watch(cityListProvider(oblastId).future);
    for (final c in cities) {
      if (c.id == cityId) {
        return c.name;
      }
    }
  } catch (e, st) {
    if (kDebugMode) {
      log(
        'clientProfile: city-name taxonomy resolution failed — falling back '
        'to placeholder',
        name: 'feature.home',
        level: 800,
        error: e,
        stackTrace: st,
      );
    }
  }
  return '';
}

/// Resolves the human-readable district name for the profile card, or null when
/// none can be resolved.
///
/// Mirrors [_resolveCityName]'s strategy one cascade level deeper, matching the
/// Settings location screen (`ClientLocationEditScreen._prePopulateLocality`):
///   1. Non-empty [User.districtName] → use it (fast path, no extra fetch).
///   2. Else [User.districtId]+[User.cityId] set → look it up in the city's
///      district list (`districtListProvider(cityId)`).
///   3. Else / on failure → null (caller falls back to the bare city).
Future<String?> _resolveDistrictName(Ref ref, User user) async {
  final districtName = user.districtName;
  if (districtName != null && districtName.isNotEmpty) {
    return districtName;
  }

  final districtId = user.districtId;
  final cityId = user.cityId;
  if (districtId == null || cityId == null) {
    return null;
  }

  try {
    final districts = await ref.watch(districtListProvider(cityId).future);
    for (final d in districts) {
      if (d.id == districtId) {
        return d.name;
      }
    }
  } catch (e, st) {
    if (kDebugMode) {
      log(
        'clientProfile: district-name taxonomy resolution failed — falling '
        'back to bare city',
        name: 'feature.home',
        level: 800,
        error: e,
        stackTrace: st,
      );
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Next appointment — data-wired (Phase 225)
// ---------------------------------------------------------------------------

/// Returns the soonest upcoming booking for the CLIENT, or `null` when none
/// qualifies.
///
/// Phase 228 — retires the Phase 225 bounded page-forward scan now that
/// `GET /bookings/me` supports the backend Phase 28.1/28.2 `partition`
/// filter: `partition: BookingPartition.upcoming` is `status = CONFIRMED AND
/// endsAt >= now`, computed server-side, so an elapsed `CONFIRMED` booking
/// (the actual Phase 225 production bug — the backend has no `@Scheduled`
/// cron that auto-transitions one) never comes back at all. Page 0 row 0 of
/// a `size: 1` request **is** the answer; there is nothing left to scan or
/// skip client-side.
///
/// Reuses the EXACT same status/sort shape the «Мої записи» Майбутні tab
/// issues ([MyBookingsNotifier]) — [BookingTabX.statuses] for
/// [BookingTab.upcoming] (currently `{CONFIRMED}`; booking auto-confirm
/// retired `PENDING`) sorted soonest-first ([BookingSort.oldest]) — so this
/// card can never disagree with that tab about which bookings count as
/// "upcoming". [BookingTabX.partition] supplies [BookingPartition.upcoming]
/// alongside it.
///
/// **Both `partition` and the legacy `statuses` are sent on every request** —
/// the same Phase 227 rollout safety valve `MyBookingsNotifier` uses (see
/// `BookingTab`'s file header and `BookingRepository.getMyBookings`'s doc).
/// Spring silently DROPS an unrecognised query param instead of 400ing, so a
/// request carrying only `partition` against a backend without Phase 28.2
/// would return the caller's entire unfiltered booking history — including a
/// year-old cancelled booking rendered as "your next appointment". Sending
/// `statuses` too degrades safely to the pre-Phase-228 status-only filtering
/// on a stale backend.
///
/// **The `from: today` bound stays even though `partition` already excludes
/// elapsed rows.** `partition` is instant-granular; `from` is day-granular —
/// they are not the same filter, and keeping `from` costs nothing while
/// keeping the query cheap for an account with a long booking history (it
/// discards every prior-day row server-side before the partition filter even
/// runs). `today` is derived as the **Europe/Kyiv** calendar day, not the
/// device's local day: the injectable [clockProvider] seam supplies "now" (so
/// tests can pin it), which is then converted to the Kyiv wall-clock via
/// [kyivToday] — the single canonical spelling for "the Kyiv calendar day the
/// injected clock's current instant falls on" (`shared/time/kyiv_day.dart`),
/// the same one `BookingsDiscoveryView` and [bookedDaysProvider] use for their
/// own day anchors. The backend interprets `from` as a
/// Europe/Kyiv local date, so this makes the two sides agree on "today"
/// regardless of the device's own zone or clock, in EITHER direction: a device
/// behind Kyiv no longer widens the window, and — the case that actually
/// matters — a device AHEAD of Kyiv (Asia-Pacific, or simply a wrong clock)
/// no longer NARROWS it and silently excludes a booking later that same Kyiv
/// day. **Do not revert this to `dateOnly(DateTime.now())`** — Phase 225's
/// audit cycles 4 and 5 fought hard to get this derivation right.
///
/// [bookedDaysProvider] was, when this doc was first written, still on the
/// OLDER device-local convention (`dateOnly(DateTime.now())`) for its own
/// `from`/`to`. It is NOT any more — commit `0434db4f` routed it through the
/// same seam (`booked_days_notifier.dart:151`,
/// `kyivToday(ref.read(clockProvider))`), pinned by that file's own
/// Asia/Tokyo-anchored test. This paragraph is kept, corrected, rather than
/// deleted because the stale version of it read as a live TODO for two
/// separate audit passes.
///
/// The `BookingDisplayX` elapsed-slot presentation getter is NOT used here —
/// that getter answers a different question ("what buttons does THIS
/// booking show", gating «Деталі запису»'s reschedule/cancel vs. read-only
/// rebook affordances, see `booking_detail_screen.dart`) than "which list
/// does this booking belong in", which the server-side partition now answers
/// on its own.
///
/// Errors (including an unauthenticated [UnauthorizedFailure] — the router
/// guard should already have redirected, but this is defensive) are not
/// caught: they propagate as this provider's `AsyncError`, exactly like
/// [clientProfile] above.
@riverpod
Future<Booking?> nextAppointment(Ref ref) async {
  final repository = ref.watch(bookingRepositoryProvider);
  // Recomputed on every build — never hoisted — so a long-lived cached
  // instance doesn't pin "today" to first-use for the process's lifetime.
  // `clockProvider`, not a bare `DateTime.now()`, so tests can pin "now" to a
  // fixed instant; [kyivToday] then decides which Europe/Kyiv calendar day
  // that instant falls on — see the doc comment above for why device-local
  // would be wrong. `kyivToday(clock)` IS `dateOnly(toBeauticaTime(clock()))`
  // (`shared/time/kyiv_day.dart:84,94`); the canonical spelling is used here
  // so `lib/` has exactly one name for this derivation, the way `test/`
  // already does.
  final DateTime today = kyivToday(ref.watch(clockProvider));

  final page = await repository.getMyBookings(
    statuses: BookingTab.upcoming.statuses,
    partition: BookingTab.upcoming.partition,
    sort: BookingSort.oldest,
    from: today,
    page: 0,
    size: 1,
  );

  // Returned AS-IS — the Home Hub renders this through the SAME `BookingCard`
  // widget «Мої записи» uses (locked decision), so there is no lossy
  // NextAppointment DTO projection any more; the caller gets the full
  // enriched Booking straight from `page.items.first`.
  return page.items.isEmpty ? null : page.items.first;
}

// ---------------------------------------------------------------------------
// Favorite masters — placeholder (backend 19.1 not ready)
// ---------------------------------------------------------------------------

/// Returns the CLIENT's favourite masters.
/// Currently always returns an empty list until the endpoint ships.
/// TODO(19.1): wire GET /favorites/masters
@riverpod
Future<List<FavoriteMasterItem>> favoriteMasters(Ref ref) async {
  // TODO(19.1): call favorites repository when endpoint ships.
  if (kDebugMode) {
    log(
      'favoriteMasters: placeholder — backend 19.1 not ready',
      name: 'feature.home',
      level: 700,
    );
  }
  return const <FavoriteMasterItem>[];
}

// ---------------------------------------------------------------------------
// Beauty Timeline — placeholder (backend 19.5 not ready)
// ---------------------------------------------------------------------------

/// Returns the CLIENT's beauty timeline entries.
/// Currently always returns an empty list until the endpoint ships.
/// TODO(19.5): wire GET /clients/me/timeline
@riverpod
Future<List<TimelineEntry>> beautyTimeline(Ref ref) async {
  // TODO(19.5): call timeline repository when endpoint ships.
  if (kDebugMode) {
    log(
      'beautyTimeline: placeholder — backend 19.5 not ready',
      name: 'feature.home',
      level: 700,
    );
  }
  return const <TimelineEntry>[];
}

// ---------------------------------------------------------------------------
// Unlike a favourite master — action (backend 19.1 not ready)
// ---------------------------------------------------------------------------

/// Notifier that manages the optimistic unlike action.
/// The actual DELETE /favorites/masters/:id is wired when 19.1 ships.
/// TODO(19.1): wire DELETE /favorites/masters/:favoriteId
@riverpod
class UnlikeFavoriteMaster extends _$UnlikeFavoriteMaster {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Optimistically removes the favorite and calls the delete endpoint.
  /// On error, reverts by invalidating [favoriteMastersProvider].
  Future<void> unlike(String favoriteId) async {
    state = const AsyncLoading();
    // TODO(19.1): call DELETE /favorites/masters/:favoriteId
    if (kDebugMode) {
      log(
        'unlike master: placeholder — backend 19.1 not ready',
        name: 'feature.home',
        level: 700,
      );
    }
    // Invalidate so the list re-fetches (will still be empty until wired).
    // cycle-safe: favoriteMasters' build() has no ref.watch at all (placeholder).
    ref.invalidate(favoriteMastersProvider);
    state = const AsyncData(null);
  }
}

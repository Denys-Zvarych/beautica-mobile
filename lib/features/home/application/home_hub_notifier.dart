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
//     see [nextAppointment]'s doc.
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
import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';

import '../../../features/auth/domain/user.dart';
import '../../../features/location/state/location_providers.dart';
import '../../booking/data/booking_providers.dart';
import '../../booking/domain/booking.dart';
import '../../booking/domain/booking_display_x.dart';
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
    memberSinceYear: DateTime.now().year,
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

/// Page size for each `getMyBookings` fetch. With the [from] bound below in
/// place, page 0 answers the question in the overwhelming majority of cases —
/// this is no longer the whole defence against elapsed rows (see
/// [_kNextAppointmentMaxPages] for that), just a reasonable page size.
const int _kNextAppointmentPeekSize = 5;

/// Hard cap on how many pages [nextAppointment] will page-forward through.
///
/// A CONFIRMED booking whose window has elapsed is NEVER auto-transitioned by
/// the backend — there is no `@Scheduled` cron in
/// `beautica-backend/.../booking/` that flips an elapsed CONFIRMED booking to
/// COMPLETED/NOT_COMPLETED; that only happens via an explicit provider action
/// (decline/complete, track 27.x). So on a sufficiently busy day, a client's
/// `CONFIRMED` list can still contain more same-day elapsed rows than fit in
/// one page even after the [from] bound below discards every PRIOR day. This
/// cap bounds how far [nextAppointment] will page forward chasing a
/// genuinely-upcoming row: bounded because one account with an unbounded pile
/// of elapsed same-day bookings must never turn a home-screen load into an
/// open-ended fan-out of requests. 3 pages × [_kNextAppointmentPeekSize] = 15
/// same-day elapsed rows scanned before giving up — comfortably past any
/// realistic single-day booking count for one client.
const int _kNextAppointmentMaxPages = 3;

/// Returns the soonest upcoming booking for the CLIENT, or `null` when none
/// qualifies.
///
/// Reuses the EXACT same request shape the «Мої записи» Майбутні tab issues
/// ([MyBookingsNotifier]) — [BookingTabX.statuses] for [BookingTab.upcoming]
/// (currently `{CONFIRMED}`; booking auto-confirm retired `PENDING`) sorted
/// soonest-first ([BookingSort.oldest]) — so this card can never disagree with
/// that tab about which bookings count as "upcoming".
///
/// [BookingRepository.getMyBookings] filters by STATUS only; it has no
/// server-side "is this instant still in the future" predicate, so a
/// CONFIRMED booking whose `endAt` has already passed can still come back.
/// Two defences combine here:
///
///   1. **`from: today`** — bounds the query to bookings starting today or
///      later (backend Phase 26.2's inclusive local-day `from`, an
///      open-ended future window when `to` is omitted). This discards every
///      elapsed booking from a PRIOR day server-side before paging at all —
///      the actual production bug: an account can accumulate an unbounded
///      number of stale CONFIRMED rows from past days (see
///      [_kNextAppointmentMaxPages]'s doc for why they exist at all), and
///      without this bound they fill the whole peek window ahead of a
///      genuinely upcoming booking. `from` is **day**-granular, so bookings
///      earlier TODAY still come back and must still be filtered client-side
///      — step 2 below.
///   2. **[BookingDisplayX.isPast] + bounded page-forward** — applied
///      client-side to skip any row whose `endAt` is already in the past and
///      return the first one that is genuinely still upcoming. If every row
///      on a page is elapsed AND the envelope's `totalElements` says more
///      rows exist, the next page is fetched, up to
///      [_kNextAppointmentMaxPages] total pages. Returns `null` once the cap
///      is hit with everything still elapsed, or once the pages are
///      exhausted — never an unbounded re-query.
///
/// `today` is derived as the **Europe/Kyiv** calendar day, not the device's
/// local day: the injectable [clockProvider] seam supplies "now" (so tests can
/// pin it), which is then converted to the Kyiv wall-clock via
/// [toBeauticaTime] before [dateOnly] reads its `.year`/`.month`/`.day` — the
/// same `dateOnly(toBeauticaTime(...))` composition `BookingsDiscoveryView`
/// already uses for its own day anchor. The backend interprets `from` as a
/// Europe/Kyiv local date, so this makes the two sides agree on "today"
/// regardless of the device's own zone or clock, in EITHER direction: a device
/// behind Kyiv no longer widens the window, and — the case that actually
/// matters — a device AHEAD of Kyiv (Asia-Pacific, or simply a wrong clock)
/// no longer NARROWS it and silently excludes a booking later that same Kyiv
/// day. [bookedDaysProvider] still uses the OLDER device-local convention
/// (`dateOnly(DateTime.now())`) for its own `from`/`to`; that is a pre-existing,
/// separately-tracked limitation on that provider and out of scope here — this
/// provider does not inherit it.
///
/// Errors (including an unauthenticated [UnauthorizedFailure] — the router
/// guard should already have redirected, but this is defensive) are not
/// caught: they propagate as this provider's `AsyncError`, exactly like
/// [clientProfile] above.
@riverpod
Future<NextAppointment?> nextAppointment(Ref ref) async {
  final repository = ref.watch(bookingRepositoryProvider);
  // Recomputed on every build — never hoisted — so a long-lived cached
  // instance doesn't pin "today" to first-use for the process's lifetime.
  // `clockProvider`, not a bare `DateTime.now()`, so tests can pin "now" to a
  // fixed instant; converted to the Europe/Kyiv wall-clock via
  // [toBeauticaTime] BEFORE [dateOnly] reads its calendar fields — see the
  // doc comment above for why device-local would be wrong.
  final DateTime today = dateOnly(toBeauticaTime(ref.watch(clockProvider)()));

  int scanned = 0;
  for (int pageIndex = 0; pageIndex < _kNextAppointmentMaxPages; pageIndex++) {
    final page = await repository.getMyBookings(
      statuses: BookingTab.upcoming.statuses,
      sort: BookingSort.oldest,
      from: today,
      page: pageIndex,
      size: _kNextAppointmentPeekSize,
    );

    for (final Booking booking in page.items) {
      if (!booking.isPast) {
        return NextAppointment(
          id: booking.id,
          masterName: booking.masterName,
          service: booking.serviceName,
          dateLabel: formatFullDate(booking.startAt),
          timeLabel: formatSlotTime(booking.startAt),
          location: booking.addressLine ?? booking.salonName ?? '',
          startsAt: booking.startAt,
          endsAt: booking.endAt,
          masterInitials: booking.masterInitials,
        );
      }
    }

    scanned += page.items.length;
    final bool morePagesRemain = scanned < page.totalElements;
    if (!morePagesRemain) {
      return null;
    }
  }
  return null;
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

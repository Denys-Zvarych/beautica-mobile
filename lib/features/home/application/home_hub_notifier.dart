// Phase 13.7 — HomeHub aggregate notifier.
//
// Exposes per-card independent AsyncValue fields so that a single failed card
// (e.g. the passport endpoint returning 404 while the profile is fine) never
// blanks the whole screen.
//
// Data-wired cards (backend already exists):
//   • profileAsync  → derived from authProvider (User) — always available.
//
// Empty-state-placeholder cards (backend 19.x not yet shipped):
//   • nextAppointmentAsync  — TODO(19.3) wire GET /bookings/me?status=PENDING,CONFIRMED&sort=startAt&size=1
//   • favoriteMastersAsync  — TODO(19.1) wire GET /favorites/masters
//   • timelineAsync         — TODO(19.5) wire GET /clients/me/timeline
//
// The client's aggregate rating (two-sided system: masters/salons rate clients)
// is derivable from GET /clients/me/rating but that endpoint is not yet shipped;
// the clientRating stat tile shows null (empty state) until then.

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../features/auth/domain/auth_session.dart';
import '../../../features/auth/domain/user.dart';
import '../../../features/auth/presentation/auth_notifier.dart';
import '../../../features/location/state/location_providers.dart';
import '../domain/home_hub_models.dart';

part 'home_hub_notifier.g.dart';

// ---------------------------------------------------------------------------
// Profile card — data-wired
// ---------------------------------------------------------------------------

/// Derives the CLIENT's [ClientProfileSummary] from the settled auth session.
/// Emits AsyncError when the session is unauthenticated (the router guard
/// should have redirected already, but defensive nonetheless).
@riverpod
Future<ClientProfileSummary> clientProfile(Ref ref) async {
  final session = await ref.watch(authProvider.future);
  return switch (session) {
    Authenticated(:final user) => ClientProfileSummary(
      firstName: user.firstName ?? '',
      lastName: user.lastName ?? '',
      // phone comes from the User profile hydrated via repo.me() during
      // cold-start / login (AuthNotifier.build → fromProfileDto); nullable
      // because CLIENT location is optional — fall back to the empty string
      // so the profile card renders its placeholder.
      city: await _resolveLocalityLabel(ref, user),
      phone: user.phoneNumber ?? '',
      // TODO(backend): GET /clients/me/rating (two-sided client rating, excludes comments)
      clientRating: null,
      memberSinceYear: DateTime.now().year,
    ),
    _ => throw StateError('clientProfile: no authenticated session'),
  };
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
// Next appointment — placeholder (backend 19.3 not ready)
// ---------------------------------------------------------------------------

/// Returns the soonest upcoming booking for the CLIENT, or null when none.
/// Currently always returns null (empty state) until the endpoint ships.
/// TODO(19.3): wire GET /bookings/me?status=PENDING,CONFIRMED&sort=startAt&size=1
@riverpod
Future<NextAppointment?> nextAppointment(Ref ref) async {
  // TODO(19.3): call bookings repository when endpoint ships.
  if (kDebugMode) {
    log(
      'nextAppointment: placeholder — backend 19.3 not ready',
      name: 'feature.home',
      level: 700,
    );
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
    ref.invalidate(favoriteMastersProvider);
    state = const AsyncData(null);
  }
}

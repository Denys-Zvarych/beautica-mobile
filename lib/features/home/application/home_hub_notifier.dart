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
// Counts of reviews are also derivable from GET /reviews/me but that endpoint
// is not yet shipped; the reviewsLeft stat tile shows a placeholder until then.

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../features/auth/domain/auth_session.dart';
import '../../../features/auth/presentation/auth_notifier.dart';
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
      // city and phone are not yet fields on the User domain model
      // (those live on the provider/user profile, not auth/me).
      // TODO(phase-19.x): replace with GET /clients/me profile endpoint.
      city: '',
      phone: '',
      reviewsLeft: 0,
      memberSinceYear: DateTime.now().year,
    ),
    _ => throw StateError('clientProfile: no authenticated session'),
  };
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

// Phase 13.8 — BEAUTY PASSPORT notifier.
//
// Exposes the CLIENT's auto-derived passport as a keep-alive FutureProvider with
// a short TTL, so hopping bottom-nav tabs back to the passport does not re-fetch
// on every visit but the data still refreshes after the window elapses.
//
// Data source: [PassportRepository.getMyPassport] → `GET /clients/me/passport`
// (backend 19.5). That endpoint is NOT yet in the committed OpenAPI client, so
// the repository is the [PlaceholderPassportRepository] which returns an empty
// passport (TODO 19.5) — mirroring how `home_hub_notifier.dart` placeholders the
// other 19.x cards. The screen therefore renders the empty-passport variant
// until the contract ships.
//
// The footer's reviews count + member-since year are part of the [Passport]
// aggregate (reviewsLeft / memberSinceYear). Until backend 19.5 supplies them
// they default to 0 / null via the placeholder, exactly like the Home Hub.

import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/passport_repository.dart';
import '../domain/passport.dart';

part 'passport_notifier.g.dart';

/// How long a fetched passport stays cached before the keep-alive link is
/// dropped, so the next read re-fetches. Derived data changes slowly (only on
/// booking completion), so a generous window avoids redundant calls.
const Duration _passportCacheTtl = Duration(minutes: 5);

/// Binds the passport repository. Swapped to an `HttpPassportRepository` once
/// backend 19.5 ships and the OpenAPI client regenerates.
/// TODO(19.5): return `HttpPassportRepository(ref.watch(clientsApiProvider))`.
@riverpod
PassportRepository passportRepository(Ref ref) =>
    const PlaceholderPassportRepository();

/// The CLIENT's auto-derived [Passport]. Kept alive with a [_passportCacheTtl]
/// TTL so tab-hopping does not re-fetch on every visit.
@riverpod
Future<Passport> passport(Ref ref) async {
  // Keep the result cached after all listeners drop, but only for the TTL —
  // then release the link so the next read re-fetches fresh derived data.
  final link = ref.keepAlive();
  final timer = Timer(_passportCacheTtl, link.close);
  ref.onDispose(timer.cancel);

  if (kDebugMode) {
    log(
      'passport: fetching via repository (placeholder until backend 19.5)',
      name: 'feature.passport',
      level: 700,
    );
  }
  return ref.watch(passportRepositoryProvider).getMyPassport();
}

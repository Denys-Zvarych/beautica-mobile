// Phase 13.8 — BEAUTY PASSPORT notifier.
//
// Exposes the CLIENT's auto-derived passport as a keep-alive FutureProvider with
// a short TTL, so hopping bottom-nav tabs back to the passport does not re-fetch
// on every visit but the data still refreshes after the window elapses.
//
// Data source: [PassportRepository.getMyPassport] → `GET /clients/me/passport`
// (backend 19.5), live via [HttpPassportRepository] over the generated
// [ClientControllerApi]. A failed fetch surfaces as a typed `Failure` in the
// [AsyncValue], which the screen renders as its error+retry state — an error is
// deliberately NOT collapsed into the empty-passport variant.
//
// The footer's reviews count + member-since year (`reviewsWritten` /
// `memberSinceYear`) ARE on the wire contract since backend 245. Neither is
// ever fabricated: an absent count maps to 0 (indistinguishable in meaning from
// "wrote none"), and an absent year is a broken payload the mapper rejects with
// a [ServerFailure] — surfaced here as the error+retry state, never as a
// synthesised current year.

import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/network/api_client_provider.dart';
import '../../auth/presentation/auth_notifier.dart';
import '../data/passport_repository.dart';
import '../domain/passport.dart';

part 'passport_notifier.g.dart';

/// How long a fetched passport stays cached before the keep-alive link is
/// dropped, so the next read re-fetches. Derived data changes slowly (only on
/// booking completion), so a generous window avoids redundant calls.
const Duration _passportCacheTtl = Duration(minutes: 5);

/// Binds the passport repository to the live `GET /clients/me/passport`
/// endpoint. Override in tests with a mocktail mock — never construct
/// [HttpPassportRepository] directly in tests.
@riverpod
PassportRepository passportRepository(Ref ref) =>
    HttpPassportRepository(ref.watch(clientApiProvider));

/// The CLIENT's auto-derived [Passport]. Kept alive with a [_passportCacheTtl]
/// TTL so tab-hopping does not re-fetch on every visit.
@riverpod
Future<Passport> passport(Ref ref) async {
  // SESSION BOUNDARY (mobile-security MEDIUM, 2026-09-17) — this provider is
  // `keepAlive` with a 5-minute TTL and its whole dependency chain
  // (`passportRepositoryProvider` → `clientApiProvider` → `dioProvider`)
  // touches nothing auth-shaped at any hop, so before this watch NOTHING
  // rebuilt it and NOTHING evicted it on logout. It is also KEYLESS: unlike
  // `effectiveScheduleProvider`, whose `ScheduleScope.masterId` re-keys a
  // session flip onto a fresh member all by itself, there is exactly one
  // member here for every account on the device. So on a shared phone the
  // next sign-in within the TTL was served the OUTGOING client's visit
  // history, member-since year and reviews-written count straight from
  // memory — no wire call, no server re-check.
  //
  // Watching the identity (rather than bare-invalidating from
  // `AuthNotifier.logout`) is self-healing: it evicts on logout, on login AND
  // on an account switch, and it needs no `auth_notifier.dart` edit — so
  // there is no back-edge from this provider into `authProvider` and no
  // `CircularDependencyError` risk (`authProvider` does not watch this).
  //
  // NARROWED through the shared [authUserIdOrNull] selector, never a bare
  // `ref.watch(authProvider)`: `Authenticated`'s freezed equality includes
  // `accessToken`, so a bare watch would also discard a live cache entry on
  // every silent token refresh. Nothing in this body reads any other part of
  // the session.
  ref.watch(authProvider.select(authUserIdOrNull));

  // Keep the result cached after all listeners drop, but only for the TTL —
  // then release the link so the next read re-fetches fresh derived data.
  final link = ref.keepAlive();
  final timer = Timer(_passportCacheTtl, link.close);
  ref.onDispose(timer.cancel);

  if (kDebugMode) {
    log(
      'passport: fetching GET /clients/me/passport',
      name: 'feature.passport',
      level: 700,
    );
  }
  return ref.watch(passportRepositoryProvider).getMyPassport();
}

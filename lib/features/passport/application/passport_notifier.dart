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
// The footer's reviews count + member-since year are part of the [Passport]
// aggregate (reviewsLeft / memberSinceYear) but are NOT on the wire contract —
// the backend record carries neither — so they keep their domain defaults
// (0 / null). The mapper does not fabricate them.

import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/network/api_client_provider.dart';
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

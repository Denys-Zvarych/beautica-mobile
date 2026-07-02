// Phase 13.6 — Salon service-catalogue loader ("Послуги" tab).
//
// A `@riverpod` family keyed on [salonId], independent of
// [publicSalonProfileProvider] so the "Послуги" tab can load/retry/error on
// its own without re-fetching the hero card or the masters rail.
//
// Cache: autoDispose by default, but [ref.keepAlive] holds the result for a
// 5-minute TTL so switching tabs away and back within the window serves the
// cached catalogue instead of re-fetching (mobile-perf MEDIUM fix, Phase 13.6
// audit — mirrors [publicSalonProfileProvider]'s TTL pattern exactly).

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/salon_repository.dart';
import '../domain/salon_service_catalog.dart';

part 'salon_service_catalog_notifier.g.dart';

/// Loads the salon's public service catalogue (already grouped + ordered
/// server-side).
///
/// Generated provider name: `salonServiceCatalogProvider` — a family, call it
/// with the target salon id.
@riverpod
Future<List<SalonServiceCategoryEntry>> salonServiceCatalog(
  Ref ref,
  String salonId,
) async {
  // 5-minute cache window. Keep the link alive across an away-and-back tab
  // switch, then close it so a stale catalogue eventually refetches. The
  // timer is cancelled on dispose so it can never fire after the provider is
  // gone.
  final link = ref.keepAlive();
  final Timer timer = Timer(const Duration(minutes: 5), link.close);
  ref.onDispose(timer.cancel);

  return ref.watch(salonRepositoryProvider).getSalonServiceCatalog(salonId);
}

// Phase 13.6 follow-up — Salon portfolio photo-rail loader ("Про салон" tab).
//
// A `@riverpod` family keyed on [salonId], independent of
// [publicSalonProfileProvider] so the "Про салон" tab's photo rail can
// load/retry/error on its own without re-fetching the hero card or the
// masters rail — mirrors [salonServiceCatalogProvider]'s independent-tab
// pattern exactly.
//
// Cache: autoDispose by default, but [ref.keepAlive] holds the result for a
// 5-minute TTL so switching tabs away and back within the window serves the
// cached gallery instead of re-fetching (mirrors the other salon tab loaders'
// TTL pattern exactly).

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/salon_repository.dart';
import '../domain/salon_portfolio_photo.dart';

part 'salon_portfolio_notifier.g.dart';

/// Loads the salon's public portfolio photo gallery.
///
/// Generated provider name: `salonPortfolioProvider` — a family, call it with
/// the target salon id.
@riverpod
Future<List<SalonPortfolioPhoto>> salonPortfolio(
  Ref ref,
  String salonId,
) async {
  // 5-minute cache window. Keep the link alive across an away-and-back tab
  // switch, then close it so a stale gallery eventually refetches. The timer
  // is cancelled on dispose so it can never fire after the provider is gone.
  final link = ref.keepAlive();
  final Timer timer = Timer(const Duration(minutes: 5), link.close);
  ref.onDispose(timer.cancel);

  return ref.watch(salonRepositoryProvider).getSalonPortfolio(salonId);
}

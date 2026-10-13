// Phase 13.6 follow-up — Salon portfolio photo-rail loader ("Про салон" tab).
//
// Phase 403 (9.8, D3) — now a THIN DELEGATE to the shared
// `portfolioProvider(PortfolioOwner.salon(salonId))` (core/media/portfolio),
// which owns the read and the shared 5-minute keepAlive TTL ([kPortfolioCacheTtl]).
// Behaviour for `public_salon_profile_screen` is unchanged: same repository
// read (`SalonRepository.getSalonPortfolio`), same cache window.
//
// This is a salon screen's provider, so it is an allowed construction site of
// `PortfolioOwner.salon` (D9 — pinned by
// `test/core/media/portfolio/portfolio_owner_call_sites_test.dart`).

import 'package:beautica_mobile/core/media/portfolio/portfolio_notifier.dart';
import 'package:beautica_mobile/core/media/portfolio/portfolio_owner.dart';
import 'package:beautica_mobile/core/media/portfolio/portfolio_photo.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'salon_portfolio_notifier.g.dart';

/// Loads the salon's public portfolio photo gallery.
///
/// Generated provider name: `salonPortfolioProvider` — a family, call it with
/// the target salon id.
@riverpod
Future<List<PortfolioPhoto>> salonPortfolio(Ref ref, String salonId) {
  // The delegate keeps the SAME TTL window: were it disposed on tab-away, the
  // re-created delegate would paint one AsyncLoading frame before reading the
  // still-cached shared value — a change from the pre-403 instant cache hit.
  // It watches the shared provider's `.future`, so an upload / delete — the
  // controller's local prepend / remove, or its invalidate fallback — reaches
  // it while it is alive (pinned by portfolio_edit_controller_test).
  keepAliveFor(ref, ref.read(portfolioCacheTtlProvider));
  return ref.watch(portfolioProvider(PortfolioOwner.salon(salonId)).future);
}

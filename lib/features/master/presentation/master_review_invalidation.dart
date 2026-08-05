// The ONE fan-out point for "a review about this master was written".
//
// Deliberately its OWN file rather than a helper inside
// `leave_review_notifier.dart` or any of the three master notifiers. Two
// reasons, one architectural and one mechanical — the same pair that put
// `services/presentation/service_catalogue_invalidation.dart` in its own file:
//
//   • It is a different concern. Each notifier owns ONE provider's lifecycle;
//     this owns the cross-provider consequence of a MUTATION, and it will grow
//     a fourth entry the day a fourth surface caches the master's rating.
//   • `scripts/forbid_provider_self_invalidation.sh` flags cross-provider
//     `ref.invalidate` inside a notifier file, and correctly so — that pattern
//     really can close a watch cycle. Its scope is purely a filename glob
//     (`find lib -type f -name '*notifier*.dart'`, line 197) — nothing about
//     the ref type or the enclosing class. So this file is exempt for one
//     reason only: `master_review_invalidation.dart` does not contain
//     `notifier`. The identical body pasted into `leave_review_notifier.dart`
//     WOULD trip it. Keeping it here keeps that guard's signal honest instead
//     of spending a `// cycle-safe:` waiver on a false positive.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/features/master/application/master_review_summary_notifier.dart';
import 'package:beautica_mobile/features/master/application/master_reviews_notifier.dart';
import 'package:beautica_mobile/features/master/application/public_master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master_review.dart';

/// Invalidates EVERY cached surface that renders [masterId]'s review data.
///
/// There are three, and they are independent fetches by design (each has its
/// own `keepAlive` + 5-minute TTL so a push/pop does not refetch):
///   • [publicMasterProfileProvider] — carries `avgRating` / `reviewCount` in
///     the identity card and the stats row.
///   • [masterReviewSummaryProvider] — the aggregate average + 5★→1★
///     distribution above the review list.
///   • [masterReviewsProvider] — the first page of received reviews.
///
/// Call this after a review is created instead of invalidating any one of them
/// directly. Phase 14.6 shipped the leave-review flow invalidating ONLY
/// `bookingDetailProvider`, so a client who left a review and re-opened the
/// master's public profile without killing the app saw neither the new review
/// nor a moved rating — it self-healed after the 5-minute TTL or a cold start,
/// which is exactly the shape that makes it look intermittent. One function is
/// what stops the next mutation site from reintroducing that.
///
/// The per-sort loop is REQUIRED, not defensive: [masterReviewsProvider] is a
/// family keyed on BOTH the master id and the [MasterReviewSort]
/// (`master_reviews_notifier.dart`), so each `(masterId, sort)` pair is its own
/// cache entry. Invalidating only `newest` would leave a client who had
/// switched to «Найвищий рейтинг» looking at a page that still predates their
/// own review.
///
/// Cost: one refetch per LIVE subscriber, not one per entry. The sort buckets
/// the user never opened have no listeners, and an invalidated `keepAlive`
/// provider with no listeners simply drops its state and rebuilds on the next
/// read — so the loop is free in the common case where at most one sort is
/// on-screen.
///
/// Salon-side scope note: `publicSalonProfileProvider` /
/// `salonReviewSummaryProvider` / `salonReviewsProvider` carry the IDENTICAL
/// staleness, but `Booking` exposes no `salonId`, so wiring them needs a domain
/// change and is tracked separately. Add them here — not at a new call site —
/// once that field exists.
void invalidateMasterReviewSurfaces(WidgetRef ref, String masterId) {
  ref.invalidate(publicMasterProfileProvider(masterId));
  ref.invalidate(masterReviewSummaryProvider(masterId));
  for (final MasterReviewSort sort in MasterReviewSort.values) {
    ref.invalidate(masterReviewsProvider(masterId, sort));
  }
}

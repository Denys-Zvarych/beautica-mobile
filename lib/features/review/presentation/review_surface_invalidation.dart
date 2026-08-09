// The ONE fan-out point for "a review was written" — both halves of it.
//
// A review about a SALON-employed master moves TWO sets of aggregates: the
// master's own, and the salon's (`ReviewEventListener` recalculates both before
// the 201 returns). Each side has three independent client-side caches, so this
// file holds two functions rather than one: [invalidateMasterReviewSurfaces]
// always applies, [invalidateSalonReviewSurfaces] only when the booking carries
// a salon.
//
// "Three caches" counts PROVIDERS, not requests. On the salon side a single
// `publicSalonProfileProvider` invalidation costs TWO HTTP calls
// (`getSalonById` + `getSalonMasters` — the masters rail carries the reviewed
// master's own `avgRating`, so it genuinely has to move too), making the salon
// fan-out 4 requests on the wire rather than 3. Measured by `mobile-perf`,
// 2026-08-06.
//
// WHY THIS FILE LIVES IN `features/review/presentation/` (phase 233)
// ------------------------------------------------------------------
// It was `features/master/presentation/master_review_invalidation.dart` until
// the salon half landed, at which point a `master_*` file reaching into
// `features/salon/application/` was a name that lied. The concern is neither
// feature's — it is the cross-provider consequence of ONE mutation (a review),
// and `features/review/` is where that mutation's other UI pieces already live.
// It stays out of `leave_review_notifier.dart` and out of the six notifiers it
// invalidates for the same reason it always did: each notifier owns exactly ONE
// provider's lifecycle, while this owns the blast radius of a write, and it will
// grow a seventh entry the day a seventh surface caches a rating.
//
// ⚠️ THE FILENAME IS LOAD-BEARING — it must not contain `notifier`.
// `scripts/forbid_provider_self_invalidation.sh` flags cross-provider
// `ref.invalidate` inside notifier files, and correctly so: that pattern really
// can close a watch cycle. Its scope is PURELY a filename glob
// (`find lib -type f -name '*notifier*.dart'`, line 197) — it inspects neither
// the ref type nor the enclosing class. So this file is exempt for exactly one
// reason: `review_surface_invalidation.dart` does not contain `notifier`. The
// identical body pasted into any `*notifier*.dart` WOULD trip it.
//
// Do NOT restate the older rationale that this is exempt because it "takes a
// `WidgetRef`, so it structurally cannot run inside a Notifier". That claim is
// false twice over — the guard never looks at the ref type, and nothing stops a
// `WidgetRef` from being passed into a plain function called from anywhere.
// Renaming this file to something containing `notifier` would silently move it
// INTO the guard's scope; any other name keeps it out. That is the whole
// mechanism.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/features/master/application/master_review_summary_notifier.dart';
import 'package:beautica_mobile/features/master/application/master_reviews_notifier.dart';
import 'package:beautica_mobile/features/master/application/public_master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master_review.dart';
import 'package:beautica_mobile/features/salon/application/public_salon_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_review_summary_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_reviews_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon_review.dart';

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
/// Cost: one refetch per LIVE subscriber, not one per entry — MEASURED against
/// the locked `riverpod 3.1.0`, not inferred. Invalidating all 6 entries with
/// one on-screen issues **0** network calls at fan-out time and 4 on resume;
/// never 6, and 0 forever if the client never reopens the salon.
///
/// Two distinct mechanisms, worth stating precisely because the imprecise
/// version has already misled this codebase:
///   • A bucket the user opened earlier and switched away from is a `keepAlive`
///     entry with NO listeners. It is DISPOSED and removed from the container —
///     not merely "state-dropped": `invalidateSelf` nulls `_keepAliveLinks` in
///     `runOnDispose()` before `mayNeedDispose()`, so the link stops protecting
///     it. It is never refetched.
///   • A bucket the user never opened has no element at all, so the call is a
///     null-guarded map lookup.
///   • The on-screen-but-COVERED entries are NOT disposed — `hasNonWeakListeners`
///     counts paused subscriptions — they are retained and dirty, and refetch
///     once on resume. See `project_riverpod_offstage_pause_invalidate`.
void invalidateMasterReviewSurfaces(WidgetRef ref, String masterId) {
  ref.invalidate(publicMasterProfileProvider(masterId));
  ref.invalidate(masterReviewSummaryProvider(masterId));
  for (final MasterReviewSort sort in MasterReviewSort.values) {
    ref.invalidate(masterReviewsProvider(masterId, sort));
  }
}

/// Invalidates EVERY cached surface that renders [salonId]'s review data.
///
/// The exact salon-side mirror of [invalidateMasterReviewSurfaces], and it
/// exists because a review of a salon-employed master moves the SALON's
/// aggregates too. Three caches, each with its own `keepAlive` + 5-minute TTL:
///   • [publicSalonProfileProvider] — the hero card's `avgRating` /
///     `reviewCount` (and the masters rail it loads alongside them).
///   • [salonReviewSummaryProvider] — the aggregate + 5★→1★ distribution at the
///     head of the «Відгуки» tab.
///   • [salonReviewsProvider] — the first page of the salon's reviews.
///
/// Call it from the review-submit success branch, GUARDED on a non-null salon
/// id: an `INDEPENDENT_MASTER` booking legitimately has no salon, and that null
/// is a normal state rather than a broken payload (see `Booking.salonId`).
///
/// The backend needs no help here — `ReviewEventListener` recalculates
/// `salons.avg_rating` / `review_count` and evicts `salon-detail` plus every
/// `reviews-by-salon` page before the `201` returns. This is purely the
/// client's own cache going stale behind those three `keepAlive` timers, which
/// is why the symptom reads as intermittent: it self-heals on TTL expiry.
///
/// The per-sort loop is REQUIRED, not defensive — same mechanism as the master
/// side. [salonReviewsProvider] is a family keyed on BOTH [salonId] and the
/// [SalonReviewSort] (`salon_reviews_notifier.dart`), and
/// `salon_reviews_section.dart` watches it with a LOCALLY-held sort, so a
/// client who had switched to «Найвищий рейтинг» would otherwise land on a page
/// that predates their own review. Invalidating only `newest` leaves the other
/// three buckets green-by-cache.
///
/// Deliberately NOT a family-wide `ref.invalidate(publicSalonProfileProvider)`:
/// that drops every cached salon rather than the one reviewed, makes any other
/// salon screen sitting on the stack refetch for nothing, and would silently
/// over-invalidate forever with no compile-time signal when a fourth
/// salon-keyed cache appears for an unrelated reason. See phase 233 § 4.
void invalidateSalonReviewSurfaces(WidgetRef ref, String salonId) {
  ref.invalidate(publicSalonProfileProvider(salonId));
  ref.invalidate(salonReviewSummaryProvider(salonId));
  for (final SalonReviewSort sort in SalonReviewSort.values) {
    ref.invalidate(salonReviewsProvider(salonId, sort));
  }
}

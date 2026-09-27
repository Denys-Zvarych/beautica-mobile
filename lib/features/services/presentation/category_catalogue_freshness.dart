// 2026-09-13 audit (M8, mobile-perf LOW) — the freshness stamp for the two
// APP-WIDE category caches.
//
// [approvedCategoriesProvider] and [serviceTypesProvider] are ROOT-scoped and
// `keepAlive` — one cache for the whole session, shared by the master's own
// services screen, the service form's category picker and the client-side
// discovery filters. `ServicesListScreen` used to bust BOTH of them
// unconditionally on every mount AND on every pop-back from the setup / edit
// flows, so a salon operator's `staff profile → services → edit → back → edit
// → back` sitting cost three `GET /service-categories/approved` round trips
// (plus three service-type fetches) for a list that changes only when an
// ADMIN approves a category server-side — an event measured in days, not
// seconds.
//
// The screen's own reason for busting them is still valid; only its CADENCE
// was wrong. This notifier holds the instant of the last bust so the screen
// can collapse its two entry points into a single guarded path
// (`_refreshCategoryCataloguesIfStale`) that refreshes at most once per
// [kCategoryCatalogueFreshFor]. Pull-to-refresh stays UNCONDITIONAL — that is
// an explicit user request for fresh data, not an incidental remount — and
// stamps this notifier too, so re-entering the screen right after a pull does
// not immediately bust the cache again.
//
// `keepAlive: true` for the same reason the two caches it guards are: the
// stamp must outlive the screen, otherwise every remount would see a null
// stamp and the guard would be a no-op. It is root-scoped and therefore
// SHARED with the salon-scoped `ProviderScope`s in `app_router.dart` — which
// is correct: the caches it guards are root-scoped too, so the salon-scoped
// screens bust exactly the same app-wide rows.
//
// The instant comes from [clockProvider], never a raw `DateTime.now()`, so
// tests pin it the same way every other time-sensitive surface in this app
// does.

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'category_catalogue_freshness.g.dart';

/// How long a category-catalogue read stays "fresh enough" that re-entering
/// the services surface must NOT bust it.
///
/// Five minutes: long enough that an in-app drill-in/back sitting costs one
/// fetch instead of N, short enough that a master who asks an admin to
/// approve a category and waits sees it without a cold restart (and
/// pull-to-refresh gets it immediately regardless).
const Duration kCategoryCatalogueFreshFor = Duration(minutes: 5);

/// The instant [approvedCategoriesProvider] / [serviceTypesProvider] were last
/// invalidated by a services surface, or `null` if never in this session.
@Riverpod(keepAlive: true)
class CategoryCatalogueFreshness extends _$CategoryCatalogueFreshness {
  @override
  DateTime? build() => null;

  /// Records that the caches were just busted at [at].
  void stamp(DateTime at) => state = at;

  /// Whether a bust at [now] is due. `true` when nothing has been stamped yet
  /// (first entry of the session) or the stamp is older than
  /// [kCategoryCatalogueFreshFor].
  ///
  /// A read, not a mutation — callers [stamp] separately so the decision and
  /// the side effect stay visible at the call site.
  bool isStaleAt(DateTime now) {
    final DateTime? last = state;
    if (last == null) return true;
    // instant-ok: a cache-age comparison between two absolute instants — this
    // is deliberately NOT a calendar-day question, so `kyivToday` does not
    // apply.
    return now.difference(last) >= kCategoryCatalogueFreshFor;
  }
}

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
// was wrong. This notifier holds the instant of the last successful refresh so
// the entry points can be throttled, on two cadences:
//
//  * OPEN paths (services list entry, service setup open, service edit open)
//    use the 30 s floor [kCategoryEntryFloor] via
//    [refreshCategoryCataloguesIfOlderThan]: skipped inside the floor or while
//    a fetch is in flight.
//  * The pop-back from the setup / edit flows uses the 5-minute throttle
//    [kCategoryCatalogueFreshFor].
//
// Pull-to-refresh stays UNCONDITIONAL — that is an explicit user request for
// fresh data, not an incidental remount — and stamps this notifier too, so
// re-entering the screen right after a pull does not immediately bust the
// cache again.
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

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart' show WidgetRef;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/presentation/service_types_provider.dart';

part 'category_catalogue_freshness.g.dart';

/// How long a category-catalogue read stays "fresh enough" that re-entering
/// the services surface must NOT bust it.
///
/// Five minutes: long enough that an in-app drill-in/back sitting costs one
/// fetch instead of N, short enough that a master who asks an admin to
/// approve a category and waits sees it without a cold restart (and
/// pull-to-refresh gets it immediately regardless).
const Duration kCategoryCatalogueFreshFor = Duration(minutes: 5);

/// Floor for the services-surface OPEN paths («Мої послуги» entry, service
/// setup open, service edit open): opening any of them within this window of
/// the last successful refresh — or while a fetch is already in flight — does
/// NOT fetch again. Pull-to-refresh ignores it.
const Duration kCategoryEntryFloor = Duration(seconds: 30);

/// Unconditionally drops both app-wide category caches and records the
/// freshness stamp once the refreshed approved-category read SUCCEEDS (a
/// failed read leaves the stamp alone so the next open retries).
///
/// Everything touched after the `await` is captured BEFORE it, so a screen
/// disposed mid-flight cannot make this touch a dead `ref`.
void refreshCategoryCatalogues(WidgetRef ref) {
  final DateTime now = ref.read(clockProvider)();
  final CategoryCatalogueFreshness stamper = ref.read(
    categoryCatalogueFreshnessProvider.notifier,
  );
  ref.invalidate(approvedCategoriesProvider);
  // A type newly approved under an EXISTING category must appear too.
  ref.invalidate(serviceTypesProvider);
  final Future<Object?> read = ref.read(approvedCategoriesProvider.future);
  unawaited(read.then<void>((_) => stamper.stamp(now), onError: (Object _) {}));
}

/// [refreshCategoryCatalogues], skipped when the last successful refresh is
/// younger than [floor] or a category fetch is already in flight. Returns
/// whether it refreshed.
bool refreshCategoryCataloguesIfOlderThan(WidgetRef ref, Duration floor) {
  // `exists` first: a cold provider is not "in flight", and reading it here
  // would itself start the fetch and then wrongly skip the refresh.
  if (ref.exists(approvedCategoriesProvider) &&
      ref.read(approvedCategoriesProvider).isLoading) {
    return false;
  }
  final DateTime? last = ref.read(categoryCatalogueFreshnessProvider);
  // instant-ok: cache-age comparison between two absolute instants, not a
  // calendar-day question.
  if (last != null && ref.read(clockProvider)().difference(last) < floor) {
    return false;
  }
  refreshCategoryCatalogues(ref);
  return true;
}

/// The instant [approvedCategoriesProvider] / [serviceTypesProvider] were last
/// invalidated by a services surface, or `null` if never in this session.
@Riverpod(keepAlive: true)
class CategoryCatalogueFreshness extends _$CategoryCatalogueFreshness {
  @override
  DateTime? build() => null;

  /// Records that the caches were just busted at [at].
  void stamp(DateTime at) => state = at;
}

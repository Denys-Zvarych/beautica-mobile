// Stale-cache regression — ServicesListScreen invalidates the serviceTypes
// family on every refresh surface (entry / pop-back / pull-to-refresh).
//
// The bug: a service type approved out-of-band by an admin under an EXISTING
// category never appeared in the "Тип послуги" dropdown, because the
// serviceTypes(category) family was pinned alive (keepAlive + 3-min Timer) and
// never re-fetched on picker re-entry.
//
// The fix added `ref.invalidate(serviceTypesProvider)` (whole family) alongside
// the existing approvedCategoriesProvider invalidations at THREE sites in
// [ServicesListScreen]:
//   1. initState (first entry),
//   2. _openAndRefresh (return from a pushed route — create / edit flows),
//   3. RefreshIndicator.onRefresh (pull-to-refresh).
//
// These tests pin sites (1) and (3) by attaching a live listener to a specific
// family key (so the family actually fetches), then asserting the screen
// re-issues `fetchServiceTypes(category)` for that key. They guard against
// someone re-adding keepAlive or dropping an invalidation call.
//
// Strategy:
//   • Build a real [ProviderContainer] with the repository mocked, host the
//     screen under an [UncontrolledProviderScope] so the test owns the
//     container and can attach a listener / count fetches on it.
//   • Keep a live subscription on serviceTypesProvider('HAIRCUT') for the whole
//     test so each invalidation triggers a real re-fetch we can verify.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/domain/service_type_option.dart';
import 'package:beautica_mobile/features/services/presentation/category_catalogue_freshness.dart';
import 'package:beautica_mobile/features/services/presentation/service_types_provider.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

// ── Mocks ──────────────────────────────────────────────────────────────────

class _MockServiceRepository extends Mock implements ServiceRepository {}

// ── Stub data ────────────────────────────────────────────────────────────────

const _hairTypes = <ServiceTypeOption>[
  ServiceTypeOption(
    id: 'type-1',
    slug: 'WOMENS_CUT',
    nameUk: 'Жіноча стрижка',
    categoryName: 'HAIRCUT',
  ),
];

const _populatedService = MasterService(
  id: 'svc-001',
  serviceDefId: 'def-001',
  name: 'Стрижка',
  durationMinutes: 45,
  priceMin: 750,
  priceDisplay: '750 ₴',
  category: 'HAIRCUT',
);

// ── Stub notifier ─────────────────────────────────────────────────────────────

/// Resolves [servicesListProvider] to a data state after one loading frame.
class _StubServicesList extends ServicesList {
  _StubServicesList(this._target);

  final List<MasterService> _target;

  @override
  Future<List<MasterService>> build() {
    Future<void>.microtask(() => state = AsyncData(_target));
    return Completer<List<MasterService>>().future;
  }
}

/// Resolves [servicesListProvider] to an ERROR state after one loading frame.
///
/// AUDIT cycle-3 (C2) — drives the screen into the arm that renders
/// `_errorScrollable(ErrorState(...))`, the ONE arm in which nothing watches
/// [approvedCategoriesProvider].
///
/// `UnauthorizedFailure` is NON-retryable under `beauticaProviderRetry` for
/// the same reason the categories override uses it: a retryable failure would
/// cycle through `AsyncLoading(retrying: true)` on a timer that outlives the
/// test. (The state is assigned directly rather than thrown from `build`, so
/// the retry policy would not fire either way — this is belt AND braces.)
class _ErroringServicesList extends ServicesList {
  @override
  Future<List<MasterService>> build() {
    Future<void>.microtask(
      () => state = const AsyncError<List<MasterService>>(
        UnauthorizedFailure(),
        StackTrace.empty,
      ),
    );
    return Completer<List<MasterService>>().future;
  }
}

void main() {
  late _MockServiceRepository repo;

  /// When true, the [approvedCategoriesProvider] override THROWS — used by the
  /// N1 case to reproduce a failed category refresh.
  late bool categoriesFail;

  /// AUDIT cycle-3 (C2) — how many times the [approvedCategoriesProvider]
  /// override body has RUN, i.e. how many category reads the screen caused.
  /// Counted on the override itself rather than on `repo`, because that
  /// provider fetches directly and never goes through the repository.
  late int categoriesFetches;

  setUp(() {
    categoriesFail = false;
    categoriesFetches = 0;
    repo = _MockServiceRepository();
    when(
      () => repo.listMyServices(),
    ).thenAnswer((_) async => const <MasterService>[_populatedService]);
    // approvedCategoriesProvider fetches DIRECTLY now (not through the
    // repository), so it is overridden in pumpScreen() rather than stubbed here.
    when(
      () => repo.fetchServiceTypes('HAIRCUT'),
    ).thenAnswer((_) async => _hairTypes);
  });

  /// Builds a container the test owns, hosts [ServicesListScreen] under an
  /// [UncontrolledProviderScope], and keeps a live listener on the
  /// serviceTypes('HAIRCUT') key so every family invalidation re-fetches.
  Future<ProviderContainer> pumpScreen(
    WidgetTester tester, {
    // 2026-09-13 audit (M8) — the entry/pop-back refresh is now rate-limited
    // by `kCategoryCatalogueFreshFor`, read off `clockProvider`. `null` keeps
    // the default real clock, under which a fresh container always has a null
    // stamp and therefore always refreshes on first entry — so every
    // pre-existing test in this file is unaffected.
    DateTime Function()? clock,
    ProviderContainer? reuse,
    // AUDIT cycle-3 (C2) — additive and defaulted `false`, so every
    // pre-existing row in this file resolves to the same data state it always
    // did.
    bool servicesFail = false,
  }) async {
    final container =
        reuse ??
        ProviderContainer(
          retry: beauticaProviderRetry,
          overrides: [
            if (clock != null) clockProvider.overrideWithValue(clock),
            serviceRepositoryProvider.overrideWithValue(repo),
            // approvedCategoriesProvider fetches directly; override it so the list's
            // category labels resolve without hitting the un-stubbed real fetch.
            approvedCategoriesProvider.overrideWith((ref) async {
              categoriesFetches++;
              // `UnauthorizedFailure` is NON-retryable under
              // `beauticaProviderRetry` — a retryable failure would cycle
              // through `AsyncLoading(retrying: true)` on a timer that
              // outlives the test and race the assertion.
              if (categoriesFail) throw const UnauthorizedFailure();
              return const <ServiceCategoryOption>[
                ServiceCategoryOption(name: 'HAIRCUT', displayName: 'Стрижка'),
              ];
            }),
            servicesListProvider.overrideWith(
              servicesFail
                  ? _ErroringServicesList.new
                  : () => _StubServicesList(const <MasterService>[
                      _populatedService,
                    ]),
            ),
          ],
        );
    if (reuse == null) addTearDown(container.dispose);

    // Keep the family key alive for the whole test: the screen invalidates the
    // family, but a fetch only fires when something watches it (the picker, in
    // production). This listener stands in for that picker subscription.
    if (reuse == null) {
      final sub = container.listen(serviceTypesProvider('HAIRCUT'), (_, _) {});
      addTearDown(sub.close);
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('uk'),
          home: ServicesListScreen(),
        ),
      ),
    );
    return container;
  }

  // ── 1. initState (first entry) invalidates the family ───────────────────────
  //
  // The post-frame callback in initState invalidates serviceTypesProvider. With
  // a live listener on 'HAIRCUT', that invalidation forces a re-fetch — so the
  // initial fetch (from the listener attaching) PLUS the entry invalidation =
  // at least two calls. Pre-fix (no initState invalidate of serviceTypes) this
  // would be exactly one.
  testWidgets(
    'REGRESSION: initState invalidates serviceTypes family — fetch re-issued '
    'on entry',
    (tester) async {
      await pumpScreen(tester);
      // Loading frame → microtask data → data frame → post-frame invalidation.
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      verify(
        () => repo.fetchServiceTypes('HAIRCUT'),
      ).called(greaterThanOrEqualTo(2));
    },
  );

  // ── 2. pull-to-refresh invalidates the family ───────────────────────────────
  //
  // RefreshIndicator.onRefresh invalidates serviceTypesProvider (whole family)
  // alongside approvedCategoriesProvider. Triggering the pull must re-issue
  // fetchServiceTypes('HAIRCUT') beyond the entry calls. This guards the
  // pull-to-refresh surface against a dropped invalidation / re-added keepAlive.
  testWidgets(
    'REGRESSION: pull-to-refresh invalidates serviceTypes family — fetch '
    're-issued for the active category',
    (tester) async {
      await pumpScreen(tester);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      // Baseline: consume (and reset) the fetch counter for the entry calls so
      // the post-pull verify counts ONLY fetches issued by the refresh.
      // (mocktail's verify() clears the recorded invocations it matches.)
      verify(() => repo.fetchServiceTypes('HAIRCUT')).called(greaterThan(0));

      // Drag down to trigger the RefreshIndicator. The loaded body is a
      // ListView; an overscroll drag from the top fires onRefresh.
      await tester.fling(
        find.byType(Scrollable).first,
        const Offset(0, 400),
        1000,
      );
      await tester.pump(); // start the indicator
      await tester.pump(const Duration(seconds: 1)); // settle the refresh
      await tester.pumpAndSettle();

      // The pull-to-refresh invalidation must have re-issued at least one fetch
      // for the active category since the baseline verify reset the counter.
      // Pre-fix (no serviceTypes invalidate in onRefresh) this would be zero.
      verify(
        () => repo.fetchServiceTypes('HAIRCUT'),
      ).called(greaterThanOrEqualTo(1));
    },
  );

  // ── 3. the entry refresh is RATE-LIMITED (2026-09-13 audit, M8) ────────────
  //
  // `approvedCategoriesProvider` and `serviceTypesProvider` are ROOT-scoped
  // `keepAlive` caches shared app-wide. `ServicesListScreen` used to bust both
  // on EVERY mount and EVERY pop-back, so an operator's
  // `services → edit → back → edit → back` sitting cost three app-wide
  // category fetches for a list that only changes when an ADMIN approves a
  // category server-side.
  //
  // Sites 1 and 2 above still hold — the guard changes the CADENCE, not the
  // behaviour. These two rows pin the cadence itself, in both directions, so
  // "always refresh" and "never refresh" are each a red build.
  group('entry refresh is rate-limited by kCategoryCatalogueFreshFor', () {
    testWidgets(
      'a REMOUNT inside the freshness window does NOT bust the caches again',
      (tester) async {
        DateTime now = DateTime.utc(2026, 9, 13, 12);
        final container = await pumpScreen(tester, clock: () => now);
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        // Baseline: consume the first-entry fetches (mocktail's verify clears
        // the invocations it matches).
        verify(() => repo.fetchServiceTypes('HAIRCUT')).called(greaterThan(0));

        // Leave the screen and come straight back, one minute later — well
        // inside the five-minute window.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        now = now.add(const Duration(minutes: 1));
        await pumpScreen(tester, clock: () => now, reuse: container);
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        verifyNever(() => repo.fetchServiceTypes('HAIRCUT'));
      },
    );

    testWidgets(
      'a REMOUNT after the freshness window HAS expired busts them again',
      (tester) async {
        DateTime now = DateTime.utc(2026, 9, 13, 12);
        final container = await pumpScreen(tester, clock: () => now);
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        verify(() => repo.fetchServiceTypes('HAIRCUT')).called(greaterThan(0));

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        // One second PAST the window — the smallest step that must flip it,
        // so the assertion cannot pass on a wildly different threshold.
        now = now.add(kCategoryCatalogueFreshFor + const Duration(seconds: 1));
        await pumpScreen(tester, clock: () => now, reuse: container);
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        verify(
          () => repo.fetchServiceTypes('HAIRCUT'),
        ).called(greaterThanOrEqualTo(1));
      },
    );

    // ── AUDIT cycle-2 (N1, mobile-perf LOW) ────────────────────────────────
    //
    // The stamp must land on SUCCESS ONLY. While it was written EAGERLY (before
    // the invalidations), a FAILED category refresh still marked the caches
    // fresh for five minutes: the screen showed humanized-slug fallback labels
    // with no automatic retry, and pull-to-refresh was the only escape.
    //
    // Anti-vacuity: the row above ('a REMOUNT inside the freshness window does
    // NOT bust the caches again') is the mirror — same clock step, same reuse,
    // SUCCEEDING first entry — and asserts `verifyNever`. So this row cannot
    // pass by the guard being broken in general; it passes only when the guard
    // distinguishes a failed refresh from a successful one.
    testWidgets(
      'a FAILED refresh does NOT stamp — the very next entry inside the '
      'window retries instead of waiting out the window',
      (tester) async {
        categoriesFail = true;
        DateTime now = DateTime.utc(2026, 9, 13, 12);
        final container = await pumpScreen(tester, clock: () => now);
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        // Baseline: consume the first-entry fetches.
        verify(() => repo.fetchServiceTypes('HAIRCUT')).called(greaterThan(0));

        // Leave and come straight back one minute later — well INSIDE the
        // five-minute window. The first refresh failed, so the caches are
        // still stale and the guard must let this entry through.
        categoriesFail = false;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        now = now.add(const Duration(minutes: 1));
        await pumpScreen(tester, clock: () => now, reuse: container);
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        verify(
          () => repo.fetchServiceTypes('HAIRCUT'),
        ).called(greaterThanOrEqualTo(1));
      },
    );

    // ── AUDIT cycle-3 (C2, mobile-perf LOW) ──────────────────────────────
    //
    // `_stampWhenRefreshSucceeds` does `await ref.read(
    // approvedCategoriesProvider.future)`. In the LOADED arm that read costs
    // nothing extra — `_LoadedBody` watches the same provider on every build.
    // In the ERROR arm nothing watches it at all, so the read is a NET-NEW
    // request in the one state that previously issued zero.
    //
    // That cost is ACCEPTED DELIBERATELY (see the helper's own doc): dropping
    // the read is the cycle-2 N1 bug through a side door, because the stamp
    // would have to go back to being eager or stop landing at all. What was
    // missing was a PIN, so the count is nailed to exactly one here — 0 (the
    // read scoped away, N1 back) and 2 (a second read added) are each red.
    //
    // Anti-vacuity: the count is read off the `approvedCategoriesProvider`
    // OVERRIDE BODY, not off a widget field and not off `repo` (that provider
    // fetches directly and never touches the repository), and the error
    // scaffold is asserted present in the same row — so the number cannot be
    // one collected from a loaded body that quietly mounted instead.
    testWidgets(
      'the ERROR state issues EXACTLY ONE category read — the deliberate '
      'net-new request, neither dropped nor doubled',
      (tester) async {
        DateTime now = DateTime.utc(2026, 9, 13, 12);
        final container = await pumpScreen(
          tester,
          clock: () => now,
          servicesFail: true,
        );
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        // The arm under test really is the error arm: no `_LoadedBody`, so
        // nothing on screen watches `approvedCategoriesProvider`.
        expect(
          find.byKey(const Key('services_error_state')),
          findsOneWidget,
          reason:
              'without this the count below could have been collected from a '
              'loaded body, which watches the provider anyway',
        );

        expect(
          categoriesFetches,
          1,
          reason:
              'the error arm must issue exactly the one deliberate stamp read '
              '— 0 means the read was scoped out of this arm (and the freshness '
              'stamp can no longer distinguish a failed refresh from a '
              'successful one, i.e. N1 is back), 2 means a second fetch crept in',
        );

        // The cap holds across a remount too: the first entry SUCCEEDED, so
        // the stamp landed and a re-entry one minute later must not read
        // again. Without this half, "exactly one" would say nothing about the
        // rate limit still applying in the error arm.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        now = now.add(const Duration(minutes: 1));
        await pumpScreen(
          tester,
          clock: () => now,
          reuse: container,
          servicesFail: true,
        );
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        expect(
          categoriesFetches,
          1,
          reason:
              'a remount inside kCategoryCatalogueFreshFor must not issue a '
              'second category read, error arm included',
        );
      },
    );
  });
}

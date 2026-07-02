// Phase 13.6 audit fix — keepAlive TTL regression tests for the three "tab"
// providers behind the public salon profile screen's "Послуги" and "Відгуки"
// tabs: [salonServiceCatalogProvider], [salonReviewSummaryProvider], and the
// (salonId, sort)-keyed [salonReviewsProvider] family.
//
// Before this fix, these three providers were plain `autoDispose` families:
// switching away from a tab (unmounting its Consumer) dropped the provider
// immediately, so switching BACK to the tab re-fetched from the repository
// every time. [publicSalonProfileProvider] already carried a 5-minute
// `ref.keepAlive()` + release-[Timer] pattern for exactly this reason; this
// pass copies the identical idiom onto the three tab providers.
//
// Mirrors the "bounded keepAlive cache (revisit regression)" idiom already
// proven for the schedule feature
// (test/features/schedule/presentation/master_schedule_screen_test.dart) and
// the `_drainKeepAliveTimers` helper in day_hours_sheet_test.dart: a single
// [ProviderContainer] persists for the whole test (via
// [UncontrolledProviderScope], which — unlike a normal [ProviderScope] —
// never disposes the container on its own), while the WATCHING widget
// subtree is mounted and unmounted across successive `pumpWidget` calls to
// simulate a tab switching away and back. [WidgetTester.pump] advances the
// SAME fake-async clock the provider's release [Timer] runs on, so advancing
// past the 5-minute TTL deterministically fires the release without a real
// wait.
//
//   • away-and-back WITHIN the TTL → repository called exactly once (cache
//     hit — this is the behaviour the fix adds).
//   • away-and-back AFTER the TTL elapses while unmounted → repository
//     called twice (the cache is bounded, not eternal).

import 'package:beautica_mobile/features/salon/application/salon_review_summary_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_reviews_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_service_catalog_notifier.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:beautica_mobile/features/salon/domain/salon_review.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockSalonRepository extends Mock implements SalonRepository {}

const String _kSalonId = 'salon-1';

const _catalog = <SalonServiceCategoryEntry>[
  SalonServiceCategoryEntry(
    category: 'Манікюр',
    displayName: 'Манікюр',
    count: 1,
    services: <SalonCatalogService>[
      SalonCatalogService(
        id: 'svc-1',
        name: 'Манікюр з покриттям',
        durationLabel: '1 год 30 хв',
        priceDisplay: '500 грн',
      ),
    ],
  ),
];

const _summary = SalonReviewSummary(
  avgRating: 4.7,
  reviewCount: 12,
  distribution: <int>[8, 2, 1, 1, 0],
);

final _reviews = <SalonReviewItem>[
  SalonReviewItem(
    id: 'review-1',
    masterId: 'master-1',
    masterName: 'Олена Ковальчук',
    clientDisplayName: 'Марія К.',
    rating: 5,
    comment: 'Чудово!',
    createdAt: DateTime(2026, 1, 1),
  ),
];

/// Mounts (or unmounts) a `ref.watch` (performed by [watch]) inside the SAME
/// [container], simulating a tab becoming visible/hidden without tearing
/// down the container itself (mirrors a real screen's persistent
/// `ProviderScope` across a tab switch). Takes a watcher callback rather than
/// a bare `ProviderListenable` so callers don't need to name that (unexported
/// by `flutter_riverpod`) type.
Future<void> _mount(
  WidgetTester tester,
  ProviderContainer container,
  void Function(WidgetRef ref) watch,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) {
            watch(ref);
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _unmount(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SizedBox.shrink()),
    ),
  );
  await tester.pump();
}

void main() {
  late _MockSalonRepository repo;
  late ProviderContainer container;

  setUp(() {
    repo = _MockSalonRepository();
    container = ProviderContainer(
      overrides: [salonRepositoryProvider.overrideWithValue(repo)],
    );
  });

  tearDown(() => container.dispose());

  group('salonServiceCatalogProvider — keepAlive TTL', () {
    testWidgets(
      'away-and-back within the TTL serves the cached catalogue (no second '
      'repository call)',
      (tester) async {
        when(
          () => repo.getSalonServiceCatalog(_kSalonId),
        ).thenAnswer((_) async => _catalog);

        await _mount(
          tester,
          container,
          (ref) => ref.watch(salonServiceCatalogProvider(_kSalonId)),
        );
        await _unmount(tester, container);

        // fixed-wait-ok: within 5-min TTL — asserts cache HIT
        await tester.pump(const Duration(seconds: 30));
        await _mount(
          tester,
          container,
          (ref) => ref.watch(salonServiceCatalogProvider(_kSalonId)),
        );

        verify(() => repo.getSalonServiceCatalog(_kSalonId)).called(1);

        await _unmount(tester, container);
        // fixed-wait-ok: drains release Timer past TTL before dispose
        await tester.pump(const Duration(minutes: 6));
      },
    );

    testWidgets(
      'away-and-back AFTER the TTL elapses re-fetches (cache is bounded)',
      (tester) async {
        when(
          () => repo.getSalonServiceCatalog(_kSalonId),
        ).thenAnswer((_) async => _catalog);

        await _mount(
          tester,
          container,
          (ref) => ref.watch(salonServiceCatalogProvider(_kSalonId)),
        );
        await _unmount(tester, container);

        // fixed-wait-ok: past 5-min TTL — asserts cache MISS
        await tester.pump(const Duration(minutes: 6));
        await _mount(
          tester,
          container,
          (ref) => ref.watch(salonServiceCatalogProvider(_kSalonId)),
        );

        verify(() => repo.getSalonServiceCatalog(_kSalonId)).called(2);

        await _unmount(tester, container);
        // fixed-wait-ok: drains release Timer past TTL before dispose
        await tester.pump(const Duration(minutes: 6));
      },
    );
  });

  group('salonReviewSummaryProvider — keepAlive TTL', () {
    testWidgets(
      'away-and-back within the TTL serves the cached summary (no second '
      'repository call)',
      (tester) async {
        when(
          () => repo.getSalonReviewSummary(_kSalonId),
        ).thenAnswer((_) async => _summary);

        await _mount(
          tester,
          container,
          (ref) => ref.watch(salonReviewSummaryProvider(_kSalonId)),
        );
        await _unmount(tester, container);

        // fixed-wait-ok: within 5-min TTL — asserts cache HIT
        await tester.pump(const Duration(seconds: 30));
        await _mount(
          tester,
          container,
          (ref) => ref.watch(salonReviewSummaryProvider(_kSalonId)),
        );

        verify(() => repo.getSalonReviewSummary(_kSalonId)).called(1);

        await _unmount(tester, container);
        // fixed-wait-ok: drains release Timer past TTL before dispose
        await tester.pump(const Duration(minutes: 6));
      },
    );

    testWidgets(
      'away-and-back AFTER the TTL elapses re-fetches (cache is bounded)',
      (tester) async {
        when(
          () => repo.getSalonReviewSummary(_kSalonId),
        ).thenAnswer((_) async => _summary);

        await _mount(
          tester,
          container,
          (ref) => ref.watch(salonReviewSummaryProvider(_kSalonId)),
        );
        await _unmount(tester, container);

        // fixed-wait-ok: past 5-min TTL — asserts cache MISS
        await tester.pump(const Duration(minutes: 6));
        await _mount(
          tester,
          container,
          (ref) => ref.watch(salonReviewSummaryProvider(_kSalonId)),
        );

        verify(() => repo.getSalonReviewSummary(_kSalonId)).called(2);

        await _unmount(tester, container);
        // fixed-wait-ok: drains release Timer past TTL before dispose
        await tester.pump(const Duration(minutes: 6));
      },
    );
  });

  group('salonReviewsProvider — keepAlive TTL (per (salonId, sort) key)', () {
    testWidgets(
      'away-and-back within the TTL, SAME sort, serves the cached page (no '
      'second repository call)',
      (tester) async {
        when(
          () => repo.getSalonReviews(
            salonId: _kSalonId,
            sort: SalonReviewSort.newest,
          ),
        ).thenAnswer((_) async => _reviews);

        await _mount(
          tester,
          container,
          (ref) => ref.watch(
            salonReviewsProvider(_kSalonId, SalonReviewSort.newest),
          ),
        );
        await _unmount(tester, container);

        // fixed-wait-ok: within 5-min TTL — asserts cache HIT
        await tester.pump(const Duration(seconds: 30));
        await _mount(
          tester,
          container,
          (ref) => ref.watch(
            salonReviewsProvider(_kSalonId, SalonReviewSort.newest),
          ),
        );

        verify(
          () => repo.getSalonReviews(
            salonId: _kSalonId,
            sort: SalonReviewSort.newest,
          ),
        ).called(1);

        await _unmount(tester, container);
        // fixed-wait-ok: drains release Timer past TTL before dispose
        await tester.pump(const Duration(minutes: 6));
      },
    );

    testWidgets(
      'away-and-back AFTER the TTL elapses re-fetches (cache is bounded)',
      (tester) async {
        when(
          () => repo.getSalonReviews(
            salonId: _kSalonId,
            sort: SalonReviewSort.newest,
          ),
        ).thenAnswer((_) async => _reviews);

        await _mount(
          tester,
          container,
          (ref) => ref.watch(
            salonReviewsProvider(_kSalonId, SalonReviewSort.newest),
          ),
        );
        await _unmount(tester, container);

        // fixed-wait-ok: past 5-min TTL — asserts cache MISS
        await tester.pump(const Duration(minutes: 6));
        await _mount(
          tester,
          container,
          (ref) => ref.watch(
            salonReviewsProvider(_kSalonId, SalonReviewSort.newest),
          ),
        );

        verify(
          () => repo.getSalonReviews(
            salonId: _kSalonId,
            sort: SalonReviewSort.newest,
          ),
        ).called(2);

        await _unmount(tester, container);
        // fixed-wait-ok: drains release Timer past TTL before dispose
        await tester.pump(const Duration(minutes: 6));
      },
    );

    testWidgets(
      'switching sort keys a NEW family entry and always fetches (a sort '
      'change is an intentional new fetch, not a cache miss)',
      (tester) async {
        when(
          () => repo.getSalonReviews(
            salonId: _kSalonId,
            sort: SalonReviewSort.newest,
          ),
        ).thenAnswer((_) async => _reviews);
        when(
          () => repo.getSalonReviews(
            salonId: _kSalonId,
            sort: SalonReviewSort.highest,
          ),
        ).thenAnswer((_) async => _reviews);

        await _mount(
          tester,
          container,
          (ref) => ref.watch(
            salonReviewsProvider(_kSalonId, SalonReviewSort.newest),
          ),
        );
        await _mount(
          tester,
          container,
          (ref) => ref.watch(
            salonReviewsProvider(_kSalonId, SalonReviewSort.highest),
          ),
        );

        verify(
          () => repo.getSalonReviews(
            salonId: _kSalonId,
            sort: SalonReviewSort.newest,
          ),
        ).called(1);
        verify(
          () => repo.getSalonReviews(
            salonId: _kSalonId,
            sort: SalonReviewSort.highest,
          ),
        ).called(1);

        await _unmount(tester, container);
        // fixed-wait-ok: drains release Timer past TTL before dispose
        await tester.pump(const Duration(minutes: 6));
      },
    );
  });
}

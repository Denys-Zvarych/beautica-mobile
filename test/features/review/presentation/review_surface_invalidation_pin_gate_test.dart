// ITEM 6 (this track) — pins the wasPinned GATE's invocation count for
// `invalidateMasterReviewSurfaces` / `invalidateSalonReviewSurfaces` (FIX C,
// `review_surface_invalidation.dart`), mirroring
// `booking_calendar_invalidation_test.dart`'s own "ITEM 6 — wasPinned gate
// call-count" group.
//
// WHY THIS FILE, SEPARATE FROM THE EXISTING SUITES
// --------------------------------------------------
// `leave_review_master_surfaces_invalidation_test.dart` /
// `leave_review_salon_surfaces_invalidation_test.dart` already drive the REAL
// `LeaveReviewScreen` end-to-end and assert refetch counts — but their harness
// (`_pumpWarmedAndPushReview`) warms ALL `MasterReviewSort.values` /
// `SalonReviewSort.values` unconditionally, so every one of their assertions
// only ever exercises the PINNED branch of the gate. A dropped
// `if (wasPinned)` in `invalidateMasterReviewSurfaces`/
// `invalidateSalonReviewSurfaces` cannot fail a PINNED-only count (an
// unconditional eager `ref.read` is a no-op extra flush on an
// already-flushed, `_mustRecomputeState == false` element) — it only breaks
// the UNPINNED case, by unconditionally BUILDING a sort nobody asked for.
// Forking the heavy `LeaveReviewScreen` harness just to add one
// non-pre-warmed sort would duplicate ~150 lines of routing/screen-protection
// boilerplate neither test needs — this file calls the two invalidation
// functions directly through a bare `Consumer`, the exact technique
// `booking_calendar_invalidation_test.dart` already uses for the same reason.
//
// TRAP AVOIDED: `verify(...).called(n)` reads the mock's own call log — never
// `value == null` (Riverpod 3.x retains the previous `.value` through a
// seamless reload).

import 'package:beautica_mobile/features/master/application/master_reviews_notifier.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master_review.dart';
import 'package:beautica_mobile/features/review/presentation/review_surface_invalidation.dart';
import 'package:beautica_mobile/features/salon/application/salon_reviews_notifier.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:beautica_mobile/features/salon/domain/salon_review.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/pump_app.dart';

const String _masterId = 'm1';
const String _salonId = 's1';

class _MockMasterRepository extends Mock implements MasterRepository {}

class _MockSalonRepository extends Mock implements SalonRepository {}

/// Stubs `getMasterReviews`/`getSalonReviews` for every declared sort so a
/// PINNED member's eager read-back has something to answer, and an
/// UNPINNED member's call (if the gate regresses) does not throw
/// "no stub found" and mask the real assertion.
void _stubAllSorts(_MockMasterRepository repo) {
  for (final MasterReviewSort s in MasterReviewSort.values) {
    when(
      () => repo.getMasterReviews(masterId: _masterId, sort: s),
    ).thenAnswer((_) async => const <MasterReviewItem>[]);
  }
}

void _stubAllSalonSorts(_MockSalonRepository repo) {
  for (final SalonReviewSort s in SalonReviewSort.values) {
    when(
      () => repo.getSalonReviews(salonId: _salonId, sort: s),
    ).thenAnswer((_) async => const <SalonReviewItem>[]);
  }
}

void main() {
  group('invalidateMasterReviewSurfaces — wasPinned gate call-count', () {
    testWidgets(
      'PINNED — a sort already built this session refetches exactly once '
      '(1 initial + 1 eager read)',
      (tester) async {
        final repo = _MockMasterRepository();
        _stubAllSorts(repo);

        await tester.pumpApp(
          Scaffold(
            body: Consumer(
              builder: (BuildContext context, WidgetRef ref, _) => TextButton(
                key: const Key('submit'),
                onPressed: () => invalidateMasterReviewSurfaces(ref, _masterId),
                child: const Text('submit'),
              ),
            ),
          ),
          overrides: <Object>[masterRepositoryProvider.overrideWithValue(repo)],
        );

        final ProviderContainer container = ProviderScope.containerOf(
          tester.element(find.byKey(const Key('submit'))),
          listen: false,
        );

        // PIN exactly ONE sort — `newest` — via a live subscription + await.
        final ProviderSubscription<AsyncValue<List<MasterReviewItem>>> sub =
            container.listen(
              masterReviewsProvider(_masterId, MasterReviewSort.newest),
              (_, _) {},
            );
        addTearDown(sub.close);
        await container.read(
          masterReviewsProvider(_masterId, MasterReviewSort.newest).future,
        );
        verify(
          () => repo.getMasterReviews(
            masterId: _masterId,
            sort: MasterReviewSort.newest,
          ),
        ).called(1); // sanity: one warm fetch before any tap.

        await tester.tap(find.byKey(const Key('submit')));
        await tester.pumpAndSettle();

        verify(
          () => repo.getMasterReviews(
            masterId: _masterId,
            sort: MasterReviewSort.newest,
          ),
        ).called(1); // ONE eager read-back, not zero, not two.
      },
    );

    testWidgets('UNPINNED — a sort nobody built this session triggers ZERO '
        'getMasterReviews calls for that sort (proves the eager read is '
        'GATED, not unconditional)', (tester) async {
      final repo = _MockMasterRepository();
      _stubAllSorts(repo);

      await tester.pumpApp(
        Scaffold(
          body: Consumer(
            builder: (BuildContext context, WidgetRef ref, _) => TextButton(
              key: const Key('submit'),
              onPressed: () => invalidateMasterReviewSurfaces(ref, _masterId),
              child: const Text('submit'),
            ),
          ),
        ),
        overrides: <Object>[masterRepositoryProvider.overrideWithValue(repo)],
      );

      // Deliberately NO subscription/read for ANY sort before tapping —
      // every `masterReviewsProvider(masterId, sort)` member is genuinely
      // absent this session.
      await tester.tap(find.byKey(const Key('submit')));
      await tester.pumpAndSettle();

      for (final MasterReviewSort s in MasterReviewSort.values) {
        verifyNever(() => repo.getMasterReviews(masterId: _masterId, sort: s));
      }
    });
  });

  group('invalidateSalonReviewSurfaces — wasPinned gate call-count', () {
    testWidgets(
      'PINNED — a sort already built this session refetches exactly once '
      '(1 initial + 1 eager read)',
      (tester) async {
        final repo = _MockSalonRepository();
        _stubAllSalonSorts(repo);

        await tester.pumpApp(
          Scaffold(
            body: Consumer(
              builder: (BuildContext context, WidgetRef ref, _) => TextButton(
                key: const Key('submit'),
                onPressed: () => invalidateSalonReviewSurfaces(ref, _salonId),
                child: const Text('submit'),
              ),
            ),
          ),
          overrides: <Object>[salonRepositoryProvider.overrideWithValue(repo)],
        );

        final ProviderContainer container = ProviderScope.containerOf(
          tester.element(find.byKey(const Key('submit'))),
          listen: false,
        );

        final ProviderSubscription<AsyncValue<List<SalonReviewItem>>> sub =
            container.listen(
              salonReviewsProvider(_salonId, SalonReviewSort.newest),
              (_, _) {},
            );
        addTearDown(sub.close);
        await container.read(
          salonReviewsProvider(_salonId, SalonReviewSort.newest).future,
        );
        verify(
          () => repo.getSalonReviews(
            salonId: _salonId,
            sort: SalonReviewSort.newest,
          ),
        ).called(1);

        await tester.tap(find.byKey(const Key('submit')));
        await tester.pumpAndSettle();

        verify(
          () => repo.getSalonReviews(
            salonId: _salonId,
            sort: SalonReviewSort.newest,
          ),
        ).called(1);
      },
    );

    testWidgets('UNPINNED — a sort nobody built this session triggers ZERO '
        'getSalonReviews calls for that sort', (tester) async {
      final repo = _MockSalonRepository();
      _stubAllSalonSorts(repo);

      await tester.pumpApp(
        Scaffold(
          body: Consumer(
            builder: (BuildContext context, WidgetRef ref, _) => TextButton(
              key: const Key('submit'),
              onPressed: () => invalidateSalonReviewSurfaces(ref, _salonId),
              child: const Text('submit'),
            ),
          ),
        ),
        overrides: <Object>[salonRepositoryProvider.overrideWithValue(repo)],
      );

      await tester.tap(find.byKey(const Key('submit')));
      await tester.pumpAndSettle();

      for (final SalonReviewSort s in SalonReviewSort.values) {
        verifyNever(() => repo.getSalonReviews(salonId: _salonId, sort: s));
      }
    });
  });
}

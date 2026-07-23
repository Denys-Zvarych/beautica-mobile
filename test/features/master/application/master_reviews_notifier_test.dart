// Phase 4.5 — Unit tests for the two review loader providers.
//
// Thin passthroughs, but they pin the CONTRACT that matters for the "Мої
// відгуки" correctness bug: the exact (masterId, sort) the screen supplies must
// reach the repository unchanged, and a repository [Failure] must surface as an
// AsyncError (not be swallowed). Strict argument matching (mobile-qa M4) — the
// happy-path verify asserts the concrete id + sort, so a test could not pass
// with a garbage argument.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/master/application/master_review_summary_notifier.dart';
import 'package:beautica_mobile/features/master/application/master_reviews_notifier.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master_review.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockMasterRepository extends Mock implements MasterRepository {}

void main() {
  late _MockMasterRepository repo;

  setUp(() {
    repo = _MockMasterRepository();
    registerFallbackValue(MasterReviewSort.newest);
  });

  ProviderContainer makeContainer() {
    final ProviderContainer container = ProviderContainer(
      overrides: [masterRepositoryProvider.overrideWithValue(repo)],
      // Disable Riverpod's exponential-backoff retry so a failed build surfaces
      // the typed Failure immediately (and leaves no pending backoff Timer).
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    return container;
  }

  group('masterReviewsProvider', () {
    test('threads the exact masterId + sort into the repository', () async {
      final List<MasterReviewItem> items = <MasterReviewItem>[
        MasterReviewItem(
          id: 'r1',
          clientDisplayName: 'Іра К.',
          rating: 5,
          comment: 'Супер',
          createdAt: DateTime.utc(2026, 6, 1),
        ),
      ];
      when(
        () => repo.getMasterReviews(
          masterId: any(named: 'masterId'),
          sort: any(named: 'sort'),
        ),
      ).thenAnswer((_) async => items);

      final ProviderContainer container = makeContainer();
      final List<MasterReviewItem> result = await container.read(
        masterReviewsProvider('m-1', MasterReviewSort.highest).future,
      );

      expect(result, items);
      // Strict args: the concrete id AND sort must reach the repository.
      verify(
        () => repo.getMasterReviews(
          masterId: 'm-1',
          sort: MasterReviewSort.highest,
        ),
      ).called(1);
    });

    test('surfaces a repository Failure as an AsyncError', () async {
      when(
        () => repo.getMasterReviews(
          masterId: any(named: 'masterId'),
          sort: any(named: 'sort'),
        ),
      ).thenThrow(const NetworkFailure());

      final ProviderContainer container = makeContainer();

      await expectLater(
        container.read(
          masterReviewsProvider('m-1', MasterReviewSort.newest).future,
        ),
        throwsA(isA<NetworkFailure>()),
      );
    });
  });

  group('masterReviewSummaryProvider', () {
    test('threads the exact masterId into the repository', () async {
      const MasterReviewSummary summary = MasterReviewSummary(
        avgRating: 4.0,
        reviewCount: 3,
        distribution: <int>[1, 1, 1, 0, 0],
      );
      when(
        () => repo.getMasterReviewSummary(any()),
      ).thenAnswer((_) async => summary);

      final ProviderContainer container = makeContainer();
      final MasterReviewSummary result = await container.read(
        masterReviewSummaryProvider('m-1').future,
      );

      expect(result, summary);
      verify(() => repo.getMasterReviewSummary('m-1')).called(1);
    });

    test('surfaces a repository Failure as an AsyncError', () async {
      when(
        () => repo.getMasterReviewSummary(any()),
      ).thenThrow(const ServerFailure(statusCode: 404));

      final ProviderContainer container = makeContainer();

      await expectLater(
        container.read(masterReviewSummaryProvider('m-1').future),
        throwsA(isA<ServerFailure>()),
      );
    });
  });
}

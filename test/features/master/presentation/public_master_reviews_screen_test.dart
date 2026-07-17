// Phase 4.x — Widget tests for PublicMasterReviewsScreen.
//
// The CLIENT-facing reviews list reached from the public master profile's
// «Відгуки» stat tile. Deliberately param-driven (masterId comes straight
// from the route, never from the session) — see the file header on the
// screen itself for why this must NOT resolve via masterProfileProvider.
// Had no dedicated test file before this — the verifier flagged the gap.
//
// Covers:
//   1. Title      — the localised «Відгуки» app-bar title renders.
//   2. Threading  — the exact masterId passed to the screen reaches
//                   MasterReviewsBody unchanged (a lightweight prop-wiring
//                   pin, independent of the deeper identity-confusion test
//                   owned by master_reviews_body_test.dart).
//   3. Data       — the given masterId's reviews render end to end through
//                   this screen (not just the shared body in isolation).
//   4. Loading    — shimmer frame, no resolved data.
//   5. Empty      — the shared empty placeholder renders.
//   6. Error+retry — ErrorState renders and retry re-fetches.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/master/application/master_review_summary_notifier.dart';
import 'package:beautica_mobile/features/master/application/master_reviews_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master_review.dart';
import 'package:beautica_mobile/features/master/presentation/public_master_reviews_screen.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/master_reviews_body.dart';
import 'package:beautica_mobile/features/review/presentation/widgets/rating_summary_card.dart';
import 'package:beautica_mobile/features/review/presentation/widgets/review_card.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/pump_app.dart';

const String _kMasterId = 'master-public-1';

const MasterReviewSummary _summary = MasterReviewSummary(
  avgRating: 4.7,
  reviewCount: 1,
  distribution: <int>[1, 0, 0, 0, 0],
);

final MasterReviewItem _review = MasterReviewItem(
  id: 'pub-rev-1',
  clientDisplayName: 'Клієнтка Н.',
  rating: 5,
  comment: 'Дуже задоволена!',
  createdAt: DateTime.utc(2026, 6, 1),
);

List<Object> _dataOverrides({String masterId = _kMasterId}) => <Object>[
  masterReviewSummaryProvider(masterId).overrideWith((ref) => _summary),
  masterReviewsProvider(
    masterId,
    MasterReviewSort.newest,
  ).overrideWith((ref) => <MasterReviewItem>[_review]),
];

// Fixtures for the sort re-query test — deliberately distinct ids per sort so
// a widget-tree assertion pins which dataset is actually showing.
final List<MasterReviewItem> _newestList = <MasterReviewItem>[
  MasterReviewItem(
    id: 'pub-rev-newest-1',
    clientDisplayName: 'Клієнтка А.',
    rating: 5,
    comment: 'Найновіший відгук.',
    createdAt: DateTime.utc(2026, 6, 5),
  ),
];

final List<MasterReviewItem> _oldestList = <MasterReviewItem>[
  MasterReviewItem(
    id: 'pub-rev-oldest-1',
    clientDisplayName: 'Клієнтка Б.',
    rating: 3,
    comment: 'Найстаріший відгук.',
    createdAt: DateTime.utc(2026, 1, 1),
  ),
];

GoRouter _router() => GoRouter(
  initialLocation: '/reviews',
  routes: <RouteBase>[
    GoRoute(
      path: '/reviews',
      builder: (BuildContext context, GoRouterState state) =>
          const PublicMasterReviewsScreen(masterId: _kMasterId),
    ),
  ],
);

void main() {
  group('title', () {
    testWidgets('renders the localised reviews-screen title', (tester) async {
      await tester.pumpApp(
        const PublicMasterReviewsScreen(masterId: _kMasterId),
        overrides: _dataOverrides(),
      );
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(PublicMasterReviewsScreen)),
      );
      expect(find.text(l10n.publicMasterReviewsTitle), findsWidgets);
    });
  });

  group('masterId threading', () {
    testWidgets(
      'passes the exact given masterId into MasterReviewsBody unchanged',
      (tester) async {
        await tester.pumpApp(
          const PublicMasterReviewsScreen(masterId: _kMasterId),
          overrides: _dataOverrides(),
        );
        await tester.pumpAndSettle();

        final MasterReviewsBody body = tester.widget<MasterReviewsBody>(
          find.byType(MasterReviewsBody),
        );
        expect(body.masterId, _kMasterId);
      },
    );
  });

  group('data state', () {
    testWidgets('renders the given masterId\'s summary + review end to end', (
      tester,
    ) async {
      await tester.pumpApp(
        const PublicMasterReviewsScreen(masterId: _kMasterId),
        overrides: _dataOverrides(),
      );
      await tester.pumpAndSettle();

      expect(find.byType(RatingSummaryCard), findsOneWidget);
      final Text avg = tester.widget<Text>(
        find.byKey(const Key('master-review-summary-average')),
      );
      expect(avg.data, '4.7');
      expect(find.byKey(Key('master-review-${_review.id}')), findsOneWidget);
    });
  });

  // mobile-qa LOW — the sort-reorder path is owned by the shared
  // MasterReviewsBody and was previously only exercised transitively via
  // MasterReceivedReviewsScreen's own sort-re-query test. This pins the same
  // behaviour for THIS screen's masterId, hosted under a real GoRouter
  // (required for the sort sheet's `context.pop(option)`).
  group('sort re-query', () {
    testWidgets(
      'selecting a new sort re-keys the provider and reorders the list to '
      'the new sort data',
      (tester) async {
        await tester.pumpRoutedApp(
          _router(),
          overrides: <Object>[
            masterReviewSummaryProvider(
              _kMasterId,
            ).overrideWith((ref) => _summary),
            masterReviewsProvider(
              _kMasterId,
              MasterReviewSort.newest,
            ).overrideWith((ref) => _newestList),
            masterReviewsProvider(
              _kMasterId,
              MasterReviewSort.oldest,
            ).overrideWith((ref) => _oldestList),
          ],
        );
        await tester.pumpAndSettle();

        // Default NEWEST data shown.
        expect(
          find.byKey(const Key('master-review-pub-rev-newest-1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('master-review-pub-rev-oldest-1')),
          findsNothing,
        );

        // Open the sort sheet.
        await tester.tap(find.byKey(const Key('master-reviews-sort-button')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('master-review-sort-option-oldest')),
          findsOneWidget,
        );

        // Select OLDEST → sheet pops → screen re-keys to (masterId, oldest).
        await tester.tap(
          find.byKey(const Key('master-review-sort-option-oldest')),
        );
        await tester.pumpAndSettle();

        // The list observably switched to the OLDEST dataset, keyed on THIS
        // screen's masterId (not some other id).
        expect(
          find.byKey(const Key('master-review-pub-rev-oldest-1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('master-review-pub-rev-newest-1')),
          findsNothing,
        );
      },
    );
  });

  group('loading state', () {
    testWidgets('shows a shimmer frame with no resolved data', (tester) async {
      await tester.pumpApp(
        const PublicMasterReviewsScreen(masterId: _kMasterId),
        overrides: <Object>[
          masterReviewSummaryProvider(
            _kMasterId,
          ).overrideWith((ref) => Completer<MasterReviewSummary>().future),
          masterReviewsProvider(
            _kMasterId,
            MasterReviewSort.newest,
          ).overrideWith((ref) => Completer<List<MasterReviewItem>>().future),
        ],
      );
      await tester.pump();

      expect(find.byType(SkeletonShimmerScope), findsWidgets);
      expect(find.byType(RatingSummaryCard), findsNothing);
      expect(find.byType(ReviewCard), findsNothing);
    });
  });

  group('empty state', () {
    testWidgets('renders the empty placeholder for a reviewless master', (
      tester,
    ) async {
      await tester.pumpApp(
        const PublicMasterReviewsScreen(masterId: _kMasterId),
        overrides: <Object>[
          masterReviewSummaryProvider(_kMasterId).overrideWith(
            (ref) => const MasterReviewSummary(
              avgRating: null,
              reviewCount: 0,
              distribution: <int>[0, 0, 0, 0, 0],
            ),
          ),
          masterReviewsProvider(
            _kMasterId,
            MasterReviewSort.newest,
          ).overrideWith((ref) => const <MasterReviewItem>[]),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('master-reviews-empty')), findsOneWidget);
      expect(find.byType(ReviewCard), findsNothing);
    });
  });

  group('error + retry', () {
    testWidgets('list error renders ErrorState and retry re-fetches', (
      tester,
    ) async {
      int calls = 0;
      await tester.pumpApp(
        const PublicMasterReviewsScreen(masterId: _kMasterId),
        overrides: <Object>[
          masterReviewSummaryProvider(
            _kMasterId,
          ).overrideWith((ref) => _summary),
          masterReviewsProvider(
            _kMasterId,
            MasterReviewSort.newest,
          ).overrideWith((ref) {
            calls++;
            if (calls == 1) {
              return Future<List<MasterReviewItem>>.error(
                const NetworkFailure(),
                StackTrace.empty,
              );
            }
            return <MasterReviewItem>[_review];
          }),
        ],
        retry: (_, _) => null,
      );
      await tester.pumpAndSettle();

      final Finder retry = find.byKey(const Key('error_state_retry_button'));
      expect(retry, findsOneWidget);
      expect(find.byType(ReviewCard), findsNothing);

      await tester.tap(retry);
      await tester.pumpAndSettle();

      expect(calls, greaterThanOrEqualTo(2));
      expect(find.byType(ErrorState), findsNothing);
      expect(find.byKey(Key('master-review-${_review.id}')), findsOneWidget);
    });
  });
}

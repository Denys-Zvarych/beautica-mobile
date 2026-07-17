// Phase 4.x — Widget tests for MasterReviewsBody + MasterReviewsBodySkeleton.
//
// MasterReviewsBody was extracted from MasterReceivedReviewsScreen so it can
// be shared with PublicMasterReviewsScreen (the CLIENT-facing surface). It
// had NO dedicated test file before this — the verifier flagged the gap.
//
// Covers:
//   1. Loading  — shimmer scope present for both the summary card and the
//                 list; no resolved data rendered.
//   2. Data     — summary average + N ReviewCards render for the GIVEN
//                 masterId.
//   3. Empty    — `master-reviews-empty` placeholder, summary still renders.
//   4. Error    — ErrorState + retry for BOTH the summary and the list
//                 sections independently (each `.when` is its own AsyncValue).
//   5. Skeleton — `MasterReviewsBodySkeleton` (used by callers that need a
//                 loading frame before a masterId is even known) matches the
//                 same shimmer shape with no key/data leaking through.
//   6. IDENTITY-CONFUSION GUARD (highest-value test in this file) — pumping
//      `MasterReviewsBody(masterId: B)` while AUTHENTICATED as a DIFFERENT
//      master (A) renders ONLY B's reviews. `masterProfileProvider` is
//      deliberately left un-overridden: the widget must never read it. If a
//      future refactor wires the body to the session's own
//      `masterProfileProvider` instead of the constructor's `masterId`, this
//      test fails two ways: (a) B's data never appears (nothing overrides the
//      family keyed on whatever id the profile would resolve to), and
//      (b) A's review key would leak in if the wiring silently fell back to
//      A. Both are asserted explicitly.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/application/master_review_summary_notifier.dart';
import 'package:beautica_mobile/features/master/application/master_reviews_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master_review.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/master_reviews_body.dart';
import 'package:beautica_mobile/features/review/presentation/widgets/rating_summary_card.dart';
import 'package:beautica_mobile/features/review/presentation/widgets/review_card.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

const String _kMasterIdA = 'master-a';
const String _kMasterIdB = 'master-b';

const User _masterAUser = User(
  id: 'user-master-a',
  email: 'a@beautica.ua',
  role: UserRole.independentMaster,
  firstName: 'Master',
  lastName: 'A',
);

class _StubAuthAsMasterA extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.authenticated(
    user: _masterAUser,
    accessToken: 'token-a',
  );
}

const MasterReviewSummary _summaryA = MasterReviewSummary(
  avgRating: 2.0,
  reviewCount: 1,
  distribution: <int>[0, 0, 1, 0, 0],
);
const MasterReviewSummary _summaryB = MasterReviewSummary(
  avgRating: 4.5,
  reviewCount: 1,
  distribution: <int>[1, 0, 0, 0, 0],
);

MasterReviewItem _reviewFor(String masterId) => MasterReviewItem(
  id: 'rev-$masterId',
  clientDisplayName: 'Client of $masterId',
  rating: 5,
  comment: 'Comment for $masterId',
  createdAt: DateTime.utc(2026, 6, 1),
);

void main() {
  group('loading state', () {
    testWidgets('shows shimmer scope for both sections while loading', (
      tester,
    ) async {
      await tester.pumpApp(
        const MasterReviewsBody(masterId: _kMasterIdA),
        overrides: <Object>[
          masterReviewSummaryProvider(
            _kMasterIdA,
          ).overrideWith((ref) => Completer<MasterReviewSummary>().future),
          masterReviewsProvider(
            _kMasterIdA,
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

  group('data state', () {
    testWidgets('renders the summary + review cards for the given masterId', (
      tester,
    ) async {
      final MasterReviewItem review = _reviewFor(_kMasterIdA);
      await tester.pumpApp(
        const MasterReviewsBody(masterId: _kMasterIdA),
        overrides: <Object>[
          masterReviewSummaryProvider(
            _kMasterIdA,
          ).overrideWith((ref) => _summaryA),
          masterReviewsProvider(
            _kMasterIdA,
            MasterReviewSort.newest,
          ).overrideWith((ref) => <MasterReviewItem>[review]),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.byType(RatingSummaryCard), findsOneWidget);
      final Text avg = tester.widget<Text>(
        find.byKey(const Key('master-review-summary-average')),
      );
      expect(avg.data, '2.0');
      expect(find.byKey(Key('master-review-${review.id}')), findsOneWidget);
    });
  });

  group('empty state', () {
    testWidgets('renders the empty placeholder while the summary still shows', (
      tester,
    ) async {
      await tester.pumpApp(
        const MasterReviewsBody(masterId: _kMasterIdA),
        overrides: <Object>[
          masterReviewSummaryProvider(
            _kMasterIdA,
          ).overrideWith((ref) => _summaryA),
          masterReviewsProvider(
            _kMasterIdA,
            MasterReviewSort.newest,
          ).overrideWith((ref) => const <MasterReviewItem>[]),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('master-reviews-empty')), findsOneWidget);
      expect(find.byType(ReviewCard), findsNothing);
      expect(find.byType(RatingSummaryCard), findsOneWidget);
    });
  });

  group('error states', () {
    testWidgets(
      'summary error renders ErrorState independently of a healthy list',
      (tester) async {
        final MasterReviewItem review = _reviewFor(_kMasterIdA);
        await tester.pumpApp(
          const MasterReviewsBody(masterId: _kMasterIdA),
          overrides: <Object>[
            masterReviewSummaryProvider(_kMasterIdA).overrideWith(
              (ref) => Future<MasterReviewSummary>.error(
                const NetworkFailure(),
                StackTrace.empty,
              ),
            ),
            masterReviewsProvider(
              _kMasterIdA,
              MasterReviewSort.newest,
            ).overrideWith((ref) => <MasterReviewItem>[review]),
          ],
          retry: (_, _) => null,
        );
        await tester.pumpAndSettle();

        expect(find.byType(ErrorState), findsOneWidget);
        expect(find.byType(RatingSummaryCard), findsNothing);
        // The list section is unaffected by the summary's error.
        expect(find.byKey(Key('master-review-${review.id}')), findsOneWidget);
      },
    );

    testWidgets(
      'list error renders ErrorState independently of a healthy summary, '
      'and retry re-fetches',
      (tester) async {
        int calls = 0;
        final MasterReviewItem review = _reviewFor(_kMasterIdA);
        await tester.pumpApp(
          const MasterReviewsBody(masterId: _kMasterIdA),
          overrides: <Object>[
            masterReviewSummaryProvider(
              _kMasterIdA,
            ).overrideWith((ref) => _summaryA),
            masterReviewsProvider(
              _kMasterIdA,
              MasterReviewSort.newest,
            ).overrideWith((ref) {
              calls++;
              if (calls == 1) {
                return Future<List<MasterReviewItem>>.error(
                  const NetworkFailure(),
                  StackTrace.empty,
                );
              }
              return <MasterReviewItem>[review];
            }),
          ],
          retry: (_, _) => null,
        );
        await tester.pumpAndSettle();

        expect(find.byType(RatingSummaryCard), findsOneWidget);
        final Finder retry = find.byKey(const Key('error_state_retry_button'));
        expect(retry, findsOneWidget);

        await tester.tap(retry);
        await tester.pumpAndSettle();

        expect(calls, greaterThanOrEqualTo(2));
        expect(find.byType(ErrorState), findsNothing);
        expect(find.byKey(Key('master-review-${review.id}')), findsOneWidget);
      },
    );
  });

  group('MasterReviewsBodySkeleton', () {
    testWidgets('renders a shimmer frame with no data/keys', (tester) async {
      await tester.pumpApp(const MasterReviewsBodySkeleton());
      await tester.pump();

      expect(find.byType(SkeletonShimmerScope), findsWidgets);
      expect(find.byType(RatingSummaryCard), findsNothing);
      expect(find.byType(ReviewCard), findsNothing);
      expect(find.byKey(const Key('master-reviews-empty')), findsNothing);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // IDENTITY-CONFUSION GUARD — see file header.
  // ──────────────────────────────────────────────────────────────────────────
  group('identity-confusion guard', () {
    testWidgets(
      'authenticated as master A but passed masterId B renders ONLY B\'s '
      'reviews — masterProfileProvider is never read (not overridden here)',
      (tester) async {
        final MasterReviewItem reviewA = _reviewFor(_kMasterIdA);
        final MasterReviewItem reviewB = _reviewFor(_kMasterIdB);

        await tester.pumpApp(
          const MasterReviewsBody(masterId: _kMasterIdB),
          overrides: <Object>[
            // Authenticated as a DIFFERENT master (A) than the one this
            // widget was explicitly told to render (B). MasterReviewsBody
            // must ignore the session entirely.
            authProvider.overrideWith(_StubAuthAsMasterA.new),
            masterReviewSummaryProvider(
              _kMasterIdA,
            ).overrideWith((ref) => _summaryA),
            masterReviewsProvider(
              _kMasterIdA,
              MasterReviewSort.newest,
            ).overrideWith((ref) => <MasterReviewItem>[reviewA]),
            masterReviewSummaryProvider(
              _kMasterIdB,
            ).overrideWith((ref) => _summaryB),
            masterReviewsProvider(
              _kMasterIdB,
              MasterReviewSort.newest,
            ).overrideWith((ref) => <MasterReviewItem>[reviewB]),
          ],
        );
        await tester.pumpAndSettle();

        // B's data rendered …
        expect(find.byKey(Key('master-review-${reviewB.id}')), findsOneWidget);
        final Text avg = tester.widget<Text>(
          find.byKey(const Key('master-review-summary-average')),
        );
        expect(avg.data, _summaryB.avgRating!.toStringAsFixed(1));

        // … A's data — the AUTHENTICATED session's own master — never leaks
        // in, even though A's providers were also stubbed and available.
        expect(
          find.byKey(Key('master-review-${reviewA.id}')),
          findsNothing,
          reason:
              'the authenticated session\'s own reviews must never render '
              'in place of the explicitly-passed masterId\'s reviews',
        );
      },
    );
  });
}

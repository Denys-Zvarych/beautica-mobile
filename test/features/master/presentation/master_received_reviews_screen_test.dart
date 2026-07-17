// Phase 4.6 — Widget tests for [MasterReceivedReviewsScreen] ("Мої відгуки").
//
// Covers the four AsyncValue states plus the flows unique to this screen:
//   1. Loading   — skeleton shimmer blocks; no data, no empty state.
//   2. Empty     — `master-reviews-empty` placeholder rendered.
//   3. Error+retry — the list error surfaces an ErrorState whose retry
//                    re-runs the fetch and reveals the data.
//   4. Data      — N ReviewCards + the RatingSummaryCard (avg + count +
//                  distribution), with at least one concrete backend value
//                  asserted (not a smoke-only findsWidgets).
//   5. Sort re-query — opening the sort sheet and selecting a new order
//                      re-keys `masterReviewsProvider`, observably reordering
//                      the list to the new sort's data.
//   6. Fail-closed — an Unauthenticated session renders an ErrorState instead
//                    of reading the review providers (the redirect guard's
//                    belt-and-braces).
//   7. Service sub-line (backend `92280c3`) — `_masterReviewCard` gates the
//      «послуга: …» sub-line on serviceName being BOTH non-null AND
//      non-empty. Three items pin all three branches: a present name renders
//      the formatted sub-line, a null name omits it entirely, and — the
//      branch most likely to silently regress — an EMPTY-STRING name must
//      ALSO omit it (never a bare «послуга: » with nothing after the colon).
//
// Strategy: override [authProvider] with a stub Authenticated session and
// override [masterProfileProvider] with a stub whose [Master.id] is DISTINCT
// from the session user id — because the review endpoints must key on the
// Master-row id (`master.id != user.id`), NOT `session.user.id`. The two review
// family providers are therefore overridden by that Master-row id. A screen
// that (incorrectly) queried by `session.user.id` would miss these overrides and
// never render, so this wiring pins the corrected contract. The screen is hosted
// under a real GoRouter (pumpRoutedApp) so the sort sheet's `context.pop(option)`
// and ProfileScaffold's back affordance have a router in the tree.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/application/master_review_summary_notifier.dart';
import 'package:beautica_mobile/features/master/application/master_reviews_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/domain/master_review.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/presentation/master_received_reviews_screen.dart';
import 'package:beautica_mobile/features/review/presentation/widgets/rating_summary_card.dart';
import 'package:beautica_mobile/features/review/presentation/widgets/review_card.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/pump_app.dart';

// The session user id — NOT the id the review endpoints key on.
const String _kUserId = 'user-master-1';

// The Master-row id resolved from the loaded profile — DISTINCT from the user
// id. The review family providers are keyed on THIS id (the corrected
// contract): `master.id != user.id`.
const String _kMasterId = 'master-self-9';

const User _masterUser = User(
  id: _kUserId,
  email: 'master@beautica.ua',
  role: UserRole.independentMaster,
  firstName: 'Олена',
  lastName: 'Ковальчук',
);

const Master _stubMaster = Master(
  id: _kMasterId,
  firstName: 'Олена',
  lastName: 'Ковальчук',
  avgRating: 4.0,
  reviewCount: 3,
  type: MasterType.independentMaster,
);

class _StubAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async =>
      const AuthSession.authenticated(user: _masterUser, accessToken: 'token');
}

class _UnauthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.unauthenticated();
}

class _StubMasterProfileNotifier extends MasterProfile {
  @override
  Future<Master> build() async => _stubMaster;
}

const MasterReviewSummary _summary = MasterReviewSummary(
  avgRating: 4.0,
  reviewCount: 3,
  distribution: <int>[1, 1, 1, 0, 0],
);

MasterReviewItem _item(
  String id,
  String name,
  int rating, {
  String? serviceName,
}) => MasterReviewItem(
  id: id,
  clientDisplayName: name,
  rating: rating,
  comment: 'Коментар $id',
  createdAt: DateTime.utc(2026, 6, 10, 10),
  serviceName: serviceName,
);

final List<MasterReviewItem> _newestList = <MasterReviewItem>[
  _item('mr-a1', 'Іра К.', 5),
  _item('mr-a2', 'Оля В.', 4),
];

final List<MasterReviewItem> _oldestList = <MasterReviewItem>[
  _item('mr-b1', 'Ніна С.', 3),
  _item('mr-b2', 'Тарас Д.', 4),
];

GoRouter _router() => GoRouter(
  initialLocation: '/reviews',
  routes: <RouteBase>[
    GoRoute(
      path: '/reviews',
      builder: (BuildContext context, GoRouterState state) =>
          const MasterReceivedReviewsScreen(),
    ),
  ],
);

void main() {
  group('loading state', () {
    testWidgets('shows skeleton blocks while the list is loading', (
      tester,
    ) async {
      await tester.pumpRoutedApp(
        _router(),
        overrides: <Object>[
          authProvider.overrideWith(_StubAuthNotifier.new),
          masterProfileProvider.overrideWith(_StubMasterProfileNotifier.new),
          masterReviewSummaryProvider(
            _kMasterId,
          ).overrideWith((ref) => _summary),
          masterReviewsProvider(
            _kMasterId,
            MasterReviewSort.newest,
          ).overrideWith((ref) => Completer<List<MasterReviewItem>>().future),
        ],
      );
      // Resolve the async auth build without settling the repeating shimmer.
      await tester.pump();
      await tester.pump();

      expect(find.byType(SkeletonBlock), findsWidgets);
      expect(find.byKey(const Key('master-reviews-empty')), findsNothing);
    });
  });

  group('empty state', () {
    testWidgets('renders the empty placeholder when the list is empty', (
      tester,
    ) async {
      await tester.pumpRoutedApp(
        _router(),
        overrides: <Object>[
          authProvider.overrideWith(_StubAuthNotifier.new),
          masterProfileProvider.overrideWith(_StubMasterProfileNotifier.new),
          masterReviewSummaryProvider(
            _kMasterId,
          ).overrideWith((ref) => _summary),
          masterReviewsProvider(
            _kMasterId,
            MasterReviewSort.newest,
          ).overrideWith((ref) => const <MasterReviewItem>[]),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('master-reviews-empty')), findsOneWidget);
      expect(find.byType(ReviewCard), findsNothing);
      // The summary header still renders above the empty list.
      expect(find.byType(RatingSummaryCard), findsOneWidget);
    });
  });

  group('error + retry', () {
    testWidgets('list error renders an ErrorState whose retry reveals the data', (
      tester,
    ) async {
      int calls = 0;
      await tester.pumpRoutedApp(
        _router(),
        overrides: <Object>[
          authProvider.overrideWith(_StubAuthNotifier.new),
          masterProfileProvider.overrideWith(_StubMasterProfileNotifier.new),
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
            return _newestList;
          }),
        ],
        // Disable Riverpod's retry so the first AsyncError settles deterministically.
        retry: (_, _) => null,
      );
      await tester.pumpAndSettle();

      // The typed NetworkFailure surfaces its specific copy via ErrorState.
      expect(find.byType(ErrorState), findsOneWidget);
      final retry = find.byKey(const Key('error_state_retry_button'));
      expect(retry, findsOneWidget);
      expect(find.byType(ReviewCard), findsNothing);

      // Tap retry → invalidate re-runs the fetch → the data now renders.
      await tester.tap(retry);
      await tester.pumpAndSettle();

      expect(calls, greaterThanOrEqualTo(2));
      expect(find.byType(ErrorState), findsNothing);
      expect(find.byKey(const Key('master-review-mr-a1')), findsOneWidget);
    });
  });

  group('data state', () {
    testWidgets('renders one ReviewCard per item + the summary card with a '
        'concrete backend value', (tester) async {
      await tester.pumpRoutedApp(
        _router(),
        overrides: <Object>[
          authProvider.overrideWith(_StubAuthNotifier.new),
          masterProfileProvider.overrideWith(_StubMasterProfileNotifier.new),
          masterReviewSummaryProvider(
            _kMasterId,
          ).overrideWith((ref) => _summary),
          masterReviewsProvider(
            _kMasterId,
            MasterReviewSort.newest,
          ).overrideWith((ref) => _newestList),
        ],
      );
      await tester.pumpAndSettle();

      // One card per item, targeted by the composed master-review key.
      expect(find.byType(ReviewCard), findsNWidgets(_newestList.length));
      expect(find.byKey(const Key('master-review-mr-a1')), findsOneWidget);
      expect(find.byKey(const Key('master-review-mr-a2')), findsOneWidget);

      // Summary card present with the average bound from the summary data
      // (a concrete value, not smoke-only).
      expect(find.byType(RatingSummaryCard), findsOneWidget);
      final Text avg = tester.widget<Text>(
        find.byKey(const Key('master-review-summary-average')),
      );
      expect(avg.data, '4.0');

      // i18n-finder-ok: masked client name is backend data, not UI copy.
      expect(find.text('Іра К.'), findsOneWidget);
    });
  });

  group('sort re-query', () {
    testWidgets('selecting a new sort re-keys the provider and reorders the '
        'list to the new sort data', (tester) async {
      await tester.pumpRoutedApp(
        _router(),
        overrides: <Object>[
          authProvider.overrideWith(_StubAuthNotifier.new),
          masterProfileProvider.overrideWith(_StubMasterProfileNotifier.new),
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
      expect(find.byKey(const Key('master-review-mr-a1')), findsOneWidget);
      expect(find.byKey(const Key('master-review-mr-b1')), findsNothing);

      // Open the sort sheet.
      await tester.tap(find.byKey(const Key('master-reviews-sort-button')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('master-review-sort-option-oldest')),
        findsOneWidget,
      );

      // Select OLDEST → sheet pops → screen re-keys to (id, oldest).
      await tester.tap(
        find.byKey(const Key('master-review-sort-option-oldest')),
      );
      await tester.pumpAndSettle();

      // The list observably switched to the OLDEST dataset.
      expect(find.byKey(const Key('master-review-mr-b1')), findsOneWidget);
      expect(find.byKey(const Key('master-review-mr-a1')), findsNothing);
    });
  });

  group('fail-closed (unauthenticated)', () {
    testWidgets(
      'renders an ErrorState instead of reading the review providers',
      (tester) async {
        var summaryRead = false;
        var listRead = false;
        await tester.pumpRoutedApp(
          _router(),
          overrides: <Object>[
            authProvider.overrideWith(_UnauthNotifier.new),
            masterReviewSummaryProvider(_kMasterId).overrideWith((ref) {
              summaryRead = true;
              return _summary;
            }),
            masterReviewsProvider(
              _kMasterId,
              MasterReviewSort.newest,
            ).overrideWith((ref) {
              listRead = true;
              return _newestList;
            }),
          ],
        );
        await tester.pumpAndSettle();

        expect(find.byType(ErrorState), findsOneWidget);
        expect(find.byType(RatingSummaryCard), findsNothing);
        expect(find.byType(ReviewCard), findsNothing);
        // The fail-closed branch must short-circuit BEFORE any review fetch.
        expect(summaryRead, isFalse);
        expect(listRead, isFalse);
      },
    );
  });

  group('title', () {
    testWidgets('renders the localised «Мої відгуки» title', (tester) async {
      await tester.pumpRoutedApp(
        _router(),
        overrides: <Object>[
          authProvider.overrideWith(_StubAuthNotifier.new),
          masterProfileProvider.overrideWith(_StubMasterProfileNotifier.new),
          masterReviewSummaryProvider(
            _kMasterId,
          ).overrideWith((ref) => _summary),
          masterReviewsProvider(
            _kMasterId,
            MasterReviewSort.newest,
          ).overrideWith((ref) => _newestList),
        ],
      );
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(MasterReceivedReviewsScreen)),
      );
      expect(find.text(l10n.masterReviewsTitle), findsWidgets);
    });
  });

  group('service sub-line (backend serviceName)', () {
    // One item per branch of `_masterReviewCard`'s
    // `service != null && service.isNotEmpty` guard: present, null, empty.
    final List<MasterReviewItem> serviceItems = <MasterReviewItem>[
      _item('mr-svc-present', 'Марта Л.', 5, serviceName: 'Манікюр'),
      _item('mr-svc-null', 'Дарʼя П.', 4),
      _item('mr-svc-empty', 'Софія Н.', 3, serviceName: ''),
    ];

    Future<void> pumpServiceItems(WidgetTester tester) async {
      await tester.pumpRoutedApp(
        _router(),
        overrides: <Object>[
          authProvider.overrideWith(_StubAuthNotifier.new),
          masterProfileProvider.overrideWith(_StubMasterProfileNotifier.new),
          masterReviewSummaryProvider(
            _kMasterId,
          ).overrideWith((ref) => _summary),
          masterReviewsProvider(
            _kMasterId,
            MasterReviewSort.newest,
          ).overrideWith((ref) => serviceItems),
        ],
      );
      await tester.pumpAndSettle();
    }

    testWidgets('renders the «послуга: …» sub-line when serviceName is present', (
      tester,
    ) async {
      await pumpServiceItems(tester);

      final l10n = AppLocalizations.of(
        tester.element(find.byType(MasterReceivedReviewsScreen)),
      );
      final Finder card = find.byKey(const Key('master-review-mr-svc-present'));
      expect(card, findsOneWidget);
      expect(
        find.descendant(
          of: card,
          // i18n-finder-ok: 'Манікюр' is fixture service-name data, not translated UI copy
          matching: find.text(l10n.salonReviewServicePrefix('Манікюр')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.byIcon(Icons.spa_outlined)),
        findsOneWidget,
      );
    });

    testWidgets('omits the sub-line entirely when serviceName is null', (
      tester,
    ) async {
      await pumpServiceItems(tester);

      final Finder card = find.byKey(const Key('master-review-mr-svc-null'));
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.byIcon(Icons.spa_outlined)),
        findsNothing,
      );
    });

    testWidgets(
      'omits the sub-line when serviceName is an empty string (guards '
      'non-null AND non-empty — never a bare «послуга: »)',
      (tester) async {
        await pumpServiceItems(tester);

        final Finder card = find.byKey(const Key('master-review-mr-svc-empty'));
        expect(card, findsOneWidget);
        expect(
          find.descendant(of: card, matching: find.byIcon(Icons.spa_outlined)),
          findsNothing,
        );
        // Belt-and-braces: no partial «послуга:» text rendered anywhere under
        // this card — guards against a bare "послуга: " with nothing after
        // the colon.
        expect(
          find.descendant(of: card, matching: find.textContaining('послуга')),
          findsNothing,
        );
      },
    );
  });
}

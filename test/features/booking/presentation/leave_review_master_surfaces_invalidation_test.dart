// mobile-qa REGRESSION SUITE — «залишив відгук, а профіль майстра не змінився».
//
// THE BUG THIS FILE PINS
// ----------------------
// A client left a review on a COMPLETED booking and, WITHOUT killing the app,
// re-opened the master's public profile: the new review was absent and the
// rating / review-count were stale. It self-healed after 5 minutes or a cold
// restart — the shape that makes a real bug look intermittent.
//
// Root cause: `leave_review_notifier.dart` invalidated ONLY
// `bookingDetailProvider(bookingId)`. The three providers backing the master's
// public surfaces each hold `ref.keepAlive()` behind a 5-minute TTL, so nothing
// refetched:
//   • publicMasterProfileProvider(masterId)  — carries avgRating / reviewCount
//   • masterReviewSummaryProvider(masterId)  — the aggregate + distribution
//   • masterReviewsProvider(masterId, sort)  — a family keyed on (id, SORT)
//
// The fix is `invalidateMasterReviewSurfaces(ref, masterId)`
// (`lib/features/master/presentation/master_review_invalidation.dart`), called
// from the success branch of `LeaveReviewScreen._submit`.
//
// WHAT THIS SUITE ASSERTS, AND WHY IN THIS SHAPE
// ----------------------------------------------
// 1. Refetch is proven by a SECOND REPOSITORY CALL (mocktail call counts), never
//    by poking at Riverpod internals and never by `value == null` — an
//    invalidated provider RETAINS its previous `.value`, so a null-check style
//    assertion here would be permanently green (project memory: "Riverpod
//    seamless-invalidate gotcha").
//
// 2. All FOUR `MasterReviewSort` values are pinned INDIVIDUALLY, not as a total.
//    `masterReviewsProvider` is a family keyed on (masterId, sort), so each sort
//    is its own cache entry; a future edit that shortens the loop to
//    `[MasterReviewSort.newest]` would leave a client who had switched to
//    «Найвищий рейтинг» looking at a page predating their own review. A summed
//    assertion would not catch that; four separate ones do.
//
// 3. The warm subscriptions are CONTAINER-level (`container.listen`), NOT widget
//    consumers. Deliberate: Riverpod 3 PAUSES consumers that a pushed route
//    covers, so a warming Consumer sitting under the pushed review screen would
//    defer its rebuild to resume-time and the test would be asserting pause/
//    resume scheduling rather than the invalidation itself (project memory:
//    "Riverpod offstage-pause invalidate gotcha"). A container listener is never
//    paused, so a refetch that does not happen synchronously is a real failure.
//
// 4. The screen is reached with the REAL `context.push` the app uses — never
//    `router.go`, which resolves a different match and false-passes navigation
//    assertions (project memory: "go_router push excludes fullPath").
//
// MUTATION-PROBED: with `invalidateMasterReviewSurfaces(ref, booking.masterId)`
// commented out at `leave_review_screen.dart:119`, every test below fails on its
// own assertion (expected 2, actual 1). See the QA report for the verbatim red.

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booking_detail_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/leave_review_screen.dart';
import 'package:beautica_mobile/features/master/application/master_review_summary_notifier.dart';
import 'package:beautica_mobile/features/master/application/master_reviews_notifier.dart';
import 'package:beautica_mobile/features/master/application/public_master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/domain/master_review.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/pump_app.dart';

const String _bookingId = 'b1';
const String _masterId = 'm1';

class _MockBookingRepository extends Mock implements BookingRepository {}

class _MockMasterRepository extends Mock implements MasterRepository {}

class _MockServiceRepository extends Mock implements ServiceRepository {}

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

/// Settled CLIENT session — `publicMasterProfileProvider` `ref.watch`es
/// [authProvider] for auth-boundary eviction, so the real notifier would
/// otherwise reach for secure storage.
class _StubAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.authenticated(
    user: User(id: 'client-1', email: 'c@beautica.ua', role: UserRole.client),
    accessToken: 'test-token',
  );
}

Booking _booking({required bool canReview}) {
  // This instant is deliberately in the PAST and must stay pinned. The fixture
  // is a COMPLETED visit — the only state a client can review — so a
  // now-relative anchor is not merely unnecessary here, it would be WRONG:
  // `futureBookingStart()` would produce a completed booking that has not
  // happened yet, and `BookingDisplayX` would render it as upcoming.
  //
  // It is therefore not the time bomb this gate exists to stop: a past instant
  // can never become "upcoming" later, which is the exemption the gate itself
  // documents. It trips only because the constructor rule compares the YEAR
  // (`YYYY >= current year`), not the full date, so a within-current-year past
  // literal reads as future to it. The value also stays deterministic against
  // the widget tier's clock, which no assertion in this file reads.
  // future-date-ok: pinned PAST instant for a COMPLETED, reviewable booking.
  final DateTime start = DateTime.utc(2026, 7, 10, 15);
  return Booking(
    id: _bookingId,
    masterId: _masterId,
    masterFirstName: 'Софія',
    masterLastName: 'Бондар',
    masterType: 'INDEPENDENT_MASTER',
    serviceId: 's1',
    serviceName: 'Манікюр з покриттям',
    categoryName: 'Манікюр',
    cityLabel: 'Київ',
    durationMinutes: 90,
    price: 650,
    startAt: start,
    endAt: start.add(const Duration(minutes: 90)),
    status: BookingStatus.completed,
    canReview: canReview,
  );
}

const Master _master = Master(
  id: _masterId,
  firstName: 'Софія',
  lastName: 'Бондар',
  city: 'Київ',
  avgRating: 4.8,
  reviewCount: 47,
  type: MasterType.independentMaster,
);

const List<MasterService> _services = <MasterService>[
  MasterService(
    id: 'svc-1',
    serviceDefId: 'def-1',
    name: 'Манікюр з покриттям',
    durationMinutes: 90,
    priceMin: 500,
    priceDisplay: '500 ₴',
    category: 'NAILS',
  ),
];

/// Live repository fetch counters, incremented inside the mock answers.
///
/// NOT `verify(...).callCount`: mocktail's `verify` CONSUMES the recorded calls,
/// so a baseline `expect(count, 1)` would zero the log and the post-submit
/// assertion would read 1 for a correctly-refetched provider — a test that fails
/// on working code. Plain counters are also what makes the stubs strict (M4):
/// each `when(...)` below is registered for the CONCRETE (masterId, sort), so a
/// call with any other argument finds no stub and throws instead of quietly
/// incrementing the wrong bucket.
class _Counts {
  int profile = 0;
  int summary = 0;
  final Map<MasterReviewSort, int> reviews = <MasterReviewSort, int>{
    for (final MasterReviewSort s in MasterReviewSort.values) s: 0,
  };
}

/// Everything the suite needs to drive one submit and read the resulting
/// repository call counts.
class _Harness {
  _Harness(this.counts, this.bookingRepo);

  final _Counts counts;
  final _MockBookingRepository bookingRepo;

  /// `getMasterById` fetch count — the profile provider's repository read.
  int get profileFetches => counts.profile;

  int get summaryFetches => counts.summary;

  int reviewFetches(MasterReviewSort sort) => counts.reviews[sort]!;
}

/// Boots `/host` (an inert screen), warms every master-review surface through
/// CONTAINER-level subscriptions, then pushes the REAL review route on top and
/// returns once [LeaveReviewScreen] is mounted.
Future<_Harness> _pumpWarmedAndPushReview(WidgetTester tester) async {
  final _MockMasterRepository masterRepo = _MockMasterRepository();
  final _MockServiceRepository serviceRepo = _MockServiceRepository();
  final _MockBookingRepository bookingRepo = _MockBookingRepository();

  final _Counts counts = _Counts();

  when(() => masterRepo.getMasterById(_masterId)).thenAnswer((_) async {
    counts.profile++;
    return _master;
  });
  when(
    () => serviceRepo.getMasterServices(_masterId),
  ).thenAnswer((_) async => _services);
  when(() => masterRepo.getMasterReviewSummary(_masterId)).thenAnswer((
    _,
  ) async {
    counts.summary++;
    return const MasterReviewSummary(avgRating: 4.8, reviewCount: 47);
  });
  for (final MasterReviewSort s in MasterReviewSort.values) {
    when(
      () => masterRepo.getMasterReviews(masterId: _masterId, sort: s),
    ).thenAnswer((_) async {
      counts.reviews[s] = counts.reviews[s]! + 1;
      return <MasterReviewItem>[];
    });
  }
  when(
    () => bookingRepo.createReview(
      bookingId: any(named: 'bookingId'),
      rating: any(named: 'rating'),
      comment: any(named: 'comment'),
    ),
  ).thenAnswer((_) async {});

  final GoRouter router = GoRouter(
    initialLocation: '/host',
    routes: <RouteBase>[
      GoRoute(
        path: '/host',
        builder: (BuildContext context, _) => Scaffold(
          body: Center(
            child: TextButton(
              key: const Key('go-review'),
              // The REAL production affordance is a `context.push`; `router.go`
              // would replace the stack and change what "pop back" means.
              onPressed: () =>
                  context.push(RouteNames.bookingReview(_bookingId)),
              child: const Text('go'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/bookings/:bookingId/review',
        builder: (BuildContext context, GoRouterState state) =>
            LeaveReviewScreen(bookingId: state.pathParameters['bookingId']!),
      ),
    ],
  );

  await tester.pumpRoutedApp(
    router,
    overrides: <Object>[
      authProvider.overrideWith(_StubAuthNotifier.new),
      screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
      masterRepositoryProvider.overrideWithValue(masterRepo),
      publicServiceRepositoryProvider.overrideWithValue(serviceRepo),
      bookingRepositoryProvider.overrideWithValue(bookingRepo),
      bookingDetailProvider(
        _bookingId,
      ).overrideWith((Ref ref) async => _booking(canReview: true)),
    ],
  );
  await tester.pumpAndSettle();

  final ProviderContainer container = ProviderScope.containerOf(
    tester.element(find.byKey(const Key('go-review'))),
  );

  // Resolve auth BEFORE the profile loader first builds, so the settled session
  // is already there and the AsyncLoading→AsyncData transition cannot mark the
  // loader dirty and inflate `getMasterById` to 2 before the submit even runs.
  await container.read(authProvider.future);

  // ── Warm every surface through container-level listeners (never paused). ──
  container.listen(publicMasterProfileProvider(_masterId), (_, _) {});
  container.listen(masterReviewSummaryProvider(_masterId), (_, _) {});
  for (final MasterReviewSort s in MasterReviewSort.values) {
    container.listen(masterReviewsProvider(_masterId, s), (_, _) {});
  }
  await container.read(publicMasterProfileProvider(_masterId).future);
  await container.read(masterReviewSummaryProvider(_masterId).future);
  for (final MasterReviewSort s in MasterReviewSort.values) {
    await container.read(masterReviewsProvider(_masterId, s).future);
  }
  await tester.pumpAndSettle();

  // Push the review screen over `/host` exactly as the booking detail does.
  await tester.tap(find.byKey(const Key('go-review')));
  await tester.pumpAndSettle();
  expect(find.byType(LeaveReviewScreen), findsOneWidget);

  return _Harness(counts, bookingRepo);
}

/// Taps a star and the submit CTA, then settles. Returns with the screen popped
/// (submit succeeds in every test here).
Future<void> _submitReview(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey<String>('review-star-5')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('leave-review-submit')));
  await tester.pumpAndSettle();
}

void main() {
  group('LeaveReviewScreen — a successful submit refreshes the master public '
      'surfaces', () {
    testWidgets(
      'the submit really succeeded and popped — precondition for every '
      'refetch assertion below',
      (tester) async {
        final _Harness h = await _pumpWarmedAndPushReview(tester);

        // Baseline: exactly one fetch per surface after warming.
        expect(h.profileFetches, 1);
        expect(h.summaryFetches, 1);
        for (final MasterReviewSort s in MasterReviewSort.values) {
          expect(h.reviewFetches(s), 1, reason: 'warm fetch for $s');
        }

        await _submitReview(tester);

        verify(
          () => h.bookingRepo.createReview(
            bookingId: _bookingId,
            rating: 5,
            comment: '',
          ),
        ).called(1);
        expect(
          find.byType(LeaveReviewScreen),
          findsNothing,
          reason:
              'the fan-out runs in the SUCCESS branch, before the pop — if '
              'the screen never popped, the refetch tests below would be '
              'measuring a failed submit instead.',
        );

        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byKey(const Key('go-review'))),
        );
        await tester.pumpUntilGone(find.text(l10n.reviewSubmitSuccess));
      },
    );

    testWidgets('publicMasterProfileProvider(masterId) refetches — the stale '
        'avgRating / reviewCount on the identity card', (tester) async {
      final _Harness h = await _pumpWarmedAndPushReview(tester);
      expect(h.profileFetches, 1);

      await _submitReview(tester);

      expect(
        h.profileFetches,
        2,
        reason:
            'the public profile carries avgRating/reviewCount behind a '
            '5-minute keepAlive; without the fan-out the client re-opens '
            'the master and the rating has not moved.',
      );

      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byKey(const Key('go-review'))),
      );
      await tester.pumpUntilGone(find.text(l10n.reviewSubmitSuccess));
    });

    testWidgets(
      'masterReviewSummaryProvider(masterId) refetches — the aggregate + '
      'distribution above the review list',
      (tester) async {
        final _Harness h = await _pumpWarmedAndPushReview(tester);
        expect(h.summaryFetches, 1);

        await _submitReview(tester);

        expect(
          h.summaryFetches,
          2,
          reason:
              'the summary is an independent keepAlive cache — nothing else '
              'refreshes it after a review lands.',
        );

        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byKey(const Key('go-review'))),
        );
        await tester.pumpUntilGone(find.text(l10n.reviewSubmitSuccess));
      },
    );

    // ── The per-sort loop, pinned ONE SORT AT A TIME. ────────────────────
    //
    // Generated rather than hand-written so a fifth MasterReviewSort value
    // cannot be added without this suite growing a case for it. Each case
    // asserts ONLY its own bucket: a partial loop (e.g. `newest` only) leaves
    // the other three green-by-cache and would sail through a summed count.
    for (final MasterReviewSort sort in MasterReviewSort.values) {
      testWidgets(
        'masterReviewsProvider(masterId, ${sort.name}) refetches — each '
        '(masterId, sort) pair is its OWN cache entry',
        (tester) async {
          final _Harness h = await _pumpWarmedAndPushReview(tester);
          expect(h.reviewFetches(sort), 1);

          await _submitReview(tester);

          expect(
            h.reviewFetches(sort),
            2,
            reason:
                'the ${sort.wireValue} bucket must be invalidated too — a '
                'client who had switched to this sort would otherwise still '
                'be looking at a page that predates their own review.',
          );

          final AppLocalizations l10n = AppLocalizations.of(
            tester.element(find.byKey(const Key('go-review'))),
          );
          await tester.pumpUntilGone(find.text(l10n.reviewSubmitSuccess));
        },
      );
    }
  });
}

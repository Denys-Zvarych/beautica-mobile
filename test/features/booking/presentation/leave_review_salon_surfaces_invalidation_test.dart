// mobile-qa REGRESSION SUITE — «залишив відгук, а профіль САЛОНУ не змінився».
//
// THE BUG THIS FILE PINS
// ----------------------
// The salon-side half of the bug `848e8929` fixed for masters. A client leaves
// a review on a COMPLETED booking made at a SALON and, without killing the app,
// opens that salon's public profile: the average has not moved and their review
// is absent. It self-heals after 5 minutes or a cold restart — the shape that
// makes a real bug look intermittent.
//
// Root cause: `LeaveReviewScreen._submit` fanned out to the MASTER triplet only.
// The three providers backing the salon's surfaces each hold `ref.keepAlive()`
// behind a 5-minute TTL, so nothing refetched:
//   • publicSalonProfileProvider(salonId)  — hero avgRating / reviewCount
//   • salonReviewSummaryProvider(salonId)  — the aggregate + distribution
//   • salonReviewsProvider(salonId, sort)  — a family keyed on (id, SORT)
//
// The backend was already correct on this path — `ReviewEventListener`
// recalculates `salons.avg_rating` / `review_count` and evicts its caches
// before the 201 returns. This was purely the client's own cache.
//
// The fix is `invalidateSalonReviewSurfaces(ref, salonId)`
// (`lib/features/review/presentation/review_surface_invalidation.dart`), called
// from the success branch of `LeaveReviewScreen._submit` and GUARDED on a
// non-null `booking.salonId`.
//
// WHAT THIS SUITE ASSERTS, AND WHY IN THIS SHAPE
// ----------------------------------------------
// Deliberately mirrors `leave_review_master_surfaces_invalidation_test.dart`
// clause for clause, because the same four traps apply:
//
// 1. Refetch is proven by a SECOND REPOSITORY CALL (plain counters), never by
//    poking at Riverpod internals and never by `value == null` — an invalidated
//    provider RETAINS its previous `.value`, so a null-check assertion here
//    would be permanently green (project memory: "Riverpod seamless-invalidate
//    gotcha"). Counters rather than `verify(...).callCount` because mocktail's
//    `verify` CONSUMES the recorded calls, so a baseline `expect(count, 1)`
//    would zero the log and make the post-submit read 1 on working code.
//
// 2. All FOUR `SalonReviewSort` values are pinned INDIVIDUALLY, not as a total.
//    `salonReviewsProvider` is a family keyed on (salonId, sort) and
//    `salon_reviews_section.dart` watches it with a LOCALLY-held sort, so each
//    sort is its own cache entry. An implementation that drops the loop to
//    `[SalonReviewSort.newest]` passes a summed assertion and fails these.
//
// 3. The warm subscriptions are CONTAINER-level (`container.listen`), NOT widget
//    consumers. Riverpod 3 PAUSES consumers a pushed route covers, so a warming
//    Consumer under the pushed review screen would defer its rebuild to
//    resume-time and this suite would be measuring pause/resume scheduling
//    instead of the invalidation (project memory: "Riverpod offstage-pause
//    invalidate gotcha"). A container listener is never paused.
//
// 4. The screen is reached with the REAL `context.push` the app uses — never
//    `router.go`, which resolves a different match and false-passes navigation
//    assertions (project memory: "go_router push excludes fullPath").
//
// THE NEGATIVE CASE IS NOT OPTIONAL. The last test drives an
// INDEPENDENT_MASTER booking (`salonId == null`) and asserts that NOT ONE salon
// provider refetches. It pins two things at once: the `if (salonId != null)`
// guard at the call site, and that nobody "helpfully" derived a salon key from
// `salonName` — the master fan-out must still fire, so a suite that only
// counted salon fetches downward could not tell the guard from a no-op submit.
//
// MUTATION-PROBED: with `invalidateSalonReviewSurfaces`'s body disabled, SIX of
// the eight tests here go red on their own assertion (`Expected: <2> / Actual:
// <1>`) — the profile, the summary and each of the four sort buckets. The other
// two stay green BY DESIGN and that is the correct result: the first only
// asserts that the submit succeeded and popped, and the last asserts the
// ABSENCE of salon invalidation, which a removed fan-out trivially satisfies.
// A negative test that went red under this mutation would be asserting the
// wrong thing.

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
import 'package:beautica_mobile/features/salon/application/public_salon_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_review_summary_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_reviews_notifier.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_master_summary.dart';
import 'package:beautica_mobile/features/salon/domain/salon_review.dart';
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
const String _salonId = 'salon-xyz';

class _MockBookingRepository extends Mock implements BookingRepository {}

class _MockMasterRepository extends Mock implements MasterRepository {}

class _MockSalonRepository extends Mock implements SalonRepository {}

class _MockServiceRepository extends Mock implements ServiceRepository {}

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

/// Settled CLIENT session — BOTH `publicMasterProfileProvider` and
/// `publicSalonProfileProvider` `ref.watch` [authProvider] for auth-boundary
/// eviction, so the real notifier would otherwise reach for secure storage.
class _StubAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.authenticated(
    user: User(id: 'client-1', email: 'c@beautica.ua', role: UserRole.client),
    accessToken: 'test-token',
  );
}

Booking _booking({required String? salonId}) {
  // Deliberately a pinned PAST instant, and it must stay pinned: the fixture is
  // a COMPLETED visit — the only state a client can review — so a now-relative
  // anchor would be WRONG, not merely unnecessary (`futureBookingStart()` would
  // produce a completed booking that has not happened yet, and
  // `BookingDisplayX` would render it as upcoming). A past instant can never
  // become "upcoming" later, which is the exemption the date gate documents; it
  // trips only because the constructor rule compares the YEAR, not the date.
  // future-date-ok: pinned PAST instant for a COMPLETED, reviewable booking.
  final DateTime start = DateTime.utc(2026, 7, 10, 15);
  return Booking(
    id: _bookingId,
    masterId: _masterId,
    masterFirstName: 'Софія',
    masterLastName: 'Бондар',
    masterType: salonId == null ? 'INDEPENDENT_MASTER' : 'SALON_MASTER',
    // NOTE the asymmetry in the negative case: `salonName` is non-null ONLY
    // when `salonId` is. The negative fixture below leaves BOTH null, which is
    // the honest independent-master shape.
    salonName: salonId == null ? null : 'Студія Краси «Камелія»',
    salonId: salonId,
    serviceId: 's1',
    serviceName: 'Манікюр з покриттям',
    categoryName: 'Манікюр',
    cityLabel: 'Київ',
    durationMinutes: 90,
    price: 650,
    startAt: start,
    endAt: start.add(const Duration(minutes: 90)),
    status: BookingStatus.completed,
    canReview: true,
  );
}

const Master _master = Master(
  id: _masterId,
  firstName: 'Софія',
  lastName: 'Бондар',
  city: 'Київ',
  avgRating: 4.8,
  reviewCount: 47,
  type: MasterType.salonMaster,
);

const Salon _salon = Salon(
  id: _salonId,
  name: 'Студія Краси «Камелія»',
  avgRating: 4.0,
  reviewCount: 4,
);

const List<SalonMasterSummary> _salonMasters = <SalonMasterSummary>[
  SalonMasterSummary(
    masterId: _masterId,
    firstName: 'Софія',
    lastName: 'Бондар',
    avgRating: 4.8,
    reviewCount: 47,
    type: MasterType.salonMaster,
  ),
];

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
/// See the header (clause 1) for why these are plain counters and not
/// `verify(...).callCount`. Each `when(...)` is registered for the CONCRETE
/// (salonId, sort), so a call with any other argument finds no stub and throws
/// instead of quietly incrementing the wrong bucket (M4).
class _Counts {
  int salonProfile = 0;
  int salonSummary = 0;
  final Map<SalonReviewSort, int> salonReviews = <SalonReviewSort, int>{
    for (final SalonReviewSort s in SalonReviewSort.values) s: 0,
  };
  int masterProfile = 0;
}

class _Harness {
  _Harness(this.counts, this.bookingRepo);

  final _Counts counts;
  final _MockBookingRepository bookingRepo;

  /// `getSalonById` fetch count — `publicSalonProfileProvider`'s repository
  /// read. (It also calls `getSalonMasters` in the same `Future.wait`; one of
  /// the pair is enough to count the provider's rebuilds.)
  int get salonProfileFetches => counts.salonProfile;

  int get salonSummaryFetches => counts.salonSummary;

  int salonReviewFetches(SalonReviewSort sort) => counts.salonReviews[sort]!;

  int get masterProfileFetches => counts.masterProfile;
}

/// Boots `/host` (an inert screen), warms every salon-review surface through
/// CONTAINER-level subscriptions, then pushes the REAL review route on top and
/// returns once [LeaveReviewScreen] is mounted.
Future<_Harness> _pumpWarmedAndPushReview(
  WidgetTester tester, {
  required String? bookingSalonId,
}) async {
  final _MockMasterRepository masterRepo = _MockMasterRepository();
  final _MockSalonRepository salonRepo = _MockSalonRepository();
  final _MockServiceRepository serviceRepo = _MockServiceRepository();
  final _MockBookingRepository bookingRepo = _MockBookingRepository();

  final _Counts counts = _Counts();

  when(() => masterRepo.getMasterById(_masterId)).thenAnswer((_) async {
    counts.masterProfile++;
    return _master;
  });
  when(
    () => serviceRepo.getMasterServices(_masterId),
  ).thenAnswer((_) async => _services);
  when(() => masterRepo.getMasterReviewSummary(_masterId)).thenAnswer(
    (_) async => const MasterReviewSummary(avgRating: 4.8, reviewCount: 47),
  );
  for (final MasterReviewSort s in MasterReviewSort.values) {
    when(
      () => masterRepo.getMasterReviews(masterId: _masterId, sort: s),
    ).thenAnswer((_) async => <MasterReviewItem>[]);
  }

  when(() => salonRepo.getSalonById(_salonId)).thenAnswer((_) async {
    counts.salonProfile++;
    return _salon;
  });
  when(
    () => salonRepo.getSalonMasters(_salonId),
  ).thenAnswer((_) async => _salonMasters);
  when(() => salonRepo.getSalonReviewSummary(_salonId)).thenAnswer((_) async {
    counts.salonSummary++;
    return const SalonReviewSummary(avgRating: 4.0, reviewCount: 4);
  });
  for (final SalonReviewSort s in SalonReviewSort.values) {
    when(
      () => salonRepo.getSalonReviews(salonId: _salonId, sort: s),
    ).thenAnswer((_) async {
      counts.salonReviews[s] = counts.salonReviews[s]! + 1;
      return <SalonReviewItem>[];
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
      salonRepositoryProvider.overrideWithValue(salonRepo),
      publicServiceRepositoryProvider.overrideWithValue(serviceRepo),
      bookingRepositoryProvider.overrideWithValue(bookingRepo),
      bookingDetailProvider(
        _bookingId,
      ).overrideWith((Ref ref) async => _booking(salonId: bookingSalonId)),
    ],
  );
  await tester.pumpAndSettle();

  final ProviderContainer container = ProviderScope.containerOf(
    tester.element(find.byKey(const Key('go-review'))),
  );

  // Resolve auth BEFORE the salon/master loaders first build, so the settled
  // session is already there and the AsyncLoading→AsyncData transition cannot
  // mark a loader dirty and inflate its fetch count to 2 before the submit.
  await container.read(authProvider.future);

  // ── Warm every surface through container-level listeners (never paused). ──
  //
  // The SALON surfaces are warmed unconditionally, including in the negative
  // (independent-master) case. That is the point: the negative test must show
  // these are warm and STAY at 1, which is only meaningful if they were
  // subscribed in the first place.
  container.listen(publicSalonProfileProvider(_salonId), (_, _) {});
  container.listen(salonReviewSummaryProvider(_salonId), (_, _) {});
  for (final SalonReviewSort s in SalonReviewSort.values) {
    container.listen(salonReviewsProvider(_salonId, s), (_, _) {});
  }
  container.listen(publicMasterProfileProvider(_masterId), (_, _) {});
  container.listen(masterReviewSummaryProvider(_masterId), (_, _) {});
  for (final MasterReviewSort s in MasterReviewSort.values) {
    container.listen(masterReviewsProvider(_masterId, s), (_, _) {});
  }

  await container.read(publicSalonProfileProvider(_salonId).future);
  await container.read(salonReviewSummaryProvider(_salonId).future);
  for (final SalonReviewSort s in SalonReviewSort.values) {
    await container.read(salonReviewsProvider(_salonId, s).future);
  }
  await container.read(publicMasterProfileProvider(_masterId).future);
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

/// Drains the success snackbar so the next test starts from a quiet messenger.
Future<void> _drainSuccessSnackbar(WidgetTester tester) async {
  final AppLocalizations l10n = AppLocalizations.of(
    tester.element(find.byKey(const Key('go-review'))),
  );
  await tester.pumpUntilGone(find.text(l10n.reviewSubmitSuccess));
}

void main() {
  group('LeaveReviewScreen — a successful submit refreshes the SALON public '
      'surfaces', () {
    testWidgets(
      'the submit really succeeded and popped — precondition for every '
      'refetch assertion below',
      (tester) async {
        final _Harness h = await _pumpWarmedAndPushReview(
          tester,
          bookingSalonId: _salonId,
        );

        // Baseline: exactly one fetch per surface after warming.
        expect(h.salonProfileFetches, 1);
        expect(h.salonSummaryFetches, 1);
        for (final SalonReviewSort s in SalonReviewSort.values) {
          expect(h.salonReviewFetches(s), 1, reason: 'warm fetch for $s');
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

        await _drainSuccessSnackbar(tester);
      },
    );

    testWidgets('publicSalonProfileProvider(salonId) refetches — the stale '
        'avgRating / reviewCount on the salon hero card', (tester) async {
      final _Harness h = await _pumpWarmedAndPushReview(
        tester,
        bookingSalonId: _salonId,
      );
      expect(h.salonProfileFetches, 1);

      await _submitReview(tester);

      expect(
        h.salonProfileFetches,
        2,
        reason:
            'the public salon profile carries avgRating/reviewCount behind a '
            '5-minute keepAlive; without the fan-out the client re-opens the '
            'salon and the rating has not moved.',
      );

      await _drainSuccessSnackbar(tester);
    });

    testWidgets(
      'salonReviewSummaryProvider(salonId) refetches — the aggregate + '
      'distribution above the salon review list',
      (tester) async {
        final _Harness h = await _pumpWarmedAndPushReview(
          tester,
          bookingSalonId: _salonId,
        );
        expect(h.salonSummaryFetches, 1);

        await _submitReview(tester);

        expect(
          h.salonSummaryFetches,
          2,
          reason:
              'the summary is an independent keepAlive cache — nothing else '
              'refreshes it after a review lands.',
        );

        await _drainSuccessSnackbar(tester);
      },
    );

    // ── The per-sort loop, pinned ONE SORT AT A TIME. ────────────────────
    //
    // Generated rather than hand-written so a fifth SalonReviewSort value
    // cannot be added without this suite growing a case for it. Each case
    // asserts ONLY its own bucket: a partial loop (e.g. `newest` only) leaves
    // the other three green-by-cache and would sail through a summed count.
    for (final SalonReviewSort sort in SalonReviewSort.values) {
      testWidgets(
        'salonReviewsProvider(salonId, ${sort.name}) refetches — each '
        '(salonId, sort) pair is its OWN cache entry',
        (tester) async {
          final _Harness h = await _pumpWarmedAndPushReview(
            tester,
            bookingSalonId: _salonId,
          );
          expect(h.salonReviewFetches(sort), 1);

          await _submitReview(tester);

          expect(
            h.salonReviewFetches(sort),
            2,
            reason:
                'the ${sort.wireValue} bucket must be invalidated too — a '
                'client who had switched to this sort would otherwise still '
                'be looking at a page that predates their own review.',
          );

          await _drainSuccessSnackbar(tester);
        },
      );
    }

    // ── The GUARD. ───────────────────────────────────────────────────────
    testWidgets(
      'an INDEPENDENT_MASTER booking (salonId == null) invalidates NO salon '
      'provider — while the MASTER fan-out still fires',
      (tester) async {
        final _Harness h = await _pumpWarmedAndPushReview(
          tester,
          // The whole point of this case.
          bookingSalonId: null,
        );

        expect(h.salonProfileFetches, 1);
        expect(h.salonSummaryFetches, 1);
        for (final SalonReviewSort s in SalonReviewSort.values) {
          expect(h.salonReviewFetches(s), 1);
        }
        expect(h.masterProfileFetches, 1);

        await _submitReview(tester);

        // The master half MUST still have fired. Without this, every salon
        // assertion below would also pass against a submit that silently
        // failed or a fan-out that was deleted wholesale — the guard would be
        // indistinguishable from "nothing happened at all".
        expect(
          h.masterProfileFetches,
          2,
          reason:
              'the master fan-out is unconditional — if it did not fire, this '
              'test is measuring a broken submit, not the salon guard.',
        );

        expect(
          h.salonProfileFetches,
          1,
          reason:
              'THE GUARD: a booking with no salon must not invalidate a salon '
              'the client never had anything to do with. A 2 here means '
              'someone dropped the `if (salonId != null)` check — or derived '
              'a salon key from `salonName`, which is also null on this '
              'fixture and would have to have been invented.',
        );
        expect(h.salonSummaryFetches, 1, reason: 'THE GUARD (summary)');
        for (final SalonReviewSort s in SalonReviewSort.values) {
          expect(
            h.salonReviewFetches(s),
            1,
            reason: 'THE GUARD (${s.wireValue} bucket)',
          );
        }

        await _drainSuccessSnackbar(tester);
      },
    );
  });
}

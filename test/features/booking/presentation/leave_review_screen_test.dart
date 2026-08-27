// mobile-qa (Phase 14.6 — «ВІДГУК ПРО МАЙСТРА» leave-review) — behavioural
// suite for [LeaveReviewScreen] and the booking-detail entry CTA.
//
// The screen is the CLIENT's review form. This suite proves the state machine
// the phase exists for:
//   • the rating gate — the submit CTA is disabled at rating 0 and enabled the
//     instant a star is tapped (the ONLY required field);
//   • the star widget — tapping «5» fills all five and crossfades the live
//     «Чудово» readout;
//   • the submit wiring — a tap runs the REAL [LeaveReview] notifier through an
//     overridden [bookingRepositoryProvider] mock, so the exact
//     bookingId/rating/comment reaching `createReview` is asserted (never a mock
//     of the widget under test);
//   • success — the notifier invalidates `bookingDetailProvider` (the detail's
//     `canReview` re-resolves false), the screen shows «Дякуємо за відгук!» and
//     pops back to the detail;
//   • the `!canReview` info state — a stale `/bookings/{id}/review` deep link
//     lands on the not-reviewable body, NOT the form;
//   • an API failure ([ReviewNotAllowedFailure]) — the localized message
//     surfaces in a VelvetSnack and the client STAYS on the form (no pop);
//   • the fetch error + loading states behind the shared top bar.
//
// Plus the booking-detail ENTRY CTA: `booking-detail-leave-review` is present
// only when `canReview == true`, and tapping it PUSHES the review route (driven
// through the real `context.push` the screen uses — never `router.go`, which
// would yield a different match and false-pass; see the go_router push memory).
//
// Finders are key-first; every asserted string goes through l10n (CI no-raw-
// Cyrillic gate), matching booking_detail_screen_test.dart.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/booking/application/booking_detail_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/leave_review_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_feedback_card.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_strip.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/pump_app.dart';
import '../../../helpers/velvet_snack_matchers.dart';

const String _bookingId = 'b1';

class _MockBookingRepository extends Mock implements BookingRepository {}

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

Booking _booking({
  BookingStatus status = BookingStatus.completed,
  required bool canReview,
  // MO-7 — non-null when this booking is one service of a multi-service
  // VISIT. Defaults to null (a plain single-service booking) so every
  // existing call site is unaffected; see the "MO-7 regression pin" test
  // below for why this param exists.
  String? appointmentId,
  // Phase 240 — the master identity/rating fields the feedback card now
  // renders and routes on. `masterId` is settable because `booking_mapper`
  // maps `dto.masterId ?? ''`, so an EMPTY id is a reachable payload and it is
  // now a NAVIGATION TARGET.
  String masterId = 'm1',
  double? masterAvgRating,
  int? masterReviewCount,
}) {
  final DateTime start = DateTime.utc(2026, 7, 10, 15);
  return Booking(
    id: _bookingId,
    masterId: masterId,
    masterFirstName: 'Софія',
    masterLastName: 'Бондар',
    masterType: 'INDEPENDENT_MASTER',
    serviceId: 's1',
    serviceName: 'Манікюр з покриттям',
    categoryName: 'NAIL_SERVICE',
    cityLabel: 'Київ',
    street: 'вул. Хрещатик',
    buildingNo: '12',
    durationMinutes: 90,
    price: 650,
    startAt: start,
    endAt: start.add(const Duration(minutes: 90)),
    status: status,
    canReview: canReview,
    masterProfessionalTitle: 'Майстриня манікюру',
    appointmentId: appointmentId,
    masterAvgRating: masterAvgRating,
    masterReviewCount: masterReviewCount,
  );
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(LeaveReviewScreen)));

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // The review FORM + submit path
  // ─────────────────────────────────────────────────────────────────────────
  group('LeaveReviewScreen — form + submit', () {
    /// Boots a two-route GoRouter (`/host` ⇄ the real review route) with the
    /// review screen already PUSHED onto `/host` (so `context.pop()` has a
    /// destination to assert against). `/host` also watches
    /// `bookingDetailProvider(_bookingId)` and renders its `canReview` — so an
    /// invalidation from the notifier is observable AFTER the screen pops.
    Future<(GoRouter, _MockBookingRepository)> pumpReview(
      WidgetTester tester, {
      required Future<Booking> Function(Ref ref) detail,
      _MockBookingRepository? repo,
    }) async {
      final _MockBookingRepository r = repo ?? _MockBookingRepository();
      final GoRouter router = GoRouter(
        initialLocation: '/host',
        routes: <RouteBase>[
          GoRoute(
            path: '/host',
            builder: (BuildContext context, _) => Consumer(
              builder: (BuildContext context, WidgetRef ref, _) {
                final AsyncValue<Booking> async = ref.watch(
                  bookingDetailProvider(_bookingId),
                );
                return Scaffold(
                  body: Column(
                    children: <Widget>[
                      TextButton(
                        key: const Key('go-review'),
                        onPressed: () =>
                            context.push(RouteNames.bookingReview(_bookingId)),
                        child: const Text('go'),
                      ),
                      async.maybeWhen(
                        data: (Booking b) => Text(
                          'cr:${b.canReview}',
                          key: const Key('host-canreview'),
                        ),
                        orElse: () => const SizedBox.shrink(),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          GoRoute(
            path: '/bookings/:bookingId/review',
            builder: (BuildContext context, GoRouterState state) =>
                LeaveReviewScreen(
                  bookingId: state.pathParameters['bookingId']!,
                ),
          ),
        ],
      );

      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[
          screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
          bookingRepositoryProvider.overrideWithValue(r),
          bookingDetailProvider(_bookingId).overrideWith(detail),
        ],
      );
      await tester.pumpAndSettle();

      // Push the review route onto /host.
      await tester.tap(find.byKey(const Key('go-review')));
      await tester.pumpAndSettle();
      expect(find.byType(LeaveReviewScreen), findsOneWidget);
      return (router, r);
    }

    // ── Phase 240 — the master card's rating + its route into reviews ──────
    //
    // `booking_mapper.dart:119` maps `masterId: dto.masterId ?? ''`, so an
    // empty id is a reachable payload — and Phase 240 made this card a
    // NAVIGATION TARGET. `/masters//reviews` matches no route (go_router
    // compiles `:masterId` to `[^/]+`) and `app_router.dart` declares no
    // `errorBuilder`, so a tap on an empty id would dump the client on
    // go_router's "page not found".
    //
    // The RE-AUDIT gap this fills: mobile-dev pinned exactly this guard on the
    // «Записатись знову» CTA (`booking_detail_screen_test.dart`) and on
    // nothing else — but Phase 240 added TWO MORE unguarded push sites, this
    // card and the booking-detail master strip. Both are covered now.
    //
    // Paired positive/negative per M14: an "is null" assertion alone can pass
    // because the card is inert for some unrelated reason, so the populated
    // case must show it is live.
    testWidgets('an EMPTY masterId leaves the master card inert rather than '
        'pushing a route that cannot match', (tester) async {
      await pumpReview(
        tester,
        detail: (ref) async => _booking(canReview: true, masterId: ''),
      );

      final Finder card = find.byKey(const Key('leave-review-master-card'));
      expect(card, findsOneWidget);
      expect(
        tester.widget<MasterFeedbackCard>(card).onTap,
        isNull,
        reason:
            'a blank id means "we do not know which master" — the honest '
            'affordance is an inert card, not a button that breaks.',
      );
    });

    testWidgets('a populated masterId leaves the master card tappable', (
      tester,
    ) async {
      await pumpReview(
        tester,
        detail: (ref) async => _booking(canReview: true),
      );

      expect(
        tester
            .widget<MasterFeedbackCard>(
              find.byKey(const Key('leave-review-master-card')),
            )
            .onTap,
        isNotNull,
        reason:
            'the negative test above must be pinned to the empty-id guard, '
            'not to the card being dead in general.',
      );
    });

    testWidgets('the master card renders the booking\'s rating, and folds an '
        'unrated master onto «—» rather than «0.0»', (tester) async {
      await pumpReview(
        tester,
        detail: (ref) async => _booking(
          canReview: true,
          masterAvgRating: 4.9,
          masterReviewCount: 24,
        ),
      );

      final Finder card = find.byKey(const Key('leave-review-master-card'));
      expect(
        find.descendant(of: card, matching: find.text('4.9')),
        findsOneWidget,
        reason:
            'this screen was a dead end for ratings — a client about to write '
            'a review could not see what other clients had said.',
      );
      expect(
        find.descendant(of: card, matching: find.text('(24)')),
        findsOneWidget,
      );
    });

    testWidgets('a stale 0.0 average with an ABSENT count renders «—» on the '
        'master card', (tester) async {
      await pumpReview(
        tester,
        detail: (ref) async => _booking(
          canReview: true,
          masterAvgRating: 0,
          masterReviewCount: null,
        ),
      );

      final Finder card = find.byKey(const Key('leave-review-master-card'));
      expect(
        find.descendant(
          of: card,
          matching: find.text(MasterStrip.noRatingLabel),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('0.0')),
        findsNothing,
        reason: 'the exact artefact Phase 240 exists to remove',
      );
    });

    testWidgets('submit is disabled at rating 0 and enabled after a star tap', (
      tester,
    ) async {
      await pumpReview(
        tester,
        detail: (ref) async => _booking(canReview: true),
      );

      // Rating 0 → the submit CTA has a null onPressed (disabled).
      NeumorphicButton submit() => tester.widget<NeumorphicButton>(
        find.byKey(const Key('leave-review-submit')),
      );
      expect(
        submit().onPressed,
        isNull,
        reason: 'the required rating is unset, so submit must be disabled',
      );

      await tester.tap(find.byKey(const ValueKey<String>('review-star-3')));
      await tester.pumpAndSettle();

      expect(
        submit().onPressed,
        isNotNull,
        reason: 'a rating is now set, so submit must be enabled',
      );
    });

    testWidgets('tapping the 5th star fills all five and shows «Чудово»', (
      tester,
    ) async {
      await pumpReview(
        tester,
        detail: (ref) async => _booking(canReview: true),
      );

      await tester.tap(find.byKey(const ValueKey<String>('review-star-5')));
      await tester.pumpAndSettle();

      // All five stars are filled; none is left as an outline.
      //
      // Scoped to the INPUT: the screen now also renders the master's own ★
      // rating readout in the header card (`MasterRatingReadout`, M4), which
      // is a sixth `star_rounded` and has nothing to do with the value being
      // entered here. The unscoped count only ever worked by accident.
      expect(
        find.descendant(
          of: find.byKey(const Key('leave-review-stars')),
          matching: find.byIcon(Icons.star_rounded),
        ),
        findsNWidgets(5),
      );
      expect(find.byIcon(Icons.star_border_rounded), findsNothing);
      // The live readout crossfaded to the 5★ word.
      expect(find.text(_l10n(tester).reviewRatingLabel5), findsOneWidget);
    });

    testWidgets('submitting with a comment calls createReview with the exact '
        'bookingId, rating and comment', (tester) async {
      final _MockBookingRepository repo = _MockBookingRepository();
      when(
        () => repo.createReview(
          bookingId: any(named: 'bookingId'),
          rating: any(named: 'rating'),
          comment: any(named: 'comment'),
        ),
      ).thenAnswer((_) async {});

      await pumpReview(
        tester,
        repo: repo,
        detail: (ref) async => _booking(canReview: true),
      );

      await tester.tap(find.byKey(const ValueKey<String>('review-star-5')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('leave-review-comment')),
        'Чудова робота, дякую!',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('leave-review-submit')));
      await tester.pumpAndSettle();

      verify(
        () => repo.createReview(
          bookingId: _bookingId,
          rating: 5,
          comment: 'Чудова робота, дякую!',
        ),
      ).called(1);
    });

    testWidgets(
      'a successful submit invalidates bookingDetailProvider, shows the '
      'thank-you VelvetSnack and pops back to the detail',
      (tester) async {
        final _MockBookingRepository repo = _MockBookingRepository();
        // The "server": before the review exists canReview is true; the
        // createReview mock flips `reviewed`, so the notifier's invalidation
        // refetches a NOW-not-reviewable booking.
        bool reviewed = false;
        int fetches = 0;
        when(
          () => repo.createReview(
            bookingId: any(named: 'bookingId'),
            rating: any(named: 'rating'),
            comment: any(named: 'comment'),
          ),
        ).thenAnswer((_) async {
          reviewed = true;
        });

        final (GoRouter router, _) = await pumpReview(
          tester,
          repo: repo,
          detail: (ref) async {
            fetches++;
            return _booking(canReview: !reviewed);
          },
        );
        expect(fetches, 1, reason: 'the initial detail fetch');

        await tester.tap(find.byKey(const ValueKey<String>('review-star-4')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('leave-review-submit')));
        await tester.pumpAndSettle();

        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byKey(const Key('host-canreview'))),
        );
        // The write fired once with the chosen rating.
        verify(
          () =>
              repo.createReview(bookingId: _bookingId, rating: 4, comment: ''),
        ).called(1);
        // The thank-you VelvetSnack surfaced…
        expectVelvetSnack(
          l10n.reviewSubmitSuccess,
          variant: VelvetSnackVariant.success,
        );
        // …the screen popped back to /host…
        expect(find.byType(LeaveReviewScreen), findsNothing);
        expect(
          router.routerDelegate.currentConfiguration.uri.toString(),
          '/host',
        );
        // …and the invalidation forced a refetch that now says canReview:false.
        expect(fetches, 2, reason: 'ref.invalidate(bookingDetailProvider)');
        expect(find.text('cr:false'), findsOneWidget);

        await pumpPastVelvetSnack(tester);
      },
    );

    testWidgets(
      'a ReviewNotAllowedFailure surfaces the localized message and stays on '
      'the form (no pop)',
      (tester) async {
        final _MockBookingRepository repo = _MockBookingRepository();
        when(
          () => repo.createReview(
            bookingId: any(named: 'bookingId'),
            rating: any(named: 'rating'),
            comment: any(named: 'comment'),
          ),
        ).thenThrow(const ReviewNotAllowedFailure());

        await pumpReview(
          tester,
          repo: repo,
          detail: (ref) async => _booking(canReview: true),
        );

        await tester.tap(find.byKey(const ValueKey<String>('review-star-2')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('leave-review-submit')));
        await tester.pumpAndSettle();

        final AppLocalizations l10n = _l10n(tester);
        // The clean localized "can't be reviewed" message — never errUnknown.
        expectVelvetSnack(
          l10n.reviewErrNotAllowed,
          variant: VelvetSnackVariant.error,
        );
        expect(find.text(l10n.errUnknown), findsNothing);
        // The client is STILL on the review form (no pop on failure). The
        // review screen was reached via `context.push`, so its ImperativeRoute-
        // Match is dropped from `currentConfiguration.uri` (the go_router push
        // memory) — the mounted screen is the reliable "did not pop" proof.
        expect(find.byType(LeaveReviewScreen), findsOneWidget);

        await pumpPastVelvetSnack(tester);
      },
    );

    testWidgets(
      'a not-reviewable booking renders the info state, not the form',
      (tester) async {
        await pumpReview(
          tester,
          detail: (ref) async => _booking(canReview: false),
        );

        // The info state is shown…
        expect(
          find.byKey(const Key('leave-review-unavailable-back')),
          findsOneWidget,
        );
        expect(find.text(_l10n(tester).reviewUnavailableTitle), findsOneWidget);
        // …and the form (its stars + submit) is NOT.
        expect(find.byKey(const Key('leave-review-stars')), findsNothing);
        expect(find.byKey(const Key('leave-review-submit')), findsNothing);
      },
    );

    testWidgets('shows a spinner while the booking loads', (tester) async {
      final Completer<Booking> completer = Completer<Booking>();
      final GoRouter router = GoRouter(
        initialLocation: '/bookings/$_bookingId/review',
        routes: <RouteBase>[
          GoRoute(
            path: '/bookings/:bookingId/review',
            builder: (BuildContext context, GoRouterState state) =>
                LeaveReviewScreen(
                  bookingId: state.pathParameters['bookingId']!,
                ),
          ),
        ],
      );
      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[
          screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
          bookingDetailProvider(
            _bookingId,
          ).overrideWith((ref) => completer.future),
        ],
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // The back affordance is live even mid-fetch.
      expect(find.byKey(const Key('leave-review-back')), findsOneWidget);

      completer.complete(_booking(canReview: true));
      await tester.pumpAndSettle();
    });

    testWidgets('shows the error state with a retry on a failed fetch', (
      tester,
    ) async {
      final GoRouter router = GoRouter(
        initialLocation: '/bookings/$_bookingId/review',
        routes: <RouteBase>[
          GoRoute(
            path: '/bookings/:bookingId/review',
            builder: (BuildContext context, GoRouterState state) =>
                LeaveReviewScreen(
                  bookingId: state.pathParameters['bookingId']!,
                ),
          ),
        ],
      );
      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[
          screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
          bookingDetailProvider(
            _bookingId,
          ).overrideWith((ref) async => throw Exception('down')),
        ],
        retry: (_, _) => null,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('leave-review-error-retry')), findsOneWidget);
      // Tapping retry re-invalidates without throwing out of the widget.
      await tester.tap(find.byKey(const Key('leave-review-error-retry')));
      await tester.pump();
      expect(find.byKey(const Key('leave-review-error-retry')), findsOneWidget);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // The booking-detail ENTRY CTA (`booking-detail-leave-review`)
  // ─────────────────────────────────────────────────────────────────────────
  group('booking detail — leave-review entry CTA', () {
    /// Boots the detail screen inside a GoRouter whose review route is a keyed
    /// STUB, so a tap on the entry CTA (the screen's real `context.push`) is
    /// asserted by the stub mounting + the router landing on the review path.
    Future<GoRouter> pumpDetail(
      WidgetTester tester, {
      required bool canReview,
      // MO-7 — threaded through so the "visit leg" regression-pin test below
      // can seed a non-null appointmentId through the SAME harness the plain
      // single-service cases use, rather than a parallel setup.
      String? appointmentId,
    }) async {
      final GoRouter router = GoRouter(
        initialLocation: '/bookings/$_bookingId',
        routes: <RouteBase>[
          GoRoute(
            path: '/bookings/:bookingId',
            builder: (BuildContext context, GoRouterState state) =>
                BookingDetailScreen(
                  bookingId: state.pathParameters['bookingId']!,
                ),
          ),
          GoRoute(
            path: '/bookings/:bookingId/review',
            builder: (_, _) => const Scaffold(key: Key('review-stub')),
          ),
        ],
      );
      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[
          screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
          bookingRepositoryProvider.overrideWithValue(_MockBookingRepository()),
          bookingDetailProvider(_bookingId).overrideWith(
            (ref) async =>
                _booking(canReview: canReview, appointmentId: appointmentId),
          ),
        ],
      );
      await tester.pumpAndSettle();
      return router;
    }

    testWidgets(
      'a reviewable COMPLETED booking shows the CTA and tapping it PUSHES the '
      'review route',
      (tester) async {
        await pumpDetail(tester, canReview: true);

        final Finder cta = find.byKey(const Key('booking-detail-leave-review'));
        expect(cta, findsOneWidget);

        await tester.tap(cta);
        await tester.pumpAndSettle();

        // The real `context.push` landed on the review route (the stub mounted).
        // `currentConfiguration.uri` collapses to the parent on a push (the
        // go_router push memory), so the mounted stub is the reliable proof.
        expect(find.byKey(const Key('review-stub')), findsOneWidget);
      },
    );

    testWidgets('an already-reviewed COMPLETED booking hides the entry CTA', (
      tester,
    ) async {
      await pumpDetail(tester, canReview: false);

      expect(
        find.byKey(const Key('booking-detail-leave-review')),
        findsNothing,
      );
    });

    // ─────────────────────────────────────────────────────────────────────
    // MO-7 regression pin
    // ─────────────────────────────────────────────────────────────────────
    // The whole-visit review journey (`VisitCard` → `VisitDetailScreen` →
    // `AppointmentReviewScreen`) lost its only tap target when «Мої записи»
    // stopped grouping a visit's rows into one card (see
    // `my_bookings_visit_grouping_test.dart`'s file header). This test proves
    // the PER-SERVICE review journey survived that refactor: `_actions`
    // (`booking_detail_screen.dart`) gates the entry CTA on `booking.canReview`
    // alone — it never branches on `booking.appointmentId` — and every row in
    // the list (visit leg or not) now opens THIS same `BookingDetailScreen`.
    // A reviewable COMPLETED visit leg must therefore still show the CTA and
    // push the review route exactly like a plain single-service booking. If
    // this ever regresses, the client's only way to review a multi-service
    // visit's individual service is gone.
    testWidgets(
      'MO-7: a reviewable COMPLETED VISIT LEG (non-null appointmentId) still '
      'shows the entry CTA and tapping it pushes the review route — the '
      'per-service review journey survives the grouping removal',
      (tester) async {
        await pumpDetail(tester, canReview: true, appointmentId: 'appt-1');

        final Finder cta = find.byKey(const Key('booking-detail-leave-review'));
        expect(cta, findsOneWidget);

        await tester.tap(cta);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('review-stub')), findsOneWidget);
      },
    );
  });
}

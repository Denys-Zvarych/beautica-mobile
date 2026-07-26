// mobile-qa (track 7.x Wave B — «ВІДГУК ПРО КЛІЄНТА» leave-client-feedback) —
// behavioural suite for [LeaveClientFeedbackScreen].
//
// The screen is the PROVIDER's feedback-about-client form — the mirror image
// of `leave_review_screen_test.dart`'s CLIENT→MASTER suite, for the opposite
// direction. It proves:
//   • the rating gate — the submit CTA is disabled at rating 0 and enabled
//     the instant a star is tapped (the ONLY required field);
//   • the star widget — tapping «5» fills all five and crossfades the live
//     «Чудово» readout;
//   • the submit wiring — a tap runs the REAL [LeaveClientFeedback] notifier
//     through an overridden [clientReviewRepositoryProvider] mock, so the
//     exact bookingId/rating/comment reaching `createClientReview` is
//     asserted (never a mock of the widget under test);
//   • success — the screen shows «Відгук збережено» and pops back;
//   • a [ClientReviewAlreadyExistsFailure] (409) — the ONLY signal this
//     screen ever gets that feedback was already left, per the file header's
//     gating-limitation note — swaps the form for the not-reviewable info
//     state, no SnackBar;
//   • a [ClientReviewNotAllowedFailure] — the localized message surfaces in a
//     SnackBar and the provider STAYS on the form (no pop);
//   • the inline «Клієнт цього коментаря не побачить» reminder renders (the
//     thing that makes this screen more than a mirror of the client's own
//     leave-review form);
//   • the fetch error + loading states behind the shared top bar.
//
// Finders are key-first; every asserted string goes through l10n (CI no-raw-
// Cyrillic gate), matching leave_review_screen_test.dart.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/booking/application/booking_detail_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/client_review_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/leave_client_feedback_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/pump_app.dart';

const String _bookingId = 'b1';

class _MockClientReviewRepository extends Mock
    implements ClientReviewRepository {}

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

Booking _booking({
  BookingStatus status = BookingStatus.completed,
  String? clientFirstName = 'Олена',
  String? clientLastName = 'Ткаченко',
  String? clientId = 'c1',
}) {
  // A fixed PAST instant, not a stale future one (scripts/
  // forbid_stale_future_date_fixture.sh): this fixture defaults to a
  // COMPLETED booking, which is always in the past by construction, and
  // nothing in this suite reads `BookingDisplayX.isPast` or asserts on the
  // formatted date string — so there is no "upcoming" behaviour to anchor to
  // `DateTime.now()` for, unlike the reschedule/cancel-affordance fixtures
  // `futureBookingStart()` exists for. A year < the current year is exempt
  // from the gate automatically (it can never become "upcoming" again).
  final DateTime start = DateTime.utc(2020, 7, 14, 12);
  return Booking(
    id: _bookingId,
    masterId: 'm1',
    masterFirstName: 'Софія',
    masterLastName: 'Бондар',
    masterType: 'INDEPENDENT_MASTER',
    clientId: clientId,
    clientFirstName: clientFirstName,
    clientLastName: clientLastName,
    serviceId: 's1',
    serviceName: 'Манікюр з покриттям',
    categoryName: 'Манікюр',
    cityLabel: 'Київ',
    durationMinutes: 90,
    price: 650,
    startAt: start,
    endAt: start.add(const Duration(minutes: 90)),
    status: status,
    canReview: false,
  );
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(LeaveClientFeedbackScreen)));

void main() {
  group('LeaveClientFeedbackScreen — form + submit', () {
    /// Boots a two-route GoRouter (`/host` ⇄ the real client-review route)
    /// with the screen already PUSHED onto `/host` (so `context.pop()` has a
    /// destination to assert against).
    Future<(GoRouter, _MockClientReviewRepository)> pumpFeedback(
      WidgetTester tester, {
      required Future<Booking> Function(Ref ref) detail,
      _MockClientReviewRepository? repo,
    }) async {
      final _MockClientReviewRepository r =
          repo ?? _MockClientReviewRepository();
      final GoRouter router = GoRouter(
        initialLocation: '/host',
        routes: <RouteBase>[
          GoRoute(
            path: '/host',
            builder: (BuildContext context, _) => Scaffold(
              body: TextButton(
                key: const Key('go-client-review'),
                onPressed: () =>
                    context.push(RouteNames.clientReview(_bookingId)),
                child: const Text('go'),
              ),
            ),
          ),
          GoRoute(
            path: '/master/bookings/:bookingId/review',
            builder: (BuildContext context, GoRouterState state) =>
                LeaveClientFeedbackScreen(
                  bookingId: state.pathParameters['bookingId']!,
                ),
          ),
        ],
      );

      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[
          screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
          clientReviewRepositoryProvider.overrideWithValue(r),
          bookingDetailProvider(_bookingId).overrideWith(detail),
        ],
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('go-client-review')));
      await tester.pumpAndSettle();
      expect(find.byType(LeaveClientFeedbackScreen), findsOneWidget);
      return (router, r);
    }

    testWidgets('submit is disabled at rating 0 and enabled after a star tap', (
      tester,
    ) async {
      await pumpFeedback(tester, detail: (ref) async => _booking());

      NeumorphicButton submit() => tester.widget<NeumorphicButton>(
        find.byKey(const Key('leave-client-feedback-submit')),
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
      await pumpFeedback(tester, detail: (ref) async => _booking());

      await tester.tap(find.byKey(const ValueKey<String>('review-star-5')));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.star_rounded), findsNWidgets(5));
      expect(find.byIcon(Icons.star_border_rounded), findsNothing);
      expect(find.text(_l10n(tester).clientReviewRatingLabel5), findsOneWidget);
    });

    testWidgets('the privacy reminder renders beside the comment field', (
      tester,
    ) async {
      await pumpFeedback(tester, detail: (ref) async => _booking());

      final AppLocalizations l10n = _l10n(tester);
      expect(
        find.byKey(const Key('leave-client-feedback-privacy-note')),
        findsOneWidget,
      );
      expect(find.text(l10n.clientReviewCommentPrivacyNote), findsOneWidget);
    });

    testWidgets('submitting with a comment calls createClientReview with the '
        'exact bookingId, rating and comment', (tester) async {
      final repo = _MockClientReviewRepository();
      when(
        () => repo.createClientReview(
          bookingId: any(named: 'bookingId'),
          rating: any(named: 'rating'),
          comment: any(named: 'comment'),
        ),
      ).thenAnswer((_) async {});

      await pumpFeedback(tester, repo: repo, detail: (ref) async => _booking());

      await tester.tap(find.byKey(const ValueKey<String>('review-star-5')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('leave-client-feedback-comment')),
        'Пунктуальна, приємна клієнтка.',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('leave-client-feedback-submit')));
      await tester.pumpAndSettle();

      verify(
        () => repo.createClientReview(
          bookingId: _bookingId,
          rating: 5,
          comment: 'Пунктуальна, приємна клієнтка.',
        ),
      ).called(1);
    });

    testWidgets(
      'a successful submit shows the success SnackBar and pops back',
      (tester) async {
        final repo = _MockClientReviewRepository();
        when(
          () => repo.createClientReview(
            bookingId: any(named: 'bookingId'),
            rating: any(named: 'rating'),
            comment: any(named: 'comment'),
          ),
        ).thenAnswer((_) async {});

        final (GoRouter router, _) = await pumpFeedback(
          tester,
          repo: repo,
          detail: (ref) async => _booking(),
        );
        // Captured BEFORE the pop — the screen is gone afterwards.
        final AppLocalizations l10n = _l10n(tester);

        await tester.tap(find.byKey(const ValueKey<String>('review-star-4')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('leave-client-feedback-submit')));
        await tester.pumpAndSettle();

        verify(
          () => repo.createClientReview(
            bookingId: _bookingId,
            rating: 4,
            comment: '',
          ),
        ).called(1);
        expect(find.text(l10n.clientReviewSubmitSuccess), findsOneWidget);
        expect(find.byType(LeaveClientFeedbackScreen), findsNothing);
        // Read AFTER the pop, not while the feedback screen's
        // ImperativeRouteMatch (from context.push) is still on the stack —
        // go_router's ImperativeRouteMatch exclusion (the trap this gate
        // guards) only makes this read wrong for a still-pushed leaf. Here
        // the pop already collapsed the stack back to the plain, never-
        // pushed '/host' match, so `.uri` correctly reflects it; the
        // `LeaveClientFeedbackScreen` findsNothing assertion just above is
        // what actually proves the pop happened.
        expect(
          // router-location-ok: read after the pop, not a still-pushed leaf
          router.routerDelegate.currentConfiguration.uri.toString(),
          '/host',
        );

        await tester.pumpUntilGone(find.text(l10n.clientReviewSubmitSuccess));
      },
    );

    testWidgets('REGRESSION (was: CTA stayed visible → re-tappable → 409) — a '
        'successful submit invalidates bookingDetailProvider(bookingId) so the '
        'underlying detail re-fetches', (tester) async {
      // Before the fix, `_submit`'s success branch popped straight back
      // WITHOUT invalidating `bookingDetailProvider`, so
      // `BookingDetailScreen` (which `ref.watch`es the SAME family
      // instance and stays mounted beneath this pushed route) kept serving
      // its stale cached booking — the «Залишити відгук про клієнта» CTA
      // stayed visible and re-tappable, and a second tap 409'd against the
      // backend. This pins the fix directly at the provider level: the
      // `detail` override below counts how many times
      // `bookingDetailProvider(_bookingId)` is actually (re)fetched. One
      // fetch on first load, and — the whole point of the fix — a SECOND
      // fetch the instant a successful submit invalidates it, before the
      // pop even completes.
      final repo = _MockClientReviewRepository();
      when(
        () => repo.createClientReview(
          bookingId: any(named: 'bookingId'),
          rating: any(named: 'rating'),
          comment: any(named: 'comment'),
        ),
      ).thenAnswer((_) async {});

      int fetchCount = 0;
      await pumpFeedback(
        tester,
        repo: repo,
        detail: (ref) async {
          fetchCount++;
          return _booking();
        },
      );
      expect(
        fetchCount,
        1,
        reason: 'exactly one fetch backs the initial screen load',
      );
      // Captured BEFORE the pop — the screen is gone afterwards.
      final AppLocalizations l10n = _l10n(tester);

      await tester.tap(find.byKey(const ValueKey<String>('review-star-4')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('leave-client-feedback-submit')));
      await tester.pumpAndSettle();

      expect(
        fetchCount,
        2,
        reason:
            'a successful submit must invalidate '
            'bookingDetailProvider(bookingId), forcing a real re-fetch — '
            'without it the underlying BookingDetailScreen never learns '
            'providerCanReviewClient flipped to false and keeps showing a '
            'CTA that would 409 on a second tap',
      );

      await tester.pumpUntilGone(find.text(l10n.clientReviewSubmitSuccess));
    });

    testWidgets(
      'a ClientReviewNotAllowedFailure surfaces the localized message and '
      'stays on the form (no pop)',
      (tester) async {
        final repo = _MockClientReviewRepository();
        when(
          () => repo.createClientReview(
            bookingId: any(named: 'bookingId'),
            rating: any(named: 'rating'),
            comment: any(named: 'comment'),
          ),
        ).thenThrow(const ClientReviewNotAllowedFailure());

        await pumpFeedback(
          tester,
          repo: repo,
          detail: (ref) async => _booking(),
        );

        await tester.tap(find.byKey(const ValueKey<String>('review-star-2')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('leave-client-feedback-submit')));
        await tester.pumpAndSettle();

        final AppLocalizations l10n = _l10n(tester);
        expect(find.text(l10n.clientReviewErrNotAllowed), findsOneWidget);
        expect(find.text(l10n.errUnknown), findsNothing);
        expect(find.byType(LeaveClientFeedbackScreen), findsOneWidget);
        expect(
          find.byKey(const Key('leave-client-feedback-unavailable-back')),
          findsNothing,
          reason: 'a not-allowed failure must NOT swap to the info state',
        );

        await tester.pumpUntilGone(find.text(l10n.clientReviewErrNotAllowed));
      },
    );

    testWidgets(
      'a ClientReviewAlreadyExistsFailure (409) swaps the form for the '
      'not-reviewable info state — the only signal this screen gets of a '
      'duplicate submit',
      (tester) async {
        final repo = _MockClientReviewRepository();
        when(
          () => repo.createClientReview(
            bookingId: any(named: 'bookingId'),
            rating: any(named: 'rating'),
            comment: any(named: 'comment'),
          ),
        ).thenThrow(const ClientReviewAlreadyExistsFailure());

        await pumpFeedback(
          tester,
          repo: repo,
          detail: (ref) async => _booking(),
        );

        await tester.tap(find.byKey(const ValueKey<String>('review-star-3')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('leave-client-feedback-submit')));
        await tester.pumpAndSettle();

        final AppLocalizations l10n = _l10n(tester);
        expect(
          find.byKey(const Key('leave-client-feedback-unavailable-back')),
          findsOneWidget,
          reason: 'the 409 must swap the form for the not-reviewable state',
        );
        expect(find.text(l10n.clientReviewUnavailableTitle), findsOneWidget);
        expect(
          find.byKey(const Key('leave-client-feedback-stars')),
          findsNothing,
          reason: 'the form must be gone once the info state is shown',
        );
        expect(
          find.byKey(const Key('leave-client-feedback-submit')),
          findsNothing,
        );
        // Still mounted — no pop on a duplicate submit either.
        expect(find.byType(LeaveClientFeedbackScreen), findsOneWidget);
      },
    );

    testWidgets(
      'a guest booking renders the «Гість» fallback name and the guest role '
      'label instead of «Клієнт»',
      (tester) async {
        await pumpFeedback(
          tester,
          detail: (ref) async => _booking(
            clientId: null,
            clientFirstName: null,
            clientLastName: null,
          ),
        );

        final AppLocalizations l10n = _l10n(tester);
        expect(find.text(l10n.bookingDetailGuestClient), findsOneWidget);
        expect(find.text(l10n.bookingDetailGuestBookingLabel), findsOneWidget);
        expect(find.text(l10n.clientReviewRoleLabel), findsNothing);
      },
    );

    testWidgets('shows a spinner while the booking loads', (tester) async {
      final Completer<Booking> completer = Completer<Booking>();
      final GoRouter router = GoRouter(
        initialLocation: '/master/bookings/$_bookingId/review',
        routes: <RouteBase>[
          GoRoute(
            path: '/master/bookings/:bookingId/review',
            builder: (BuildContext context, GoRouterState state) =>
                LeaveClientFeedbackScreen(
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
      expect(
        find.byKey(const Key('leave-client-feedback-back')),
        findsOneWidget,
      );

      completer.complete(_booking());
      await tester.pumpAndSettle();
    });

    testWidgets('shows the error state with a retry on a failed fetch', (
      tester,
    ) async {
      final GoRouter router = GoRouter(
        initialLocation: '/master/bookings/$_bookingId/review',
        routes: <RouteBase>[
          GoRoute(
            path: '/master/bookings/:bookingId/review',
            builder: (BuildContext context, GoRouterState state) =>
                LeaveClientFeedbackScreen(
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

      expect(
        find.byKey(const Key('leave-client-feedback-error-retry')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const Key('leave-client-feedback-error-retry')),
      );
      await tester.pump();
      expect(
        find.byKey(const Key('leave-client-feedback-error-retry')),
        findsOneWidget,
      );
    });
  });
}

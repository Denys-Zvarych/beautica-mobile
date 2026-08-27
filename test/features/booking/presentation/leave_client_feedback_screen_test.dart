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
//     state, no VelvetSnack;
//   • a [ClientReviewNotAllowedFailure] — the localized message surfaces in a
//     VelvetSnack and the provider STAYS on the form (no pop);
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
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booking_detail_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/data/client_review_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/leave_client_feedback_screen.dart';
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

class _MockBookingRepository extends Mock implements BookingRepository {}

class _StubAuth extends AuthNotifier {
  _StubAuth(this._session);

  final AuthSession _session;

  @override
  Future<AuthSession> build() async => _session;
}

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
  // Defaults `true` — most of this suite exercises the reviewable form;
  // the pre-gate tests below pass `false` explicitly to pin the
  // not-reviewable-on-open behaviour.
  bool providerCanReviewClient = true,
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
    categoryName: 'NAIL_SERVICE',
    cityLabel: 'Київ',
    durationMinutes: 90,
    price: 650,
    startAt: start,
    endAt: start.add(const Duration(minutes: 90)),
    status: status,
    canReview: false,
    providerCanReviewClient: providerCanReviewClient,
  );
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(LeaveClientFeedbackScreen)));

void main() {
  group('LeaveClientFeedbackScreen — form + submit', () {
    /// Boots a two-route GoRouter (`/host` ⇄ the real client-review route)
    /// with the screen already PUSHED onto `/host` (so `context.pop()` has a
    /// destination to assert against).
    ///
    /// [entry] travels exactly the way production sends it — as go_router
    /// `extra` on the push, decoded by a route builder that MIRRORS
    /// `app_router.dart`'s own `switch` (2026-08-17). Defaults to
    /// [ClientReviewEntry.bookingDetail], which is both this suite's
    /// historical shape and app_router's own fallback for an absent `extra`.
    ///
    /// The returned `List<bool?>` records what the pushed screen POPPED, in
    /// push order — `MasterArchiveScreen._openReview` awaits exactly this value
    /// and patches the reviewed row from it, so pinning it here is pinning the
    /// contract, not an incidental return value.
    Future<(GoRouter, _MockClientReviewRepository, List<bool?>)> pumpFeedback(
      WidgetTester tester, {
      required Future<Booking> Function(Ref ref) detail,
      _MockClientReviewRepository? repo,
      ClientReviewEntry entry = ClientReviewEntry.bookingDetail,
    }) async {
      final _MockClientReviewRepository r =
          repo ?? _MockClientReviewRepository();
      final List<bool?> popResults = <bool?>[];
      final GoRouter router = GoRouter(
        initialLocation: '/host',
        routes: <RouteBase>[
          GoRoute(
            path: '/host',
            builder: (BuildContext context, _) => Scaffold(
              body: TextButton(
                key: const Key('go-client-review'),
                onPressed: () async {
                  popResults.add(
                    await context.push<bool>(
                      RouteNames.clientReview(_bookingId),
                      extra: entry,
                    ),
                  );
                },
                child: const Text('go'),
              ),
            ),
          ),
          GoRoute(
            path: '/master/bookings/:bookingId/review',
            builder: (BuildContext context, GoRouterState state) =>
                LeaveClientFeedbackScreen(
                  bookingId: state.pathParameters['bookingId']!,
                  // Mirrors `app_router.dart`'s real decode, including its
                  // fallback for an absent/foreign `extra`.
                  entry: switch (state.extra) {
                    final ClientReviewEntry e => e,
                    _ => ClientReviewEntry.bookingDetail,
                  },
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
      return (router, r, popResults);
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
      'a successful submit shows the success VelvetSnack and pops back',
      (tester) async {
        final repo = _MockClientReviewRepository();
        when(
          () => repo.createClientReview(
            bookingId: any(named: 'bookingId'),
            rating: any(named: 'rating'),
            comment: any(named: 'comment'),
          ),
        ).thenAnswer((_) async {});

        final (GoRouter router, _, List<bool?> popResults) = await pumpFeedback(
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
        expectVelvetSnack(
          l10n.clientReviewSubmitSuccess,
          variant: VelvetSnackVariant.success,
        );
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
        // The POP RESULT is part of this screen's contract (2026-08-17):
        // `true` means "this booking is no longer reviewable by this
        // provider". `MasterArchiveScreen._openReview` awaits it and calls
        // `MasterArchiveNotifier.markClientReviewed` on `true` — that is the
        // ONLY signal the archive gets now that this screen no longer
        // invalidates the whole `masterArchiveProvider` family, so a pop that
        // reported `null`/`false` here would resurrect the stale-CTA bug.
        expect(
          popResults,
          <bool?>[true],
          reason:
              'exactly ONE pop, carrying `true` — the success path must not '
              'also pop from the 409 branch, and must not pop bare',
        );

        await pumpPastVelvetSnack(tester);
      },
    );

    testWidgets('REGRESSION (was: CTA stayed visible → re-tappable → 409) — a '
        'successful submit from the DETAIL entry invalidates '
        'bookingDetailProvider(bookingId) so the underlying detail '
        're-fetches', (tester) async {
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
      //
      // The entry point is [ClientReviewEntry.bookingDetail] (pumpFeedback's
      // default), which is exactly the case where that refetch is REQUIRED.
      // Its counterpart below pins that the ARCHIVE entry skips it.
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

      await pumpPastVelvetSnack(tester);
    });

    testWidgets('the ARCHIVE entry does NOT invalidate bookingDetailProvider '
        'on success — it reports through the pop result instead', (
      tester,
    ) async {
      // mobile-perf LOW (2026-08-17). Reached from `MasterArchiveScreen`,
      // nothing on the stack watches `bookingDetailProvider(id)`: this screen's
      // own `ref.watch` is the last listener and the autoDispose element dies
      // with the pop, so an invalidate here fires a `GET /bookings/{id}` whose
      // response is read by nobody. The archive learns what it needs from the
      // `true` this pops — see `MasterArchiveNotifier.markClientReviewed`.
      //
      // The assertion is deliberately paired: "no second fetch" alone would
      // also pass if the submit had silently failed, so the pop result and the
      // repository call are pinned in the same test.
      final repo = _MockClientReviewRepository();
      when(
        () => repo.createClientReview(
          bookingId: any(named: 'bookingId'),
          rating: any(named: 'rating'),
          comment: any(named: 'comment'),
        ),
      ).thenAnswer((_) async {});

      int fetchCount = 0;
      final (_, _, List<bool?> popResults) = await pumpFeedback(
        tester,
        repo: repo,
        entry: ClientReviewEntry.masterArchive,
        detail: (ref) async {
          fetchCount++;
          return _booking();
        },
      );
      expect(fetchCount, 1, reason: 'the initial screen load, and only that');

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
      expect(
        fetchCount,
        1,
        reason:
            'the archive entry must NOT re-fetch GET /bookings/{id} after a '
            'successful submit — nobody on that stack reads it',
      );
      expect(
        popResults,
        <bool?>[true],
        reason:
            'the pop result is how the archive learns the row is no longer '
            'reviewable; skipping the detail invalidate is only safe because '
            'this fires',
      );

      await pumpPastVelvetSnack(tester);
    });

    testWidgets('a 409 does NOT pop, and backing out afterwards reports '
        '`true` so the archive still drops the stale row', (tester) async {
      // The 409 path never pops on its own (the master reads the info state
      // first), so it cannot report through the submit. What it CAN do is make
      // every later pop carry `true` — which is what replaced the bare
      // `ref.invalidate(masterArchiveProvider)` this branch used to fire.
      final repo = _MockClientReviewRepository();
      when(
        () => repo.createClientReview(
          bookingId: any(named: 'bookingId'),
          rating: any(named: 'rating'),
          comment: any(named: 'comment'),
        ),
      ).thenThrow(const ClientReviewAlreadyExistsFailure());

      final (_, _, List<bool?> popResults) = await pumpFeedback(
        tester,
        repo: repo,
        entry: ClientReviewEntry.masterArchive,
        detail: (ref) async => _booking(),
      );

      await tester.tap(find.byKey(const ValueKey<String>('review-star-3')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('leave-client-feedback-submit')));
      await tester.pumpAndSettle();

      expect(
        popResults,
        isEmpty,
        reason: 'a duplicate submit must NOT pop — the info state is the point',
      );
      expect(
        find.byKey(const Key('leave-client-feedback-unavailable-back')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('leave-client-feedback-unavailable-back')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LeaveClientFeedbackScreen), findsNothing);
      expect(
        popResults,
        <bool?>[true],
        reason:
            'the booking is known un-reviewable by now, so the pop must say '
            'so — otherwise the archive keeps a CTA the server already '
            'rejected once',
      );
    });

    testWidgets('a 409 never flashes the loading skeleton on its way to the '
        'not-reviewable state (skipLoadingOnReload)', (tester) async {
      // mobile-security INFO (2026-08-17). The finding predicted that the 409
      // branch's `ref.invalidate(bookingDetailProvider)` drives `async.when`
      // back through `loading:` and flashes `_LoadingForm` between the form and
      // `_NotReviewable`. It does NOT — `AsyncValue.when`'s
      // `skipLoadingOnRefresh` already defaults to `true` and an invalidate is
      // a refresh — and this test is the standing proof of the real behaviour
      // either way. Asserted frame-by-frame rather than after a settle, because
      // a settle is exactly what would hide a flash.
      //
      // The REFETCH IS HELD PENDING on purpose. An `async (ref) => _booking()`
      // override resolves inside the very microtask drain `tester.pump()` runs
      // BEFORE building, so no frame would ever observe a pending reload at
      // all and this test would be asserting nothing. Gating the SECOND fetch
      // on a Completer is what makes the frames below real — the
      // `fetches.length == 2` assertion after the loop is what pins that.
      final repo = _MockClientReviewRepository();
      when(
        () => repo.createClientReview(
          bookingId: any(named: 'bookingId'),
          rating: any(named: 'rating'),
          comment: any(named: 'comment'),
        ),
      ).thenThrow(const ClientReviewAlreadyExistsFailure());

      final List<Completer<Booking>> fetches = <Completer<Booking>>[];
      await pumpFeedback(
        tester,
        repo: repo,
        detail: (ref) {
          final Completer<Booking> c = Completer<Booking>();
          fetches.add(c);
          // Only the FIRST fetch (the initial load) resolves eagerly, so the
          // form renders; every later one stays pending until this test says
          // otherwise.
          if (fetches.length == 1) c.complete(_booking());
          return c.future;
        },
      );
      expect(fetches, hasLength(1));

      await tester.tap(find.byKey(const ValueKey<String>('review-star-3')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('leave-client-feedback-submit')));

      final Finder loading = find.byKey(
        const Key('leave-client-feedback-loading'),
      );
      for (int frame = 0; frame < 8; frame++) {
        await tester.pump();
        expect(
          loading,
          findsNothing,
          reason:
              'frame $frame after the duplicate submit: the invalidated '
              'booking fetch must reload SEAMLESSLY, keeping the previous '
              'value on screen instead of falling back to _LoadingForm',
        );
      }
      expect(
        fetches,
        hasLength(2),
        reason:
            'the 409 branch really did invalidate the detail provider, and '
            'the refetch really is still pending across every frame asserted '
            'above — otherwise there was no reload to skip the loading state '
            'for and the loop proved nothing',
      );
      expect(
        find.byKey(const Key('leave-client-feedback-unavailable-back')),
        findsOneWidget,
        reason:
            'and the not-reviewable state is on screen THROUGHOUT the pending '
            'reload — the retained previous value, not a skeleton',
      );

      fetches.last.complete(_booking(providerCanReviewClient: false));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('leave-client-feedback-unavailable-back')),
        findsOneWidget,
      );
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
        expectVelvetSnack(
          l10n.clientReviewErrNotAllowed,
          variant: VelvetSnackVariant.error,
        );
        expect(find.text(l10n.errUnknown), findsNothing);
        expect(find.byType(LeaveClientFeedbackScreen), findsOneWidget);
        expect(
          find.byKey(const Key('leave-client-feedback-unavailable-back')),
          findsNothing,
          reason: 'a not-allowed failure must NOT swap to the info state',
        );

        await pumpPastVelvetSnack(tester);
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
      'providerCanReviewClient == true renders the form (rating stars + '
      'submit CTA), not the not-reviewable state',
      (tester) async {
        await pumpFeedback(
          tester,
          detail: (ref) async => _booking(providerCanReviewClient: true),
        );

        expect(
          find.byKey(const Key('leave-client-feedback-stars')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('leave-client-feedback-submit')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('leave-client-feedback-unavailable-back')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'PRE-GATE: providerCanReviewClient == false renders the not-reviewable '
      'state IMMEDIATELY on open — the form never appears',
      (tester) async {
        final repo = _MockClientReviewRepository();

        await pumpFeedback(
          tester,
          repo: repo,
          detail: (ref) async => _booking(providerCanReviewClient: false),
        );

        final AppLocalizations l10n = _l10n(tester);
        expect(
          find.byKey(const Key('leave-client-feedback-unavailable-back')),
          findsOneWidget,
          reason:
              'a booking that is not reviewable on open must pre-gate to '
              'the not-reviewable state without ever building the form',
        );
        expect(find.text(l10n.clientReviewUnavailableTitle), findsOneWidget);
        expect(
          find.byKey(const Key('leave-client-feedback-stars')),
          findsNothing,
          reason:
              'the rating form must never render for a non-reviewable '
              'booking',
        );
        expect(
          find.byKey(const Key('leave-client-feedback-submit')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('leave-client-feedback-comment')),
          findsNothing,
        );
        // Confirms the pre-gate never even reaches the repository — no
        // wasted typing was possible because no form existed to submit.
        verifyNever(
          () => repo.createClientReview(
            bookingId: any(named: 'bookingId'),
            rating: any(named: 'rating'),
            comment: any(named: 'comment'),
          ),
        );
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

      // mobile-qa LOW fix (2026-08-16, finding 3) — a bare spinner used to
      // sit here; replaced with a skeleton shaped like the real form so the
      // archive→«Відгук» path (now a guaranteed cold fetch, see
      // `master_archive_screen.dart`'s `_openReview` prefetch) doesn't flash
      // blank-then-pop into the loaded layout.
      expect(
        find.byKey(const Key('leave-client-feedback-loading')),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.byKey(const Key('leave-client-feedback-back')),
        findsOneWidget,
      );
      // Neither the form nor the not-reviewable state may flash while the
      // pre-gate's own fetch is still in flight.
      expect(
        find.byKey(const Key('leave-client-feedback-stars')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('leave-client-feedback-unavailable-back')),
        findsNothing,
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

  group('LeaveClientFeedbackScreen — entering from BookingDetailScreen '
      '(efficiency)', () {
    testWidgets('REGRESSION GUARD: pushing from the detail screen\'s own '
        '«Залишити відгук про клієнта» CTA reuses the already-loaded '
        'bookingDetailProvider — no second fetch', (tester) async {
      // Real router nesting matching production
      // (`RouteNames.masterBookingDetail` / `.clientReview`) — the
      // detail screen stays mounted (paused, not disposed) beneath the
      // pushed leave-feedback route, exactly like the live app.
      final GoRouter router = GoRouter(
        initialLocation: RouteNames.masterBookingDetail(_bookingId),
        routes: <RouteBase>[
          GoRoute(
            path: '/master/bookings/:bookingId',
            builder: (BuildContext context, GoRouterState state) =>
                BookingDetailScreen(
                  bookingId: state.pathParameters['bookingId']!,
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

      int fetchCount = 0;
      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[
          screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
          bookingRepositoryProvider.overrideWithValue(_MockBookingRepository()),
          // Independent master → BookingViewerRole.provider, the SAME
          // derivation production uses (never overriding
          // bookingViewerRoleProvider directly).
          authProvider.overrideWith(
            () => _StubAuth(
              const AuthSession.authenticated(
                user: User(
                  id: 'u1',
                  email: 'm@e.com',
                  role: UserRole.independentMaster,
                ),
                accessToken: 't',
              ),
            ),
          ),
          bookingDetailProvider(_bookingId).overrideWith((ref) async {
            fetchCount++;
            return _booking(); // providerCanReviewClient: true (default)
          }),
        ],
      );
      await tester.pumpAndSettle();

      expect(
        fetchCount,
        1,
        reason: 'exactly one fetch backs the detail screen\'s load',
      );
      expect(find.byType(BookingDetailScreen), findsOneWidget);
      expect(
        find.byKey(const Key('booking-detail-leave-client-feedback')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('booking-detail-leave-client-feedback')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LeaveClientFeedbackScreen), findsOneWidget);
      // The form must render immediately (pre-gate passed using the
      // ALREADY-CACHED provider state) — and, the whole point of this
      // test, WITHOUT a second network round trip.
      expect(
        find.byKey(const Key('leave-client-feedback-stars')),
        findsOneWidget,
      );
      expect(
        fetchCount,
        1,
        reason:
            'entering LeaveClientFeedbackScreen from BookingDetailScreen '
            'must reuse the SAME bookingDetailProvider(bookingId) '
            'instance — BookingDetailScreen stays mounted (paused, not '
            'disposed) beneath the pushed route and keeps it alive, so '
            'the second `ref.watch` attaches to already-resolved '
            'AsyncData instead of re-running the fetch',
      );
    });
  });
}

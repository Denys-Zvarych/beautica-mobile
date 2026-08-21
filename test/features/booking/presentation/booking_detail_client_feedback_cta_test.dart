// Track 7.x Wave B — the PROVIDER footer's «Залишити відгук про клієнта» CTA
// on «Деталі запису».
//
// `booking_detail_provider_footer_test.dart` (track 27.x Wave A) proves the
// footer content for CONFIRMED (reschedule/decline/complete) and pins every
// terminal status EMPTY for that phase — including COMPLETED, which this
// track now fills. This suite covers what track 7.x Wave B adds:
//   • a COMPLETED provider booking shows the entry CTA ONLY when
//     `Booking.providerCanReviewClient` is `true`, and tapping it PUSHES the
//     leave-client-feedback route (real `context.push`, matching the
//     provider reschedule test's technique — the go_router push memory means
//     the pushed route's `fullPath` collapses to its parent, so the mounted
//     stub is the reliable proof, not `currentConfiguration.uri`);
//   • a COMPLETED provider booking with `providerCanReviewClient: false`
//     (already reviewed / not eligible) does NOT show it, even though the
//     status alone would have offered it before this flag existed;
//   • every OTHER terminal status (CANCELLED / DECLINED / NOT_COMPLETED) and
//     a not-yet-terminal CONFIRMED booking do NOT show it — it is a
//     COMPLETED-and-eligible-only affordance, never a blanket "any provider
//     booking";
//   • the CLIENT viewer never sees this key, on any status.
//
// GATING NOTE: this mirrors the CLIENT footer's «Залишити відгук про
// майстра» (gated on the server-computed `booking.canReview`) — the
// provider-side equivalent is `booking.providerCanReviewClient`, added
// specifically to close the gap this suite used to document as a known
// limitation (see `LeaveClientFeedbackScreen`'s file header for the residual
// 409 defense-in-depth that still guards a load/submit race).
//
// Finders are key-first; all copy is asserted through l10n.

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
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/booking_fixture_dates.dart';
import '../../../helpers/pump_app.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

class _StubAuth extends AuthNotifier {
  _StubAuth(this._session);

  final AuthSession _session;

  @override
  Future<AuthSession> build() async => _session;
}

const User _providerUser = User(
  id: 'u1',
  email: 'master@e.com',
  role: UserRole.independentMaster,
);

const User _clientUser = User(
  id: 'u2',
  email: 'client@e.com',
  role: UserRole.client,
);

Booking _booking({
  BookingStatus status = BookingStatus.completed,
  DateTime? startAt,
  bool providerCanReviewClient = true,
}) {
  final DateTime start = startAt ?? futureBookingStart();
  return Booking(
    id: 'b1',
    masterId: 'm1',
    masterFirstName: 'Марія',
    masterLastName: 'Іванюк',
    masterType: 'INDEPENDENT_MASTER',
    clientId: 'c1',
    clientFirstName: 'Олена',
    clientLastName: 'Ковальчук',
    serviceId: 's1',
    serviceName: 'Манікюр з покриттям',
    durationMinutes: 90,
    price: 650,
    startAt: start,
    endAt: start.add(const Duration(minutes: 90)),
    status: status,
    canReview: false,
    providerCanReviewClient: providerCanReviewClient,
  );
}

List<Object> _overrides(Booking booking, User user) => <Object>[
  screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
  bookingRepositoryProvider.overrideWithValue(_MockBookingRepository()),
  bookingDetailProvider(booking.id).overrideWith((ref) async => booking),
  authProvider.overrideWith(
    () => _StubAuth(AuthSession.authenticated(user: user, accessToken: 't')),
  ),
];

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(BookingDetailScreen)));

Future<void> _pumpDetail(
  WidgetTester tester,
  Booking booking, {
  User viewer = _providerUser,
}) async {
  await tester.pumpApp(
    BookingDetailScreen(bookingId: booking.id),
    overrides: _overrides(booking, viewer),
  );
  await tester.pumpAndSettle();
}

void main() {
  const Key ctaKey = Key('booking-detail-leave-client-feedback');

  testWidgets(
    'a COMPLETED, reviewable provider booking shows «Залишити відгук про '
    'клієнта»',
    (tester) async {
      await _pumpDetail(
        tester,
        _booking(
          status: BookingStatus.completed,
          providerCanReviewClient: true,
        ),
      );

      final AppLocalizations l10n = _l10n(tester);
      expect(find.byKey(ctaKey), findsOneWidget);
      expect(find.text(l10n.bookingDetailClientReviewCta), findsOneWidget);
    },
  );

  testWidgets(
    'a COMPLETED provider booking with providerCanReviewClient: false does '
    'NOT show the client-feedback CTA (already reviewed / not eligible)',
    (tester) async {
      await _pumpDetail(
        tester,
        _booking(
          status: BookingStatus.completed,
          providerCanReviewClient: false,
        ),
      );

      expect(
        find.byKey(const Key('booking-detail-client-strip')),
        findsOneWidget,
        reason: 'the provider view did not render',
      );
      expect(find.byKey(ctaKey), findsNothing);
    },
  );

  // PHASE 256 D4 — should_notOfferClientRating_when_bookingIsWalkIn.
  //
  // **DECIDED 2026-08-20** — user decision, verbatim: "for manual bookings
  // restrict reviews and hide this button". This is now LOCKED product
  // behaviour: a walk-in booking has no client ACCOUNT to write a rating
  // onto (`POST /client-reviews` returns 400, "Cannot review a guest
  // booking" — `ClientReviewService.java:83-86`), so the provider→client
  // feedback affordance must never render for one.
  //
  // Phase 256 adds NO new UI here — the test above this one already pins the
  // exact mechanism a walk-in booking rides: the mobile tier gates the CTA
  // on `Booking.providerCanReviewClient` ALONE, and the server sends that
  // flag as `false` for a walk-in (its `hasClient` conjunct — see backend
  // `phase-262` D4). This test is the SAME assertion, reframed to name the
  // walk-in scenario explicitly and cite the decision date, so a future
  // reader does not mistake the generic flag test above for a coincidence.
  // What this test actually pins is flag-handling, not walk-in-ness itself —
  // the real guarantee that a walk-in's flag is `false` lives in the backend
  // conjunct, not here.
  testWidgets(
    'should_notOfferClientRating_when_bookingIsWalkIn — a COMPLETED walk-in '
    'booking (providerCanReviewClient: false, the flag a guest booking with '
    'no client account always carries) never shows the client-feedback CTA',
    (tester) async {
      await _pumpDetail(
        tester,
        _booking(
          status: BookingStatus.completed,
          providerCanReviewClient: false,
        ),
      );

      expect(
        find.byKey(const Key('booking-detail-client-strip')),
        findsOneWidget,
        reason: 'the provider view did not render',
      );
      expect(find.byKey(ctaKey), findsNothing);
    },
  );

  testWidgets('tapping it PUSHES the leave-client-feedback route', (
    tester,
  ) async {
    final Booking booking = _booking(status: BookingStatus.completed);
    final router = GoRouter(
      initialLocation: RouteNames.masterBookingDetail(booking.id),
      routes: <RouteBase>[
        GoRoute(
          path: '/master/bookings/:bookingId',
          builder: (_, _) => BookingDetailScreen(bookingId: booking.id),
        ),
        GoRoute(
          path: RouteNames.clientReview(booking.id),
          builder: (_, _) => const Scaffold(key: Key('feedback_stub')),
        ),
      ],
    );

    await tester.pumpRoutedApp(
      router,
      overrides: _overrides(booking, _providerUser),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ctaKey));
    await tester.pumpAndSettle();

    // The go_router push memory: `currentConfiguration.uri` collapses to
    // the parent on a push, so the mounted stub is the reliable proof.
    expect(find.byKey(const Key('feedback_stub')), findsOneWidget);
    expect(find.byType(BookingDetailScreen), findsNothing);
  });

  testWidgets(
    'every OTHER terminal status does NOT show the client-feedback CTA',
    (tester) async {
      for (final BookingStatus status in <BookingStatus>[
        BookingStatus.cancelled,
        BookingStatus.declined,
        BookingStatus.notCompleted,
      ]) {
        await _pumpDetail(tester, _booking(status: status));

        expect(
          find.byKey(const Key('booking-detail-client-strip')),
          findsOneWidget,
          reason: 'the provider view did not render at $status',
        );
        expect(
          find.byKey(ctaKey),
          findsNothing,
          reason: 'the client-feedback CTA leaked at $status',
        );
      }
    },
  );

  testWidgets(
    'a CONFIRMED, not-yet-started booking does NOT show the client-feedback '
    'CTA (reschedule/decline own the footer there)',
    (tester) async {
      await _pumpDetail(
        tester,
        _booking(
          status: BookingStatus.confirmed,
          startAt: futureBookingStart(),
        ),
      );

      expect(find.byKey(ctaKey), findsNothing);
      expect(
        find.byKey(const Key('booking-detail-provider-reschedule')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'the CLIENT viewer never sees the provider client-feedback CTA on a '
    'COMPLETED booking',
    (tester) async {
      await _pumpDetail(
        tester,
        _booking(status: BookingStatus.completed),
        viewer: _clientUser,
      );

      expect(find.byKey(ctaKey), findsNothing);
    },
  );
}

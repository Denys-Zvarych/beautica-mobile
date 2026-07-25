// Track 7.x Wave B — the PROVIDER footer's «Залишити відгук про клієнта» CTA
// on «Деталі запису».
//
// `booking_detail_provider_footer_test.dart` (track 27.x Wave A) proves the
// footer content for CONFIRMED (reschedule/decline/complete) and pins every
// terminal status EMPTY for that phase — including COMPLETED, which this
// track now fills. This suite covers what track 7.x Wave B adds:
//   • a COMPLETED provider booking shows the entry CTA, and tapping it PUSHES
//     the leave-client-feedback route (real `context.push`, matching the
//     provider reschedule test's technique — the go_router push memory means
//     the pushed route's `fullPath` collapses to its parent, so the mounted
//     stub is the reliable proof, not `currentConfiguration.uri`);
//   • every OTHER terminal status (CANCELLED / DECLINED / NOT_COMPLETED) and
//     a not-yet-terminal CONFIRMED booking do NOT show it — it is a
//     COMPLETED-only affordance, never a blanket "any provider booking";
//   • the CLIENT viewer never sees this key, on any status.
//
// GATING NOTE asserted here as a NEGATIVE space, not a positive one: unlike
// the CLIENT footer's «Залишити відгук про майстра» (gated on the
// server-computed `booking.canReview`), there is no provider-side
// canReview-equivalent flag to test against — this suite intentionally shows
// the CTA is offered on COMPLETED regardless of any prior feedback, per
// `LeaveClientFeedbackScreen`'s file header.
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
    'a COMPLETED provider booking shows «Залишити відгук про клієнта»',
    (tester) async {
      await _pumpDetail(tester, _booking(status: BookingStatus.completed));

      final AppLocalizations l10n = _l10n(tester);
      expect(find.byKey(ctaKey), findsOneWidget);
      expect(find.text(l10n.bookingDetailClientReviewCta), findsOneWidget);
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

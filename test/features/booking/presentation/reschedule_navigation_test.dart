// mobile-qa (track 24.x booking auto-confirm) — guard coverage for
// [startBookingReschedule].
//
// booking_detail_interactions_test.dart proves the HAPPY path (a CONFIRMED
// booking → the slot picker seeded with `rescheduleBookingId`). This suite pins
// the three short-circuits the helper owns — each must surface the calm
// «Цей запис не можна перенести» / «errUnknown» VelvetSnack and NEVER navigate:
//
//   1. a non-CONFIRMED booking (defensive — the CTA is confirmed-gated, but the
//      helper must not rely on that);
//   2. a CONFIRMED booking whose booked service is no longer in the master's
//      public catalogue (nothing to fetch slots against);
//   3. a booking-detail load error (the catch-all branch → errUnknown).
//
// Track 30.x — [startBookingReschedule] now ALSO doubles as the per-item
// VISIT reschedule entry point (an optional `appointmentId` parameter,
// forwarded onto `BookingSlotPickerArgs.rescheduleAppointmentId`), superseding
// the retired whole-VISIT `startAppointmentReschedule` sibling that used to
// live in this file's second `main()` group. `booking_detail_appointment_
// child_footer_test.dart` covers the appointment-child routing end to end
// (via `BookingDetailScreen`); this file stays scoped to the three guards
// above, which apply identically regardless of `appointmentId`.
//
// Finders are key-first; every string is asserted through l10n (CI no-raw-Cyrillic
// gate). The helper is driven inside a real `GoRouter` whose `RouteNames.bookingSlots`
// stub flips a flag — so "did not navigate" is a positive assertion, not the
// absence of an exception.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booking_detail_notifier.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot_picker_args.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/reschedule_navigation.dart';
import 'package:beautica_mobile/features/master/application/public_master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/pump_app.dart';
import '../../../helpers/velvet_snack_matchers.dart';

/// A fixed-session auth stub — mirrors `booking_detail_provider_footer_test
/// .dart`'s `_StubAuth`.
class _StubAuth extends AuthNotifier {
  _StubAuth(this._session);

  final AuthSession _session;

  @override
  Future<AuthSession> build() async => _session;
}

const User _kProviderUser = User(
  id: 'u1',
  email: 'master@e.com',
  role: UserRole.independentMaster,
);

const User _kClientUser = User(
  id: 'c1',
  email: 'client@e.com',
  role: UserRole.client,
);

const String _bookingId = 'booking-1';
const String _masterId = 'master-aaa';
const String _serviceId = 'pub-assign-1';

const Master _master = Master(
  id: _masterId,
  firstName: 'Софія',
  lastName: 'Бондар',
  avgRating: 4.9,
  reviewCount: 24,
  type: MasterType.independentMaster,
);

const MasterService _bookedService = MasterService(
  id: _serviceId,
  serviceDefId: 'pub-svc-1',
  name: 'Манікюр з покриттям',
  durationMinutes: 90,
  priceMin: 650,
  priceDisplay: '650 ₴',
  category: 'NAILS',
);

/// [clientId] defaults to `null` (unset) — every PRE-EXISTING call site in
/// this file relies on that, so [Booking.isGuestBooking] (`booking_display_x
/// .dart`) is `true` by default here, same as before this parameter existed.
/// Callers that need a REAL client's booking (the calendar-button regression
/// guard below) pass a non-null [clientId] explicitly.
Booking _booking({required BookingStatus status, String? clientId}) {
  final DateTime start = DateTime.utc(2026, 7, 20, 15);
  return Booking(
    id: _bookingId,
    masterId: _masterId,
    masterFirstName: 'Софія',
    masterLastName: 'Бондар',
    masterType: 'INDEPENDENT_MASTER',
    serviceId: _serviceId,
    serviceName: 'Манікюр з покриттям',
    durationMinutes: 90,
    price: 650,
    startAt: start,
    endAt: start.add(const Duration(minutes: 90)),
    status: status,
    canReview: false,
    clientId: clientId,
  );
}

/// Drives [startBookingReschedule] once from a `/start` button and reports
/// whether the [RouteNames.bookingSlots] stub was reached. [detail] overrides
/// the booking-detail load (return a booking, or throw for the error case);
/// [services] is the master's public catalogue the helper resolves against.
class _NavProbe {
  bool navigated = false;
}

Future<_NavProbe> _drive(
  WidgetTester tester, {
  required Future<Booking> Function() detail,
  required List<MasterService> services,
}) async {
  final _NavProbe probe = _NavProbe();
  final GoRouter router = GoRouter(
    initialLocation: '/start',
    routes: <RouteBase>[
      GoRoute(
        path: '/start',
        builder: (BuildContext context, _) => Scaffold(
          body: Consumer(
            builder: (BuildContext context, WidgetRef ref, _) => TextButton(
              key: const Key('go'),
              onPressed: () => startBookingReschedule(
                context: context,
                ref: ref,
                bookingId: _bookingId,
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: RouteNames.bookingSlots,
        builder: (_, _) {
          probe.navigated = true;
          return const Scaffold(key: Key('slots_stub'));
        },
      ),
    ],
  );

  await tester.pumpRoutedApp(
    router,
    overrides: <Object>[
      bookingDetailProvider(_bookingId).overrideWith((ref) => detail()),
      publicMasterProfileProvider(
        _masterId,
      ).overrideWith((ref) async => (_master, services)),
    ],
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('go')));
  await tester.pumpAndSettle();
  return probe;
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byKey(const Key('go'))));

/// Drives [startBookingReschedule] and captures the [BookingSlotPickerArgs]
/// the slot picker was pushed with — unlike [_drive] above, which only
/// observes whether navigation happened. [detail] overrides the
/// booking-detail load so callers can vary the fetched [Booking] shape (e.g.
/// `clientId` set vs. unset) without duplicating this driver. Hoisted to file
/// scope (REUSE-FIRST) — originally a local function inside the
/// `hideMasterIdentity` group; the `rescheduleTargetIsWalkIn` group below
/// needs the identical driver rather than a hand-copied sibling.
Future<BookingSlotPickerArgs?> _driveCaptured(
  WidgetTester tester, {
  required Future<Booking> Function() detail,
  required List<Object> overrides,
}) async {
  BookingSlotPickerArgs? captured;
  final GoRouter router = GoRouter(
    initialLocation: '/start',
    routes: <RouteBase>[
      GoRoute(
        path: '/start',
        builder: (BuildContext context, _) => Scaffold(
          body: Consumer(
            builder: (BuildContext context, WidgetRef ref, _) => TextButton(
              key: const Key('go'),
              onPressed: () => startBookingReschedule(
                context: context,
                ref: ref,
                bookingId: _bookingId,
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: RouteNames.bookingSlots,
        builder: (BuildContext context, GoRouterState state) {
          captured = state.extra as BookingSlotPickerArgs?;
          return const Scaffold(key: Key('slots_stub'));
        },
      ),
    ],
  );

  await tester.pumpRoutedApp(
    router,
    overrides: <Object>[
      bookingDetailProvider(_bookingId).overrideWith((ref) => detail()),
      publicMasterProfileProvider(_masterId).overrideWith(
        (ref) async => (_master, const <MasterService>[_bookedService]),
      ),
      ...overrides,
    ],
  );
  await tester.pumpAndSettle();

  // Warm `authProvider` BEFORE tapping — see the original call site's own
  // comment (still true here: nothing in this bare `/start` fixture watches
  // it otherwise, so the very first read would land mid-flight inside the
  // tap handler).
  final ProviderContainer container = ProviderScope.containerOf(
    tester.element(find.byKey(const Key('go'))),
  );
  await container.read(authProvider.future);

  await tester.tap(find.byKey(const Key('go')));
  await tester.pumpAndSettle();
  return captured;
}

void main() {
  testWidgets(
    'a non-CONFIRMED booking short-circuits with «не можна перенести» and does '
    'not navigate',
    (tester) async {
      final _NavProbe probe = await _drive(
        tester,
        detail: () async => _booking(status: BookingStatus.declined),
        services: const <MasterService>[_bookedService],
      );

      expectVelvetSnack(
        _l10n(tester).bookingRescheduleUnavailable,
        variant: VelvetSnackVariant.warning,
      );
      expect(probe.navigated, isFalse);
      expect(find.byKey(const Key('slots_stub')), findsNothing);
      // Drains the dwell Timer — otherwise flutter_test flags it as a leak.
      await pumpPastVelvetSnack(tester);
    },
  );

  testWidgets(
    'a CONFIRMED booking whose booked service is gone from the catalogue '
    'short-circuits with «не можна перенести» and does not navigate',
    (tester) async {
      final _NavProbe probe = await _drive(
        tester,
        detail: () async => _booking(status: BookingStatus.confirmed),
        // The booked service (`pub-assign-1`) is absent — only an unrelated one.
        services: const <MasterService>[
          MasterService(
            id: 'some-other-service',
            serviceDefId: 'def-x',
            name: 'Педикюр',
            durationMinutes: 60,
            priceMin: 500,
            priceDisplay: '500 ₴',
            category: 'NAILS',
          ),
        ],
      );

      expectVelvetSnack(
        _l10n(tester).bookingRescheduleUnavailable,
        variant: VelvetSnackVariant.warning,
      );
      expect(probe.navigated, isFalse);
      expect(find.byKey(const Key('slots_stub')), findsNothing);
      await pumpPastVelvetSnack(tester);
    },
  );

  testWidgets(
    'a booking-detail load error surfaces errUnknown and does not navigate',
    (tester) async {
      final _NavProbe probe = await _drive(
        tester,
        detail: () async => throw const ServerFailure(statusCode: 500),
        services: const <MasterService>[_bookedService],
      );

      expectVelvetSnack(
        _l10n(tester).errUnknown,
        variant: VelvetSnackVariant.error,
      );
      expect(probe.navigated, isFalse);
      expect(find.byKey(const Key('slots_stub')), findsNothing);
      await pumpPastVelvetSnack(tester);
    },
  );

  // ---------------------------------------------------------------------
  // Audit-fix cycle 3 (FIX 3, 2026-08-21) — `hideMasterIdentity` is now
  // seeded from the RESCHEDULE VIEWER's role (`bookingViewerRoleProvider`),
  // not left at its `false` default. A PROVIDER rescheduling their own
  // booking must not see their own identity card echoed back on the
  // slot/confirm chain; a CLIENT rescheduling their own booking is the
  // user-locked path this fix must NEVER touch — it must keep seeing the
  // master card exactly as before.
  // ---------------------------------------------------------------------
  group('hideMasterIdentity seeded by viewer role (FIX 3)', () {
    testWidgets(
      'a PROVIDER-initiated reschedule seeds hideMasterIdentity: true — a '
      'master must not see their own identity card echoed back',
      (tester) async {
        final BookingSlotPickerArgs? captured = await _driveCaptured(
          tester,
          detail: () async => _booking(status: BookingStatus.confirmed),
          overrides: <Object>[
            authProvider.overrideWith(
              () => _StubAuth(
                const AuthSession.authenticated(
                  user: _kProviderUser,
                  accessToken: 't',
                ),
              ),
            ),
          ],
        );

        expect(captured, isNotNull);
        expect(captured!.hideMasterIdentity, isTrue);
      },
    );

    testWidgets(
      'a CLIENT-initiated reschedule keeps hideMasterIdentity: false — the '
      'LOCKED client path must still SHOW the master card and address',
      (tester) async {
        final BookingSlotPickerArgs? captured = await _driveCaptured(
          tester,
          detail: () async => _booking(status: BookingStatus.confirmed),
          overrides: <Object>[
            authProvider.overrideWith(
              () => _StubAuth(
                const AuthSession.authenticated(
                  user: _kClientUser,
                  accessToken: 't',
                ),
              ),
            ),
          ],
        );

        expect(captured, isNotNull);
        expect(captured!.hideMasterIdentity, isFalse);
      },
    );

    testWidgets(
      'an UNAUTHENTICATED viewer fails CLOSED onto hideMasterIdentity: false '
      // Explicitly stubbed to `Unauthenticated` rather than leaving
      // `authProvider` on its REAL notifier (the three guard tests above
      // never reach the `hideMasterIdentity` line at all — they short-
      // circuit before it — so they never trigger the real `AuthNotifier`'s
      // own boot sequence, which needs platform-channel mocks (secure
      // storage / a live refresh call) this bare fixture does not set up and
      // would otherwise hang the test).
      '— session-not-yet-resolved and never-logged-in both degrade the same '
      'way as any other non-provider session',
      (tester) async {
        final BookingSlotPickerArgs? captured = await _driveCaptured(
          tester,
          detail: () async => _booking(status: BookingStatus.confirmed),
          overrides: <Object>[
            authProvider.overrideWith(
              () => _StubAuth(const AuthSession.unauthenticated()),
            ),
          ],
        );

        expect(captured, isNotNull);
        expect(captured!.hideMasterIdentity, isFalse);
      },
    );
  });

  // ---------------------------------------------------------------------
  // «Додати в календар» removal (2026-08-21) — [rescheduleTargetIsWalkIn]
  // must mirror `booking.isGuestBooking` (`clientId == null`) off the SAME
  // fresh fetch this helper already uses for `rescheduleAppointmentId` /
  // `hideMasterIdentity`. The regression guard that matters MORE than the
  // new assertion: a booking WITH a registered client (`clientId` set) —
  // whether the reschedule viewer is the CLIENT themselves or a PROVIDER
  // moving that client's booking — must keep `rescheduleTargetIsWalkIn:
  // false`, so `BookingSuccessScreen`'s calendar button stays visible.
  // ---------------------------------------------------------------------
  group('rescheduleTargetIsWalkIn seeded by booking.isGuestBooking', () {
    testWidgets(
      'a WALK-IN booking (no clientId) seeds rescheduleTargetIsWalkIn: true',
      (tester) async {
        final BookingSlotPickerArgs? captured = await _driveCaptured(
          tester,
          detail: () async =>
              _booking(status: BookingStatus.confirmed, clientId: null),
          overrides: <Object>[
            authProvider.overrideWith(
              () => _StubAuth(
                const AuthSession.authenticated(
                  user: _kProviderUser,
                  accessToken: 't',
                ),
              ),
            ),
          ],
        );

        expect(captured, isNotNull);
        expect(captured!.rescheduleTargetIsWalkIn, isTrue);
      },
    );

    testWidgets(
      'REGRESSION GUARD — a CLIENT rescheduling their OWN booking (clientId '
      'set) keeps rescheduleTargetIsWalkIn: false — the calendar button must '
      'stay visible on the locked client path',
      (tester) async {
        final BookingSlotPickerArgs? captured = await _driveCaptured(
          tester,
          detail: () async =>
              _booking(status: BookingStatus.confirmed, clientId: 'c1'),
          overrides: <Object>[
            authProvider.overrideWith(
              () => _StubAuth(
                const AuthSession.authenticated(
                  user: _kClientUser,
                  accessToken: 't',
                ),
              ),
            ),
          ],
        );

        expect(captured, isNotNull);
        expect(captured!.rescheduleTargetIsWalkIn, isFalse);
      },
    );

    testWidgets(
      'a PROVIDER rescheduling a REAL CLIENT\'s booking (clientId set) also '
      'keeps rescheduleTargetIsWalkIn: false — only a true walk-in target '
      'hides the calendar button',
      (tester) async {
        final BookingSlotPickerArgs? captured = await _driveCaptured(
          tester,
          detail: () async =>
              _booking(status: BookingStatus.confirmed, clientId: 'c1'),
          overrides: <Object>[
            authProvider.overrideWith(
              () => _StubAuth(
                const AuthSession.authenticated(
                  user: _kProviderUser,
                  accessToken: 't',
                ),
              ),
            ),
          ],
        );

        expect(captured, isNotNull);
        expect(captured!.rescheduleTargetIsWalkIn, isFalse);
      },
    );
  });
}

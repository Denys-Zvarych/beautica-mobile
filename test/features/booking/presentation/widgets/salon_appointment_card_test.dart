// mobile-qa regression coverage — SalonAppointmentCard.showSucceededStatus
// (Phase 14.18 bugfix follow-up).
//
// THE BUG: the per-appointment «Заплановано» success line used to flash
// pointlessly on the all-succeeded settled path (the confirm screen
// `pushReplacement`s away with no `await` between the last state write and
// the navigation call, so that frame never paints) — so it was gated behind
// `showSucceededStatus`. The FIRST attempt gated it on the live `hasFailures`
// flag, which was WRONG: both mobile-perf and mobile-security independently
// caught that it hid an already-succeeded master's checkmark for the whole
// mid-submit / mid-retry window (see `salon_booking_confirm_screen.dart`'s
// `_AppointmentCardSlot` doc comment for the two windows this closes). The
// fix widened the gate to `inFlight || hasFailures`.
//
// This file pins the CARD's OWN contract in isolation (no screen, no
// providers, no router — `SalonAppointmentCard` takes `status`/`failure`/
// `showSucceededStatus` as plain constructor args): every combination of
// `status` × `showSucceededStatus` renders (or doesn't render) exactly the
// line the doc comment promises. The companion screen-level tests in
// `salon_booking_confirm_screen_test.dart` (`showSucceededStatus gate` group)
// pin that the SCREEN wires `inFlight || hasFailures` into this prop
// correctly across a real multi-master submit/retry pass — this file pins
// what the CARD does once it receives that flag, including the two states
// (`submitting`, `failed`) the gate must never be able to suppress.
//
// No `find.text(<Cyrillic literal>)` anywhere — content assertions go
// through the resolved `l10n.<key>` object (`forbid_cyrillic_finder.sh`
// gate).

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/booking/application/salon_booking_submit_notifier.dart';
import 'package:beautica_mobile/features/booking/domain/salon_booking_confirm_args.dart';
import 'package:beautica_mobile/features/booking/domain/salon_master_schedule.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_recap.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/salon_appointment_card.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

const String _kMasterId = 'm1';

SalonMasterSchedule _schedule() => const SalonMasterSchedule(
  masterId: _kMasterId,
  firstName: 'Олена',
  lastName: 'Ковальчук',
  type: MasterType.independentMaster,
  services: <SalonCatalogService>[
    SalonCatalogService(
      id: 'svc-$_kMasterId',
      name: 'Манікюр',
      durationLabel: '1 год',
      priceDisplay: '500 ₴',
      durationMinutes: 60,
      priceType: ServicePriceType.fixed,
      priceMin: 500,
    ),
  ],
  primaryServiceAssignmentId: 'assign-$_kMasterId',
);

final SalonBookingAppointment _appointment = SalonBookingAppointment(
  schedule: _schedule(),
  startAt: DateTime(2026, 7, 20, 14),
  idempotencyKey: 'key-$_kMasterId',
);

final List<BookingSelection> _selections = _appointment.schedule.services
    .map(BookingSelection.fromSalonCatalogService)
    .toList();

const List<Color> _kAvatarGradient = <Color>[
  Color(0xFFD4B896),
  Color(0xFF8A6840),
];

/// Pumps a bare [SalonAppointmentCard] — no ProviderScope overrides needed,
/// it is a pure `StatelessWidget` fed entirely by constructor args.
Future<void> _pumpCard(
  WidgetTester tester, {
  SalonAppointmentSubmitStatus? status,
  Failure? failure,
  bool showSucceededStatus = true,
}) async {
  await tester.pumpApp(
    Scaffold(
      body: SalonAppointmentCard(
        appointment: _appointment,
        selections: _selections,
        avatarGradient: _kAvatarGradient,
        status: status,
        failure: failure,
        showSucceededStatus: showSucceededStatus,
      ),
    ),
  );
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(SalonAppointmentCard)));

void main() {
  group('SalonAppointmentCard.showSucceededStatus — succeeded status', () {
    testWidgets(
      'status=succeeded, showSucceededStatus=true → renders the «Заплановано» '
      'line + the success checkmark',
      (tester) async {
        await _pumpCard(
          tester,
          status: SalonAppointmentSubmitStatus.succeeded,
          showSucceededStatus: true,
        );
        final AppLocalizations l10n = _l10n(tester);

        expect(
          find.text(l10n.salonBookingAppointmentSucceeded),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      },
    );

    testWidgets(
      'status=succeeded, showSucceededStatus=false → renders NOTHING — this '
      'is the settled/all-succeeded case (screen navigates away with no '
      'await, so this frame is documented as never painting in production, '
      'but the card must still suppress it if it somehow did)',
      (tester) async {
        await _pumpCard(
          tester,
          status: SalonAppointmentSubmitStatus.succeeded,
          showSucceededStatus: false,
        );
        final AppLocalizations l10n = _l10n(tester);

        expect(find.text(l10n.salonBookingAppointmentSucceeded), findsNothing);
        expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
      },
    );
  });

  group('SalonAppointmentCard.showSucceededStatus — submitting/failed are '
      'UNAFFECTED by the gate', () {
    for (final bool gate in <bool>[true, false]) {
      testWidgets(
        'status=submitting always renders the spinner + submitting label, '
        'regardless of showSucceededStatus=$gate',
        (tester) async {
          await _pumpCard(
            tester,
            status: SalonAppointmentSubmitStatus.submitting,
            showSucceededStatus: gate,
          );
          final AppLocalizations l10n = _l10n(tester);

          expect(
            find.text(l10n.salonBookingAppointmentSubmitting),
            findsOneWidget,
            reason:
                'showSucceededStatus must only ever gate the SUCCEEDED '
                'line — submitting must render unconditionally',
          );
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
        },
      );

      testWidgets(
        'status=failed always renders the error icon + failure message, '
        'regardless of showSucceededStatus=$gate',
        (tester) async {
          await _pumpCard(
            tester,
            status: SalonAppointmentSubmitStatus.failed,
            failure: const ConflictFailure(),
            showSucceededStatus: gate,
          );
          final AppLocalizations l10n = _l10n(tester);

          expect(
            find.text(l10n.errConflict),
            findsOneWidget,
            reason:
                'showSucceededStatus must only ever gate the SUCCEEDED '
                'line — failed must render unconditionally',
          );
          expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
        },
      );
    }
  });

  // mobile-qa gap-fix — Step 2.7 Rule 3b: a ClientBookingConflictFailure on
  // ONE master's card must render the SAME composed "you already have a
  // booking" sentence the dialog uses (never a generic/blank error), proving
  // the card renders the conflict on a PER-MASTER basis via
  // `failure.userMessage(context)` — the salon submit notifier's own unit
  // test (`salon_booking_submit_notifier_test.dart`) pins that only the
  // conflicting master's STATE carries the failure; this pins that the CARD
  // actually surfaces it correctly once it does.
  group('SalonAppointmentCard — ClientBookingConflictFailure renders the '
      'composed clash sentence', () {
    testWidgets('status=failed with a ClientBookingConflictFailure renders the '
        'composed service/master/window sentence, not a generic message', (
      tester,
    ) async {
      final DateTime clashStart = DateTime.utc(2026, 7, 20, 9);
      final ClientBookingConflictFailure conflict =
          ClientBookingConflictFailure(
            conflictingBookingId: 'other-booking-1',
            serviceName: 'Педикюр апаратний',
            masterName: 'Ірина Шевченко',
            startsAt: clashStart,
            endsAt: clashStart.add(const Duration(minutes: 45)),
          );

      await _pumpCard(
        tester,
        status: SalonAppointmentSubmitStatus.failed,
        failure: conflict,
        showSucceededStatus: true,
      );
      final AppLocalizations l10n = _l10n(tester);

      expect(
        find.text(
          l10n.bookingErrClientConflict(
            'Педикюр апаратний',
            'Ірина Шевченко',
            formatBookingWindow(
              clashStart,
              clashStart.add(const Duration(minutes: 45)),
            ),
          ),
        ),
        findsOneWidget,
        reason:
            'the failed card must surface the SAME composed sentence '
            'ClientBookingConflictDialog uses — the clashing service, '
            'master, and formatted window, not a generic conflict message',
      );
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      // The generic conflict copy must NOT be the one rendered here.
      expect(find.text(l10n.errConflict), findsNothing);
    });
  });

  group('SalonAppointmentCard.showSucceededStatus — pending/null are always '
      'silent', () {
    for (final bool gate in <bool>[true, false]) {
      testWidgets('status=pending renders no status line at all, regardless of '
          'showSucceededStatus=$gate', (tester) async {
        await _pumpCard(
          tester,
          status: SalonAppointmentSubmitStatus.pending,
          showSucceededStatus: gate,
        );
        final AppLocalizations l10n = _l10n(tester);

        expect(find.text(l10n.salonBookingAppointmentSucceeded), findsNothing);
        expect(find.text(l10n.salonBookingAppointmentSubmitting), findsNothing);
        expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
        expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
      });

      testWidgets(
        'status=null (success screen / before first submit) renders no '
        'status line at all, regardless of showSucceededStatus=$gate',
        (tester) async {
          await _pumpCard(tester, status: null, showSucceededStatus: gate);
          final AppLocalizations l10n = _l10n(tester);

          expect(
            find.text(l10n.salonBookingAppointmentSucceeded),
            findsNothing,
          );
          expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
        },
      );
    }
  });
}

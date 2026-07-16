// mobile-qa (independent-flow "selected services" shelf addition) — widget
// tests for [IndependentScheduleConfirmBar], the NEW pinned bottom shelf on the
// independent-master `BookingTimeScreen` ("Час") step. It is the independent
// analogue of the salon `ScheduleConfirmBar`: the SAME expandable
// [SelectedServicesShelf] pinned above a «Разом» total + the «Підтвердити» CTA,
// PLUS the independent flow's distinguishing beat — a per-SERVICE chosen-window
// third line ([SelectedServicesShelf.chosenLabelFor]) that the salon bars never
// supply.
//
// Covers (dev-flagged gaps 1a–1e + the reschedule single-row invariant):
//   (a) collapsed — the service count + «Разом» total render without expanding.
//   (b) the CTA is disabled while `enabled == false` (not every service
//       scheduled yet) and enabled + fires `onConfirm` once `enabled == true`.
//   (c) expanded — a SCHEDULED service (present in `chosenWindowByServiceId`)
//       renders its chosen-window third line (event_available_rounded + the
//       formatted window) while an UNSCHEDULED sibling renders none.
//   (d) the «Разом» total sums FIXED + RANGE services correctly (a degenerate
//       FIXED band collapses to "<sum> ₴"; a RANGE band widens the band).
//   (e) overflow guard — a chosen-window label present at a narrow stress width
//       lays out without a RenderFlex overflow (the shared guard auto-fails).
//   (+) a single service (the reschedule case) renders EXACTLY one shelf entry.
//
// No Cyrillic UI-copy literals appear in any finder: entries are located by
// their `ValueKey(service.id)`, the CTA by its key, the chosen line by its
// icon, and every text assertion compares against a value produced by the SAME
// shared formatter the widget itself calls (never a hand-typed string).

import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/independent_schedule_confirm_bar.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:beautica_mobile/shared/formatters/booking_price_labels.dart';
import 'package:beautica_mobile/shared/formatters/service_count_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _svcFixedA = MasterService(
  id: 'svc-a',
  serviceDefId: 'def-a',
  name: 'Манікюр з покриттям',
  durationMinutes: 60,
  priceMin: 500,
  priceDisplay: '500 ₴',
  category: 'NAILS',
);

const _svcFixedB = MasterService(
  id: 'svc-b',
  serviceDefId: 'def-b',
  name: 'Педикюр апаратний',
  durationMinutes: 60,
  priceMin: 400,
  priceDisplay: '400 ₴',
  category: 'NAILS',
);

/// A RANGE-priced service — its band widens the «Разом» total (min ≠ max).
const _svcRange = MasterService(
  id: 'svc-r',
  serviceDefId: 'def-r',
  name: 'Догляд за обличчям',
  durationMinutes: 45,
  priceType: ServicePriceType.range,
  priceMin: 200,
  priceMax: 600,
  priceDisplay: 'від 200 до 600 ₴',
  category: 'FACE',
);

const Key _ctaKey = Key('booking-time-confirm-cta');
const Key _toggleKey = Key('booking-summary-expand-toggle');

/// A canonical-UTC start whose Europe/Kyiv wall-clock (the zone every booking
/// formatter pins to) is a stable 14:00 — 11:00Z + 3h summer offset. Used to
/// build the chosen-window label via the SAME formatter the source calls, so
/// the assertion never hard-codes a Cyrillic date string.
final DateTime _startA = DateTime.utc(2026, 7, 14, 11);

Widget _bar({
  required List<MasterService> services,
  Map<String, String> chosen = const <String, String>{},
  bool enabled = true,
  VoidCallback? onConfirm,
}) => Scaffold(
  bottomNavigationBar: IndependentScheduleConfirmBar(
    services: services,
    chosenWindowByServiceId: chosen,
    enabled: enabled,
    onConfirm: onConfirm ?? () {},
    ctaKey: _ctaKey,
  ),
);

/// Scopes a finder to ONE service's expanded shelf entry (keyed by service id),
/// so an assertion proves the chosen line landed in THAT service's row — not
/// merely somewhere in the pumped tree.
Finder _inEntry(String serviceId, Finder matching) => find.descendant(
  of: find.byKey(ValueKey<String>(serviceId)),
  matching: matching,
);

NeumorphicButton _cta(WidgetTester tester) =>
    tester.widget<NeumorphicButton>(find.byKey(_ctaKey));

void main() {
  group('collapsed content', () {
    testWidgets(
      'renders the selected-service count and the «Разом» total without '
      'expanding the shelf',
      (tester) async {
        await tester.pumpApp(
          _bar(services: const <MasterService>[_svcFixedA, _svcFixedB]),
        );
        await tester.pumpAndSettle();

        // The itemized list stays collapsed by default.
        expect(
          find.byKey(const Key('booking-summary-expanded-list')),
          findsNothing,
        );

        // Count label — generated via the SAME shared formatter the widget
        // calls, never a hand-typed literal.
        expect(find.text(formatServiceCountUk(2)), findsOneWidget);

        // «Разом» label + the summed FIXED+FIXED total (500 + 400 = 900 ₴,
        // degenerate band collapses to "<sum> ₴").
        final l10n = AppLocalizations.of(
          tester.element(find.byType(IndependentScheduleConfirmBar)),
        );
        expect(find.text(l10n.bookingTotalLabel), findsOneWidget);
        final ({String priceLabel, String? durationLabel}) totals =
            formatBookingTotals(minSum: 900, maxSum: 900, minutes: 120);
        expect(find.text(totals.priceLabel), findsOneWidget);
        expect(totals.priceLabel, '900 $bookingPriceCurrencySuffix');
        // 120 min → duration label rendered beside «Разом».
        expect(find.text(totals.durationLabel!), findsOneWidget);
      },
    );
  });

  group('confirm CTA gating', () {
    testWidgets('the CTA is disabled while not every service is scheduled '
        '(enabled == false)', (tester) async {
      await tester.pumpApp(
        _bar(
          services: const <MasterService>[_svcFixedA, _svcFixedB],
          enabled: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        _cta(tester).onPressed,
        isNull,
        reason: 'a null onPressed makes NeumorphicButton non-tappable',
      );
    });

    testWidgets(
      'once every service is scheduled (enabled == true) the CTA is tappable '
      'and fires onConfirm',
      (tester) async {
        bool confirmed = false;
        await tester.pumpApp(
          _bar(
            services: const <MasterService>[_svcFixedA, _svcFixedB],
            enabled: true,
            onConfirm: () => confirmed = true,
          ),
        );
        await tester.pumpAndSettle();

        expect(_cta(tester).onPressed, isNotNull);

        await tester.tap(find.byKey(_ctaKey));
        await tester.pumpAndSettle();
        expect(confirmed, isTrue);
      },
    );
  });

  group('per-service chosen-window third line (independent-flow beat)', () {
    testWidgets(
      'a scheduled service renders its chosen-window line (event icon + the '
      'formatted window) while an unscheduled sibling renders none',
      (tester) async {
        final String windowA = formatBookingWindow(
          _startA,
          _startA.add(const Duration(minutes: 60)),
        );
        await tester.pumpApp(
          _bar(
            services: const <MasterService>[_svcFixedA, _svcFixedB],
            // Only service A has a pick; service B is still unscheduled.
            chosen: <String, String>{_svcFixedA.id: windowA},
          ),
        );
        await tester.pumpAndSettle();

        // Expand the shelf to reveal the itemized entries.
        await tester.tap(find.byKey(_toggleKey));
        await tester.pumpAndSettle();

        // Service A's row shows the chosen-window third line…
        expect(
          _inEntry(_svcFixedA.id, find.byIcon(Icons.event_available_rounded)),
          findsOneWidget,
        );
        // …with the exact formatted window (formatter output, not a literal).
        expect(_inEntry(_svcFixedA.id, find.text(windowA)), findsOneWidget);

        // Service B (unscheduled) shows NO chosen-window line.
        expect(
          _inEntry(_svcFixedB.id, find.byIcon(Icons.event_available_rounded)),
          findsNothing,
        );

        // Shelf-wide: exactly one chosen line across both entries.
        expect(find.byIcon(Icons.event_available_rounded), findsOneWidget);
      },
    );
  });

  group('«Разом» total across price types', () {
    testWidgets(
      'sums a FIXED service and a RANGE service into a widened band',
      (tester) async {
        await tester.pumpApp(
          // FIXED 500 + RANGE 200–600 → min 700, max 1100 → "700–1100 ₴".
          _bar(services: const <MasterService>[_svcFixedA, _svcRange]),
        );
        await tester.pumpAndSettle();

        final ({String priceLabel, String? durationLabel}) totals =
            formatBookingTotals(minSum: 700, maxSum: 1100, minutes: 105);
        expect(totals.priceLabel, '700–1100 $bookingPriceCurrencySuffix');
        expect(find.text(totals.priceLabel), findsOneWidget);
      },
    );
  });

  group('narrow-width overflow guard', () {
    testWidgets(
      'a chosen-window label present at a narrow stress width lays out without '
      'a RenderFlex overflow',
      (tester) async {
        final String windowA = formatBookingWindow(
          _startA,
          _startA.add(const Duration(minutes: 60)),
        );
        // Narrow width so a mis-constrained chosen line would overflow the row;
        // pump_app.dart's shared overflow guard fails the test automatically on
        // any "RenderFlex overflowed" report — reaching pumpAndSettle clean IS
        // the assertion.
        await tester.pumpApp(
          _bar(
            services: const <MasterService>[_svcFixedA, _svcFixedB],
            chosen: <String, String>{_svcFixedA.id: windowA},
          ),
          width: 320,
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(_toggleKey));
        await tester.pumpAndSettle();

        expect(
          _inEntry(_svcFixedA.id, find.byIcon(Icons.event_available_rounded)),
          findsOneWidget,
        );
      },
    );
  });

  group('single-service reschedule', () {
    testWidgets(
      'a single service (the rescheduleBookingId case) renders exactly one '
      'shelf entry when expanded',
      (tester) async {
        await tester.pumpApp(_bar(services: const <MasterService>[_svcFixedA]));
        await tester.pumpAndSettle();

        expect(find.text(formatServiceCountUk(1)), findsOneWidget);

        await tester.tap(find.byKey(_toggleKey));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey<String>('svc-a')), findsOneWidget);
        expect(find.byKey(const ValueKey<String>('svc-b')), findsNothing);
      },
    );
  });
}

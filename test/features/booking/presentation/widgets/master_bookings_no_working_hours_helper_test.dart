// Qase defects #37 / #45 — the NO_SCHEDULE empty state addresses the right
// person.
//
// `MasterBookingsNoWorkingHoursState` already drops its «Додати робочі години»
// CTA when `onAddHours` is null (Phase 330, the invited read-only
// SALON_MASTER). The helper line underneath did NOT follow: it always rendered
// `scheduleNoScheduleHelper`, which is imperative — "YOU add working hours" —
// so a salon master was told to do the one thing the screen gives them no
// affordance for. Their hours are set by the salon owner/admin (Phase 312).
//
// Both strings already existed and `master_schedule_screen.dart` (1238, 1452)
// already picked between them; only this widget ignored the pair. Each one's
// ARB description explicitly forbids merging them, because they are addressed
// to different people — which is exactly what these tests pin.

import 'package:beautica_mobile/features/booking/presentation/widgets/master_bookings_states.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<AppLocalizations> _pumpState(
  WidgetTester tester, {
  required bool canAddHours,
  bool dayOff = false,
}) async {
  late AppLocalizations l10n;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('uk'),
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) {
            l10n = AppLocalizations.of(context);
            return MasterBookingsNoWorkingHoursState(
              dayOff: dayOff,
              onAddHours: canAddHours ? () {} : null,
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return l10n;
}

void main() {
  group('NO_SCHEDULE helper copy follows the viewer, not the screen', () {
    testWidgets(
      'a READ-ONLY viewer (no CTA) is not told to add hours himself',
      (WidgetTester tester) async {
        final AppLocalizations l10n = await _pumpState(
          tester,
          canAddHours: false,
        );

        expect(
          find.text(l10n.scheduleNoScheduleHelperReadOnly),
          findsOneWidget,
          reason:
              'the invited salon master cannot publish their own hours — the '
              'copy must name the owner/admin who can',
        );
        expect(
          find.text(l10n.scheduleNoScheduleHelper),
          findsNothing,
          reason:
              'this is the defect: an imperative "you add working hours" shown '
              'to a viewer whose CTA is deliberately absent two lines below',
        );
        expect(
          find.byKey(const Key('master-bookings-no-schedule-cta')),
          findsNothing,
          reason:
              'the control this test hangs on — if the CTA ever comes back for '
              'this viewer, the copy assertion above stops meaning anything',
        );
      },
    );

    testWidgets('an EDITABLE viewer keeps the imperative copy AND the CTA', (
      WidgetTester tester,
    ) async {
      final AppLocalizations l10n = await _pumpState(tester, canAddHours: true);

      expect(find.text(l10n.scheduleNoScheduleHelper), findsOneWidget);
      expect(find.text(l10n.scheduleNoScheduleHelperReadOnly), findsNothing);
      expect(
        find.byKey(const Key('master-bookings-no-schedule-cta')),
        findsOneWidget,
        reason:
            'the independent master must be unaffected — this fix is additive '
            'for every viewer who could already act',
      );
    });

    testWidgets('the day-off title is independent of who may edit', (
      WidgetTester tester,
    ) async {
      // `dayOff` selects the TITLE, `onAddHours` selects the HELPER. They are
      // different facts — a settled day off is not the same state as "no
      // schedule was ever set" — so the two must not be collapsed into one
      // condition.
      final AppLocalizations l10n = await _pumpState(
        tester,
        canAddHours: false,
        dayOff: true,
      );

      expect(find.text(l10n.scheduleDayOffEmptyState), findsOneWidget);
      expect(find.text(l10n.masterBookingsNoScheduleTitle), findsNothing);
      expect(find.text(l10n.scheduleNoScheduleHelperReadOnly), findsOneWidget);
    });
  });
}

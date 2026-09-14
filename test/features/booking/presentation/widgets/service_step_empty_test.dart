// 2026-09-13 audit (M11) — widget coverage for [ServiceStepEmpty]'s two
// additive overrides.
//
// `titleOverride` / `bodyOverride` (Phase 250, the salon wizard) had NO test
// reference anywhere in `test/` or `integration_test/`: the `??` fallback fork
// was uncovered in BOTH directions. That matters because the two forks say
// materially different things to the reader. The master wizard's default copy
// ("Додайте послугу в розділі «Послуги»…") tells the viewer to go add a
// service themselves — which is simply wrong for the `SALON_ADMIN` the salon
// wizard serves: that role has no master profile and no services screen at
// all. A regression that dropped the `??` (always the default) or inverted it
// (always the override) would have been silent.
//
// Both forks are asserted on RENDERED TEXT, never on widget fields
// (`project_widget_field_assertion_is_vacuous`), and the default fork is
// pinned against the resolved ARB value rather than a hard-coded literal so
// this file does not become a second, drifting copy pin — the literal pin
// lives in `test/l10n/master_create_booking_service_empty_copy_test.dart`.

import 'package:beautica_mobile/features/booking/presentation/widgets/booking_wizard_steps.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<AppLocalizations> _pump(WidgetTester tester, Widget child) async {
  late AppLocalizations l10n;
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('uk', 'UA'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (BuildContext ctx) {
            l10n = AppLocalizations.of(ctx);
            return child;
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return l10n;
}

void main() {
  group('ServiceStepEmpty override forks', () {
    testWidgets(
      'NO overrides (the master wizard call site) renders the DEFAULT l10n '
      'title and body',
      (WidgetTester tester) async {
        final AppLocalizations l10n = await _pump(
          tester,
          const ServiceStepEmpty(),
        );

        expect(
          find.text(l10n.masterCreateBookingServiceEmptyTitle),
          findsOneWidget,
        );
        expect(
          find.text(l10n.masterCreateBookingServiceEmptyBody),
          findsOneWidget,
        );
        // The salon copy must be nowhere near this fork.
        expect(
          find.text(l10n.salonCreateBookingServiceEmptyTitle),
          findsNothing,
        );
        expect(
          find.text(l10n.salonCreateBookingServiceEmptyBody),
          findsNothing,
        );
      },
    );

    testWidgets(
      'BOTH overrides (the salon wizard call site) replace the default copy '
      'entirely',
      (WidgetTester tester) async {
        late AppLocalizations captured;
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('uk', 'UA'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (BuildContext ctx) {
                  captured = AppLocalizations.of(ctx);
                  return ServiceStepEmpty(
                    titleOverride: captured.salonCreateBookingServiceEmptyTitle,
                    bodyOverride: captured.salonCreateBookingServiceEmptyBody,
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(captured.salonCreateBookingServiceEmptyTitle),
          findsOneWidget,
        );
        expect(
          find.text(captured.salonCreateBookingServiceEmptyBody),
          findsOneWidget,
        );
        // The `??` fallback must NOT also render — the salon wizard's whole
        // reason for existing is that the master copy is wrong for its role.
        expect(
          find.text(captured.masterCreateBookingServiceEmptyTitle),
          findsNothing,
        );
        expect(
          find.text(captured.masterCreateBookingServiceEmptyBody),
          findsNothing,
        );
      },
    );

    testWidgets(
      'the two overrides are INDEPENDENT — a title-only override keeps the '
      'default body, and vice versa',
      (WidgetTester tester) async {
        const String customTitle = 'ЗАГОЛОВОК-ТЕСТ';
        const String customBody = 'ТІЛО-ТЕСТ';

        AppLocalizations l10n = await _pump(
          tester,
          const ServiceStepEmpty(titleOverride: customTitle),
        );
        expect(find.text(customTitle), findsOneWidget);
        expect(
          find.text(l10n.masterCreateBookingServiceEmptyTitle),
          findsNothing,
        );
        expect(
          find.text(l10n.masterCreateBookingServiceEmptyBody),
          findsOneWidget,
          reason: 'bodyOverride was not supplied — the default must survive',
        );

        l10n = await _pump(
          tester,
          const ServiceStepEmpty(bodyOverride: customBody),
        );
        expect(find.text(customBody), findsOneWidget);
        expect(
          find.text(l10n.masterCreateBookingServiceEmptyBody),
          findsNothing,
        );
        expect(
          find.text(l10n.masterCreateBookingServiceEmptyTitle),
          findsOneWidget,
          reason: 'titleOverride was not supplied — the default must survive',
        );
      },
    );
  });
}

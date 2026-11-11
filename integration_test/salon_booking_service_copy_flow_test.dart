// E2E — phase 470 acceptance 3: the copy-name hint on the CLIENT *salon*
// surfaces (the master path lives in `client_booking_service_copy_flow_test`).
//
// WHY THIS FLOW EXISTS
// --------------------
// The salon catalogue reaches the client through THREE separately-wired
// surfaces, each with its own hint memo:
//   • the public profile «Послуги» tab — `SalonServicesAccordion`
//     (`_hintsByCatalogue` Expando over the whole catalogue);
//   • the booking service picker — `SalonServiceSelectionScreen`'s
//     `_CatalogueBody` memo → `CatalogueRow.hint` → `CatalogueServiceTile`;
//   • the master-assignment shelf (`SelectedServicesShelf`) and the confirm
//     recap (`SalonAppointmentCard` → `BookingRecap`).
// The widget tier pins each widget in isolation; this flow pins that the REAL
// `GET /salons/salon-xyz/services` payload reaches each of them hinted.
//
// FIXTURE: the shared `salon-xyz` fixture + `FakeBackend.seedSalonCatalogCopy`
// — a 90-min copy (`salon-svc-shared-copy`) of «Манікюр класичний» 60 min
// (`salon-svc-shared`), both bookable by `master-ccc`. «Манікюр класичний
// VIP» (`salon-svc-namefallback`) shares the category but not the name and
// must stay un-hinted.
//
// KEY POLICY: every finder is key/type based (salon-tab-2,
// salon-service-row-<id>, salon-book-cta, salon_booking_service_tile_<id>,
// booking-summary-*, salon-assign-confirm-cta, salon-schedule-page-<id>,
// salon-slot-chip-<iso>, schedule-confirm-cta, salon-confirm-appt-<id>,
// service-name-hint); expected hint text is built from `AppLocalizations` +
// `DurationMinutes.format` + `NameWithHint.isolate`, never a Cyrillic literal.

import 'dart:async';

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_master_selection_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_service_selection_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_time_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/duration_minutes.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:beautica_mobile/shared/widgets/name_with_hint.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import '../test/helpers/pump_app.dart';
import 'support/app_harness.dart';

const String _original = FakeBackend.kSalonSharedCatalogServiceId;
const String _copy = FakeBackend.kSalonSharedCopyCatalogServiceId;
const String _otherName = 'salon-svc-namefallback';
const Key _hintKey = Key('service-name-hint');

String? _hintIn(WidgetTester tester, Finder scope) {
  final Finder hint = find.descendant(
    of: scope,
    matching: find.byKey(_hintKey),
  );
  if (hint.evaluate().isEmpty) return null;
  return tester.widget<Text>(hint).data;
}

String Function(int) _suffixFor(WidgetTester tester, Finder anchor) {
  final AppLocalizations l10n = AppLocalizations.of(tester.element(anchor));
  return (int minutes) => l10n.serviceNameHintSuffix(
    NameWithHint.isolate(DurationMinutes.format(minutes)),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'CLIENT salon: the «Послуги» accordion and the booking picker hint both '
    'copies (not the differently-named row), both can be picked, and the '
    'masters step queries both ids with a hinted shelf',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.client;
        fb.seedSalonCatalogCopy();
        final GoRouter router = await AppHarness.boot(tester, fb);
        await AppHarness.loginAs(tester, fb, UserRole.client);
        await AppHarness.settle(tester);

        // ── Public profile «Послуги» tab — SalonServicesAccordion ─────────
        unawaited(router.push(RouteNames.salonPublicProfile('salon-xyz')));
        await AppHarness.settle(tester);
        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('salon-tab-2')),
        );
        await AppHarness.settle(tester);

        Finder row(String id) => find.byKey(Key('salon-service-row-$id'));
        await AppHarness.pumpUntilFound(tester, row(_copy));
        final String Function(int) suffix = _suffixFor(tester, row(_copy));

        expect(_hintIn(tester, row(_original)), suffix(60));
        expect(_hintIn(tester, row(_copy)), suffix(90));
        expect(
          _hintIn(tester, row(_otherName)),
          isNull,
          reason: 'a differently-named service in the same salon is un-hinted',
        );

        // ── Booking picker — SalonServiceSelectionScreen ────────────────────
        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('salon-book-cta')),
        );
        await AppHarness.settle(tester);
        expect(find.byType(SalonServiceSelectionScreen), findsOneWidget);

        Finder tile(String id) =>
            find.byKey(Key('salon_booking_service_tile_$id'));
        await AppHarness.pumpUntilFound(tester, tile(_copy));
        expect(_hintIn(tester, tile(_original)), suffix(60));
        expect(_hintIn(tester, tile(_copy)), suffix(90));
        expect(_hintIn(tester, tile(_otherName)), isNull);

        // Both copies in one visit (D2 — no client-side block).
        await AppHarness.tapVisible(tester, tile(_original));
        await AppHarness.settle(tester);
        await AppHarness.tapVisible(tester, tile(_copy));
        await AppHarness.settle(tester);
        for (final String id in <String>[_original, _copy]) {
          expect(
            find.descendant(
              of: tile(id),
              matching: find.byKey(const ValueKey<bool>(true)),
            ),
            findsOneWidget,
            reason: '$id must be checked',
          );
        }

        // ── «Далі» → masters step: both ids queried, shelf hinted ────────────
        final int callsBefore = fb.getBookableMastersCalls;
        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('booking-summary-cta')),
        );
        await AppHarness.settle(tester);
        AppHarness.expectShellLocation(router, RouteNames.salonBookingMasters);
        expect(find.byType(SalonMasterSelectionScreen), findsOneWidget);
        expect(fb.getBookableMastersCalls - callsBefore, 2);
        expect(
          fb.requestedBookableMastersServiceDefIds,
          containsAll(<String>[_original, _copy]),
        );

        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('booking-summary-expand-toggle')),
        );
        await AppHarness.settle(tester);
        final Finder shelf = find.byKey(
          const Key('booking-summary-expanded-list'),
        );
        final List<String?> shelfHints = tester
            .widgetList<Text>(
              find.descendant(of: shelf, matching: find.byKey(_hintKey)),
            )
            .map((Text t) => t.data)
            .toList();
        expect(shelfHints, unorderedEquals(<String>[suffix(60), suffix(90)]));
        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('booking-summary-expand-toggle')),
        );
        await AppHarness.settle(tester);

        // ── master-ccc carries both copies → «Час» step ─────────────────────
        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('salon_booking_master_row_master-ccc')),
        );
        await AppHarness.settle(tester);
        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('salon-assign-confirm-cta')),
        );
        await AppHarness.settle(tester);
        AppHarness.expectShellLocation(router, RouteNames.salonBookingTime);
        expect(find.byType(SalonTimeScreen), findsOneWidget);

        // Pick today's 07:00Z slot (the fixture's morning slot) and continue
        // — the REAL path into the confirm recap, not a hand-built args push.
        Finder slide(Finder matching) => find.descendant(
          of: find.byKey(
            const Key('salon-schedule-page-master-ccc'),
            skipOffstage: false,
          ),
          matching: matching,
          skipOffstage: false,
        );
        final DateTime today = kyivToday(() => kFixedNow);
        await tester.tapCalendarDay(
          today.day,
          within: find.byKey(const Key('salon-schedule-page-master-ccc')),
        );
        await AppHarness.settle(tester);
        await tester.tap(find.byKey(const Key('schedule-confirm-cta')));
        await AppHarness.settle(tester);
        final String morningIso = DateTime.utc(
          today.year,
          today.month,
          today.day,
          7,
        ).toIso8601String();
        final Finder chip = slide(
          find.byKey(Key('salon-slot-chip-$morningIso')),
        );
        await AppHarness.pumpUntilFound(tester, chip);
        await tester.ensureVisible(chip);
        await AppHarness.settle(tester);
        await tester.tap(chip);
        await AppHarness.settle(tester);
        await tester.tap(find.byKey(const Key('schedule-confirm-cta')));
        await AppHarness.settle(tester);

        // ── Confirm recap: each copy with its own duration hint ─────────────
        AppHarness.expectShellLocation(router, RouteNames.salonBookingConfirm);
        final Finder card = find.byKey(
          const ValueKey<String>('salon-confirm-appt-master-ccc'),
        );
        expect(card, findsOneWidget);
        final Finder recapRows = find.descendant(
          of: card,
          matching: find.byType(NameWithHint),
        );
        expect(
          tester
              .widgetList<NameWithHint>(recapRows)
              .map((NameWithHint w) => w.hint)
              .toList(),
          unorderedEquals(<String>[
            DurationMinutes.format(60),
            DurationMinutes.format(90),
          ]),
        );
        // What the client actually SEES: the recap renders in wrapping mode
        // (one `Text.rich` per row), painting «FSI name PDI · FSI hint PDI».
        final String recapName = tester
            .widget<NameWithHint>(recapRows.first)
            .name;
        expect(
          tester
              .widgetList<RichText>(
                find.descendant(of: recapRows, matching: find.byType(RichText)),
              )
              .map((RichText t) => t.text.toPlainText())
              .toList(),
          unorderedEquals(<String>[
            NameWithHint.isolate(recapName) + suffix(60),
            NameWithHint.isolate(recapName) + suffix(90),
          ]),
        );
        expect(tester.takeException(), isNull);
      });
    },
    timeout: const Timeout(Duration(seconds: 180)),
  );
}

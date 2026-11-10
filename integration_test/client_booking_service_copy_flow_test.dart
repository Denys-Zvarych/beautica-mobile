// E2E — phase 470: the copy-name hint on the CLIENT booking flow (acceptance
// 1–2).
//
// WHY THIS FLOW EXISTS
// --------------------
// A master may hold two copies of one service type under the same name (468).
// 469 hints them on the owner list; 470 carries the SAME rule
// (`serviceNameHints`) to every surface where a client picks or reviews
// services. The widget tier pins each tile with/without a hint; this flow pins
// the WIRING across the real router: public catalogue → `ServiceSelectorSheet`
// memo → `CatalogueServiceTile` → slot picker shelf → confirm recap → submit,
// and that booking BOTH copies in one visit is allowed (D2): the visit sums
// 90 + 60 = 150 min, both ids reach availability and the create.
//
// FIXTURE
// -------
// `FakeBackend.publicMasterServiceCopy` adds a 60-min copy of master-aaa's
// `pub-assign-1` («Манікюр з покриттям», 90 min). `pub-assign-2` keeps a
// unique name and must stay un-hinted.
//
// KEY POLICY: every finder is key/type based; expected hint text is built from
// `AppLocalizations` + `DurationMinutes.format` + `NameWithHint.isolate`.

import 'dart:async';

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/data/appointment_repository.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/domain/appointment.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/create_appointment_request.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_confirm_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_success_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/service_selector_sheet.dart';
import 'package:beautica_mobile/features/booking/presentation/slot_picker_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/slot_chip.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/duration_minutes.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:beautica_mobile/shared/widgets/name_with_hint.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import '../test/helpers/pump_app.dart';
import 'support/app_harness.dart';

const String _original = 'pub-assign-1';
const String _copy = FakeBackend.publicMasterServiceCopyId;
const String _unique = 'pub-assign-2';
const Key _hintKey = Key('service-name-hint');

/// Records the single visit create and answers with a CONFIRMED appointment.
class _RecordingAppointmentRepository implements AppointmentRepository {
  final List<CreateAppointmentRequest> requests = <CreateAppointmentRequest>[];

  @override
  Future<Appointment> createAppointment(CreateAppointmentRequest req) async {
    requests.add(req);
    final DateTime end = req.startAt.add(const Duration(minutes: 150));
    return Appointment(
      id: 'appt-copy-1',
      status: BookingStatus.confirmed,
      masterId: req.masterId,
      masterFirstName: 'Софія',
      masterLastName: 'Бондар',
      masterType: 'INDEPENDENT_MASTER',
      startAt: req.startAt,
      endAt: end,
      totalDurationMinutes: 150,
      totalPrice: 900,
      items: <AppointmentItem>[
        for (final String id in req.masterServiceIds)
          AppointmentItem(
            bookingId: 'booking-$id',
            masterServiceId: id,
            serviceName: 'Послуга',
            startAt: req.startAt,
            endAt: end,
            durationMinutes: 75,
            price: 450,
          ),
      ],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Finder _tile(String id) => find.byKey(Key('booking_service_tile_$id'));

String? _tileHint(WidgetTester tester, String id) {
  final Finder hint = find.descendant(
    of: _tile(id),
    matching: find.byKey(_hintKey),
  );
  if (hint.evaluate().isEmpty) return null;
  return tester.widget<Text>(hint).data;
}

/// The painted plain text of every recap row ([NameWithHint] in wrapping
/// mode renders one `Text.rich` → one [RichText]) under [scope].
List<String> _paintedRecapRows(WidgetTester tester, Finder scope) => tester
    .widgetList<RichText>(
      find.descendant(
        of: find.descendant(of: scope, matching: find.byType(NameWithHint)),
        matching: find.byType(RichText),
      ),
    )
    .map((RichText t) => t.text.toPlainText())
    .toList();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'CLIENT sees both copies hinted in the selector, picks both, the shelf and '
    'the confirm recap carry the hints, the visit sums 150 min, slots load and '
    'one POST carries both ids',
    (tester) async {
      final fb = FakeBackend()
        ..currentRole = UserRole.client
        ..publicMasterServiceCopy = true;
      final repo = _RecordingAppointmentRepository();
      final GoRouter router = await AppHarness.boot(
        tester,
        fb,
        extraOverrides: <Object>[
          appointmentRepositoryProvider.overrideWithValue(repo),
        ],
      );
      await AppHarness.loginAs(tester, fb, UserRole.client);
      await AppHarness.settle(tester);

      // ── Selector (acceptance 1) ────────────────────────────────────────
      unawaited(router.push(RouteNames.masterPublicProfile('master-aaa')));
      await AppHarness.settle(tester);
      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('public-master-book-cta')),
      );
      await AppHarness.settle(tester);
      expect(find.byType(ServiceSelectorSheet), findsOneWidget);

      if (_tile(_original).evaluate().isEmpty) {
        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('booking_category_NAILS')),
        );
      }
      await AppHarness.pumpUntilFound(tester, _tile(_copy));

      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(ServiceSelectorSheet)),
      );
      String suffix(int minutes) => l10n.serviceNameHintSuffix(
        NameWithHint.isolate(DurationMinutes.format(minutes)),
      );

      expect(_tileHint(tester, _original), suffix(90));
      expect(_tileHint(tester, _copy), suffix(60));
      expect(
        _tileHint(tester, _unique),
        isNull,
        reason: 'a uniquely-named service in the same list gets no hint',
      );

      // Book BOTH copies in one visit (D2 — no client-side block).
      await AppHarness.tapVisible(tester, _tile(_original));
      await AppHarness.tapVisible(tester, _tile(_copy));
      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('booking-summary-cta')),
      );
      await AppHarness.settle(tester);

      // ── Date step: both ids reach availability; the shelf is hinted ─────
      AppHarness.expectShellLocation(router, RouteNames.bookingSlots);
      expect(find.byType(SlotDateScreen), findsOneWidget);
      expect(
        fb.lastMasterAaaWorkingDaysServiceIds,
        unorderedEquals(<String>[_original, _copy]),
      );

      await tester.tap(find.byKey(const Key('booking-summary-expand-toggle')));
      await AppHarness.settle(tester);
      final Finder shelf = find.byKey(
        const Key('booking-summary-expanded-list'),
      );
      expect(
        find.descendant(of: shelf, matching: find.byKey(_hintKey)),
        findsNWidgets(2),
      );
      await tester.tap(find.byKey(const Key('booking-summary-expand-toggle')));
      await AppHarness.settle(tester);

      // ── Time step: slots load for the 150-min visit ─────────────────────
      final DateTime today = kyivToday(() => kFixedNow);
      await tester.tapCalendarDay(today.day);
      await AppHarness.settle(tester);
      await tester.tap(find.byKey(const Key('booking-summary-cta')));
      await AppHarness.settle(tester);
      AppHarness.expectShellLocation(router, RouteNames.bookingSlotsTime);
      expect(
        fb.lastMasterAaaSlotsServiceIds,
        unorderedEquals(<String>[_original, _copy]),
      );
      final Finder chip = find
          .byWidgetPredicate((Widget w) => w is SlotChip && w.available)
          .first;
      expect(chip, findsOneWidget, reason: 'slots load for both copies');
      await tester.ensureVisible(chip);
      await AppHarness.settle(tester);
      await tester.tap(chip);
      await AppHarness.settle(tester);
      await tester.tap(find.byKey(const Key('booking-summary-cta')));
      await AppHarness.settle(tester);

      // ── Confirm recap (acceptance 2) ────────────────────────────────────
      AppHarness.expectShellLocation(router, RouteNames.bookingConfirm);
      final Finder confirm = find.byType(BookingConfirmScreen);
      expect(confirm, findsOneWidget);
      final List<String?> recapHints = tester
          .widgetList<NameWithHint>(
            find.descendant(of: confirm, matching: find.byType(NameWithHint)),
          )
          .map((NameWithHint w) => w.hint)
          .toList();
      expect(
        recapHints,
        unorderedEquals(<String>[
          DurationMinutes.format(90),
          DurationMinutes.format(60),
        ]),
      );
      // What the client actually SEES: each recap row paints
      // «FSI name PDI · FSI hint PDI» as one wrapping paragraph (name and hint each
      // bidi-isolated).
      final String recapName = tester
          .widget<NameWithHint>(
            find
                .descendant(of: confirm, matching: find.byType(NameWithHint))
                .first,
          )
          .name;
      expect(
        _paintedRecapRows(tester, confirm),
        unorderedEquals(<String>[
          NameWithHint.isolate(recapName) + suffix(90),
          NameWithHint.isolate(recapName) + suffix(60),
        ]),
      );
      expect(
        find.descendant(
          of: confirm,
          matching: find.text(DurationMinutes.format(150)),
        ),
        findsWidgets,
        reason: 'the «Разом» total sums both copies: 90 + 60 = 150 min',
      );

      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('booking-confirm-submit-cta')),
      );
      await AppHarness.settle(tester);

      AppHarness.expectShellLocation(router, RouteNames.bookingSuccess);
      expect(find.byType(BookingSuccessScreen), findsOneWidget);
      expect(repo.requests, hasLength(1));
      expect(
        repo.requests.single.masterServiceIds,
        unorderedEquals(<String>[_original, _copy]),
      );
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );
}

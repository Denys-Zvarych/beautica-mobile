// QA (track 14.x "Додати в календар") — the THIRD calendar call site.
//
// `add_to_calendar_test.dart` covers the shared [addBookingToCalendar] helper
// and `booking_detail_interactions_test.dart` covers «Деталі запису»'s call
// site. The BOOKING-SUCCESS screen is the remaining, structurally DISTINCT one:
// its `_onAddToCalendar` maps its OWN domain shapes into the Event, and none of
// that mapping is exercised elsewhere —
//   • provider    = "<master.firstName> <master.lastName>" (NOT Booking.masterName);
//   • location    = formatStreetCityLine(master.street/buildingNo/city);
//   • start       = the TAPPED appointment's start;
//   • end         = that appointment's start + its service.durationMinutes
//                   (COMPUTED here — the success screen has no Booking.endAt).
//
// ONE BUTTON PER APPOINTMENT (the defect this suite now pins): the OS INSERT
// sheet takes one event per invocation, so the screen's old single page-level
// pill could only ever seed the FIRST of N services — a multi-service booking
// silently lost the rest. Every appointment card now carries its own
// `CalendarButton`, keyed `booking-success-add-calendar-<serviceId>-<i>`, and
// the page-level pill is gone. The fixture books TWO services with DIFFERENT
// durations, prices and starts so each button's Event can be pinned to ITS
// OWN appointment, and a third case books the SAME service twice to prove the
// index-suffixed keys stay distinguishable.
//
// FAILURE PATH + GUARD RELEASE: `_calendarInFlight` is cleared in a `finally`,
// so a FAILED export must leave every button on the screen usable. Both native
// failure shapes are driven from the channel (a thrown `PlatformException` —
// the ActivityNotFoundException a device with no calendar app raises — and a
// plain `false` return), each asserting the error SnackBar AND that the next
// tap still reaches the channel with ITS OWN appointment. Without this, a
// leaked flag would permanently deafen a screen the client cannot back out of
// (`PopScope(canPop: false)`).
//
// SEMANTICS: N visually identical pills on one recap are distinguishable to a
// screen reader ONLY by `bookingAddCalendarServiceSemantics(service)`, so the
// labels are asserted on the real semantics tree, present and DISTINCT.
//
// The `add_2_calendar` plugin is mocked at the CHANNEL boundary (the same
// `setMockMethodCallHandler('add_2_calendar', …)` seam the two sibling suites
// use) — no real OS sheet ever opens. Copy is asserted through l10n keys and
// the location through the real `formatStreetCityLine`, never a raw Cyrillic
// literal, so the assertions stay in lockstep with the source.

import 'dart:async';

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/booking/domain/booking_success_args.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_success_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/calendar_button.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/service_price_display.dart';
import 'package:beautica_mobile/shared/formatters/street_city_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/booking_fixture_dates.dart';
import '../../../helpers/pump_app.dart';

// The add_2_calendar plugin's platform boundary — intercepted so tapping
// «Додати в календар» never opens a real OS calendar sheet.
const MethodChannel _kCalendarChannel = MethodChannel('add_2_calendar');

// A solo master with a full home address AND a private location note. The note
// must NEVER ride into the calendar Event (only street/buildingNo/city do).
const Master _kMaster = Master(
  id: 'm1',
  firstName: 'Марія',
  lastName: 'Іванюк',
  city: 'Львів',
  street: 'вул. Городоцька',
  buildingNo: '12',
  locationNote: 'кв. 3, домашня адреса — СЕКРЕТ',
  avgRating: 4.9,
  reviewCount: 20,
  type: MasterType.independentMaster,
);

// FIRST appointment: 90 min.
const MasterService _kFirstService = MasterService(
  id: 's1',
  serviceDefId: 'def-1',
  name: 'Манікюр з покриттям',
  durationMinutes: 90,
  priceMin: 650,
  priceDisplay: '650 ₴',
  category: 'MANICURE',
);

// SECOND appointment: a DIFFERENT duration, price and start, so each button's
// Event can be pinned to its own appointment rather than the first's.
const MasterService _kSecondService = MasterService(
  id: 's2',
  serviceDefId: 'def-2',
  name: 'Педикюр',
  durationMinutes: 45,
  priceMin: 550,
  priceDisplay: '550 ₴',
  category: 'PEDICURE',
);

// Anchored to the wall clock (never an absolute literal — see
// `helpers/booking_fixture_dates.dart`).
final DateTime _kFirstStart = futureBookingStart();
final DateTime _kSecondStart = futureBookingStart(
  aheadOfNow: const Duration(days: 31),
);

// The per-appointment button keys the screen builds:
// 'booking-success-add-calendar-<serviceId>-<index>'.
Key _calendarKey(String serviceId, int index) =>
    ValueKey<String>('booking-success-add-calendar-$serviceId-$index');

BookingSuccessArgs _args({List<BookingSuccessAppointment>? appointments}) =>
    BookingSuccessArgs(
      master: _kMaster,
      appointments:
          appointments ??
          <BookingSuccessAppointment>[
            BookingSuccessAppointment(
              service: _kFirstService,
              start: _kFirstStart,
            ),
            BookingSuccessAppointment(
              service: _kSecondService,
              start: _kSecondStart,
            ),
          ],
    );

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(BookingSuccessScreen)));

Future<void> _pumpSuccess(
  WidgetTester tester, {
  BookingSuccessArgs? args,
}) async {
  await tester.pumpApp(
    BookingSuccessScreen(args: args ?? _args()),
    overrides: <Object>[
      screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
    ],
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Key key) async {
  final Finder button = find.byKey(key);
  expect(button, findsOneWidget);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

/// Waits out the error SnackBar's own auto-dismiss before the NEXT tap.
///
/// The floating SnackBar occupies the bottom of the surface, exactly where
/// `ensureVisible` parks a scrolled-to button — tapping through it would land
/// on the SnackBar instead of the pill and turn a real regression into a
/// mystery. Pump-until-gone (never a fixed sleep) so the wait is exactly the
/// SnackBar's real lifetime.
Future<void> _dismissErrorSnackBar(
  WidgetTester tester,
  AppLocalizations l10n,
) async {
  final Finder snack = find.text(l10n.bookingAddToCalendarError);
  expect(snack, findsOneWidget);
  await tester.pumpUntilGone(snack);
}

/// The Event payload of the single recorded `add2Cal` call.
Map<Object?, Object?> _argsOf(List<MethodCall> calls) {
  expect(calls, hasLength(1));
  return calls.single.arguments as Map<Object?, Object?>;
}

void main() {
  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_kCalendarChannel, (MethodCall call) async {
          calls.add(call);
          return true; // pretend a calendar app opened
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_kCalendarChannel, null);
  });

  group('booking success — «Додати в календар»', () {
    testWidgets(
      'renders ONE button per confirmed appointment and NO page-level pill '
      '(a single button could only ever export one of N)',
      (tester) async {
        await _pumpSuccess(tester);

        expect(find.byType(CalendarButton), findsNWidgets(2));
        expect(find.byKey(_calendarKey('s1', 0)), findsOneWidget);
        expect(find.byKey(_calendarKey('s2', 1)), findsOneWidget);
        // The retired page-level pill's key must not reappear as a second door
        // that exports only the first appointment. `CalendarButton.buttonKey`
        // is REQUIRED now precisely so nothing can silently fall back to it.
        expect(
          find.byKey(const Key('booking-add-calendar')),
          findsNothing,
          reason:
              'the page-level pill below the recap is gone — every export is '
              'card-scoped',
        );
      },
    );

    testWidgets(
      'a tap on a SECOND card while the first INSERT is still in flight is '
      'coalesced — never two stacked platform intents',
      (tester) async {
        // RE-ENTRY GUARD (`_calendarInFlight`): N buttons where there used to
        // be one means two taps can now overlap. A second INSERT intent would
        // stack on the activity stack and the first `await` would resolve
        // against a backgrounded app, landing its failure SnackBar on the wrong
        // screen state. Gate the channel on a Completer so the first call is
        // genuinely still pending when the second tap lands.
        final Completer<bool> gate = Completer<bool>();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_kCalendarChannel, (MethodCall call) {
              calls.add(call);
              return gate.future;
            });

        await _pumpSuccess(tester);

        await tester.ensureVisible(find.byKey(_calendarKey('s1', 0)));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(_calendarKey('s1', 0)));
        await tester.pump();

        await tester.ensureVisible(find.byKey(_calendarKey('s2', 1)));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(_calendarKey('s2', 1)));
        await tester.pump();

        expect(
          calls,
          hasLength(1),
          reason: 'the in-flight guard dropped the overlapping second tap',
        );

        // Once the pending request resolves the guard clears, so the screen is
        // not left permanently deaf to the remaining exports.
        gate.complete(true);
        await tester.pumpAndSettle();

        await _tap(tester, _calendarKey('s2', 1));
        expect(
          calls,
          hasLength(2),
          reason: 'the guard released — the second appointment still exports',
        );
      },
    );

    testWidgets(
      'the FIRST card invokes add2Cal with the service·master title, the '
      'formatStreetCityLine location, ITS start and the COMPUTED end '
      '(start + service.durationMinutes)',
      (tester) async {
        await _pumpSuccess(tester);
        final AppLocalizations l10n = _l10n(tester);

        await _tap(tester, _calendarKey('s1', 0));

        expect(calls, hasLength(1), reason: 'add2Cal must have fired once');
        expect(calls.single.method, 'add2Cal');
        final Map<Object?, Object?> args =
            calls.single.arguments as Map<Object?, Object?>;

        // Title: service · "<firstName> <lastName>" — the success screen builds
        // the provider from the Master, not from a Booking.masterName.
        expect(
          args['title'],
          l10n.bookingCalendarEventTitle(
            _kFirstService.name,
            '${_kMaster.firstName} ${_kMaster.lastName}',
          ),
        );

        // Location: the SAME street/buildingNo/city join the recap card renders.
        expect(
          args['location'],
          formatStreetCityLine(
            street: _kMaster.street,
            buildingNo: _kMaster.buildingNo,
            city: _kMaster.city,
          ),
        );

        // Start = FIRST appointment; end = start + FIRST service's duration
        // (90 min) — not the second appointment's, not summed.
        expect(args['startDate'], _kFirstStart.millisecondsSinceEpoch);
        expect(
          args['endDate'],
          _kFirstStart
              .add(Duration(minutes: _kFirstService.durationMinutes))
              .millisecondsSinceEpoch,
        );

        // Success path: the OS sheet "opened" — no error SnackBar.
        expect(find.text(l10n.bookingAddToCalendarError), findsNothing);
      },
    );

    testWidgets(
      'THE DEFECT: the SECOND card exports the SECOND appointment — its own '
      'service, start, computed end and price — never the first\'s',
      (tester) async {
        await _pumpSuccess(tester);
        final AppLocalizations l10n = _l10n(tester);

        await _tap(tester, _calendarKey('s2', 1));

        expect(calls, hasLength(1));
        final Map<Object?, Object?> args =
            calls.single.arguments as Map<Object?, Object?>;

        // Title carries the SECOND service.
        expect(
          args['title'],
          l10n.bookingCalendarEventTitle(
            _kSecondService.name,
            '${_kMaster.firstName} ${_kMaster.lastName}',
          ),
        );
        expect(
          args['title'],
          isNot(
            l10n.bookingCalendarEventTitle(
              _kFirstService.name,
              '${_kMaster.firstName} ${_kMaster.lastName}',
            ),
          ),
          reason: 'the pre-fix behaviour exported the FIRST service here',
        );

        // Window = the SECOND appointment's start + the SECOND service's 45 min
        // duration. Both differ from the first's, so neither can pass by luck.
        expect(args['startDate'], _kSecondStart.millisecondsSinceEpoch);
        expect(args['startDate'], isNot(_kFirstStart.millisecondsSinceEpoch));
        expect(
          args['endDate'],
          _kSecondStart
              .add(Duration(minutes: _kSecondService.durationMinutes))
              .millisecondsSinceEpoch,
        );
        expect(
          args['endDate'],
          isNot(
            _kFirstStart
                .add(Duration(minutes: _kFirstService.durationMinutes))
                .millisecondsSinceEpoch,
          ),
        );

        // The structured description follows the same appointment: the SECOND
        // service's name and ITS price, with no trace of the first's.
        final String desc = args['desc'] as String;
        expect(desc.contains(_kSecondService.name), isTrue);
        expect(desc.contains(_kFirstService.name), isFalse);
        expect(
          desc.contains(ServicePriceDisplay.format(_kSecondService)),
          isTrue,
        );
        expect(
          desc.contains(ServicePriceDisplay.format(_kFirstService)),
          isFalse,
        );
      },
    );

    testWidgets(
      'the SAME service booked twice at different times keeps two distinct '
      'buttons, each exporting its own start',
      (tester) async {
        final DateTime later = futureBookingStart(
          aheadOfNow: const Duration(days: 32),
        );
        await _pumpSuccess(
          tester,
          args: _args(
            appointments: <BookingSuccessAppointment>[
              BookingSuccessAppointment(
                service: _kFirstService,
                start: _kFirstStart,
              ),
              BookingSuccessAppointment(service: _kFirstService, start: later),
            ],
          ),
        );

        expect(find.byType(CalendarButton), findsNWidgets(2));

        await _tap(tester, _calendarKey('s1', 0));
        expect(
          (calls.single.arguments as Map<Object?, Object?>)['startDate'],
          _kFirstStart.millisecondsSinceEpoch,
        );

        calls.clear();
        await _tap(tester, _calendarKey('s1', 1));
        expect(
          (calls.single.arguments as Map<Object?, Object?>)['startDate'],
          later.millisecondsSinceEpoch,
        );
      },
    );

    testWidgets(
      'a SINGLE-service booking still gets its card-scoped button (one rule, '
      'one layout — no page-level special case for N == 1)',
      (tester) async {
        await _pumpSuccess(
          tester,
          args: _args(
            appointments: <BookingSuccessAppointment>[
              BookingSuccessAppointment(
                service: _kFirstService,
                start: _kFirstStart,
              ),
            ],
          ),
        );

        expect(find.byType(CalendarButton), findsOneWidget);
        await _tap(tester, _calendarKey('s1', 0));
        expect(
          (calls.single.arguments as Map<Object?, Object?>)['startDate'],
          _kFirstStart.millisecondsSinceEpoch,
        );
      },
    );

    testWidgets(
      'the Event description carries the STRUCTURED facts (service / master / '
      'date-time / address / price / status) yet the master locationNote '
      '(home-address PII) never rides into it (change #3)',
      (tester) async {
        // Change #3 reversed the old "desc stays null" premise: the success
        // screen now builds a structured-facts description. It must carry the
        // facts (asserted via l10n label keys) AND still exclude the private
        // location note.
        await _pumpSuccess(tester);
        final AppLocalizations l10n = _l10n(tester);

        await _tap(tester, _calendarKey('s1', 0));

        final Map<Object?, Object?> args =
            calls.single.arguments as Map<Object?, Object?>;

        // Structured description is now POPULATED — every label present via its
        // l10n key (an independent master → the «Майстер:» label, never salon).
        final String desc = args['desc'] as String;
        expect(desc, isNotEmpty);
        for (final String label in <String>[
          l10n.bookingCalendarNoteService,
          l10n.bookingCalendarNoteMaster,
          l10n.bookingCalendarNoteDateTime,
          l10n.bookingCalendarNoteAddress,
          l10n.bookingCalendarNotePrice,
          l10n.bookingCalendarNoteStatus,
        ]) {
          expect(
            desc.contains(label),
            isTrue,
            reason: 'structured description must carry the «$label» line',
          );
        }
        // The real facts behind those labels — the tapped appointment's
        // service, the master name, the address line and the confirmed status.
        expect(desc.contains(_kFirstService.name), isTrue);
        expect(
          desc.contains('${_kMaster.firstName} ${_kMaster.lastName}'),
          isTrue,
        );
        expect(
          desc.contains(
            formatStreetCityLine(
              street: _kMaster.street,
              buildingNo: _kMaster.buildingNo,
              city: _kMaster.city,
            )!,
          ),
          isTrue,
        );
        expect(desc.contains(l10n.bookingStatusConfirmed), isTrue);

        // PRIVACY: the private location note must not leak into ANY Event field
        // (there is no builder parameter that can carry it).
        final String payload = args.values.map((Object? v) => '$v').join('|');
        expect(
          payload.contains(_kMaster.locationNote!),
          isFalse,
          reason:
              'the private location note must not leak into any Event field',
        );
      },
    );

    testWidgets(
      'a FAILED export surfaces the error SnackBar AND releases the in-flight '
      'guard — the next card still exports ITS OWN appointment',
      (tester) async {
        // THE LEAK THIS PINS: `_calendarInFlight` is set BEFORE the Event is
        // built and cleared in a `finally`. The existing coalescing test only
        // proves the guard clears on a SUCCESSFUL resolve. If the release ever
        // moves onto the happy path only, the FIRST failed export deafens
        // EVERY calendar button on the screen for the rest of its lifetime —
        // and the screen is a dead end (`PopScope(canPop: false)`; «На
        // головну» is the only way out), so the client cannot even retry by
        // going back. Silent, permanent, and invisible to the happy-path
        // suite.
        //
        // A no-calendar-app device raises ActivityNotFoundException, which
        // crosses the channel as a `PlatformException` — the failure mode
        // `add_to_calendar_test.dart` pins at the HELPER tier. Here it is the
        // SCREEN's reaction that is under test.
        bool failNext = true;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_kCalendarChannel, (
              MethodCall call,
            ) async {
              calls.add(call);
              if (failNext) {
                failNext = false;
                throw PlatformException(code: 'no_activity');
              }
              return true;
            });

        await _pumpSuccess(tester);
        final AppLocalizations l10n = _l10n(tester);

        // ── First card: the export fails ──────────────────────────────────
        await _tap(tester, _calendarKey('s1', 0));
        expect(calls, hasLength(1));
        // The ONLY user feedback this fire-and-forget action has.
        await _dismissErrorSnackBar(tester, l10n);

        // ── Guard released: the SECOND card still works, and still exports
        // the SECOND appointment (a leaked guard would drop this tap; a
        // first-appointment fallback would export the wrong window). ───────
        calls.clear();
        await _tap(tester, _calendarKey('s2', 1));

        final Map<Object?, Object?> args = _argsOf(calls);
        expect(
          args['startDate'],
          _kSecondStart.millisecondsSinceEpoch,
          reason: 'the guard released after the failure — card 2 exported',
        );
        expect(
          args['endDate'],
          _kSecondStart
              .add(Duration(minutes: _kSecondService.durationMinutes))
              .millisecondsSinceEpoch,
        );
        // The recovered export succeeded — no second error SnackBar.
        expect(find.text(l10n.bookingAddToCalendarError), findsNothing);
      },
    );

    testWidgets(
      'the plugin answering FALSE (no calendar app) is treated as a failure '
      'too — SnackBar shown, guard released, a repeat tap re-exports',
      (tester) async {
        // The other native failure shape: no throw, just `false`. It must not
        // be mistaken for a success, and — like the throw — it must not wedge
        // the guard.
        bool refuseNext = true;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_kCalendarChannel, (
              MethodCall call,
            ) async {
              calls.add(call);
              if (refuseNext) {
                refuseNext = false;
                return false;
              }
              return true;
            });

        await _pumpSuccess(tester);
        final AppLocalizations l10n = _l10n(tester);

        await _tap(tester, _calendarKey('s1', 0));
        expect(calls, hasLength(1));
        await _dismissErrorSnackBar(tester, l10n);

        // Re-tapping the SAME card must reach the channel again.
        calls.clear();
        await _tap(tester, _calendarKey('s1', 0));
        expect(
          _argsOf(calls)['startDate'],
          _kFirstStart.millisecondsSinceEpoch,
          reason: 'a refused export must leave the button usable',
        );
      },
    );

    testWidgets(
      'each button announces WHICH appointment it adds — the per-service '
      'semantics labels are present and DISTINCT',
      (tester) async {
        // THE POINT OF `bookingAddCalendarServiceSemantics`: a multi-service
        // recap stacks N visually identical «Додати в календар» pills. Under a
        // screen reader they are distinguishable ONLY by this label — N
        // buttons all announcing the same generic string is an unusable
        // screen. Asserted on the real SEMANTICS TREE (not the widget
        // property) so it is the announcement itself that is pinned, and via
        // the l10n key so it survives a copy change.
        // Disposed INSIDE the body (not via addTearDown): flutter_test's
        // end-of-test handle verification runs BEFORE tearDowns, so a
        // tearDown-scheduled dispose still trips "A SemanticsHandle was active
        // at the end of the test".
        final SemanticsHandle handle = tester.ensureSemantics();

        await _pumpSuccess(tester);
        final AppLocalizations l10n = _l10n(tester);

        final String firstLabel = l10n.bookingAddCalendarServiceSemantics(
          _kFirstService.name,
        );
        final String secondLabel = l10n.bookingAddCalendarServiceSemantics(
          _kSecondService.name,
        );

        expect(
          firstLabel,
          isNot(secondLabel),
          reason:
              'the label must be service-qualified — a shared string would '
              'defeat its entire purpose',
        );
        // The `Semantics` wrapper does not set `container`, so its label MERGES
        // with the pill's own «Додати в календар» copy — the node reads
        // "<service-qualified label>\n<CTA copy>". The service-qualified part
        // therefore has to LEAD (it is what a screen reader announces first),
        // which is what `startsWith` pins; asserting the full merged string
        // would just re-encode the CTA copy a second time.
        final SemanticsNode firstNode = tester.getSemantics(
          find.byKey(_calendarKey('s1', 0)),
        );
        final SemanticsNode secondNode = tester.getSemantics(
          find.byKey(_calendarKey('s2', 1)),
        );

        expect(firstNode.label, startsWith(firstLabel));
        expect(secondNode.label, startsWith(secondLabel));
        expect(
          firstNode.label,
          isNot(secondNode.label),
          reason:
              'two identically-announced buttons on one screen is exactly '
              'what the service-qualified label exists to prevent',
        );

        // Both are announced as buttons and are actually operable by an
        // assistive tap (a label on an inert node would be a lie).
        for (final SemanticsNode node in <SemanticsNode>[
          firstNode,
          secondNode,
        ]) {
          final SemanticsData data = node.getSemanticsData();
          expect(data.flagsCollection.isButton, isTrue);
          expect(data.hasAction(SemanticsAction.tap), isTrue);
          // The retired generic label must not have survived as a fallback
          // here (it still belongs to «Деталі запису», which has exactly ONE
          // calendar affordance and so does not need qualifying).
          expect(
            node.label.startsWith(l10n.bookingAddCalendarSemantics),
            isFalse,
          );
        }

        handle.dispose();
      },
    );

    // STRESS SIZES: 320dp @ 2.0 (the narrowest Android phone at the maximum
    // accessibility text scale) and 400dp @ 2.0. Both are CLEAN, and 320 @ 2.0
    // is now the tightest reachable configuration this screen has to survive.
    //
    // It did not used to be. 320 @ 2.0 overflowed the recap card by 35px on the
    // right, in the grand-total row: «Разом» (70.1) + the `sm` gap (8) + «2 год
    // 15 хв» (121.7) + «1200 ₴» (83.3) wanted 283.1dp of the card's 248dp, and
    // every one of the three was an UNFLEXED child of a `Row` whose only
    // elastic member was a `Spacer` — which can donate space but can never
    // absorb a deficit, so the row had no way to give. `_TotalRow` now states
    // an explicit order of sacrifice instead (duration `Flexible` and wrapping,
    // price unflexed and right-pinned via `MainAxisAlignment.spaceBetween`) —
    // see its class doc in `booking_recap.dart`. This loop is the pin that
    // keeps that fix in place: `pumpApp`'s overflow guard fails on ANY
    // RenderFlex overflow, so a revert to the unflexed row reddens 320 @ 2.0
    // here immediately.
    //
    // WHERE THE CLIFF ACTUALLY IS — stated plainly rather than left for the
    // next person to rediscover: the row is elastic, not infinitely so. 320 @
    // 4.0 and 240 @ 2.0 both still overflow. Neither is a configuration this
    // app can be put into: `sw320dp` is the Android platform minimum width (no
    // narrower bucket exists), and 2.0 is the ceiling of the OS accessibility
    // font scale. So the untested region above is unreachable, NOT unknown —
    // but if a future device, a desktop/window-resize target, or an in-app
    // text-scale control ever pushes past 320 @ 2.0, the answer is another
    // elastic member in that row, not a larger number in this list.
    for (final (double width, double scale) in <(double, double)>[
      (320, 2.0),
      (400, 2.0),
    ]) {
      testWidgets(
        'the N-button recap lays out at ${width.toInt()}dp / $scale× text — '
        'each pill hugs its label instead of overflowing its card',
        (tester) async {
          // The pill is sized BY its label row and sits flush right on the
          // card's value column. That is comfortable at the default 800dp; on
          // a narrow phone with the OS font raised, «Додати в календар» plus
          // its glyph plus the card padding is the tightest row on the screen
          // — and there are now N of them where there used to be one, inside
          // cards that already carry a date, a time, a service and a price.
          // Nothing else pumps this screen at stress size.
          //
          // `pumpApp`'s overflow guard fails the test on ANY RenderFlex
          // overflow, so the assertions below only have to prove the buttons
          // really rendered at that size (an empty tree would trivially not
          // overflow).
          await tester.pumpApp(
            BookingSuccessScreen(args: _args()),
            overrides: <Object>[
              screenProtectionProvider.overrideWithValue(
                _NoOpScreenProtection(),
              ),
            ],
            width: width,
            textScaleFactor: scale,
          );
          await tester.pumpAndSettle();

          expect(find.byType(CalendarButton), findsNWidgets(2));

          // Each pill stays inside the surface — the guard catches a
          // RenderFlex overflow, this catches a silent horizontal spill.
          for (final (String serviceId, int i) in <(String, int)>[
            ('s1', 0),
            ('s2', 1),
          ]) {
            final Finder pill = find.byKey(_calendarKey(serviceId, i));
            expect(pill, findsOneWidget);
            expect(tester.getSize(pill).width, lessThanOrEqualTo(width));
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}

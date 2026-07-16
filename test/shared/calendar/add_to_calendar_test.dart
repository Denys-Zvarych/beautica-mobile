// QA (track 14.x "Додати в календар") — unit/behaviour suite for the shared
// [addBookingToCalendar] helper (lib/shared/calendar/add_to_calendar.dart).
//
// The helper is the ONE code path behind every calendar affordance (My Bookings
// detail, booking success, home-hub next-appointment). It builds an
// `add_2_calendar` [Event] and fires the platform INSERT via
// `Add2Calendar.addEvent2Cal`, whose sole side-effect surface is:
//   • the native `add2Cal` platform method (channel `add_2_calendar`), and
//   • a localised error SnackBar when that call returns `false` (no calendar
//     app) OR throws (PlatformException / MissingPluginException).
//
// We mock the plugin at the CHANNEL boundary
// (`setMockMethodCallHandler('add_2_calendar', …)`) — no real OS sheet ever
// opens — and assert:
//   1. the exact payload transmitted (title / location / absolute-UTC-instant
//      start+end in ms / pinned Europe/Kyiv timeZone),
//   2. the `false`-return failure path shows the localised SnackBar,
//   3. the throwing failure path shows the localised SnackBar and NO exception
//      escapes,
//   4. STRUCTURED DESCRIPTION (change #3) — `buildCalendarDescription` builds a
//      `desc` block of STRUCTURED FACTS ONLY (service / provider / date-time /
//      address / price / status), one labelled line per supplied fact, and the
//      helper forwards it to the Event `desc` on the wire, AND
//   5. SECURITY REGRESSION GUARD — the builder has NO free-text-note parameter
//      by construction, so no booking note / client PII can ride into a
//      calendar entry even when a full structured description is populated.
//
// Copy is asserted through l10n keys, never a raw Cyrillic literal (CI
// no-raw-string gate). No fixed `pump(Duration)` waits — the SnackBar
// assertions use the bounded [PumpUntil.pumpUntilFound] helper.

import 'dart:convert';

import 'package:add_2_calendar/add_2_calendar.dart' show Add2Calendar;
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/calendar/add_to_calendar.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

// The plugin's channel + method names (add_2_calendar 3.1.1) — the exact
// boundary we intercept.
const MethodChannel _kChannel = MethodChannel('add_2_calendar');
const String _kMethod = 'add2Cal';

// A fixed, timezone-independent instant so the ms-since-epoch assertions read
// the SAME absolute value on any CI runner's local zone (the whole point of the
// helper pinning Europe/Kyiv on the RENDER side, not the wire side).
final DateTime _kStart = DateTime.utc(2026, 7, 20, 12, 0);
final DateTime _kEnd = DateTime.utc(2026, 7, 20, 13, 30);

void main() {
  // Captures every MethodCall the helper makes on the plugin channel, plus the
  // responder used for the pending call (return a bool, or throw).
  late List<MethodCall> calls;
  late Future<Object?> Function(MethodCall) responder;

  setUp(() {
    calls = <MethodCall>[];
    responder = (_) async => true; // default: calendar app opened
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_kChannel, (MethodCall call) async {
          calls.add(call);
          return responder(call);
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_kChannel, null);
  });

  // Pumps a minimal l10n-configured MaterialApp + Scaffold and returns the
  // Scaffold-body context (has both AppLocalizations and a ScaffoldMessenger
  // ancestor, so the helper can resolve copy AND show a SnackBar).
  Future<BuildContext> pumpHost(WidgetTester tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
        home: Scaffold(
          body: Builder(
            builder: (BuildContext c) {
              ctx = c;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    return ctx;
  }

  MethodCall onlyCall() {
    expect(calls, hasLength(1), reason: 'exactly one platform call expected');
    return calls.single;
  }

  Map<Object?, Object?> onlyArgs() =>
      onlyCall().arguments as Map<Object?, Object?>;

  group('addBookingToCalendar — payload', () {
    testWidgets(
      'invokes add2Cal with title, location, absolute-UTC ms and Europe/Kyiv '
      'timeZone',
      (tester) async {
        final BuildContext ctx = await pumpHost(tester);
        final AppLocalizations l10n = AppLocalizations.of(ctx);
        final String title = l10n.bookingCalendarEventTitle(
          'Манікюр з покриттям',
          'Салон Люкс',
        );

        await addBookingToCalendar(
          context: ctx,
          title: title,
          location: 'вул. Городоцька 12, Львів',
          start: _kStart,
          end: _kEnd,
        );
        await tester.pump();

        expect(onlyCall().method, _kMethod);
        expect(onlyArgs()['title'], title);
        expect(onlyArgs()['location'], 'вул. Городоцька 12, Львів');
        // Absolute instant on the wire — the OS renders it in `timeZone`.
        expect(onlyArgs()['startDate'], _kStart.millisecondsSinceEpoch);
        expect(onlyArgs()['endDate'], _kEnd.millisecondsSinceEpoch);
        expect(onlyArgs()['timeZone'], kBeauticaTimeZoneName);
        expect(kBeauticaTimeZoneName, 'Europe/Kyiv');

        // Success: the OS sheet is "open" — no error SnackBar.
        expect(find.text(l10n.bookingAddToCalendarError), findsNothing);
      },
    );

    testWidgets('passes a null location straight through when none is given', (
      tester,
    ) async {
      final BuildContext ctx = await pumpHost(tester);

      await addBookingToCalendar(
        context: ctx,
        title: 'Подія',
        start: _kStart,
        end: _kEnd,
      );
      await tester.pump();

      expect(onlyArgs()['location'], isNull);
    });

    testWidgets(
      'forwards a non-null structured description to the Event `desc` on the '
      'wire (change #3)',
      (tester) async {
        // The helper is the transport: a caller that hands it a pre-built
        // structured-facts block must see it land in `desc`. (The builder is
        // exercised separately below; this pins the pass-through.)
        final BuildContext ctx = await pumpHost(tester);
        final AppLocalizations l10n = AppLocalizations.of(ctx);
        final String description = buildCalendarDescription(
          l10n: l10n,
          service: 'Манікюр',
          provider: 'Салон Люкс',
          providerRole: CalendarProviderRole.salon,
          dateTime: '20 липня 2026, 12:00 – 13:30',
          address: 'вул. Городоцька 12, Львів',
          price: '650 ₴',
          status: 'Підтверджено',
        )!;

        await addBookingToCalendar(
          context: ctx,
          title: 'Подія',
          location: 'вул. Городоцька 12, Львів',
          start: _kStart,
          end: _kEnd,
          description: description,
        );
        await tester.pump();

        expect(onlyArgs()['desc'], description);
      },
    );
  });

  group('addBookingToCalendar — failure feedback', () {
    testWidgets('shows the localised SnackBar when the plugin returns false', (
      tester,
    ) async {
      responder = (_) async => false; // no calendar app available
      final BuildContext ctx = await pumpHost(tester);
      final AppLocalizations l10n = AppLocalizations.of(ctx);

      await addBookingToCalendar(
        context: ctx,
        title: 'Подія',
        location: 'вул. Городоцька 12, Львів',
        start: _kStart,
        end: _kEnd,
      );
      await tester.pumpUntilFound(find.text(l10n.bookingAddToCalendarError));

      expect(find.text(l10n.bookingAddToCalendarError), findsOneWidget);
    });

    testWidgets(
      'shows the localised SnackBar when the plugin throws a PlatformException '
      'and no exception escapes',
      (tester) async {
        responder = (_) async => throw PlatformException(code: 'no_activity');
        final BuildContext ctx = await pumpHost(tester);
        final AppLocalizations l10n = AppLocalizations.of(ctx);

        // Must not rethrow — the helper swallows native failures.
        await addBookingToCalendar(
          context: ctx,
          title: 'Подія',
          location: 'вул. Городоцька 12, Львів',
          start: _kStart,
          end: _kEnd,
        );
        await tester.pumpUntilFound(find.text(l10n.bookingAddToCalendarError));

        expect(find.text(l10n.bookingAddToCalendarError), findsOneWidget);
      },
    );

    testWidgets(
      'shows the localised SnackBar when no calendar app is registered '
      '(MissingPluginException)',
      (tester) async {
        // A device with no calendar-app implementation surfaces this on the
        // channel; the helper must treat it exactly like any other failure.
        responder = (_) async =>
            throw MissingPluginException('No implementation for add2Cal');
        final BuildContext ctx = await pumpHost(tester);
        final AppLocalizations l10n = AppLocalizations.of(ctx);

        await addBookingToCalendar(
          context: ctx,
          title: 'Подія',
          start: _kStart,
          end: _kEnd,
        );
        await tester.pumpUntilFound(find.text(l10n.bookingAddToCalendarError));

        expect(find.text(l10n.bookingAddToCalendarError), findsOneWidget);
      },
    );
  });

  group('buildCalendarDescription — structured facts (change #3)', () {
    testWidgets(
      'builds one labelled line per supplied fact, joined by newlines, in '
      'service → provider → date-time → address → price → status order',
      (tester) async {
        final BuildContext ctx = await pumpHost(tester);
        final AppLocalizations l10n = AppLocalizations.of(ctx);

        final String? desc = buildCalendarDescription(
          l10n: l10n,
          service: 'Манікюр з покриттям',
          provider: 'Марія Іванюк',
          providerRole: CalendarProviderRole.master,
          dateTime: '20 липня 2026, 15:00 – 16:30',
          address: 'вул. Городоцька 12, Львів',
          price: '650 ₴',
          status: 'Підтверджено',
        );

        expect(desc, isNotNull);
        final List<String> lines = desc!.split('\n');
        // Six facts → six labelled lines, each `<l10n label> <value>`.
        expect(lines, hasLength(6));
        expect(
          lines[0],
          '${l10n.bookingCalendarNoteService} Манікюр з покриттям',
        );
        expect(lines[1], '${l10n.bookingCalendarNoteMaster} Марія Іванюк');
        expect(
          lines[2],
          '${l10n.bookingCalendarNoteDateTime} 20 липня 2026, 15:00 – 16:30',
        );
        expect(
          lines[3],
          '${l10n.bookingCalendarNoteAddress} вул. Городоцька 12, Львів',
        );
        expect(lines[4], '${l10n.bookingCalendarNotePrice} 650 ₴');
        expect(lines[5], '${l10n.bookingCalendarNoteStatus} Підтверджено');
      },
    );

    testWidgets('a salon role picks the «Салон:» provider label', (
      tester,
    ) async {
      final BuildContext ctx = await pumpHost(tester);
      final AppLocalizations l10n = AppLocalizations.of(ctx);

      final String? desc = buildCalendarDescription(
        l10n: l10n,
        service: 'Манікюр',
        provider: 'Салон Люкс',
        providerRole: CalendarProviderRole.salon,
      );

      expect(desc, contains('${l10n.bookingCalendarNoteSalon} Салон Люкс'));
      expect(desc, isNot(contains(l10n.bookingCalendarNoteMaster)));
    });

    testWidgets('null / blank facts are skipped — no dangling labels', (
      tester,
    ) async {
      final BuildContext ctx = await pumpHost(tester);
      final AppLocalizations l10n = AppLocalizations.of(ctx);

      // Only service + status supplied; the rest null/blank.
      final String? desc = buildCalendarDescription(
        l10n: l10n,
        service: 'Манікюр',
        provider: '   ', // blank → skipped, no provider label
        dateTime: null,
        address: '',
        price: null,
        status: 'Підтверджено',
      );

      final List<String> lines = desc!.split('\n');
      expect(lines, hasLength(2));
      expect(desc, isNot(contains(l10n.bookingCalendarNoteProvider)));
      expect(desc, isNot(contains(l10n.bookingCalendarNoteDateTime)));
      expect(desc, isNot(contains(l10n.bookingCalendarNoteAddress)));
      expect(desc, isNot(contains(l10n.bookingCalendarNotePrice)));
    });

    testWidgets(
      'returns null when nothing was supplied (caller leaves desc unset)',
      (tester) async {
        final BuildContext ctx = await pumpHost(tester);
        final AppLocalizations l10n = AppLocalizations.of(ctx);

        expect(buildCalendarDescription(l10n: l10n), isNull);
      },
    );
  });

  group('addBookingToCalendar — no note / PII leak (security guard)', () {
    testWidgets(
      'a structured-facts Event carries the venue + facts but NO free-text note '
      'or client PII — the builder has no parameter that can carry one',
      (tester) async {
        final BuildContext ctx = await pumpHost(tester);
        final AppLocalizations l10n = AppLocalizations.of(ctx);
        // Sentinels that a regression MIGHT wrongly splice into the event.
        const String secretNote = 'СЕКРЕТНА КЛІЄНТСЬКА НОТАТКА';
        const String clientPhone = '+380 97 123 45 67';

        // A realistic call: a fully-populated structured description (the shape
        // the detail + success screens now build) plus title + location.
        final String description = buildCalendarDescription(
          l10n: l10n,
          service: 'Манікюр',
          provider: 'Салон Люкс',
          providerRole: CalendarProviderRole.salon,
          dateTime: '20 липня 2026, 15:00 – 16:30',
          address: 'вул. Городоцька 12, Львів',
          price: '650 ₴',
          status: 'Підтверджено',
        )!;

        await addBookingToCalendar(
          context: ctx,
          title: l10n.bookingCalendarEventTitle('Манікюр', 'Салон Люкс'),
          location: 'вул. Городоцька 12, Львів',
          start: _kStart,
          end: _kEnd,
          description: description,
        );
        await tester.pump();

        // The structured description IS present now (change #3)…
        expect(onlyArgs()['desc'], isNotNull);
        expect(onlyArgs()['desc'], contains(l10n.bookingCalendarNoteStatus));

        // …but the FULL serialised payload must not carry any note / PII
        // sentinel. There is no builder parameter that can carry free text, so
        // neither a client note nor a phone number can reach the event.
        final String payload = jsonEncode(
          onlyArgs().map((k, v) => MapEntry(k.toString(), v)),
        );
        expect(payload.contains(secretNote), isFalse);
        expect(payload.contains(clientPhone), isFalse);
      },
    );
  });

  group('Add2Calendar sanity', () {
    test('addEvent2Cal is the method the helper delegates to', () {
      // Compile-time reference guard: if the plugin API is renamed, this file
      // (and the helper) must be updated in lockstep.
      expect(Add2Calendar.addEvent2Cal, isNotNull);
    });
  });
}

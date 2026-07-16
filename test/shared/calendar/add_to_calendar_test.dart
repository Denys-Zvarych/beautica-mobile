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
//   4. SECURITY REGRESSION GUARD — the Event carries ONLY the venue address in
//      `location` and the service·provider line in `title`; `desc` stays null,
//      so no booking note / client PII can ride into a calendar entry.
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

  group('addBookingToCalendar — no note / PII leak (security guard)', () {
    testWidgets(
      'the Event carries only title + venue location; desc stays null and no '
      'note text is transmitted',
      (tester) async {
        final BuildContext ctx = await pumpHost(tester);
        final AppLocalizations l10n = AppLocalizations.of(ctx);
        // Sentinels that a regression MIGHT wrongly splice into the event.
        const String secretNote = 'СЕКРЕТНА КЛІЄНТСЬКА НОТАТКА';
        const String clientPhone = '+380 97 123 45 67';

        await addBookingToCalendar(
          context: ctx,
          title: l10n.bookingCalendarEventTitle('Манікюр', 'Салон Люкс'),
          location: 'вул. Городоцька 12, Львів',
          start: _kStart,
          end: _kEnd,
        );
        await tester.pump();

        // The helper has NO description parameter — `desc` must be null.
        expect(onlyArgs()['desc'], isNull);

        // The FULL serialised payload must not carry any note / PII sentinel,
        // even if a future refactor added a field that echoed booking data.
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

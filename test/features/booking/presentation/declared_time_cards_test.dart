// Phase 244 follow-up — [DeclaredTimeCards] / [_mergeDeclaredAndBookings]
// (declared_time_cards.dart), the master «Мої записи» EXPLICIT_TIMES day
// body.
//
// `_mergeDeclaredAndBookings` is private — its whole correctness contract
// (see that file's header, "THE ENTRY LIST IS A UNION, NEVER A FILTER") is
// pinned here ONLY through the public widget's rendered output (M2 — `Key`s,
// never localised text as the primary finder), never by reaching into the
// private helper.
//
// THE ONE CASE THAT MATTERS MOST: a booking whose start matches no declared
// time must still render as its own card. `bookings_discovery_view.dart`
// hands `DeclaredTimeCards` `state.items` UNFILTERED specifically so this
// case can never regress into a silent drop — see the "anti-data-loss"
// group below, mutation-verified.

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/declared_time_cards.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/timeline_hour_ruler.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../helpers/booking_fixture_dates.dart';
import '../../../helpers/pump_app.dart';

/// The KYIV calendar day every fixture below is anchored to — mirrors
/// `bookings_timeline_grid_test.dart`'s identically-named constant.
final DateTime _day = dateOnly(toBeauticaTime(futureBookingStart()));

/// The UTC instant for `hour:minute` KYIV wall-clock on [_day] — built
/// through [tz.TZDateTime] so the fixture is correct regardless of which DST
/// half of the year the suite runs in, and regardless of the HOST device's
/// own timezone (mirrors `bookings_timeline_grid_test.dart`'s `_kyivAtUtc`).
DateTime _kyivAtUtc(int hour, [int minute = 0]) => tz.TZDateTime(
  beauticaZone,
  _day.year,
  _day.month,
  _day.day,
  hour,
  minute,
).toUtc();

Booking _booking({
  required String id,
  required DateTime startAtUtc,
  int durationMinutes = 30,
  String? clientFirstName = 'Марія',
  String? clientLastName = 'Іванюк',
  String serviceName = 'Манікюр',
}) => Booking(
  id: id,
  masterId: 'master-1',
  masterFirstName: 'Оля',
  masterLastName: 'Коваль',
  masterType: 'INDEPENDENT_MASTER',
  clientId: 'client-1',
  clientFirstName: clientFirstName,
  clientLastName: clientLastName,
  serviceId: 'service-1',
  serviceName: serviceName,
  durationMinutes: durationMinutes,
  price: 500,
  startAt: startAtUtc,
  endAt: startAtUtc.add(Duration(minutes: durationMinutes)),
  status: BookingStatus.confirmed,
  canReview: false,
);

Key _freeKey(int hour, int minute) => Key(
  'declared-time-card-free-'
  '${hour.toString().padLeft(2, '0')}${minute.toString().padLeft(2, '0')}',
);

Key _bookedKey(String id) => Key('declared-time-card-$id');

Future<void> _pumpCards(
  WidgetTester tester, {
  required List<TimeOfDay> declaredTimes,
  required List<Booking> bookings,
  ValueChanged<Booking>? onTapBooking,
}) async {
  await tester.pumpApp(
    DeclaredTimeCards(
      declaredTimes: declaredTimes,
      bookings: bookings,
      day: _day,
      onTapBooking: onTapBooking ?? (Booking _) {},
    ),
  );
  await tester.pumpAndSettle();
}

/// Every ruler/gridline element `BookingsTimelineGrid` would paint — asserted
/// ABSENT throughout this file (`DeclaredTimeCards` renders no ruler, no
/// gridlines: duration is text, never geometry — see the file header).
bool _anyGridlinePainted(WidgetTester tester) {
  final Color halfHour = BrandColors.faint.withValues(alpha: 0.4);
  return find
      .byWidgetPredicate(
        (Widget w) =>
            w is ColoredBox &&
            (w.color == BrandColors.faint || w.color == halfHour),
      )
      .evaluate()
      .isNotEmpty;
}

void main() {
  group('free card — one declared time, zero bookings', () {
    testWidgets('renders exactly one free card reading «Вільно», no ruler, no '
        'gridlines', (tester) async {
      await _pumpCards(
        tester,
        declaredTimes: const <TimeOfDay>[TimeOfDay(hour: 11, minute: 0)],
        bookings: const <Booking>[],
      );

      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(DeclaredTimeCards)),
      );

      expect(find.byKey(const Key('declared-time-cards')), findsOneWidget);
      expect(find.byKey(_freeKey(11, 0)), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(_freeKey(11, 0)),
          matching: find.text(l10n.masterBookingsDeclaredTimeFree),
        ),
        findsOneWidget,
      );
      expect(
        find.byType(TimelineHourRuler),
        findsNothing,
        reason: 'no hour ruler on an EXPLICIT_TIMES day — cards only',
      );
      expect(
        _anyGridlinePainted(tester),
        isFalse,
        reason: 'no gridlines either — duration is text, never geometry',
      );
      // Not a tappable button — no GestureDetector under the free card.
      expect(
        find.descendant(
          of: find.byKey(_freeKey(11, 0)),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
        reason:
            'a free declared time is informational only, never a '
            'button',
      );
    });
  });

  group('booked card — one declared time with a booking on it', () {
    testWidgets('renders time, client name, and «service · duration»', (
      tester,
    ) async {
      final Booking booking = _booking(
        id: 'b-11',
        startAtUtc: _kyivAtUtc(11, 0),
        durationMinutes: 45,
        serviceName: 'Манікюр з покриттям',
      );

      await _pumpCards(
        tester,
        declaredTimes: const <TimeOfDay>[TimeOfDay(hour: 11, minute: 0)],
        bookings: <Booking>[booking],
      );

      final Finder card = find.byKey(_bookedKey('b-11'));
      expect(card, findsOneWidget);
      expect(find.byKey(_freeKey(11, 0)), findsNothing);
      expect(
        find.descendant(of: card, matching: find.text('11:00')),
        findsOneWidget,
      );
      expect(
        // i18n-finder-ok: 'Марія Іванюк' is the fixture's clientName data.
        find.descendant(of: card, matching: find.text('Марія Іванюк')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.textContaining('Манікюр з покриттям'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.textContaining('45 хв')),
        findsOneWidget,
        reason: 'line 3 shows the DURATION, not a start–end range',
      );
    });

    testWidgets('tapping the booked card fires onTapBooking with THIS '
        'booking', (tester) async {
      final Booking booking = _booking(id: 'b-tap', startAtUtc: _kyivAtUtc(9));
      Booking? tapped;

      await _pumpCards(
        tester,
        declaredTimes: const <TimeOfDay>[TimeOfDay(hour: 9, minute: 0)],
        bookings: <Booking>[booking],
        onTapBooking: (Booking b) => tapped = b,
      );

      await tester.tap(find.byKey(_bookedKey('b-tap')));
      await tester.pump();

      expect(tapped?.id, 'b-tap');
    });

    testWidgets(
      'guest booking (null clientName) falls back to bookingDetailGuestClient',
      (tester) async {
        final Booking guest = _booking(
          id: 'guest-1',
          startAtUtc: _kyivAtUtc(14),
          clientFirstName: null,
          clientLastName: null,
        );

        await _pumpCards(
          tester,
          declaredTimes: const <TimeOfDay>[TimeOfDay(hour: 14, minute: 0)],
          bookings: <Booking>[guest],
        );

        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byType(DeclaredTimeCards)),
        );
        expect(
          find.descendant(
            of: find.byKey(_bookedKey('guest-1')),
            matching: find.text(l10n.bookingDetailGuestClient),
          ),
          findsOneWidget,
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════
  // ANTI-DATA-LOSS — a booking whose start matches NO declared time must
  // still render. This is the whole correctness contract of
  // `_mergeDeclaredAndBookings`'s "pass 2" — mutation-verified below.
  // ═══════════════════════════════════════════════════════════════════════
  group('a booking with no matching declared time (the union, never a '
      'filter)', () {
    testWidgets(
      'still renders — as its own entry, sorted by minute alongside the '
      'declared-time cards',
      (tester) async {
        final Booking stray = _booking(
          id: 'stray',
          startAtUtc: _kyivAtUtc(13, 30), // matches NO declared time below
        );

        await _pumpCards(
          tester,
          declaredTimes: const <TimeOfDay>[
            TimeOfDay(hour: 11, minute: 0),
            TimeOfDay(hour: 16, minute: 0),
          ],
          bookings: <Booking>[stray],
        );

        expect(
          find.byKey(_bookedKey('stray')),
          findsOneWidget,
          reason:
              'a booking whose start matches no declared time is NOT a '
              'filter miss — it must still render as its own card '
              '(MUTATION-VERIFIED: see the QA report)',
        );
        // Both surrounding declared times still render as free — the stray
        // booking must not consume either of them.
        expect(find.byKey(_freeKey(11, 0)), findsOneWidget);
        expect(find.byKey(_freeKey(16, 0)), findsOneWidget);

        // Sort order: 11:00 (free), 13:30 (stray), 16:00 (free) — top to
        // bottom in the list.
        final double y11 = tester.getTopLeft(find.byKey(_freeKey(11, 0))).dy;
        final double yStray = tester
            .getTopLeft(find.byKey(_bookedKey('stray')))
            .dy;
        final double y16 = tester.getTopLeft(find.byKey(_freeKey(16, 0))).dy;
        expect(y11, lessThan(yStray));
        expect(yStray, lessThan(y16));
      },
    );
  });

  group('two bookings at the SAME declared minute', () {
    testWidgets(
      'pass 1 consumes one; pass 2 emits the other — neither vanishes',
      (tester) async {
        final Booking first = _booking(
          id: 'dup-a',
          startAtUtc: _kyivAtUtc(10, 0),
          clientFirstName: 'Ольга',
          clientLastName: 'Бондар',
        );
        final Booking second = _booking(
          id: 'dup-b',
          startAtUtc: _kyivAtUtc(10, 0),
          clientFirstName: 'Ірина',
          clientLastName: 'Петренко',
        );

        await _pumpCards(
          tester,
          declaredTimes: const <TimeOfDay>[TimeOfDay(hour: 10, minute: 0)],
          bookings: <Booking>[first, second],
        );

        expect(
          find.byKey(_bookedKey('dup-a')),
          findsOneWidget,
          reason: 'pass 1 matches the first unconsumed booking at 10:00',
        );
        expect(
          find.byKey(_bookedKey('dup-b')),
          findsOneWidget,
          reason:
              'pass 2 must still emit the SECOND booking at the same '
              'minute — it must not be silently dropped',
        );
        expect(find.byKey(_freeKey(10, 0)), findsNothing);
      },
    );

    testWidgets(
      'the id tie-break — not input order — decides which booking becomes '
      'the declared card; the other renders below it as the stray entry',
      (tester) async {
        final Booking first = _booking(
          id: 'dup-a',
          startAtUtc: _kyivAtUtc(10, 0),
        );
        final Booking second = _booking(
          id: 'dup-b',
          startAtUtc: _kyivAtUtc(10, 0),
        );

        // Fed in the OPPOSITE of id order — the merge's determinism must
        // come from `Booking.id` (the documented secondary sort key,
        // `_mergeDeclaredAndBookings`'s doc), not from whichever order the
        // bookings happen to arrive in.
        await _pumpCards(
          tester,
          declaredTimes: const <TimeOfDay>[TimeOfDay(hour: 10, minute: 0)],
          bookings: <Booking>[second, first],
        );

        final double yA = tester.getTopLeft(find.byKey(_bookedKey('dup-a'))).dy;
        final double yB = tester.getTopLeft(find.byKey(_bookedKey('dup-b'))).dy;
        expect(
          yA,
          lessThan(yB),
          reason:
              "'dup-a' sorts before 'dup-b' by id, so it must win the "
              'declared-time match and render FIRST regardless of the '
              'order the bookings were passed in '
              '(MUTATION-VERIFIED: see the QA report)',
        );
      },
    );
  });

  group('uniform card heights — duration is text, never geometry', () {
    testWidgets('30/60/90-minute bookings render identically-sized cards', (
      tester,
    ) async {
      final Booking b30 = _booking(
        id: 'd30',
        startAtUtc: _kyivAtUtc(9),
        durationMinutes: 30,
      );
      final Booking b60 = _booking(
        id: 'd60',
        startAtUtc: _kyivAtUtc(11),
        durationMinutes: 60,
      );
      final Booking b90 = _booking(
        id: 'd90',
        startAtUtc: _kyivAtUtc(13),
        durationMinutes: 90,
      );

      await _pumpCards(
        tester,
        declaredTimes: const <TimeOfDay>[
          TimeOfDay(hour: 9, minute: 0),
          TimeOfDay(hour: 11, minute: 0),
          TimeOfDay(hour: 13, minute: 0),
        ],
        bookings: <Booking>[b30, b60, b90],
      );

      final double h30 = tester.getSize(find.byKey(_bookedKey('d30'))).height;
      final double h60 = tester.getSize(find.byKey(_bookedKey('d60'))).height;
      final double h90 = tester.getSize(find.byKey(_bookedKey('d90'))).height;

      expect(
        h30,
        h60,
        reason:
            'a 30-minute and a 60-minute booking must render the same '
            'card height (MUTATION-VERIFIED: see the QA report)',
      );
      expect(h60, h90);
    });
  });
}

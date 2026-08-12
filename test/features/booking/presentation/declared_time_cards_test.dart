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
//
// ## THE SWAP (2026-08) — booked entries now render the SHIPPED
// `MasterBookingCard`
//
// A booked entry's `Key` moved from `declared-time-card-<id>` (the retired
// bespoke card) to `master-booking-card-<id>` — [MasterBookingCard]'s OWN
// key, the same one every other suite that pumps that card finds it by (see
// `master_bookings_screen_test.dart`). This file no longer asserts a
// duration string («45 хв») — the shipped card prints a time RANGE instead —
// but every other pin below (content renders, taps through, guest fallback,
// the union/anti-data-loss contract, the id tie-break, uniform heights)
// carries over unchanged in spirit, re-pointed at the new key and the new
// card's real text.

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

/// [MasterBookingCard]'s OWN key — see this file's header "THE SWAP" note.
/// Found the same way every other suite that pumps that card finds it (e.g.
/// `master_bookings_screen_test.dart`), rather than a key this file mints
/// itself.
Key _bookedKey(String id) => Key('master-booking-card-$id');

Future<void> _pumpCards(
  WidgetTester tester, {
  required List<TimeOfDay> declaredTimes,
  required List<Booking> bookings,
  ValueChanged<Booking>? onTapBooking,
  double? textScaleFactor,
}) async {
  await tester.pumpApp(
    DeclaredTimeCards(
      declaredTimes: declaredTimes,
      bookings: bookings,
      day: _day,
      onTapBooking: onTapBooking ?? (Booking _) {},
    ),
    textScaleFactor: textScaleFactor,
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
    testWidgets(
      'renders the shipped MasterBookingCard with THIS booking\'s content — '
      'client name, service, and a start–end time range (not the retired '
      'duration line)',
      (tester) async {
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
          // `MasterBookingCard`'s own `formatSlotTimeRange` — start (11:00)
          // en-dash end (11:00 + 45 min = 11:45). NOT the retired bespoke
          // card's leading time line, and NOT a duration string — the swap's
          // whole point (see this file's header).
          // i18n-finder-ok: digits + en-dash, locale-invariant time range.
          find.descendant(of: card, matching: find.text('11:00–11:45')),
          findsOneWidget,
        );
      },
    );

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
      'guest booking (null clientName, null clientAvatarUrl) falls back to '
      'bookingDetailGuestClient AND the local glyph — no remote fetch '
      'attempted',
      (tester) async {
        final Booking guest = _booking(
          id: 'guest-1',
          startAtUtc: _kyivAtUtc(14),
          clientFirstName: null,
          clientLastName: null,
        );
        // clientAvatarUrl is null by construction — `_booking` never sets it.
        expect(guest.clientAvatarUrl, isNull);

        await _pumpCards(
          tester,
          declaredTimes: const <TimeOfDay>[TimeOfDay(hour: 14, minute: 0)],
          bookings: <Booking>[guest],
        );

        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byType(DeclaredTimeCards)),
        );
        final Finder card = find.byKey(_bookedKey('guest-1'));
        expect(
          find.descendant(
            of: card,
            matching: find.text(l10n.bookingDetailGuestClient),
          ),
          findsOneWidget,
        );
        // `_ClientAvatarMark` — a null/disallowed url returns the local
        // `person_outlined` glyph immediately, before ever constructing an
        // `Image`/`ResizeImage`/`beauticaMediaProvider` — see that widget's
        // doc. Asserting BOTH the glyph's presence and Image's absence pins
        // that no-network-attempt contract, not merely "something rendered".
        expect(
          find.descendant(
            of: card,
            matching: find.byIcon(Icons.person_outlined),
          ),
          findsOneWidget,
          reason: 'no avatar url — falls back to the local glyph',
        );
        expect(
          find.descendant(of: card, matching: find.byType(Image)),
          findsNothing,
          reason:
              'a null clientAvatarUrl must never attempt a remote image '
              'fetch',
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════
  // STATUS RENDERS AND DIFFERENTIATES — the regression this swap exists to
  // fix. The retired bespoke card never read `Booking.status`, so a
  // CANCELLED booking rendered identically to a CONFIRMED one here. The
  // shipped `MasterBookingCard` restores the status badge AND gates the
  // price pill on `BookingDisplayX.showsPrice` — both asserted below as two
  // INDEPENDENT differentiators, since either one alone regressing would
  // silently reopen part of the gap.
  //
  // MUTATION-VERIFIED (see the QA report): forcing `declared_time_cards
  // .dart`'s itemBuilder to pass `entry.booking!.copyWith(status:
  // BookingStatus.confirmed)` into `MasterBookingCard` — i.e. reintroducing
  // "the card never reads the booking's real status" — turns this test RED.
  // ═══════════════════════════════════════════════════════════════════════
  group('status renders and differentiates', () {
    testWidgets(
      'a CONFIRMED and a CANCELLED booking on the same declared-times day '
      'render visibly different cards — status label AND price presence '
      'both differ',
      (tester) async {
        final Booking confirmed = _booking(
          id: 'status-confirmed',
          startAtUtc: _kyivAtUtc(9),
        );
        final Booking cancelled = _booking(
          id: 'status-cancelled',
          startAtUtc: _kyivAtUtc(11),
        ).copyWith(status: BookingStatus.cancelled);

        await _pumpCards(
          tester,
          declaredTimes: const <TimeOfDay>[
            TimeOfDay(hour: 9, minute: 0),
            TimeOfDay(hour: 11, minute: 0),
          ],
          bookings: <Booking>[confirmed, cancelled],
        );

        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byType(DeclaredTimeCards)),
        );
        final Finder confirmedCard = find.byKey(_bookedKey('status-confirmed'));
        final Finder cancelledCard = find.byKey(_bookedKey('status-cancelled'));

        // Differentiator 1 — the status badge's label text.
        expect(
          find.descendant(
            of: confirmedCard,
            matching: find.text(l10n.bookingStatusConfirmed),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: cancelledCard,
            matching: find.text(l10n.bookingStatusCancelled),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: cancelledCard,
            matching: find.text(l10n.bookingStatusConfirmed),
          ),
          findsNothing,
          reason: 'the two cards must never share a status label',
        );

        // Differentiator 2 — `BookingDisplayX.showsPrice`: CONFIRMED owes
        // money, CANCELLED owes nothing.
        expect(
          find.descendant(
            of: confirmedCard,
            matching: find.textContaining('₴'),
          ),
          findsOneWidget,
          reason: 'a CONFIRMED booking must show its price',
        );
        expect(
          find.descendant(
            of: cancelledCard,
            matching: find.textContaining('₴'),
          ),
          findsNothing,
          reason: 'a CANCELLED booking owes nothing — no price pill',
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════
  // PRICE RENDERS on a declared-times booked card — both the single-price
  // and the frozen min–max BAND cases (`Booking.priceMax` non-null is a
  // real, server-frozen snapshot — see `booking.dart`'s "PRICE MAY BE A
  // FROZEN BAND" section — never re-derived here).
  // ═══════════════════════════════════════════════════════════════════════
  group('price renders on a declared-times booked card', () {
    testWidgets('a single price renders as "500 ₴"', (tester) async {
      final Booking booking = _booking(
        id: 'price-single',
        startAtUtc: _kyivAtUtc(9),
      );

      await _pumpCards(
        tester,
        declaredTimes: const <TimeOfDay>[TimeOfDay(hour: 9, minute: 0)],
        bookings: <Booking>[booking],
      );

      expect(
        find.descendant(
          of: find.byKey(_bookedKey('price-single')),
          // i18n-finder-ok: digits + ₴, locale-invariant price formatting.
          matching: find.text('500 ₴'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a frozen min–max band (priceMaxAtBooking non-null) renders as '
        '"300–500 ₴"', (tester) async {
      final Booking booking = _booking(
        id: 'price-band',
        startAtUtc: _kyivAtUtc(9),
      ).copyWith(price: 300, priceMax: 500);

      await _pumpCards(
        tester,
        declaredTimes: const <TimeOfDay>[TimeOfDay(hour: 9, minute: 0)],
        bookings: <Booking>[booking],
      );

      expect(
        find.descendant(
          of: find.byKey(_bookedKey('price-band')),
          // i18n-finder-ok: digits + en-dash + ₴, locale-invariant price band.
          matching: find.text('300–500 ₴'),
        ),
        findsOneWidget,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // THE FULL LAYOUT IS ALWAYS SELECTED — `minHeight: 120` must never fall
  // back to `MasterBookingCard`'s compact/micro variant, for ANY duration.
  // This is what actually guarantees status/price/avatar are present at
  // all: `_kEntryMinHeight` alone forcing a tall BOX (proven by the
  // "uniform card heights" group above) does not by itself prove the FULL
  // body was selected inside it — see `master_booking_card.dart`'s `build`,
  // where `minHeight` is a floor, never a ceiling, so a mis-selected
  // compact/micro body would still stretch to fill 120dp of blank space
  // and every height-only assertion in this file would stay green.
  //
  // MUTATION-VERIFIED (see the QA report): dropping
  // `declared_time_cards.dart`'s `_kEntryMinHeight` from 120 to 100 (still
  // inside `[microLayoutMaxHeight, fullLayoutMinHeight)` = compact) turns
  // this test RED.
  // ═══════════════════════════════════════════════════════════════════════
  group('the full layout is always selected, regardless of duration', () {
    testWidgets(
      '30/60/90-minute bookings all render the FULL body\'s own divider '
      'key, never the compact or micro shape',
      (tester) async {
        final Booking b30 = _booking(
          id: 'full30',
          startAtUtc: _kyivAtUtc(9),
          durationMinutes: 30,
        );
        final Booking b60 = _booking(
          id: 'full60',
          startAtUtc: _kyivAtUtc(11),
          durationMinutes: 60,
        );
        final Booking b90 = _booking(
          id: 'full90',
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

        for (final String id in <String>['full30', 'full60', 'full90']) {
          expect(
            find.byKey(Key('master-booking-card-divider-$id')),
            findsOneWidget,
            reason: '$id must render the FULL body, not compact or micro',
          );
          expect(
            find.byKey(Key('master-booking-card-compact-divider-$id')),
            findsNothing,
          );
        }
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

    testWidgets(
      'a FREE card and a BOOKED card in the SAME list occupy the SAME box '
      '(height AND width) — a hard product requirement: "need to keep box '
      'sizes same for empty slot and for booked slot"',
      (tester) async {
        final Booking b30 = _booking(
          id: 'mix30',
          startAtUtc: _kyivAtUtc(9),
          durationMinutes: 30,
        );
        final Booking b60 = _booking(
          id: 'mix60',
          startAtUtc: _kyivAtUtc(13),
          durationMinutes: 60,
        );

        await _pumpCards(
          tester,
          declaredTimes: const <TimeOfDay>[
            TimeOfDay(hour: 9, minute: 0),
            TimeOfDay(hour: 11, minute: 0), // stays free — no booking here
            TimeOfDay(hour: 13, minute: 0),
          ],
          bookings: <Booking>[b30, b60],
        );

        final Size sizeFree = tester.getSize(find.byKey(_freeKey(11, 0)));
        final Size sizeBooked30 = tester.getSize(
          find.byKey(_bookedKey('mix30')),
        );
        final Size sizeBooked60 = tester.getSize(
          find.byKey(_bookedKey('mix60')),
        );

        expect(
          sizeFree.height,
          sizeBooked30.height,
          reason:
              'the free card and a booked (30-minute, full-body) card must '
              'render the exact same box height — see declared_time_cards'
              '.dart\'s `_kEntryMinHeight` doc',
        );
        expect(sizeFree.height, sizeBooked60.height);
        expect(
          sizeFree.width,
          sizeBooked30.width,
          reason:
              'and the same width — both stretch to the list\'s full cross '
              'axis, so a mismatch here would mean one variant picked up an '
              'unintended width constraint',
        );
        expect(sizeFree.width, sizeBooked60.width);
      },
    );

    // ═══════════════════════════════════════════════════════════════════
    // ABOVE 1.0 TEXT SCALE — the gap `_freeCardMinHeightFor` closes. The
    // booked card's FULL body genuinely grows past `_kEntryMinHeight`
    // above scale 1.0 (real `Text` widgets, not an estimate — see
    // `MasterBookingCard.fullLayoutNaturalHeight`'s doc: "124dp @ 1.15,
    // 132dp @ 1.3 — re-measured, not assumed"); the free card's own floor
    // must track that growth instead of staying pinned at 120, or the
    // "same box" contract above holds only at the one scale most devices
    // happen to run at.
    //
    // MUTATION-VERIFIED (see this session's report): reverting
    // `_freeCardMinHeightFor` to return the bare `_kEntryMinHeight`
    // constant unconditionally turns the 1.15 and 1.3 cases in this loop
    // RED, with the booked card measurably taller than the free one
    // (124 vs 120, 132 vs 120) — the 1.0 case stays green either way,
    // which is exactly why a single-scale test cannot catch this gap.
    // ═══════════════════════════════════════════════════════════════════
    for (final (double scale, double expectedHeight)
        in const <(double, double)>[(1.0, 120), (1.15, 124), (1.3, 132)]) {
      testWidgets('a FREE card and a BOOKED card match at textScaler $scale '
          '(expected box: ${expectedHeight}dp)', (tester) async {
        final Booking booking = _booking(
          id: 'scale-${scale.toStringAsFixed(2)}',
          startAtUtc: _kyivAtUtc(9),
        );

        await _pumpCards(
          tester,
          declaredTimes: const <TimeOfDay>[
            TimeOfDay(hour: 9, minute: 0),
            TimeOfDay(hour: 11, minute: 0), // stays free — no booking here
          ],
          bookings: <Booking>[booking],
          textScaleFactor: scale,
        );

        final double heightFree = tester
            .getSize(find.byKey(_freeKey(11, 0)))
            .height;
        final double heightBooked = tester
            .getSize(
              find.byKey(_bookedKey('scale-${scale.toStringAsFixed(2)}')),
            )
            .height;

        expect(
          heightBooked,
          closeTo(expectedHeight, 0.01),
          reason:
              'fixture guard — the booked card\'s own real box at scale '
              '$scale must still measure ${expectedHeight}dp (re-measured, '
              'see MasterBookingCard.fullLayoutNaturalHeight\'s doc); if '
              'this fails, the equality assertion below is meaningless '
              'because the target itself moved.',
        );
        expect(
          heightFree,
          closeTo(heightBooked, 0.01),
          reason:
              'at textScaler $scale the free card must occupy the SAME '
              'box height as the booked card — see this file\'s '
              '`_freeCardMinHeightFor` doc',
        );
      });
    }
  });
}

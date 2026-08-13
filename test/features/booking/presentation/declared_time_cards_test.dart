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
import 'package:flutter/rendering.dart' show RenderParagraph;
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

/// The style the FRAMEWORK actually paints [textFinder] with — read off the
/// built [RenderParagraph], i.e. AFTER `Text.build`'s own
/// `DefaultTextStyle.of(context).style.merge(widget.style)` resolution.
///
/// Deliberately NOT `tester.widget<Text>(...).style`: that raw field is the
/// style the call site PASSED, not the style that renders. A regression that
/// moved the size into (or lost it from) an inherited `DefaultTextStyle` —
/// or a `Text` whose own `style` left `fontSize` null and leaned on the
/// ambient theme — would slip straight past a raw-field read while the pixels
/// changed underneath it.
TextStyle _paintedStyle(WidgetTester tester, Finder textFinder) {
  final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
    textFinder,
  );
  final TextStyle? style = paragraph.text.style;
  expect(
    style,
    isNotNull,
    reason: 'a rendered Text always resolves to a non-null painted style',
  );
  return style!;
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

  // ═══════════════════════════════════════════════════════════════════════
  // CONSUMED DECLARED TIMES ARE DROPPED — `_mergeDeclaredAndBookings`'s
  // "pass 1b", the ONLY path in that file that can ERASE a row.
  //
  // THE BUG (user-reported, 2026-08-13): pass 1 paired a declared time to a
  // booking by exact START minute and never read `endAt`, so a declared time
  // swallowed by an EARLIER booking's duration rendered as a free «Вільно»
  // card. Real shape: the master declares 11:00 and 12:00, a booking runs
  // 10:00–12:30, and 12:00 falsely offered itself as free — while the
  // backend's own `GET /slots` had already omitted it.
  //
  // LOCKED DECISION: such an entry is HIDDEN ENTIRELY — no card, no muted
  // state, no «Зайнято» label.
  //
  // WHY THIS GROUP EXISTS AS ITS OWN BLOCK: before it, the destructive
  // membership rule was 100% unpinned. Every pre-existing fixture in this
  // file either matched its booking to a declared time by exact start, or
  // put no declared time inside any booking's span — so DELETING the
  // `removeWhere` left all 21 tests green. A rule that can only ever remove
  // a row, verified by nothing, is the highest-risk shape in the file.
  //
  // MUTATION-VERIFIED (this session — every outcome quoted in the QA
  // report):
  //   * deleting `declared_time_cards.dart`'s `declaredEntries.removeWhere`
  //     turns "the reported bug" and "a consumer starting at a NON-declared
  //     minute" RED;
  //   * relaxing the predicate's strict `dm < bookingEndMinutes[j]` to `<=`
  //     turns the 60-minute (exactly-touching) case below RED;
  //   * adding `BookingStatus.cancelled` to `_consumesDeclaredTimes`'s
  //     allowlist turns this group's `cancelled` case RED.
  // ═══════════════════════════════════════════════════════════════════════
  group('a declared time CONSUMED by an earlier booking\'s duration', () {
    testWidgets(
      'THE REPORTED BUG — an 11:00 booking running 90 minutes hides the '
      '12:00 declared time entirely, while its own 11:00 card still renders '
      'exactly once',
      (tester) async {
        final Booking booking = _booking(
          id: 'consumer-90',
          startAtUtc: _kyivAtUtc(11),
          durationMinutes: 90, // 11:00 -> 12:30, swallowing 12:00
        );

        await _pumpCards(
          tester,
          declaredTimes: const <TimeOfDay>[
            TimeOfDay(hour: 11, minute: 0),
            TimeOfDay(hour: 12, minute: 0),
          ],
          bookings: <Booking>[booking],
        );

        expect(
          find.byKey(_freeKey(12, 0)),
          findsNothing,
          reason:
              '12:00 falls inside [11:00, 12:30) — it is not bookable and '
              'must not render as a free card '
              '(MUTATION-VERIFIED: deleting pass 1b\'s removeWhere turns '
              'this RED)',
        );
        expect(
          find.byKey(_bookedKey('consumer-90')),
          findsOneWidget,
          reason:
              'the consuming booking itself still renders — hiding the slot '
              'it swallowed must never hide the booking that swallowed it',
        );
        expect(
          find.byKey(_freeKey(11, 0)),
          findsNothing,
          reason: '11:00 is BOOKED, not free',
        );
      },
    );

    // ─────────────────────────────────────────────────────────────────────
    // THE HALF-OPEN BOUNDARY, both sides, one minute apart — the sharpest
    // possible pin on the predicate's strict `<`. `endAt == the declared
    // time` is NOT consumption (same "touching endpoints don't count" rule
    // as `booking_lane_layout.dart`'s `_overlaps` and the backend's own
    // strict slot test); one minute past it IS.
    // ─────────────────────────────────────────────────────────────────────
    for (final (int duration, bool stillFree) in const <(int, bool)>[
      (60, true), // 11:00 -> 12:00 exactly: touching, NOT consumption
      (61, false), // 11:00 -> 12:01: one minute past, consumed
    ]) {
      testWidgets(
        'half-open boundary — an 11:00 booking of $duration minutes leaves '
        '12:00 ${stillFree ? "PRESENT" : "ABSENT"}',
        (tester) async {
          final Booking booking = _booking(
            id: 'boundary-$duration',
            startAtUtc: _kyivAtUtc(11),
            durationMinutes: duration,
          );

          await _pumpCards(
            tester,
            declaredTimes: const <TimeOfDay>[
              TimeOfDay(hour: 11, minute: 0),
              TimeOfDay(hour: 12, minute: 0),
            ],
            bookings: <Booking>[booking],
          );

          expect(
            find.byKey(_freeKey(12, 0)),
            stillFree ? findsOneWidget : findsNothing,
            reason: stillFree
                ? 'a booking ending EXACTLY at 12:00 leaves 12:00 genuinely '
                      'free — the predicate is half-open `[start, end)`, so '
                      'touching endpoints are not consumption '
                      '(MUTATION-VERIFIED: relaxing `<` to `<=` turns this RED)'
                : 'one minute past 12:00 and the slot is genuinely occupied',
          );
          expect(find.byKey(_bookedKey('boundary-$duration')), findsOneWidget);
        },
      );
    }

    // ─────────────────────────────────────────────────────────────────────
    // THE STATUS ALLOWLIST — only `confirmed`/`completed` take the master's
    // clock. A CANCELLED, DECLINED, NOT_COMPLETED or UNKNOWN booking frees
    // it again, so a declared time behind one of those is genuinely FREE and
    // must still render. `unknown` is a DELIBERATE divergence from
    // `booking_lane_layout.dart`'s `_isActiveClass` (see
    // `_consumesDeclaredTimes`'s doc): hiding is the destructive direction,
    // and an unrecognised wire status may not earn the power to erase a
    // declared time.
    //
    // The consuming half of the allowlist is pinned by "THE REPORTED BUG"
    // (confirmed) and by the `completed` case below, so this loop is a real
    // discriminator on both sides, not a one-sided "everything is free"
    // assertion that a gutted predicate would also satisfy.
    // ─────────────────────────────────────────────────────────────────────
    for (final BookingStatus status in const <BookingStatus>[
      BookingStatus.cancelled,
      BookingStatus.declined,
      BookingStatus.notCompleted,
      BookingStatus.unknown,
    ]) {
      testWidgets(
        'status allowlist — a 90-minute ${status.name} booking does NOT '
        'consume 12:00; the free card still renders',
        (tester) async {
          final Booking booking = _booking(
            id: 'status-${status.name}',
            startAtUtc: _kyivAtUtc(11),
            durationMinutes: 90, // same 11:00 -> 12:30 span as the bug above
          ).copyWith(status: status);

          await _pumpCards(
            tester,
            declaredTimes: const <TimeOfDay>[
              TimeOfDay(hour: 11, minute: 0),
              TimeOfDay(hour: 12, minute: 0),
            ],
            bookings: <Booking>[booking],
          );

          expect(
            find.byKey(_freeKey(12, 0)),
            findsOneWidget,
            reason:
                'a ${status.name} booking releases the clock — 12:00 is '
                'genuinely bookable again and must still render '
                '(MUTATION-VERIFIED for cancelled: adding it to '
                '`_consumesDeclaredTimes`\'s allowlist turns this RED)',
          );
          expect(
            find.byKey(_bookedKey('status-${status.name}')),
            findsOneWidget,
            reason:
                'pass 1b hides SLOTS, never bookings — the terminal booking '
                'still owns its own 11:00 card',
          );
        },
      );
    }

    testWidgets(
      'status allowlist, the consuming half — a 90-minute COMPLETED booking '
      'DOES hide 12:00, so the four cases above discriminate',
      (tester) async {
        final Booking booking = _booking(
          id: 'status-completed',
          startAtUtc: _kyivAtUtc(11),
          durationMinutes: 90,
        ).copyWith(status: BookingStatus.completed);

        await _pumpCards(
          tester,
          declaredTimes: const <TimeOfDay>[
            TimeOfDay(hour: 11, minute: 0),
            TimeOfDay(hour: 12, minute: 0),
          ],
          bookings: <Booking>[booking],
        );

        expect(
          find.byKey(_freeKey(12, 0)),
          findsNothing,
          reason:
              'an appointment that DID happen took the master\'s time just '
              'as surely as one that will — `completed` consumes',
        );
      },
    );

    testWidgets(
      'a consumer starting at a NON-declared minute — the user\'s literal '
      'report: a 10:00 booking running to 12:30 hides BOTH declared times '
      'inside its span, still renders itself via pass 2, and leaves the '
      '13:00 declared time untouched',
      (tester) async {
        final Booking booking = _booking(
          id: 'stray-consumer',
          startAtUtc: _kyivAtUtc(10), // matches NO declared time
          durationMinutes: 150, // 10:00 -> 12:30
        );

        await _pumpCards(
          tester,
          declaredTimes: const <TimeOfDay>[
            TimeOfDay(hour: 11, minute: 0),
            TimeOfDay(hour: 12, minute: 0),
            TimeOfDay(hour: 13, minute: 0), // outside the span — stays free
          ],
          bookings: <Booking>[booking],
        );

        expect(
          find.byKey(_bookedKey('stray-consumer')),
          findsOneWidget,
          reason:
              'PASS 2 IS UNTOUCHED BY PASS 1B — dropping the slots a 10:00 '
              'booking swallowed must never drop the 10:00 booking itself '
              '(MUTATION-VERIFIED: deleting pass 1b\'s removeWhere turns the '
              'two absence assertions below RED, and a pass-1b that also '
              'wrote `consumed[]` would turn THIS one red)',
        );
        expect(
          find.byKey(_freeKey(11, 0)),
          findsNothing,
          reason: '11:00 falls inside [10:00, 12:30)',
        );
        expect(
          find.byKey(_freeKey(12, 0)),
          findsNothing,
          reason:
              '12:00 falls inside [10:00, 12:30) — the exact card the user '
              'reported as falsely free',
        );
        expect(
          find.byKey(_freeKey(13, 0)),
          findsOneWidget,
          reason:
              'the removal is TARGETED, not a wipe — 13:00 sits past the '
              'booking\'s end and is still genuinely free',
        );
      },
    );

    testWidgets(
      'UNSORTED declaredTimes — the predicate is order-independent BY '
      'CHOICE (an ascending sweep would be the cheap alternative and its '
      'failure mode is DESTRUCTIVE), so a descending input still drops '
      'exactly the consumed entry and keeps the rest',
      (tester) async {
        final Booking booking = _booking(
          id: 'unsorted-consumer',
          startAtUtc: _kyivAtUtc(11),
          durationMinutes: 90, // 11:00 -> 12:30
        );

        await _pumpCards(
          tester,
          // Deliberately DESCENDING — the schedule mapper resolves these
          // sorted, but pass 1b must not silently depend on that upstream
          // invariant: desynchronise a running-max sweep and it drops an
          // EARLY declared time sitting behind a LATER booking, which is
          // this very class of bug in mirror image.
          declaredTimes: const <TimeOfDay>[
            TimeOfDay(hour: 15, minute: 0),
            TimeOfDay(hour: 12, minute: 0),
            TimeOfDay(hour: 11, minute: 0),
          ],
          bookings: <Booking>[booking],
        );

        expect(
          find.byKey(_freeKey(12, 0)),
          findsNothing,
          reason: 'consumed regardless of where it sat in the input list',
        );
        expect(
          find.byKey(_freeKey(15, 0)),
          findsOneWidget,
          reason:
              '15:00 is outside the span and must survive — a sweep that '
              'lost its place would be as likely to eat this one',
        );
        expect(find.byKey(_bookedKey('unsorted-consumer')), findsOneWidget);
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

  // ═══════════════════════════════════════════════════════════════════════
  // TYPOGRAPHY PARITY — a FREE card must never OUT-RANK the booked card
  // beside it.
  //
  // THE BUG THIS PINS (user-reported, 2026-08-13): `_FreeTimeCard` drew its
  // declared time in `VelvetText.statValue()` (Comfortaa 17/700, the
  // stat-TILE family) and its «Вільно» caption in `VelvetText.subheading()`
  // (Comfortaa 14/600), while the sibling `MasterBookingCard` — pinned to
  // its FULL layout in the SAME `ListView.separated` — opens at Comfortaa
  // 13.5/600 with a Nunito 11/700 caption. An EMPTY slot therefore read
  // louder than every BOOKED neighbour in the column.
  //
  // WHY THE EXISTING PINS ALL STAYED GREEN THROUGH IT: the "uniform card
  // heights" group above measures the BOX (height and width, at three text
  // scales) and the "full layout is always selected" group measures the
  // BODY SHAPE. Both are geometry. Neither ever looked at type, and the
  // free card's floor is a `minHeight` constraint — so a two-tier size jump
  // inside a box that is already floored taller than its own content moves
  // no measurable dimension at all.
  //
  // ASSERTED RELATIVELY (free == its booked sibling), NEVER against the
  // literals 13.5 / 11. The invariant that actually broke is a RANKING one:
  // rescaling the whole master-card tier is a legitimate future design move
  // and must not turn this test red, whereas a pinned literal would simply
  // be edited to match the next time the scale shifts — which is exactly
  // how a ranking regression gets normalised back in.
  //
  // MUTATION-VERIFIED (this session): reverting `declared_time_cards.dart`'s
  // `_FreeTimeCard._timeStyle` to `VelvetText.statValue()` — i.e. literally
  // reintroducing the shipped bug — turns the first test below RED on the
  // fontSize assertion (17.0 vs the booked sibling's 13.5); restoring
  // `VelvetText.masterFreeCardTime` turns it GREEN again.
  // ═══════════════════════════════════════════════════════════════════════
  group('typography parity — a free card never out-ranks its booked '
      'neighbour', () {
    /// One day carrying BOTH shapes: a booked 09:00 entry (FULL layout, see
    /// the group above) and a FREE 11:00 declared time, in one list.
    Future<void> pumpMixedDay(WidgetTester tester) => _pumpCards(
      tester,
      declaredTimes: const <TimeOfDay>[
        TimeOfDay(hour: 9, minute: 0),
        TimeOfDay(hour: 11, minute: 0), // stays free — no booking here
      ],
      bookings: <Booking>[_booking(id: 'typo', startAtUtc: _kyivAtUtc(9))],
    );

    testWidgets(
      'the free card\'s TIME renders in the booked card\'s row-1 client-name '
      'tier — same painted size, weight and family',
      (tester) async {
        await pumpMixedDay(tester);

        final Finder freeCard = find.byKey(_freeKey(11, 0));
        final Finder bookedCard = find.byKey(_bookedKey('typo'));

        final TextStyle freeTime = _paintedStyle(
          tester,
          // i18n-finder-ok: digits only, locale-invariant declared time.
          find.descendant(of: freeCard, matching: find.text('11:00')),
        );
        final TextStyle bookedName = _paintedStyle(
          tester,
          // i18n-finder-ok: 'Марія Іванюк' is the fixture's clientName data.
          find.descendant(of: bookedCard, matching: find.text('Марія Іванюк')),
        );

        expect(
          freeTime.fontSize,
          bookedName.fontSize,
          reason:
              'the free card\'s time must render at the SAME size tier as '
              'the booked sibling\'s client name — an empty slot may never '
              'out-rank a booked one in the same list (asserted relatively '
              'on purpose: rescaling the whole tier is legitimate, '
              'out-ranking is not)',
        );
        expect(
          freeTime.fontWeight,
          bookedName.fontWeight,
          reason: 'same tier means the same weight, not just the same size',
        );
        expect(
          freeTime.fontFamily,
          bookedName.fontFamily,
          reason:
              'both are the Comfortaa structural face — a family swap here '
              'would re-open the same visual mismatch at an equal size',
        );
      },
    );

    testWidgets('the free card\'s «Вільно» label renders in the booked card\'s '
        'time-range caption tier — same painted size, weight and family', (
      tester,
    ) async {
      await pumpMixedDay(tester);

      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(DeclaredTimeCards)),
      );
      final Finder freeCard = find.byKey(_freeKey(11, 0));
      final Finder bookedCard = find.byKey(_bookedKey('typo'));

      final TextStyle freeLabel = _paintedStyle(
        tester,
        find.descendant(
          of: freeCard,
          matching: find.text(l10n.masterBookingsDeclaredTimeFree),
        ),
      );
      final TextStyle bookedCaption = _paintedStyle(
        tester,
        // `formatSlotTimeRange` — 09:00 + the fixture's 30 min.
        // i18n-finder-ok: digits + en-dash, locale-invariant time range.
        find.descendant(of: bookedCard, matching: find.text('09:00–09:30')),
      );

      expect(
        freeLabel.fontSize,
        bookedCaption.fontSize,
        reason:
            'the «Вільно» caption must sit in the booked card\'s own '
            'secondary caption tier, not a size above it',
      );
      expect(freeLabel.fontWeight, bookedCaption.fontWeight);
      expect(
        freeLabel.fontFamily,
        bookedCaption.fontFamily,
        reason:
            'both are the Nunito caption face — the shipped bug drew this '
            'label in the Comfortaa structural face instead',
      );
    });

    testWidgets(
      'FIXTURE GUARD — the booked card\'s two tiers are genuinely different '
      'sizes, so the two parity assertions above cannot both be satisfied by '
      'one flat size',
      (tester) async {
        await pumpMixedDay(tester);

        final Finder bookedCard = find.byKey(_bookedKey('typo'));
        final TextStyle bookedName = _paintedStyle(
          tester,
          // i18n-finder-ok: fixture clientName data.
          find.descendant(of: bookedCard, matching: find.text('Марія Іванюк')),
        );
        final TextStyle bookedCaption = _paintedStyle(
          tester,
          // i18n-finder-ok: digits + en-dash time range.
          find.descendant(of: bookedCard, matching: find.text('09:00–09:30')),
        );

        expect(
          bookedName.fontSize,
          greaterThan(bookedCaption.fontSize!),
          reason:
              'row 1 must outrank the caption on the booked card itself; if '
              'these ever collapse to one size, the parity tests above stop '
              'discriminating between the two tiers and would pass even with '
              'the free card\'s label promoted to the name tier',
        );
      },
    );
  });
}

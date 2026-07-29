// QA (frozen-price-band pass) — the STATUS GATE × BAND matrix, on both cards.
//
// WHAT THIS PINS THAT NOTHING ELSE DID
// ------------------------------------
// The band change (`priceMaxAtBooking` → `Booking.priceMax` →
// `BookingDisplayX.priceLabel`) introduced a SECOND money string per booking:
// «300–500 ₴» beside the old «300 ₴». `BookingDisplayX.showsPrice` decides
// WHETHER money is rendered at all (CONFIRMED / COMPLETED only) and is
// orthogonal to `priceLabel`, which decides HOW it reads — but the two had
// never been tested TOGETHER on the axis the change introduced.
//
// Before this file, the whole corpus's status-gate coverage was:
//   • `master_booking_card_test.dart` → one CANCELLED case, on a booking whose
//     `priceMax` is NULL (the fixture default). It asserts the floor «450 ₴»
//     is absent. A regression that gated only the FLOOR and let the BAND
//     through — e.g. `if (b.showsPrice) _PriceTag(...)` swapped for a
//     `priceMax == null ? gated : ungated` shape — passes that test untouched.
//   • `booking_card.dart` (client list) → nothing at all on the gate.
//   • DECLINED / NOT_COMPLETED → nothing on either card.
//
// So this file walks the full product: {cancelled, declined, notCompleted} ×
// {client card, master card compact, master card full} with a NON-NULL
// `priceMax`, and asserts NEITHER the band NOR its floor NOR its ceiling is
// rendered — plus a CONFIRMED/COMPLETED control per surface proving the same
// fixture DOES render the band, so a findsNothing sweep cannot pass vacuously.
//
// BOTH TREES, NOT JUST THE VISUAL ONE
// -----------------------------------
// `booking_recap_test.dart` already proves the recap's `Semantics(label: …)`
// is gated, using a `find.byWidgetPredicate((w) => w is Semantics && …)`
// sweep. That technique CANNOT work here: on both cards the price is a plain
// [Text], which contributes a semantics node from its `RenderParagraph` with
// no `Semantics` WIDGET in the tree to match. A widget-predicate sweep over
// these cards therefore returns `findsNothing` whether the price is rendered
// or not — it would be a vacuous assertion.
//
// So the semantics assertions below read the REAL semantics tree: a
// [tester.ensureSemantics] handle plus a walk of the live [SemanticsNode]
// tree, collecting every node's label. That sees exactly what TalkBack /
// VoiceOver would announce, which is the surface the gate has to hold on.
//
// FINDER POLICY: the client card's price carries `ValueKey('price-<id>')`, so
// its assertions are key-first. The master card's `_PriceTag` is private and
// unkeyed, so its price is located by the rendered figure — an ASCII-digit +
// «₴» string with no Cyrillic, which is locale-invariant data and passes
// `scripts/forbid_cyrillic_finder.sh` on its own terms.

import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_display_x.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_card.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_booking_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/booking_fixture_dates.dart';
import '../../../helpers/pump_app.dart';

// The one fixture band every case in this file uses. Kept as constants so the
// expected strings below are derived from them rather than re-typed.
const double _kFloor = 300;
const double _kCeiling = 500;
const String _kBand = '300–500 ₴';
const String _kFloorAlone = '300 ₴';
const String _kCeilingAlone = '500 ₴';

/// A booking carrying a genuine frozen RANGE (`priceMax` non-null) at [status].
Booking _banded(BookingStatus status, {String id = 'band-1'}) {
  final DateTime start = futureBookingStart();
  return Booking(
    id: id,
    masterId: 'm1',
    masterFirstName: 'Марія',
    masterLastName: 'Іванюк',
    masterAvatarUrl: null,
    masterType: 'INDEPENDENT_MASTER',
    salonName: null,
    clientFirstName: 'Оля',
    clientLastName: 'Коваль',
    serviceId: 's1',
    serviceName: 'Манікюр з покриттям',
    categoryName: 'Манікюр',
    cityLabel: 'Львів',
    districtLabel: null,
    street: 'вул. Городоцька',
    buildingNo: '12',
    durationMinutes: 60,
    price: _kFloor,
    priceMax: _kCeiling,
    startAt: start,
    endAt: start.add(const Duration(minutes: 60)),
    status: status,
    canReview: false,
    masterProfessionalTitle: 'Майстриня манікюру',
    locationNote: null,
  );
}

/// Every label in the LIVE semantics tree (what TalkBack/VoiceOver would read),
/// not the widget tree. See this file's header for why the widget-predicate
/// technique used by `booking_recap_test.dart` cannot be reused here.
///
/// Uses [SemanticsController.simulatedAccessibilityTraversal] — the same
/// ordered node walk a screen reader performs — rather than reaching into
/// `binding.pipelineOwner.semanticsOwner` (deprecated, and it would trip the
/// `--fatal-infos` analyze gate).
List<String> _semanticsLabels(WidgetTester tester) => tester.semantics
    .simulatedAccessibilityTraversal()
    .map((SemanticsNode n) => n.label)
    .where((String l) => l.isNotEmpty)
    .toList();

/// Asserts money appears NOWHERE — not the band, not either endpoint, not the
/// bare currency suffix — in the visual tree OR the semantics tree.
void _expectNoMoneyAnywhere(WidgetTester tester) {
  expect(find.text(_kBand), findsNothing, reason: 'the band must be gated');
  expect(
    find.text(_kFloorAlone),
    findsNothing,
    reason:
        'the floor alone must be gated too — a gate that only stops the '
        'BAND would leak the very figure the pre-band code rendered',
  );
  expect(find.text(_kCeilingAlone), findsNothing);

  final Iterable<String> money = _semanticsLabels(
    tester,
  ).where((String l) => l.contains('₴'));
  expect(
    money,
    isEmpty,
    reason:
        'a suppressed price must not reach the accessibility tree either; '
        'found: $money',
  );
}

/// Asserts [MasterBookingCard] is genuinely on screen AND is rendering the
/// [layout] the case claims to be exercising — `'compact'` or `'full'`.
///
/// ## Why this is not just `find.byType(TimelineStatusBadge)` any more
/// (miniature-layout pass, 2026-07-21)
///
/// This is a CONTROL, not the assertion under test: its job is to stop
/// [_expectNoMoneyAnywhere]'s `findsNothing` sweep from passing vacuously
/// because nothing was pumped at all. It used to look for
/// [TimelineStatusBadge] on both layouts, which was true until
/// `_buildCompactBody` was re-composed into a miniature of the full card:
/// the compact layout's status indicator is now [TimelineStatusDot], a bare
/// 8dp circle whose label lives in `Semantics`/`Tooltip` rather than in a
/// text pill. The full layout still draws the labelled badge, which is why
/// only the four compact cases went red.
///
/// The control's MEANING is unchanged — "a real card rendered, only the money
/// is suppressed" — and it is deliberately STRONGER than a straight swap
/// would have been: it also asserts the OTHER layout's indicator is ABSENT.
/// Without that, a regression collapsing both branches to one layout would
/// leave the four cases labelled `full` quietly re-testing the compact body,
/// and the gate would lose half its coverage with every test still green.
void _expectStatusIndicator(String layout) {
  final bool compact = layout == 'compact';
  expect(
    find.byType(TimelineStatusDot),
    compact ? findsOneWidget : findsNothing,
    reason:
        'the $layout layout must ${compact ? '' : 'NOT '}render the compact '
        'status dot — if this fails the card is either absent (making the '
        'money sweep above vacuous) or rendering the wrong branch',
  );
  expect(
    find.byType(TimelineStatusBadge),
    compact ? findsNothing : findsOneWidget,
    reason:
        'the $layout layout must ${compact ? 'NOT ' : ''}render the labelled '
        'status badge — see above',
  );
}

/// The statuses on which money is NOT a true statement — the whole point of
/// `BookingDisplayX.showsPrice`. `BookingStatus.unknown` is included: a status
/// this build cannot identify must not be assumed payable.
const List<BookingStatus> _kMoneylessStatuses = <BookingStatus>[
  BookingStatus.cancelled,
  BookingStatus.declined,
  BookingStatus.notCompleted,
  BookingStatus.unknown,
];

/// The statuses on which money IS a true statement — the controls.
const List<BookingStatus> _kMoneyedStatuses = <BookingStatus>[
  BookingStatus.confirmed,
  BookingStatus.completed,
];

void main() {
  // ───────────────────────────────────────────────────────────────────────
  // Surface 1 — the CLIENT list card (`booking_card.dart`).
  // ───────────────────────────────────────────────────────────────────────

  group('BookingCard (client list) — status gate holds against a BAND', () {
    for (final BookingStatus status in _kMoneylessStatuses) {
      testWidgets(
        '${status.name}: a non-null priceMax renders NEITHER «$_kBand» nor the '
        'floor, in the visual OR the semantics tree',
        (WidgetTester tester) async {
          final SemanticsHandle handle = tester.ensureSemantics();
          final Booking booking = _banded(status);

          await tester.pumpApp(
            BookingCard(booking: booking, onOpenDetails: () {}),
          );
          await tester.pumpAndSettle();

          // The keyed price anchor is not built at all — `_ServiceLine`
          // receives `null` and adds no child, rather than building a hidden
          // or empty one.
          expect(
            find.byKey(ValueKey<String>('price-${booking.id}')),
            findsNothing,
          );
          _expectNoMoneyAnywhere(tester);

          // Control that the card really rendered: the service name IS there,
          // so the sweep above is not passing because nothing was pumped.
          expect(
            find.byKey(ValueKey<String>('service-${booking.id}')),
            findsOneWidget,
          );

          // Disposed INSIDE the body, not via addTearDown: flutter_test's
          // end-of-test semantics-handle verification runs BEFORE tearDowns,
          // so an addTearDown disposal fails every test in the file.
          handle.dispose();
        },
      );
    }

    for (final BookingStatus status in _kMoneyedStatuses) {
      testWidgets(
        '${status.name} (control): the SAME banded fixture DOES render '
        '«$_kBand» — the gate is status-driven, not band-driven',
        (WidgetTester tester) async {
          final SemanticsHandle handle = tester.ensureSemantics();
          final Booking booking = _banded(status);

          await tester.pumpApp(
            BookingCard(booking: booking, onOpenDetails: () {}),
          );
          await tester.pumpAndSettle();

          expect(
            find.byKey(ValueKey<String>('price-${booking.id}')),
            findsOneWidget,
          );
          expect(find.text(_kBand), findsOneWidget);
          expect(
            find.text(_kFloorAlone),
            findsNothing,
            reason: 'the floor alone is exactly the bug the band fixes',
          );
          // …and it is announced, so the moneyless sweep above is a real
          // difference in the semantics tree, not an always-empty one.
          expect(
            _semanticsLabels(tester).where((String l) => l.contains(_kBand)),
            isNotEmpty,
          );

          handle.dispose();
        },
      );
    }
  });

  // ───────────────────────────────────────────────────────────────────────
  // Surface 2 — the MASTER timeline card (`master_booking_card.dart`), which
  // has TWO layouts selected by `minHeight`. The gate lives in each branch
  // independently (`_buildCompactBody` and `_buildFullBody` each carry their
  // own `if (b.showsPrice)`), so both are walked.
  // ───────────────────────────────────────────────────────────────────────

  group('MasterBookingCard — status gate holds against a BAND, both layouts', () {
    // (label, minHeight) — null minHeight selects the compact grid; a floor at
    // or above `MasterBookingCard.fullLayoutMinHeight` (118dp) selects the
    // divided full layout.
    //
    // THE `full` FLOOR IS READ OFF THE PUBLIC CONSTANT, NOT SPELLED AS A
    // LITERAL. It used to be a bare `112`, which was correct only while the
    // threshold was 112; the 2026-07-24 vertical-scale pass moved the
    // threshold to 117 (118 today) and this fixture silently started selecting
    // the COMPACT
    // layout instead — so all six `full / <moneyless status>` cases were
    // exercising the compact branch under a `full` label, and the
    // `_expectStatusIndicator` guard that exists to catch exactly that
    // started failing. Deriving the floor from the constant makes the fixture
    // follow any future threshold move on its own.
    final List<(String, double?)> layouts = <(String, double?)>[
      ('compact', null),
      ('full', MasterBookingCard.fullLayoutMinHeight),
    ];

    for (final (String name, double? minHeight) in layouts) {
      for (final BookingStatus status in _kMoneylessStatuses) {
        testWidgets(
          '$name layout / ${status.name}: a non-null priceMax renders NEITHER '
          '«$_kBand» nor the floor, in the visual OR the semantics tree',
          (WidgetTester tester) async {
            final SemanticsHandle handle = tester.ensureSemantics();
            final Booking booking = _banded(status);

            await tester.pumpApp(
              Center(
                child: MasterBookingCard(
                  booking: booking,
                  onTap: () {},
                  minHeight: minHeight,
                ),
              ),
            );
            await tester.pumpAndSettle();

            _expectNoMoneyAnywhere(tester);

            // Control: the card is genuinely on screen — the status indicator
            // and the service name still render, only the money is suppressed.
            _expectStatusIndicator(name);
            expect(find.text(booking.serviceName), findsOneWidget);

            handle.dispose();
          },
        );
      }

      for (final BookingStatus status in _kMoneyedStatuses) {
        testWidgets(
          '$name layout / ${status.name} (control): the SAME banded fixture '
          'DOES render «$_kBand»',
          (WidgetTester tester) async {
            final SemanticsHandle handle = tester.ensureSemantics();
            final Booking booking = _banded(status);

            await tester.pumpApp(
              Center(
                child: MasterBookingCard(
                  booking: booking,
                  onTap: () {},
                  minHeight: minHeight,
                ),
              ),
            );
            await tester.pumpAndSettle();

            expect(find.text(_kBand), findsOneWidget);
            expect(find.text(_kFloorAlone), findsNothing);
            expect(
              _semanticsLabels(tester).where((String l) => l.contains(_kBand)),
              isNotEmpty,
            );
            // Same layout precondition as the moneyless cases above — so a
            // control that silently started rendering the WRONG layout could
            // not keep vouching for the gated cases beside it.
            _expectStatusIndicator(name);

            handle.dispose();
          },
        );
      }
    }
  });

  // ───────────────────────────────────────────────────────────────────────
  // The derivation itself — `showsPrice` and `priceLabel` are ORTHOGONAL.
  //
  // Both cards read the pair `showsPrice ? priceLabel : <nothing>`. A
  // regression could also come from the DOMAIN side: `showsPrice` quietly
  // widened, or `priceLabel` learning to return '' on a gated status (which
  // would make every findsNothing above pass while the contract broke).
  // ───────────────────────────────────────────────────────────────────────

  group('BookingDisplayX — the two getters do not contaminate each other', () {
    test(
      'showsPrice is true for exactly {confirmed, completed}, band or not',
      () {
        for (final BookingStatus status in BookingStatus.values) {
          final bool expected =
              status == BookingStatus.confirmed ||
              status == BookingStatus.completed;
          expect(
            _banded(status).showsPrice,
            expected,
            reason:
                '${status.name} with a BAND must gate exactly as it does '
                'without one — the ceiling is not a capability',
          );
        }
      },
    );

    test('priceLabel is the SAME band on every status — the gate is the '
        "caller's job, never the formatter's", () {
      for (final BookingStatus status in BookingStatus.values) {
        expect(
          _banded(status).priceLabel,
          _kBand,
          reason:
              'priceLabel must not learn to self-suppress; if it returned '
              "'' on a gated status the card assertions would pass vacuously",
        );
      }
    });
  });
}

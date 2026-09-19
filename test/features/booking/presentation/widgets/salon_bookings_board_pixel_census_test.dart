// PIXEL census of the salon «Записи» board's column background.
//
// ── WHY THIS FILE EXISTS ───────────────────────────────────────────────────
//
// The board shipped a near-white wash under every ODD, NOT-day-off master
// column (`BrandColors.shadowLightStrong` @ 0.55, compositing to `#F4EEE4`).
// A real user read it as "the master columns with a booking have a white
// background"; the booking count was a red herring — the real gates were
// odd-column-index AND not-day-off, and on a real roster the empty columns
// are mostly the day-off ones. It violated `ARCHITECTURE-mobile.md:1068`:
// depth on this palette comes from paired light/dark shadows, NEVER from a
// fill or a border, and every surface sits on `BrandColors.base`.
//
// The suite that was supposed to guard this could not, in TWO independent
// ways, and both are closed here:
//
//  1. DIRECTION. The old assertions were `isNot(BrandColors.base)` plus a
//     minimum per-channel DELTA floor. A wrong-DIRECTION colour — lighter
//     instead of darker — satisfies both, which is exactly how an invisible
//     band shipped first and an over-bright one second. A delta floor cannot
//     express "this column has no background"; equality against
//     [BrandColors.base] plus a no-lifting rule can, and structurally forbids
//     both failures at once.
//
//  2. MECHANISM. `salon_bookings_alternating_column_test.dart`'s census walks
//     `ColoredBox` widgets, and its companion guard matches one exact
//     `ValueKey`. The wash that shipped was NEITHER — it was a
//     `CustomPainter` (`_AlternatingColumnBandPainter`) drawing straight to
//     the canvas. Reintroduced under a different key, or as any painter at
//     all, it evades both. So this file does not walk the widget tree for
//     fills: it rasterizes the real board through
//     `RenderRepaintBoundary.toImage()` and reads the pixels a user's eye
//     would receive. Anything that paints — `ColoredBox`, `CustomPainter`,
//     `BoxDecoration`, a gradient — is in scope by construction.
//
// A widget-field read (`someBox.color == X`) is NOT this. It proves what a
// widget was CONFIGURED with, never what rasterized; a painter configures
// nothing a finder can see. Same recipe and same reasoning as
// `test/features/master/presentation/settings_row_disabled_dim_test.dart`,
// which measures a composite the golden toolchain is structurally blind to.
//
// ── THE GROUND MUST BE INSIDE THE BOUNDARY ────────────────────────────────
//
// `RenderRepaintBoundary.toImage()` rasterizes only the boundary's own
// subtree. [BookingsTimelineGrid] paints no background of its own — on the
// real screen `BrandColors.base` arrives from the Scaffold
// (`app_theme.dart:24` `scaffoldBackgroundColor`, restated at
// `salon_bookings_screen.dart:713`). So the host below puts an explicit
// `ColoredBox(BrandColors.base)` INSIDE the boundary: that is the production
// ground, reproduced, and every captured pixel is opaque. Without it every
// pixel the board does not cover comes back TRANSPARENT — which is what a
// near-white wash over nothing looks like too, and the measurement would be
// reading alpha instead of the composite.
//
// ── WHY "NOTHING LIFTS" IS SAFE TO ASSERT OVER THE WHOLE BOARD ────────────
//
// Every fill the board paints is at or below base: the hour gridlines
// (`BrandColors.faint`), the half-hour gridlines (faint at alpha), the gutter
// dividers (`accent@0.16`), the day-off wash (`shadowDarkCard@0.35`), the
// «Вихідний»/«Вільний день» marker (`BrandColors.muted`). The booking card's
// own ambient shadow is `shadowDarkCard@0.45` with NO offset
// (`velvet_geometry.dart:226`), so it can only darken its surroundings.
//
// Two GLYPH regions are excluded by rect, and only those:
//
//   * a booking card's INTERIOR — a card legitimately carries white
//     highlights (`BrandColors.white@0.35` / `@0.82` on the client avatar);
//   * the empty-column «Вільний день» / «Вихідний» marker's text box.
//
// The marker exclusion is MEASURED, not precautionary. Swept without it, the
// census reports exactly 280 lifted pixels, all of them inside
// `timeline-column-marker-1`'s own 71.8 × 15.0 rect, peaking at
// `rgb(236, 230, 154)` — R +6 and G +9 over base with B far BELOW it. That
// channel signature is Skia's gamma-corrected glyph antialiasing overshooting
// on the light side of dark-on-light text, not a fill: the identical marker
// in the day-off column (whose ground is darker) produces no lift at all.
// Glyph AA is not what § 9 is about, and the region is 1 % of one column —
// everything the wash actually covered stays in scope.
//
// Excluding them costs nothing here: the defect was the background BETWEEN
// and BELOW cards, which is precisely what remains swept.
//
// ── CLOCK / TZ ─────────────────────────────────────────────────────────────
//
// One fixed PAST Kyiv date, read by nothing but the fixture; every assertion
// is a colour. No `isPast` predicate, no «зараз» hairline (the day is past),
// no host-clock read. `TZ=UTC` changes no expectation. One clock, both halves.
//
// ── MUTATION RECORD ────────────────────────────────────────────────────────
// Recorded by mobile-qa in the audit that authored this file; see the report
// for the observed RED/GREEN transitions.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_timeline_grid.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_column_strip.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/timeline_density.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/timeline_hour_ruler.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// Fixture
// ---------------------------------------------------------------------------

/// The board day. future-date-ok: a fixed PAST Kyiv day; every assertion in
/// this file is a colour, and nothing reads a clock predicate.
final DateTime _day = DateTime(2026, 6, 15);

/// The same fixed PAST day as the canonical UTC instant the wire carries.
/// future-date-ok: see [_day].
final DateTime _dayUtcMidnight = DateTime.utc(2026, 6, 15);

/// Kyiv is UTC+3 in June — the board's own day, expressed the way a
/// `BookingResponse` would carry it.
DateTime _kyiv(int hour) => _dayUtcMidnight.add(Duration(hours: hour - 3));

Booking _booking({
  required String id,
  required String masterId,
  required int hour,
  int durationMinutes = 60,
}) {
  final DateTime start = _kyiv(hour);
  return Booking(
    id: id,
    masterId: masterId,
    masterFirstName: 'Оля',
    masterLastName: 'Коваль',
    masterType: 'SALON_MASTER',
    clientFirstName: 'Марія',
    clientLastName: 'Іванюк',
    serviceId: 'service-1',
    serviceName: 'Манікюр',
    durationMinutes: durationMinutes,
    price: 500,
    startAt: start,
    endAt: start.add(Duration(minutes: durationMinutes)),
    status: BookingStatus.confirmed,
    canReview: false,
  );
}

MasterColumnEntry _entry(String id, String name, {bool dayOff = false}) =>
    MasterColumnEntry(
      masterId: id,
      name: name,
      type: MasterType.salonMaster,
      bookingCount: 0,
      professionalTitle: 'Стиліст',
      avgRating: 4.8,
      dayOff: dayOff,
    );

/// The board the defect was reported against, minimised to four columns:
///
///   | idx | state                       | the band's gate said |
///   |-----|-----------------------------|----------------------|
///   |  0  | working, two bookings       | even → untinted      |
///   |  1  | working, NO bookings        | odd + working → TINT |
///   |  2  | working, two bookings       | even → untinted      |
///   |  3  | DAY OFF, no bookings        | odd but off → skipped|
///
/// Column 1 is the shape the user actually saw go white, and column 3 is the
/// one legitimate column state, kept in frame so the sampler is proved able
/// to SEE a column fill when one exists (see the third test — without it,
/// "everything reads base" could equally mean the sampler is pointed at empty
/// canvas).
///
/// Columns 0 and 2 carry IDENTICAL booking times so one gap row and one
/// below-the-last-card row are clean in both at once.
List<TimelineBoardColumn> _columns() => <TimelineBoardColumn>[
  TimelineBoardColumn(
    header: _entry('m1', 'Оля Коваль'),
    bookings: <Booking>[
      _booking(id: 'b0a', masterId: 'm1', hour: 10),
      _booking(id: 'b0b', masterId: 'm1', hour: 12, durationMinutes: 30),
    ],
  ),
  TimelineBoardColumn(
    header: _entry('m2', 'Ніна Бойко'),
    bookings: const <Booking>[],
  ),
  TimelineBoardColumn(
    header: _entry('m3', 'Іра Ткач'),
    bookings: <Booking>[
      _booking(id: 'b2a', masterId: 'm3', hour: 10),
      _booking(id: 'b2b', masterId: 'm3', hour: 12, durationMinutes: 30),
    ],
  ),
  TimelineBoardColumn(
    header: _entry('m4', 'Настя Гриб', dayOff: true),
    bookings: const <Booking>[],
  ),
];

const List<String> _kCardIds = <String>['b0a', 'b0b', 'b2a', 'b2b'];

/// The boundary the raster is taken from.
const Key _kBoundary = Key('salon-board-raster-boundary');

/// Wide enough that ALL FOUR columns are laid out inside the lane viewport —
/// the board's horizontal scroller would otherwise clip columns 2 and 3 out
/// of the raster at the 360dp baseline, and the odd/even parity the band was
/// keyed on is only observable with both parities in frame.
///
/// Arithmetic (`TimelineDensity.salon`): lane viewport =
/// `840 − 24 (page padding) − 30 (rulerWidth) − 4 (ruler↔grid gap) = 782`;
/// `columnWidth = min(190, (782 − 6) / 2) = 190`; content =
/// `4 × 190 + 3 × 6 = 778 ≤ 782`, so nothing scrolls and no
/// `StripScrollIndicator` mounts over the board.
const double _kViewportWidth = 840;
const double _kViewportHeight = 600;

Widget _host() => RepaintBoundary(
  key: _kBoundary,
  child: ColoredBox(
    // The production ground, reproduced inside the boundary — see the header.
    color: BrandColors.base,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: BookingsTimelineGrid(
        bookings: <Booking>[
          for (final TimelineBoardColumn c in _columns()) ...c.bookings,
        ]..sort((Booking a, Booking b) => a.startAt.compareTo(b.startAt)),
        day: _day,
        onBookingTap: _noop,
        density: TimelineDensity.salon,
        columns: _columns(),
      ),
    ),
  ),
);

void _noop(Booking _) {}

// ---------------------------------------------------------------------------
// Raster
// ---------------------------------------------------------------------------

/// A captured frame plus the global-coordinate origin it was captured at, so
/// a rect measured with `tester.getRect` can be read straight out of it.
class _Raster {
  const _Raster(this.px, this.width, this.height, this.origin);

  final Uint8List px;
  final int width;
  final int height;
  final Offset origin;

  bool contains(int x, int y) => x >= 0 && y >= 0 && x < width && y < height;

  /// The opaque RGB triple at GLOBAL logical position ([gx], [gy]).
  ///
  /// `devicePixelRatio` is pinned to 1 by `pumpApp(width:)` and `toImage`'s
  /// default `pixelRatio` is 1, so one image pixel IS one logical pixel and
  /// no scaling is folded in here.
  (int, int, int) at(double gx, double gy) {
    final int x = (gx - origin.dx).round();
    final int y = (gy - origin.dy).round();
    expect(
      contains(x, y),
      isTrue,
      reason: 'sample ($gx, $gy) fell outside the captured frame',
    );
    final int i = (y * width + x) * 4;
    return (px[i], px[i + 1], px[i + 2]);
  }
}

Future<_Raster> _rasterize(WidgetTester tester) async {
  final RenderRepaintBoundary boundary = tester
      .renderObject<RenderRepaintBoundary>(find.byKey(_kBoundary));

  late final ByteData? raw;
  late final int w;
  late final int h;
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage();
    w = image.width;
    h = image.height;
    raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
  });

  final ByteData? bytes = raw;
  expect(bytes, isNotNull, reason: 'the board boundary must rasterize');
  return _Raster(
    bytes!.buffer.asUint8List(),
    w,
    h,
    tester.getTopLeft(find.byKey(_kBoundary)),
  );
}

// ---------------------------------------------------------------------------
// Geometry, read back off the real render
// ---------------------------------------------------------------------------

/// The board's laid-out geometry — derived from the render tree, never from
/// a literal, so a density change moves the samples with the board instead of
/// silently pointing them at the wrong pixels.
class _BoardGeometry {
  const _BoardGeometry({
    required this.stack,
    required this.pitch,
    required this.columnWidth,
    required this.gridlines,
    required this.cards,
    required this.markers,
  });

  final Rect stack;
  final double pitch;
  final double columnWidth;

  /// Every full-width hairline's y, in global coordinates.
  final List<double> gridlines;

  /// Every mounted booking card's rect, in global coordinates.
  final List<Rect> cards;

  /// Every empty-column marker text box, in global coordinates — the second
  /// and last GLYPH region on the board (see the header for the measurement
  /// that put it here).
  final List<Rect> markers;

  /// The regions the no-lift census skips: glyphs, and nothing else.
  bool isGlyph(Offset p) =>
      cards.any((Rect c) => c.contains(p)) ||
      markers.any((Rect m) => m.inflate(1).contains(p));

  Rect column(int index) => Rect.fromLTWH(
    stack.left + index * pitch,
    stack.top,
    columnWidth,
    stack.height,
  );
}

_BoardGeometry _geometry(WidgetTester tester) {
  final Rect stack = tester.getRect(
    find.byKey(const ValueKey<String>('timeline-column-stack')),
  );

  // Two adjacent gutter hairlines give the column pitch without this test
  // restating `TimelineDensity`'s clamp arithmetic. `columnGutter` is a plain
  // density getter, so `columnWidth` follows.
  final double d1 = tester
      .getRect(find.byKey(const ValueKey<String>('timeline-column-divider-1')))
      .left;
  final double d2 = tester
      .getRect(find.byKey(const ValueKey<String>('timeline-column-divider-2')))
      .left;
  final double pitch = d2 - d1;
  final double gutter = TimelineDensity.salon.columnGutter;

  // The half-hour hairlines, at the SAME `nudge + half * slotHeight` the grid
  // lays them out at. A sample row must clear these — they are legitimately
  // not base.
  const double nudge = TimelineHourRuler.labelCenteringNudge;
  final double slot = TimelineDensity.salon.slotHeight;
  final List<double> gridlines = <double>[
    for (int half = 0; stack.top + nudge + half * slot <= stack.bottom; half++)
      stack.top + nudge + half * slot,
  ];

  return _BoardGeometry(
    stack: stack,
    pitch: pitch,
    columnWidth: pitch - gutter,
    gridlines: gridlines,
    cards: <Rect>[
      for (final String id in _kCardIds)
        tester.getRect(find.byKey(ValueKey<String>('timeline-card-$id'))),
    ],
    // Columns 1 and 3 are the empty ones, so they are the only two that draw
    // a marker. Asserted rather than searched: a fixture that quietly stopped
    // rendering them would otherwise widen the census's blind spot to zero
    // and look like an improvement.
    markers: <Rect>[
      for (final int i in <int>[1, 3])
        tester.getRect(
          find.byKey(ValueKey<String>('timeline-column-marker-$i')),
        ),
    ],
  );
}

/// How far a sample must stay from a card edge.
///
/// `VelvetShadows.borderedCard` is a single un-offset `BoxShadow` at
/// `blurRadius: 10` (`velvet_geometry.dart:226-231`), so a card darkens up to
/// ~10dp beyond its own rect in every direction. 12 gives that two pixels of
/// slack. The shadow only ever DARKENS, so this margin protects the
/// exact-equality rows; the no-lift census below does not need it.
const double _kShadowMargin = 12;

/// How far a sample row must stay from a gridline hairline.
const double _kGridlineMargin = 2;

/// Picks the y in `[lo, hi]` that is furthest from every gridline, and proves
/// a usable one exists.
///
/// Returning a y that happened to land ON a hairline would fail the
/// exact-base assertion for a reason that has nothing to do with the defect,
/// so the search is explicit rather than "the midpoint, probably".
double _cleanRow(_BoardGeometry g, double lo, double hi, String what) {
  double? best;
  double bestGap = -1;
  for (int y = lo.ceil(); y <= hi.floor(); y++) {
    double gap = double.infinity;
    for (final double line in g.gridlines) {
      gap = gap < (y - line).abs() ? gap : (y - line).abs();
    }
    if (gap > bestGap) {
      bestGap = gap;
      best = y.toDouble();
    }
  }
  expect(
    best,
    isNotNull,
    reason:
        'the fixture left no room for a $what sample row between '
        '${lo.toStringAsFixed(1)} and ${hi.toStringAsFixed(1)} — the FIXTURE '
        'is wrong, not the board',
  );
  expect(
    bestGap,
    greaterThanOrEqualTo(_kGridlineMargin),
    reason:
        'every candidate $what row sits within ${_kGridlineMargin}dp of a '
        'gridline hairline; the sample would be measuring the hairline',
  );
  return best!;
}

/// Asserts every pixel of one horizontal run inside column [index] is
/// EXACTLY [BrandColors.base].
///
/// The run is inset by [_kShadowMargin] on both sides: a card fills its whole
/// column and its un-offset blur reaches ~10dp sideways, i.e. across the 6dp
/// gutter and a few pixels into the NEIGHBOURING column. Insetting keeps this
/// run measuring column [index]'s own background.
void _expectRowIsBase(
  _Raster r,
  _BoardGeometry g,
  int index,
  double y,
  String what,
) {
  const int baseR = 0xE6;
  const int baseG = 0xDD;
  const int baseB = 0xD0;

  final Rect col = g.column(index);
  final double from = col.left + _kShadowMargin;
  final double to = col.right - _kShadowMargin;
  expect(
    to - from,
    greaterThan(40),
    reason: 'column $index left no usable interior run to sample',
  );

  int sampled = 0;
  for (double x = from; x <= to; x += 1) {
    final (int, int, int) p = r.at(x, y);
    expect(
      p,
      (baseR, baseG, baseB),
      reason:
          'column $index ($what row, y=${y.toStringAsFixed(0)}, '
          'x=${x.toStringAsFixed(0)}) rasterized to '
          'rgb${p.toString()} instead of BrandColors.base #E6DDD0. A master '
          'column has NO background of its own — the approved preview lets '
          'the base run edge to edge behind every column, occupied and empty, '
          'odd index and even alike.',
    );
    sampled++;
  }
  expect(
    sampled,
    greaterThan(40),
    reason: 'the $what row for column $index sampled almost nothing',
  );
}

void main() {
  group(
    'the salon board rasterizes its column background as the base tone',
    () {
      testWidgets(
        'every working column body is EXACTLY BrandColors.base between cards '
        'and below the last card — odd column index and even alike',
        (WidgetTester tester) async {
          await tester.pumpApp(
            _host(),
            width: _kViewportWidth,
            height: _kViewportHeight,
          );
          await tester.pumpAndSettle();

          final _BoardGeometry g = _geometry(tester);
          final _Raster r = await _rasterize(tester);

          // Columns 0 and 2 run the same two bookings, so ONE gap row and ONE
          // below-the-last-card row are clean in both — and in the empty
          // column 1 between them, which is the shape that went white.
          final Rect first = g.cards[0]; // 10:00, column 0
          final Rect second = g.cards[1]; // 12:00, column 0

          final double gapRow = _cleanRow(
            g,
            first.bottom + _kShadowMargin,
            second.top - _kShadowMargin,
            'between-cards',
          );
          final double belowRow = _cleanRow(
            g,
            second.bottom + _kShadowMargin,
            g.stack.bottom - 1,
            'below-last-card',
          );

          // The fixture must MOVE: a gap row that coincided with the
          // below-card row would mean the board collapsed and both assertions
          // are the same one.
          expect(
            belowRow - gapRow,
            greaterThan(TimelineDensity.salon.slotHeight),
            reason:
                'the two sample rows must be a real distance apart, or this '
                'test pins one row twice',
          );

          for (final int index in <int>[0, 1, 2]) {
            _expectRowIsBase(r, g, index, gapRow, 'between-cards');
            _expectRowIsBase(r, g, index, belowRow, 'below-last-card');
          }
        },
      );

      testWidgets(
        'nothing the board rasterizes LIFTS above the base tone on any channel '
        '— a lifting fill is exactly how the near-white columns shipped, and '
        'a CustomPainter evades every widget-type census',
        (WidgetTester tester) async {
          await tester.pumpApp(
            _host(),
            width: _kViewportWidth,
            height: _kViewportHeight,
          );
          await tester.pumpAndSettle();

          final _BoardGeometry g = _geometry(tester);
          final _Raster r = await _rasterize(tester);

          const int baseR = 0xE6;
          const int baseG = 0xDD;
          const int baseB = 0xD0;

          int examined = 0;
          for (int y = g.stack.top.ceil(); y < g.stack.bottom.floor(); y++) {
            for (int x = g.stack.left.ceil(); x < g.stack.right.floor(); x++) {
              if (!r.contains(
                (x - r.origin.dx).round(),
                (y - r.origin.dy).round(),
              )) {
                continue;
              }
              // The two GLYPH regions — a card's interior and an empty
              // column's marker text box. A card's exterior shadow is
              // un-offset and dark, so no margin is needed around it; the
              // marker gets 1dp for its own AA fringe. See the header for the
              // measurement behind both.
              final Offset p = Offset(x.toDouble(), y.toDouble());
              if (g.isGlyph(p)) continue;

              final (int, int, int) rgb = r.at(x.toDouble(), y.toDouble());
              examined++;
              expect(
                <int>[rgb.$1, rgb.$2, rgb.$3],
                <Matcher>[
                  lessThanOrEqualTo(baseR),
                  lessThanOrEqualTo(baseG),
                  lessThanOrEqualTo(baseB),
                ],
                reason:
                    'the board lifted a pixel above BrandColors.base at '
                    '($x, $y): rgb${rgb.toString()}. § 9 communicates depth '
                    'through paired light/dark shadows, never through a fill; '
                    'a lifting board fill is the near-white column wash coming '
                    'back, by whatever mechanism.',
              );
            }
          }

          expect(
            examined,
            greaterThan(10000),
            reason:
                'the census must actually sweep the board — a near-empty sweep '
                'would make this test vacuous in both directions',
          );
        },
      );

      testWidgets(
        'the DAY-OFF column is the one column that is not base, and it SINKS — '
        'proves this sampler can see a column fill when one is really there',
        (WidgetTester tester) async {
          await tester.pumpApp(
            _host(),
            width: _kViewportWidth,
            height: _kViewportHeight,
          );
          await tester.pumpAndSettle();

          final _BoardGeometry g = _geometry(tester);
          final _Raster r = await _rasterize(tester);

          final Rect second = g.cards[1];
          final double row = _cleanRow(
            g,
            second.bottom + _kShadowMargin,
            g.stack.bottom - 1,
            'below-last-card',
          );

          const int baseR = 0xE6;
          const int baseG = 0xDD;
          const int baseB = 0xD0;

          final Rect off = g.column(3);
          final (int, int, int) p = r.at(off.center.dx, row);

          // STRICTLY darker on every channel. This is the anti-vacuity half of
          // the file: if the sampler were pointed at empty canvas, or the
          // coordinate mapping were off by a column, this reads base and goes
          // red — which is what makes "columns 0-2 read base" mean something.
          expect(p.$1, lessThan(baseR));
          expect(p.$2, lessThan(baseG));
          expect(p.$3, lessThan(baseB));

          // And the day-off wash is the ONLY column that differs: column 3's
          // odd index is the same parity the removed band keyed on, so the
          // column next to it at the same parity distance must still be base.
          final Rect working = g.column(1);
          expect(
            r.at(working.center.dx, row),
            (baseR, baseG, baseB),
            reason:
                'column 1 shares column 3\'s ODD parity and is NOT off — the '
                'removed band tinted exactly this column',
          );
        },
      );
    },
  );
}

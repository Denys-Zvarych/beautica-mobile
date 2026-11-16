// The DENSE (salon board) layout of MasterBookingCard: on a 136-148dp lane the
// client surname, the service name and a readable price must all be visible.
// Non-dense behaviour is pinned by master_booking_card_test.dart and the
// goldens, which this change must not move.

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_booking_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/widgets/price_tag.dart';

import '../../../helpers/pixel_census.dart';
import '../../../helpers/pump_app.dart';

Booking _booking({
  double? priceMax,
  String first = _kClientFirst,
  String last = _kClientLast,
}) {
  // future-date-ok: pinned Kyiv wall-clock fixture.
  final DateTime startAt = DateTime.utc(2026, 7, 20, 6);
  return Booking(
    id: 'dense-1',
    masterId: 'master-1',
    masterFirstName: 'Оля',
    masterLastName: 'Коваль',
    masterType: 'SALON_MASTER',
    clientFirstName: first,
    clientLastName: last,
    serviceId: 'service-1',
    serviceName: _kService,
    durationMinutes: 90,
    price: 1250,
    priceMax: priceMax,
    startAt: startAt,
    endAt: startAt.add(const Duration(minutes: 90)),
    status: BookingStatus.confirmed,
    canReview: false,
  );
}

// Fixture data (a client's name, a service name), not UI copy.
const String _kClientFirst = 'Олександра';
const String _kClientLast = 'Шевченко';
const String _kClientFull = '$_kClientFirst $_kClientLast';
// A short name that fits on one line at 136dp, and a first name too long for
// any lane.
const String _kShortFirst = 'Оля';
const String _kShortLast = 'Коваль';
const String _kShortFull = '$_kShortFirst $_kShortLast';
const String _kHugeFirst = 'Олександрарозалінданатальєвна';
const String _kHugeLast = 'Пономаренко';
const String _kService = 'Манікюр з покриттям';
// The rendered PriceTag size for «1250» at masterCardPricePill — compact tier
// (1dp vertical padding) and full tier (3dp), identical on both boards.
const Size _kCompactPill = Size(50.6, 16);
const Size _kFullPill = Size(50.6, 20);
// BrandColors.base's channel sum, and how far the pill's inset shadow must
// pull a pixel of its well below / above it (measured: about -90 / +28).
const int _kBaseSum = 0xE6 + 0xDD + 0xD0;
const int _kInsetDarkDelta = 40;
const int _kInsetLightDelta = 10;

Future<void> _pump(
  WidgetTester tester, {
  required double minHeight,
  required double lane,
  Booking? booking,
}) async {
  await tester.pumpApp(
    Center(
      child: SizedBox(
        width: lane,
        child: MasterBookingCard(
          booking: booking ?? _booking(),
          onTap: () {},
          minHeight: minHeight,
          dense: true,
          laneWidth: lane,
        ),
      ),
    ),
  );
  await tester.pump();
  expect(tester.takeException(), isNull);
}

/// One-line width of [text] in [style] as the card renders it (merged onto the
/// ambient DefaultTextStyle) under [scaler].
double _measure(
  BuildContext context,
  String text,
  TextStyle style,
  TextScaler scaler,
) {
  final TextPainter p = TextPainter(
    text: TextSpan(
      text: text,
      style: DefaultTextStyle.of(context).style.merge(style),
    ),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: 1,
  )..layout();
  final double w = p.width;
  p.dispose();
  return w;
}

bool _truncated(WidgetTester tester, Finder f) {
  // A `Text` carrying a `semanticsLabel` wraps its paragraph in a Semantics
  // node, so resolve the RenderParagraph through the RichText underneath.
  final RenderParagraph p = tester.renderObject<RenderParagraph>(
    find.descendant(of: f, matching: find.byType(RichText)),
  );
  return p.didExceedMaxLines;
}

void main() {
  for (final ({String name, double minHeight}) c
      in <({String name, double minHeight})>[
        (name: 'compact', minHeight: 84),
        (name: 'full', minHeight: 126),
      ]) {
    for (final double lane in <double>[136, 148]) {
      testWidgets(
        '${c.name} @${lane}dp: one-line name, service and price show',
        (WidgetTester tester) async {
          await _pump(tester, minHeight: c.minHeight, lane: lane);

          // The expected choice, measured in the test with the same merged
          // style and scaler: full name iff it fits the lane's name budget.
          final bool full = c.minHeight >= 126;
          final BuildContext ctx = tester.element(
            find.byType(MasterBookingCard),
          );
          final double width = _measure(
            ctx,
            _kClientFull,
            full
                ? VelvetText.masterCardClientNameFull
                : VelvetText.masterCardClientName,
            MediaQuery.textScalerOf(ctx),
          );
          final bool fits =
              width <= lane - MasterBookingCard.denseNameChrome(full: full);
          final Finder name = find.text(fits ? _kClientFull : _kClientFirst);
          expect(name, findsOneWidget);
          expect(find.text(fits ? _kClientFirst : _kClientFull), findsNothing);
          expect(_truncated(tester, name), isFalse);

          final Finder service = find.text(_kService);
          expect(service, findsOneWidget);
          expect(_truncated(tester, service), isFalse);

          final Finder price = find.textContaining('1250');
          expect(price, findsOneWidget);
          // The same pill as the non-dense card (user 2026-11-16), checked on
          // what RENDERS at this lane (the side-by-side parity test below only
          // covers 148dp): the laid-out pill size of the non-dense card.
          final Size pill = tester.getSize(find.byType(PriceTag));
          final Size expected = full ? _kFullPill : _kCompactPill;
          expect(pill.width, closeTo(expected.width, 0.1));
          expect(pill.height, expected.height);
          // Not FittedBox-scaled down: the pill's text fills its box 1:1.
          final Finder box = find.ancestor(
            of: price,
            matching: find.byType(FittedBox),
          );
          expect(
            tester.getSize(box.first).width,
            greaterThanOrEqualTo(tester.getSize(price).width - 0.1),
          );
        },
      );
    }
  }

  for (final ({String name, double minHeight}) c
      in <({String name, double minHeight})>[
        (name: 'compact', minHeight: 84),
        (name: 'full', minHeight: 126),
      ]) {
    testWidgets('${c.name} @136dp: a short full name shows on one line', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        minHeight: c.minHeight,
        lane: 136,
        booking: _booking(first: _kShortFirst, last: _kShortLast),
      );
      final Finder name = find.text(_kShortFull);
      expect(name, findsOneWidget);
      expect(_truncated(tester, name), isFalse);
    });

    testWidgets('${c.name} @136dp: a too-long full name shows ONLY the first '
        'name, with the full name in semantics', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await _pump(
        tester,
        minHeight: c.minHeight,
        lane: 136,
        booking: _booking(first: _kClientFirst, last: _kHugeLast),
      );
      expect(find.text('$_kClientFirst $_kHugeLast'), findsNothing);
      final Finder name = find.text(_kClientFirst);
      expect(name, findsOneWidget);
      expect(_truncated(tester, name), isFalse);
      expect(
        find.bySemanticsLabel(RegExp('$_kClientFirst $_kHugeLast')),
        findsWidgets,
      );
      handle.dispose();
    });

    testWidgets('${c.name} @136dp: a first name too long for the lane '
        'ellipsizes', (WidgetTester tester) async {
      await _pump(
        tester,
        minHeight: c.minHeight,
        lane: 136,
        booking: _booking(first: _kHugeFirst, last: _kHugeLast),
      );
      final Finder name = find.text(_kHugeFirst);
      expect(name, findsOneWidget);
      expect(_truncated(tester, name), isTrue);
    });
  }

  // Compact name slot: lane - border(3) - padding(20) - gap(4) - dot(8).
  Future<void> pumpScaled(
    WidgetTester tester,
    double lane,
    double scale,
  ) async {
    await tester.pumpApp(
      Center(
        child: SizedBox(
          width: lane,
          child: MasterBookingCard(
            booking: _booking(first: _kShortFirst, last: _kShortLast),
            onTap: () {},
            minHeight: 84,
            dense: true,
            laneWidth: lane,
          ),
        ),
      ),
      textScaleFactor: scale,
    );
    await tester.pump();
  }

  testWidgets('a text-scale change flips full name -> first name', (
    WidgetTester tester,
  ) async {
    // Derive the lane from the measured name: its budget is the midpoint of
    // the full name's widths at 1.0 and 1.3 (fits at 1.0, not at 1.3).
    await pumpScaled(tester, 200, 1.0);
    final BuildContext ctx = tester.element(find.byType(MasterBookingCard));
    final double w1 = _measure(
      ctx,
      _kShortFull,
      VelvetText.masterCardClientName,
      const TextScaler.linear(1.0),
    );
    final double w13 = _measure(
      ctx,
      _kShortFull,
      VelvetText.masterCardClientName,
      const TextScaler.linear(1.3),
    );
    expect(w13, greaterThan(w1));
    final double lane =
        MasterBookingCard.denseNameChrome(full: false) + (w1 + w13) / 2;
    await pumpScaled(tester, lane, 1.0);
    expect(find.text(_kShortFull), findsOneWidget);
    await pumpScaled(tester, lane, 1.3);
    expect(find.text(_kShortFull), findsNothing);
    expect(find.text(_kShortFirst), findsOneWidget);
    await pumpScaled(tester, lane, 1.0);
    expect(find.text(_kShortFull), findsOneWidget);
  });

  Future<void> pumpFonts(
    WidgetTester tester, {
    bool dense = true,
    double? laneWidth = 136,
  }) async {
    await tester.pumpApp(
      Center(
        child: SizedBox(
          width: 136,
          child: MasterBookingCard(
            booking: _booking(first: _kShortFirst, last: _kShortLast),
            onTap: () {},
            minHeight: 84,
            dense: dense,
            laneWidth: laneWidth,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  // The engine's own signal: ServicesBinding turns it into a `systemFonts`
  // notification (what FontLoader / google_fonts trigger).
  Future<void> fontsChange(WidgetTester tester) => tester.binding
      .handleSystemMessage(<String, dynamic>{'type': 'fontsChange'});

  // The card's own rebuild is observable as a NEW `Text` widget instance (the
  // compact body is rebuilt, not cached) and as a scheduled frame callback.
  Widget nameText(WidgetTester tester) => tester.widget(find.text(_kShortFull));

  group('font change re-measures the name', () {
    tearDown(() => debugDenseNameWidthOverride = null);

    testWidgets('a fontsChange drops the memoised choice (full -> first)', (
      WidgetTester tester,
    ) async {
      // Reports a width that fits, then (after the "fonts load") one that
      // does not. Only an invalidated memo + body cache can notice.
      addTearDown(() => debugDenseNameWidthOverride = null);
      debugDenseNameWidthOverride = (_, _, _) => 10;
      await pumpFonts(tester);
      expect(find.text(_kShortFull), findsOneWidget);
      final Widget before = nameText(tester);

      debugDenseNameWidthOverride = (_, _, _) => 10000;
      // A REAL rebuild with no font change (fresh card widget, new onTap):
      // the memo key is unchanged, so the stale choice must be served.
      await pumpFonts(tester);
      expect(identical(nameText(tester), before), isFalse, reason: 'rebuilt');
      expect(find.text(_kShortFull), findsOneWidget, reason: 'memo holds');

      await fontsChange(tester);
      await tester.pump();
      expect(find.text(_kShortFull), findsNothing);
      expect(find.text(_kShortFirst), findsOneWidget);
    });
  });

  testWidgets('a systemFonts notification rebuilds a dense card next frame', (
    WidgetTester tester,
  ) async {
    await pumpFonts(tester);
    final Widget before = nameText(tester);
    await fontsChange(tester);
    expect(identical(nameText(tester), before), isTrue, reason: 'deferred');
    await tester.pump();
    expect(identical(nameText(tester), before), isFalse);
    expect(find.text(_kShortFull), findsOneWidget);
  });

  // Frame callbacks the engine's own listeners (every RenderParagraph) queue
  // on `fontsChange` are the same for every card, so the card's OWN scheduling
  // is the difference against a card that does not listen.
  Future<int> fontsDelta(
    WidgetTester tester, {
    required double? laneWidth,
    required int messages,
  }) async {
    await pumpFonts(tester, laneWidth: laneWidth);
    final int base = tester.binding.transientCallbackCount;
    for (int i = 0; i < messages; i++) {
      await fontsChange(tester);
    }
    final int delta = tester.binding.transientCallbackCount - base;
    await tester.pump();
    return delta;
  }

  testWidgets('two fontsChange messages in one frame schedule ONE rebuild', (
    WidgetTester tester,
  ) async {
    final int idle = await fontsDelta(tester, laneWidth: null, messages: 1);
    final int one = await fontsDelta(tester, laneWidth: 136, messages: 1);
    final int two = await fontsDelta(tester, laneWidth: 136, messages: 2);
    expect(one - idle, 1, reason: 'a dense card schedules exactly one');
    expect(two, one, reason: 'a second notification coalesces');
  });

  for (final ({String name, bool dense, double? lane}) c
      in <({String name, bool dense, double? lane})>[
        (name: 'non-dense card', dense: false, lane: null),
        (name: 'dense card without laneWidth', dense: true, lane: null),
      ]) {
    testWidgets('a ${c.name} does not listen or rebuild on fontsChange', (
      WidgetTester tester,
    ) async {
      await pumpFonts(tester, dense: c.dense, laneWidth: c.lane);
      final Finder name = find.textContaining('Оля');
      final Widget before = tester.widget(name.first);
      await fontsChange(tester);
      await tester.pump();
      expect(identical(tester.widget(name.first), before), isTrue);
    });
  }

  testWidgets('full @136dp: a price band is not FittedBox-shrunk', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      minHeight: 126,
      lane: 136,
      booking: _booking(priceMax: 2500),
    );
    final Finder price = find.textContaining('1250');
    final Finder box = find.ancestor(
      of: price,
      matching: find.byType(FittedBox),
    );
    expect(
      tester.getSize(box.first).width,
      greaterThanOrEqualTo(tester.getSize(price).width - 0.1),
    );
  });

  testWidgets('non-dense default keeps the standard layout', (
    WidgetTester tester,
  ) async {
    await tester.pumpApp(
      Center(
        child: SizedBox(
          width: 272,
          child: MasterBookingCard(
            booking: _booking(),
            onTap: () {},
            minHeight: 126,
          ),
        ),
      ),
    );
    expect(
      MasterBookingCard.occupiedHeightFor(126),
      MasterBookingCard.occupiedHeightFor(126, dense: false),
    );
    expect(find.text(_kClientFull), findsOneWidget);
  });

  // The master-mode «Записи» board (272dp lanes) is a NON-dense caller: it must
  // keep the standard layout — the time range in the compact row and the
  // 10.2sp price token with its natural line box — while the dense layout
  // drops the range and pins the price line box to 14.4dp.
  for (final ({String name, double minHeight}) c
      in <({String name, double minHeight})>[
        (name: 'compact', minHeight: 56),
        (name: 'full', minHeight: 126),
      ]) {
    testWidgets('non-dense ${c.name} @272dp keeps the 10.2sp price token', (
      WidgetTester tester,
    ) async {
      await tester.pumpApp(
        Center(
          child: SizedBox(
            width: 272,
            child: MasterBookingCard(
              booking: _booking(),
              onTap: () {},
              minHeight: c.minHeight,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      final RenderParagraph price = tester.renderObject<RenderParagraph>(
        find.textContaining('1250'),
      );
      expect(
        price.text.style?.fontSize,
        VelvetText.masterCardPricePill.fontSize,
      );
      expect(
        price.text.style?.height,
        isNot(VelvetText.masterCardPricePillDense.height),
      );

      final Booking b = _booking();
      if (c.name == 'compact') {
        expect(
          find.text(formatSlotTimeRange(b.startAt, b.endAt)),
          findsOneWidget,
          reason: 'the standard compact row keeps the time range',
        );
      }
    });
  }

  // Regression (fix/review-stars-fill-and-salon-card-price, user 2026-11-16):
  // the salon board's DENSE card must render the SAME price pill as the
  // master's one-day (non-dense) card at the same tier. Both cards are pumped
  // side by side and compared on what renders: the pill's laid-out size (pins
  // padding + font + line box), the painted inset well, and the price
  // paragraph's resolved style (size, weight, colour).
  for (final ({String name, double dense, double standard, Size pill}) c
      in <({String name, double dense, double standard, Size pill})>[
        (name: 'compact', dense: 84, standard: 56, pill: _kCompactPill),
        (name: 'full', dense: 126, standard: 126, pill: _kFullPill),
      ]) {
    testWidgets('${c.name}: the dense price pill renders identically to the '
        'non-dense one', (WidgetTester tester) async {
      await tester.pumpApp(
        RepaintBoundary(
          key: kCensusBoundary,
          child: ColoredBox(
            color: BrandColors.base,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  key: const Key('parity-dense'),
                  width: 148,
                  child: MasterBookingCard(
                    booking: _booking(),
                    onTap: () {},
                    minHeight: c.dense,
                    dense: true,
                    laneWidth: 148,
                  ),
                ),
                SizedBox(
                  key: const Key('parity-standard'),
                  width: 272,
                  child: MasterBookingCard(
                    booking: _booking(),
                    onTap: () {},
                    minHeight: c.standard,
                  ),
                ),
              ],
            ),
          ),
        ),
        width: 400,
        height: 600,
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      Finder pill(String card) => find.descendant(
        of: find.byKey(Key(card)),
        matching: find.byType(PriceTag),
      );
      TextStyle priceStyle(String card) => tester
          .renderObject<RenderParagraph>(
            find.descendant(
              of: find.byKey(Key(card)),
              matching: find.textContaining('1250'),
            ),
          )
          .text
          .style!;

      final Raster raster = await rasterize(tester);

      for (final String card in <String>['parity-dense', 'parity-standard']) {
        final Size size = tester.getSize(pill(card));
        expect(size.width, closeTo(c.pill.width, 0.1), reason: card);
        expect(size.height, c.pill.height, reason: card);
      }
      // The pill's recessed well, read from pixels: its left padding strip
      // (no glyphs) must carry BOTH halves of the inset shadow — a pixel well
      // below and one above the base ground. The pill's FILL is base, the same
      // as the card and host behind it, so a fill check could never fail.
      for (final String card in <String>['parity-dense', 'parity-standard']) {
        final Rect r = tester.getRect(pill(card));
        final List<int> sums =
            raster
                .colorsIn(
                  Rect.fromLTWH(r.left, r.top, VelvetSpacing.sm, r.height),
                )
                .map(((int, int, int) p) => p.$1 + p.$2 + p.$3)
                .toList()
              ..sort();
        expect(
          sums.first,
          lessThan(_kBaseSum - _kInsetDarkDelta),
          reason: '$card: the inset well paints its dark inner shadow',
        );
        expect(
          sums.last,
          greaterThan(_kBaseSum + _kInsetLightDelta),
          reason: '$card: the inset well paints its light inner shadow',
        );
      }

      final TextStyle dense = priceStyle('parity-dense');
      final TextStyle standard = priceStyle('parity-standard');
      expect(dense.fontSize, 10.2);
      expect(standard.fontSize, 10.2);
      expect(dense.fontWeight, standard.fontWeight);
      expect(dense.color, standard.color);
    });
  }

  testWidgets('dense drops the time range that the standard card shows', (
    WidgetTester tester,
  ) async {
    await _pump(tester, minHeight: 84, lane: 148);
    final Booking b = _booking();
    expect(find.text(formatSlotTimeRange(b.startAt, b.endAt)), findsNothing);
  });
}

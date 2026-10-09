// The DENSE (salon board) layout of MasterBookingCard: on a 136-148dp lane the
// client surname, the service name and a readable price must all be visible.
// Non-dense behaviour is pinned by master_booking_card_test.dart and the
// goldens, which this change must not move.

import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_booking_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:flutter_test/flutter_test.dart';

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
          expect(tester.widget<Text>(price).style?.fontSize, 12);
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

  testWidgets('full @136dp: a price band is not shrunk below 12sp', (
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
  // 10.2sp price token — while the dense layout drops the range and uses 12sp.
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
      expect(price.text.style?.fontSize, isNot(12));

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

  testWidgets('dense drops the time range that the standard card shows', (
    WidgetTester tester,
  ) async {
    await _pump(tester, minHeight: 84, lane: 148);
    final Booking b = _booking();
    expect(find.text(formatSlotTimeRange(b.startAt, b.endAt)), findsNothing);
  });
}

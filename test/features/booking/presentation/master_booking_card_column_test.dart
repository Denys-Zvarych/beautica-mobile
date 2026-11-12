// Phase 481 — `MasterBookingCard(column: true)`: the «3 дні» narrow-column
// density, and `fillServices` on the column / compact / full bodies.
//
// Expected line sets are DERIVED, not measured: every line renders through
// `FixedLinesText`, whose box is `ceil(scaledFontSize × 1.2)`. Inner height =
// block − 3 (1.5 dp border × 2) − 4 (2 dp vertical padding × 2).
//   scale 1.0: range 12 + name 14 = 26 (two-line), + 1 gap + service 12 = 39
//   scale 1.3: range 16 + name 18 = 34 (two-line), + 1 gap + service 16 = 51
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_status_badge.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_booking_card.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:beautica_mobile/shared/widgets/fixed_lines_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph, SemanticsNode;
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/pump_app.dart';

const String _kId = 'col';
const String _kFirst = 'Олена';
const String _kService =
    'Манікюр з покриттям гель-лак, корекція брів, ламінування вій';
const double _kWidth = 100;

Booking _booking({
  BookingStatus status = BookingStatus.confirmed,
  String service = _kService,
  int minutes = 90,
}) {
  // future-date-ok: pinned Kyiv wall-clock fixture (10:00–11:30 Kyiv).
  final DateTime startAt = DateTime.utc(2026, 7, 20, 7);
  return Booking(
    id: _kId,
    masterId: 'master-1',
    masterFirstName: 'Оля',
    masterLastName: 'Коваль',
    masterType: 'INDEPENDENT_MASTER',
    clientFirstName: _kFirst,
    clientLastName: 'Коваленко',
    serviceId: 'service-1',
    serviceName: service,
    durationMinutes: minutes,
    price: 1250,
    startAt: startAt,
    endAt: startAt.add(Duration(minutes: minutes)),
    status: status,
    canReview: false,
  );
}

Future<void> _pumpColumn(
  WidgetTester tester, {
  required double? height,
  double width = _kWidth,
  double scale = 1.0,
  Booking? booking,
  bool fillServices = false,
  VoidCallback? onTap,
}) async {
  final Widget card = MasterBookingCard(
    booking: booking ?? _booking(),
    onTap: onTap ?? () {},
    column: true,
    fillServices: fillServices,
  );
  await tester.pumpApp(
    Center(
      child: SizedBox(width: width, height: height, child: card),
    ),
    textScaleFactor: scale,
  );
}

RenderParagraph _paragraphOf(WidgetTester tester, Finder text) =>
    tester.renderObject<RenderParagraph>(
      find.descendant(of: text, matching: find.byType(RichText)),
    );

// The preview's «3 дні» grid on a 360 dp phone (`week_time_grid.dart`):
// ruler 44, three columns, 2 dp side pad each side; hour 72 × max(1, scale),
// 2 dp gap between blocks.
const double _k360ColumnWidth = (360 - 44) / 3 - 2 * 2;
double _thirtyMinHeight(double scale) => 72 * (scale < 1 ? 1 : scale) / 2 - 2;

Finder _layoutKey(int lines) =>
    find.byKey(Key('master-booking-card-column-$lines-$_kId'));

int _renderedLines() {
  for (final int n in <int>[3, 2, 1]) {
    if (_layoutKey(n).evaluate().isNotEmpty) return n;
  }
  return 0;
}

Finder get _card => find.byKey(const Key('master-booking-card-$_kId'));

String _range(Booking b) => formatSlotTimeRange(b.startAt, b.endAt);

void main() {
  // (height, scale) → (line set, service lines with fillServices).
  final Map<(double, double), (int, int)> expected =
      <(double, double), (int, int)>{
        (34, 1.0): (2, 0),
        (45, 1.0): (2, 0),
        (60, 1.0): (3, 2),
        (90, 1.0): (3, 4),
        (34, 1.3): (1, 0),
        (45, 1.3): (2, 0),
        (60, 1.3): (3, 1),
        (90, 1.3): (3, 3),
      };

  group('content by height × text scale', () {
    for (final MapEntry<(double, double), (int, int)> e in expected.entries) {
      final double h = e.key.$1;
      final double scale = e.key.$2;
      final int lines = e.value.$1;
      final int serviceLines = e.value.$2;

      testWidgets('${h.toInt()} dp @ ${scale}x → $lines-line layout, range '
          'present, no overflow', (WidgetTester tester) async {
        await _pumpColumn(tester, height: h, scale: scale, fillServices: true);

        expect(tester.takeException(), isNull);
        expect(_renderedLines(), lines);
        expect(
          find.descendant(
            of: _card,
            matching: find.textContaining(_range(_booking())),
          ),
          findsOneWidget,
          reason: 'the start–end range is on every column layout',
        );
        expect(
          find.descendant(of: _card, matching: find.textContaining(_kFirst)),
          findsOneWidget,
        );
        expect(tester.getSize(_card).height, h);
        if (lines == 3) {
          final Text service = tester.widget<Text>(
            find.descendant(of: _card, matching: find.text(_kService)),
          );
          expect(service.maxLines, serviceLines);
        } else {
          expect(
            find.descendant(of: _card, matching: find.text(_kService)),
            findsNothing,
          );
        }
      });
    }

    testWidgets('without fillServices the 3-line layout keeps ONE service '
        'line', (WidgetTester tester) async {
      await _pumpColumn(tester, height: 90);
      expect(_renderedLines(), 3);
      final Text service = tester.widget<Text>(
        find.descendant(of: _card, matching: find.text(_kService)),
      );
      expect(service.maxLines, 1);
    });

    testWidgets('unbounded height → 3-line layout, one service line, no '
        'overflow', (WidgetTester tester) async {
      // A Column hands its child an UNBOUNDED height.
      await tester.pumpApp(
        Center(
          child: SizedBox(
            width: _kWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                MasterBookingCard(
                  booking: _booking(),
                  onTap: () {},
                  column: true,
                  fillServices: true,
                ),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(_renderedLines(), 3);
      final Text service = tester.widget<Text>(
        find.descendant(of: _card, matching: find.text(_kService)),
      );
      expect(service.maxLines, 1);
    });

    testWidgets('a LOOSE bounded parent never stretches a fillServices block '
        '— it keeps its natural 3-line height', (WidgetTester tester) async {
      // Center → loose constraints bounded by the viewport.
      await _pumpColumn(tester, height: null, fillServices: true);
      expect(tester.takeException(), isNull);
      expect(_renderedLines(), 3);
      // Exactly ONE service line, and the block is exactly its natural
      // height: border 2 x 1.5 + v-pad 2 x 2 + range + name + gap 1 + one
      // service line, each line from `fixedLineHeight`.
      final Text service = tester.widget<Text>(
        find.descendant(of: _card, matching: find.text(_kService)),
      );
      expect(service.maxLines, 1);
      final BuildContext ctx = tester.element(_card);
      final double natural =
          3 +
          4 +
          fixedLineHeight(ctx, VelvetText.weekBlockTime) +
          fixedLineHeight(ctx, VelvetText.weekBlockName) +
          1 +
          fixedLineHeight(ctx, VelvetText.weekBlockService);
      expect(tester.getSize(_card).height, closeTo(natural, 0.01));
    });

    testWidgets('one-line fallback reads «10:00–11:30 Олена»', (
      WidgetTester tester,
    ) async {
      await _pumpColumn(tester, height: 34, scale: 1.3);
      expect(_renderedLines(), 1);
      expect(
        find.descendant(
          of: _card,
          matching: find.text('${_range(_booking())} $_kFirst'),
        ),
        findsOneWidget,
      );
    });
  });

  group('type floor', () {
    for (final double scale in <double>[1.0, 1.3]) {
      for (final double h in <double>[34, 90]) {
        testWidgets('no text below 10 sp (${h.toInt()} dp @ ${scale}x)', (
          WidgetTester tester,
        ) async {
          await _pumpColumn(
            tester,
            height: h,
            scale: scale,
            fillServices: true,
          );
          final Iterable<RichText> paragraphs = tester.widgetList<RichText>(
            find.descendant(of: _card, matching: find.byType(RichText)),
          );
          expect(paragraphs, isNotEmpty);
          for (final RichText p in paragraphs) {
            p.text.visitChildren((InlineSpan span) {
              final double? size = span.style?.fontSize;
              if (size != null) {
                expect(size, greaterThanOrEqualTo(10));
              }
              return true;
            });
            final double? root = p.text.style?.fontSize;
            if (root != null) expect(root, greaterThanOrEqualTo(10));
          }
        });
      }
    }
  });

  group('status', () {
    for (final BookingStatus status in <BookingStatus>[
      BookingStatus.confirmed,
      BookingStatus.completed,
      BookingStatus.notCompleted,
      BookingStatus.cancelled,
      BookingStatus.declined,
    ]) {
      final bool gone =
          status == BookingStatus.cancelled || status == BookingStatus.declined;

      testWidgets('${status.name}: stripe colour from BookingStatusVisual'
          '${gone ? ', faded' : ''}', (WidgetTester tester) async {
        final Booking b = _booking(status: status);
        await _pumpColumn(tester, height: 60, booking: b);
        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(_card),
        );
        final Color accent = BookingStatusVisual.of(b, l10n).accent;
        final ColoredBox stripe = tester.widget<ColoredBox>(
          find.byKey(const Key('master-booking-card-stripe-$_kId')),
        );
        expect(stripe.color, gone ? accent.withValues(alpha: 0.55) : accent);
        expect(
          tester
              .getSize(
                find.byKey(const Key('master-booking-card-stripe-$_kId')),
              )
              .width,
          3,
        );
      });

      testWidgets('${status.name}: name ${gone ? 'IS' : 'is NOT'} struck '
          'through; lift ${gone ? 'dropped' : 'kept'}', (
        WidgetTester tester,
      ) async {
        await _pumpColumn(
          tester,
          height: 60,
          booking: _booking(status: status),
        );
        final Text name = tester.widget<Text>(
          find.descendant(of: _card, matching: find.text(_kFirst)),
        );
        expect(
          name.style?.decoration,
          gone ? TextDecoration.lineThrough : isNot(TextDecoration.lineThrough),
        );
        final AnimatedContainer box = tester.widget<AnimatedContainer>(
          find.descendant(of: _card, matching: find.byType(AnimatedContainer)),
        );
        final BoxDecoration deco = box.decoration! as BoxDecoration;
        expect(deco.borderRadius, BorderRadius.circular(16));
        expect(deco.boxShadow == null || deco.boxShadow!.isEmpty, gone);
        if (!gone) {
          // Goldens run with `renderShadows: false`, so the light column
          // lift (phase 482 perf audit) is pinned here.
          expect(deco.boxShadow, same(VelvetShadows.columnCard));
        }
      });
    }
  });

  testWidgets('tap by key fires onTap', (WidgetTester tester) async {
    int taps = 0;
    await _pumpColumn(tester, height: 45, onTap: () => taps++);
    await tester.tap(_card);
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  group('fillServices on the shipped bodies', () {
    Future<void> pumpCompact(
      WidgetTester tester, {
      required bool tight,
      double scale = 1.0,
    }) async {
      final Widget card = MasterBookingCard(
        booking: _booking(),
        onTap: () {},
        minHeight: 90,
        fillServices: true,
      );
      await tester.pumpApp(
        Center(
          child: SizedBox(width: 300, height: tight ? 90 : null, child: card),
        ),
        textScaleFactor: scale,
      );
    }

    for (final double scale in <double>[1.0, 1.3]) {
      testWidgets('compact at a TIGHT height: service takes every whole line '
          '(${scale}x)', (WidgetTester tester) async {
        await pumpCompact(tester, tight: true, scale: scale);
        expect(tester.takeException(), isNull);
        final Text service = tester.widget<Text>(
          find.descendant(of: _card, matching: find.text(_kService)),
        );
        expect(service.maxLines, greaterThan(1));
      });
    }

    testWidgets('compact in a LOOSE parent keeps the shipped one line', (
      WidgetTester tester,
    ) async {
      await pumpCompact(tester, tight: false);
      final Text service = tester.widget<Text>(
        find.descendant(of: _card, matching: find.text(_kService)),
      );
      expect(service.maxLines, 1);
      expect(tester.getSize(_card).height, 90);
    });

    testWidgets('full at a TIGHT height: service fills, no overflow', (
      WidgetTester tester,
    ) async {
      await tester.pumpApp(
        Center(
          child: SizedBox(
            width: 300,
            height: 180,
            child: MasterBookingCard(
              booking: _booking(),
              onTap: () {},
              minHeight: 180,
              fillServices: true,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const Key('master-booking-card-divider-$_kId')),
        findsOneWidget,
      );
      final Text service = tester.widget<Text>(
        find.descendant(of: _card, matching: find.text(_kService)),
      );
      expect(service.maxLines, greaterThan(1));
    });
  });

  // QA (phase 481) — the real 30-minute block on a 360 dp phone, the one
  // that has to survive textScaler 1.3.
  group('30-min block at a 360 dp phone column', () {
    for (final double scale in <double>[1.0, 1.3]) {
      testWidgets('@ ${scale}x shows the full range + name, no overflow, '
          'range not ellipsized', (WidgetTester tester) async {
        final Booking b = _booking(minutes: 30);
        await _pumpColumn(
          tester,
          height: _thirtyMinHeight(scale),
          width: _k360ColumnWidth,
          scale: scale,
          booking: b,
          fillServices: true,
        );

        expect(tester.takeException(), isNull);
        expect(_renderedLines(), 2);
        final Finder range = find.descendant(
          of: _card,
          matching: find.text('10:00–10:30'),
        );
        expect(range, findsOneWidget);
        expect(_paragraphOf(tester, range).didExceedMaxLines, isFalse);
        final Finder name = find.descendant(
          of: _card,
          matching: find.text(_kFirst),
        );
        expect(name, findsOneWidget);
        expect(_paragraphOf(tester, name).didExceedMaxLines, isFalse);
        // Both lines sit inside the block, not clipped by its bottom edge.
        expect(
          tester.getRect(name).bottom,
          lessThanOrEqualTo(tester.getRect(_card).bottom),
        );
      });
    }

    testWidgets('one-line fallback reads exactly «10:00–10:30 Олена»', (
      WidgetTester tester,
    ) async {
      final Booking b = _booking(minutes: 30);
      await _pumpColumn(
        tester,
        height: 30,
        width: _k360ColumnWidth,
        booking: b,
      );
      expect(tester.takeException(), isNull);
      expect(_renderedLines(), 1);
      expect(
        // i18n-finder-ok: «Олена» is client-name fixture data and the range is
        // formatter output — locale-invariant, not localized copy.
        find.descendant(of: _card, matching: find.text('10:00–10:30 Олена')),
        findsOneWidget,
      );
    });
  });

  group('services fill WHOLE lines and end with «…»', () {
    for (final (double h, double scale) in <(double, double)>[
      (90, 1.0),
      (90, 1.3),
      (60, 1.0),
    ]) {
      testWidgets('${h.toInt()} dp @ ${scale}x: the service paragraph is a '
          'whole number of lines, ellipsized, inside the block', (
        WidgetTester tester,
      ) async {
        await _pumpColumn(tester, height: h, scale: scale, fillServices: true);
        expect(tester.takeException(), isNull);
        final Finder service = find.descendant(
          of: _card,
          matching: find.text(_kService),
        );
        final Text text = tester.widget<Text>(service);
        final RenderParagraph p = _paragraphOf(tester, service);
        final double line = (10 * scale * 1.2).ceilToDouble();

        expect(text.overflow, TextOverflow.ellipsis);
        expect(p.didExceedMaxLines, isTrue, reason: 'last line ends with «…»');
        expect(p.size.height, closeTo(text.maxLines! * line, 0.01));
        // No half line: the paragraph ends inside the card's inner box
        // (border 1.5 + v-pad 2).
        expect(
          tester.getRect(service).bottom,
          lessThanOrEqualTo(tester.getRect(_card).bottom - 3.5 + 0.01),
        );
        // ...and EVERY whole line is taken: less than one line left unused.
        expect(
          tester.getRect(_card).bottom - 3.5 - tester.getRect(service).bottom,
          lessThan(line),
        );
        expect(text.maxLines, greaterThan(1));
      });
    }
  });

  group('fillServices is a no-op under LOOSE constraints', () {
    testWidgets('full body in a loose parent keeps the shipped one line', (
      WidgetTester tester,
    ) async {
      await tester.pumpApp(
        Center(
          child: SizedBox(
            width: 300,
            child: MasterBookingCard(
              booking: _booking(),
              onTap: () {},
              minHeight: 180,
              fillServices: true,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const Key('master-booking-card-divider-$_kId')),
        findsOneWidget,
      );
      final Text service = tester.widget<Text>(
        find.descendant(of: _card, matching: find.text(_kService)),
      );
      expect(service.maxLines, 1);
      expect(tester.getSize(_card).height, 180);
    });

    testWidgets(
      'column in a loose bounded parent: service is ONE line, same '
      'height as without fillServices',
      (WidgetTester tester) async {
        await _pumpColumn(tester, height: null);
        final double plain = tester.getSize(_card).height;

        await _pumpColumn(tester, height: null, fillServices: true);
        final Text service = tester.widget<Text>(
          find.descendant(of: _card, matching: find.text(_kService)),
        );
        expect(service.maxLines, 1);
        expect(tester.getSize(_card).height, plain);
      },
      // Regression (phase 481 audit): the column body used to fill whenever
      // the height was merely BOUNDED, so a loose parent gave the service
      // floor(viewport / line) lines and grew the block. It now gates on a
      // TIGHT height, like the full / compact bodies.
    );
  });

  group(
    'defaults (column: false, fillServices: false) are the shipped card',
    () {
      testWidgets('no column body, no stripe, card radius 24, lift kept', (
        WidgetTester tester,
      ) async {
        await tester.pumpApp(
          Center(
            child: SizedBox(
              width: _kWidth,
              height: 60,
              child: MasterBookingCard(booking: _booking(), onTap: () {}),
            ),
          ),
        );
        for (final int n in <int>[1, 2, 3]) {
          expect(_layoutKey(n), findsNothing);
        }
        expect(
          find.byKey(const Key('master-booking-card-stripe-$_kId')),
          findsNothing,
        );
        final AnimatedContainer box = tester.widget<AnimatedContainer>(
          find
              .descendant(of: _card, matching: find.byType(AnimatedContainer))
              .first,
        );
        final BoxDecoration deco = box.decoration! as BoxDecoration;
        expect(deco.borderRadius, BorderRadius.circular(24));
        expect(deco.boxShadow, isNotEmpty);
        expect(
          deco.boxShadow,
          same(VelvetShadows.borderedCard),
          reason: 'default cards keep the shipped lift',
        );
      });

      testWidgets('a compact card at a TIGHT height keeps ONE service line '
          'and builds no measuring LayoutBuilder', (WidgetTester tester) async {
        await tester.pumpApp(
          Center(
            child: SizedBox(
              width: 300,
              height: 90,
              child: MasterBookingCard(
                booking: _booking(),
                onTap: () {},
                minHeight: 90,
              ),
            ),
          ),
        );
        final Text service = tester.widget<Text>(
          find.descendant(of: _card, matching: find.text(_kService)),
        );
        expect(service.maxLines, 1);
        expect(
          find.descendant(of: _card, matching: find.byType(LayoutBuilder)),
          findsNothing,
        );
      });
    },
  );

  testWidgets('column semantics carry the range and the status label', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await _pumpColumn(tester, height: 34);
    final SemanticsNode node = tester.getSemantics(_card);
    expect(node.value, contains(_range(_booking())));
    final AppLocalizations l10n = AppLocalizations.of(tester.element(_card));
    expect(
      node.value,
      contains(BookingStatusVisual.of(_booking(), l10n).label),
    );
    handle.dispose();
  });

  test('columnCard is borderedCard\'s halo at no more than half the blur', () {
    expect(VelvetShadows.columnCard, hasLength(1));
    final BoxShadow light = VelvetShadows.columnCard.single;
    final BoxShadow base = VelvetShadows.borderedCard.single;
    expect(light.offset, Offset.zero, reason: 'Impeller-safe, non-offset');
    expect(light.color, base.color);
    expect(light.blurRadius, lessThanOrEqualTo(base.blurRadius / 2));
  });
}

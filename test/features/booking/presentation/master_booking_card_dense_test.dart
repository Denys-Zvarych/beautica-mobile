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

Booking _booking({double? priceMax}) {
  // future-date-ok: pinned Kyiv wall-clock fixture.
  final DateTime startAt = DateTime.utc(2026, 7, 20, 6);
  return Booking(
    id: 'dense-1',
    masterId: 'master-1',
    masterFirstName: 'Оля',
    masterLastName: 'Коваль',
    masterType: 'SALON_MASTER',
    clientFirstName: _kClientFirst,
    clientLastName: _kClientLast,
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
        ),
      ),
    ),
  );
  await tester.pump();
  expect(tester.takeException(), isNull);
}

bool _truncated(WidgetTester tester, Finder f) {
  final RenderParagraph p = tester.renderObject<RenderParagraph>(f);
  return p.didExceedMaxLines;
}

void main() {
  for (final ({String name, double minHeight}) c
      in <({String name, double minHeight})>[
        (name: 'compact', minHeight: 84),
        (name: 'full', minHeight: 126),
      ]) {
    for (final double lane in <double>[136, 148]) {
      testWidgets('${c.name} @${lane}dp: surname, service and price show', (
        WidgetTester tester,
      ) async {
        await _pump(tester, minHeight: c.minHeight, lane: lane);

        final Finder name = find.text(_kClientFull);
        expect(name, findsOneWidget);
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
      });
    }
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

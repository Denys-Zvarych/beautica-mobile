// M509 — the three ADDITIVE params on BookingClientStrip (`details`, `onTap`,
// `semanticsLabel`) and the proof that omitting them leaves the strip as the
// booking detail / reschedule confirm render it.

import 'package:beautica_mobile/features/booking/presentation/widgets/booking_client_strip.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_strip_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

const Key _detailsKey = Key('strip-details-probe');

void main() {
  group('defaults (booking detail + reschedule confirm)', () {
    testWidgets('no onTap → inert shell, no button semantics, no details', (
      tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpApp(
        const BookingClientStrip(
          name: 'Оксана Мельник',
          rating: 4.9,
          reviewCount: 12,
        ),
      );
      final MasterStripShell shell = tester.widget<MasterStripShell>(
        find.byType(MasterStripShell),
      );
      expect(shell.onTap, isNull);
      expect(shell.middleLine, isNull, reason: 'no qualifier, no details');
      expect(find.byType(InkWell), findsNothing);
      handle.dispose();
    });

    testWidgets('a guest still shows the qualifier and NO ★ readout', (
      tester,
    ) async {
      await tester.pumpApp(
        const BookingClientStrip(name: 'Ірина', isGuest: true),
      );
      // i18n-finder-ok: asserts the exact approved UA copy / data value
      expect(find.text('Запис за посиланням'), findsOneWidget);
      expect(find.text('—'), findsNothing);
    });

    testWidgets('the computed semantics label is used when none is given', (
      tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpApp(
        const BookingClientStrip(name: 'Оксана', rating: 4.9, reviewCount: 12),
      );
      final SemanticsNode node = tester.getSemantics(
        find.byKey(BookingClientStrip.defaultShellKey),
      );
      expect(node.label, contains('Оксана'));
      expect(node.label, contains('4.9'));
      handle.dispose();
    });
  });

  group('additive params', () {
    testWidgets('details render in the sub-line, under the guest qualifier', (
      tester,
    ) async {
      await tester.pumpApp(
        const BookingClientStrip(
          name: 'Ірина',
          isGuest: true,
          details: Text('Ост.: 7 лис', key: _detailsKey),
        ),
      );
      expect(find.byKey(_detailsKey), findsOneWidget);
      // i18n-finder-ok: asserts the exact approved UA copy / data value
      expect(find.text('Запис за посиланням'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(_detailsKey)).dy,
        // i18n-finder-ok: asserts the exact approved UA copy / data value
        greaterThan(tester.getTopLeft(find.text('Запис за посиланням')).dy),
      );
    });

    testWidgets('details alone (no qualifier) still render', (tester) async {
      await tester.pumpApp(
        const BookingClientStrip(
          name: 'Оксана',
          details: Text('Наст.: пт', key: _detailsKey),
        ),
      );
      expect(find.byKey(_detailsKey), findsOneWidget);
    });

    testWidgets('onTap is forwarded to the shell and fires on tap', (
      tester,
    ) async {
      int taps = 0;
      await tester.pumpApp(
        BookingClientStrip(name: 'Оксана', onTap: () => taps++),
      );
      expect(
        tester.widget<MasterStripShell>(find.byType(MasterStripShell)).onTap,
        isNotNull,
      );
      await tester.tap(find.byKey(BookingClientStrip.defaultShellKey));
      expect(taps, 1);
    });

    testWidgets('semanticsLabel replaces the computed label', (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpApp(
        const BookingClientStrip(
          name: 'Оксана',
          rating: 4.9,
          reviewCount: 12,
          semanticsLabel: 'власний підпис',
        ),
      );
      final SemanticsNode node = tester.getSemantics(
        find.byKey(BookingClientStrip.defaultShellKey),
      );
      expect(node.label, contains('власний підпис'));
      expect(node.label, isNot(contains('4.9')));
      handle.dispose();
    });
  });
}

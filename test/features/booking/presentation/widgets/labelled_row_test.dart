// Widget tests for the shared booking atoms `LabelledRow` + `SectionRule`
// (`lib/features/booking/presentation/widgets/labelled_row.dart`,
// `.../section_rule.dart`).
//
// Both were extracted from the private `_LabelledRow` / `_SectionRule` that
// were byte-duplicated across `booking_summary_cards.dart` (independent flow)
// and `salon_appointment_card.dart` (salon flow) in the widget-consolidation
// refactor. These are light render/param tests pinning the parameter contract
// both composition sites now depend on — the `detail` sub-line only renders
// when supplied, and the `compactText` / `dense` "success-screen" variants
// swap the styling notch without dropping content.
//
// Text is asserted against fixture strings the test itself supplies (not app
// l10n copy), so these finders are i18n-finder-ok.

import 'package:beautica_mobile/features/booking/presentation/widgets/labelled_row.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/section_rule.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

void main() {
  group('LabelledRow', () {
    testWidgets('renders the label above its value', (tester) async {
      await tester.pumpApp(
        const LabelledRow(label: 'Дата', value: 'вт, 14 лип'),
      );
      await tester.pumpAndSettle();

      // i18n-finder-ok: fixture strings supplied by this test, not app copy.
      expect(find.text('Дата'), findsOneWidget);
      // i18n-finder-ok: fixture value, not app copy.
      expect(find.text('вт, 14 лип'), findsOneWidget);
    });

    testWidgets('omits the detail sub-line when detail is null', (
      tester,
    ) async {
      await tester.pumpApp(const LabelledRow(label: 'Час', value: '14:00'));
      await tester.pumpAndSettle();

      // Only label + value → exactly two Text descendants, no third line.
      expect(
        find.descendant(
          of: find.byType(LabelledRow),
          matching: find.byType(Text),
        ),
        findsNWidgets(2),
      );
    });

    testWidgets('renders the detail sub-line when detail is supplied', (
      tester,
    ) async {
      await tester.pumpApp(
        const LabelledRow(
          label: 'Адреса',
          value: 'вул. Хрещатик, 1',
          detail: 'Київ',
        ),
      );
      await tester.pumpAndSettle();

      // i18n-finder-ok: fixture strings, not app copy.
      expect(find.text('вул. Хрещатик, 1'), findsOneWidget);
      // i18n-finder-ok: fixture value, not app copy.
      expect(find.text('Київ'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(LabelledRow),
          matching: find.byType(Text),
        ),
        findsNWidgets(3),
      );
    });

    testWidgets('the compactText variant still renders all three lines '
        '(success-screen recap)', (tester) async {
      await tester.pumpApp(
        const LabelledRow(
          label: 'Адреса',
          value: 'вул. Личаківська, 5',
          detail: 'Львів',
          compactText: true,
        ),
      );
      await tester.pumpAndSettle();

      // The notch-smaller variant must not DROP any content — all three lines
      // stay, only the styles differ.
      // i18n-finder-ok: fixture strings, not app copy.
      expect(find.text('Адреса'), findsOneWidget);
      // i18n-finder-ok: fixture value, not app copy.
      expect(find.text('вул. Личаківська, 5'), findsOneWidget);
      // i18n-finder-ok: fixture value, not app copy.
      expect(find.text('Львів'), findsOneWidget);
    });
  });

  group('SectionRule', () {
    // Wrap in a min-height Column so the rule gets LOOSE vertical constraints
    // and sizes to its 1px hairline + padding (a bare `home` gives tight
    // constraints that a Padding would just expand to fill).
    Widget wrap(Widget rule) =>
        Column(mainAxisSize: MainAxisSize.min, children: <Widget>[rule]);

    testWidgets('renders a single hairline Container', (tester) async {
      await tester.pumpApp(wrap(const SectionRule()));
      await tester.pumpAndSettle();

      final Finder rule = find.descendant(
        of: find.byType(SectionRule),
        matching: find.byType(Container),
      );
      expect(rule, findsOneWidget);
      expect(tester.getSize(rule).height, 1);
    });

    testWidgets('dense tightens the vertical inset versus the default rhythm', (
      tester,
    ) async {
      await tester.pumpApp(wrap(const SectionRule()));
      await tester.pumpAndSettle();
      final double defaultHeight = tester
          .getSize(find.byType(SectionRule))
          .height;

      await tester.pumpApp(wrap(const SectionRule(dense: true)));
      await tester.pumpAndSettle();
      final double denseHeight = tester
          .getSize(find.byType(SectionRule))
          .height;

      // Both wrap a 1px hairline; `dense` only shrinks the symmetric padding,
      // so its total occupied height must be strictly less than the default's.
      expect(denseHeight, lessThan(defaultHeight));
    });
  });
}

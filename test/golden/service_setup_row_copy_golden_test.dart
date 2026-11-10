// Phase 468 — the add-services row for a service type the master ALREADY
// offers, switched on again to add a COPY (backend 464/465).
//
// No golden covered `ServiceTypeRowCard` before this file (grep of
// `test/golden/` for `ServiceTypeRowCard|ServiceRowState` found nothing; the
// sibling `service_setup_category_golden_test.dart` covers the category chips
// and headers only), so this is a new file rather than new scenarios on an
// existing one.
//
// SCENARIOS (360dp x {1.0, 1.3})
//   - `owned`: an owned type (owned durations {60}) OFF — «Вже додано» + the
//     include switch it gained in phase 468 — above the same type ON, seeded
//     to the free quick-pick 90 with no error.
//   - `duration_taken`: the owned type ON at the owned duration 60 — red rim +
//     inline `serviceSetupDurationTaken`.
//
// GOLDENS ARE NOT ACCEPTANCE BY THEMSELVES: the `measured ground truth` group
// below pins the behaviour each picture depends on (seeded value, error copy
// present / absent) so a baseline cannot silently capture the wrong state.

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_setup_widgets.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/golden_pump.dart';

const String _typeId = 'type-massage-classic';
const String _typeName = 'Класичний масаж';

ServiceRowState _ownedRow({required bool included, String? duration}) {
  final row = ServiceRowState(
    serviceTypeId: _typeId,
    nameUk: _typeName,
    alreadyAdded: true,
    ownedDurations: const <int>{60},
  );
  if (included) row.included = true;
  if (duration != null) row.duration.text = duration;
  return row;
}

Widget _card(ServiceRowState row) =>
    ServiceTypeRowCard(row: row, resolveRangeError: (_) => null);

Widget _frame(double width, List<Widget> children) => ColoredBox(
  color: BrandColors.base,
  child: SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final Widget c in children) ...<Widget>[
            c,
            const SizedBox(height: 16),
          ],
        ],
      ),
    ),
  ),
);

Widget _ownedFixture(double width) => _frame(width, <Widget>[
  _card(_ownedRow(included: false)),
  _card(_ownedRow(included: true)),
]);

Widget _takenFixture(double width) =>
    _frame(width, <Widget>[_card(_ownedRow(included: true, duration: '60'))]);

Future<AppLocalizations> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('uk'),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.pumpAndSettle();
  return AppLocalizations.of(tester.element(find.byType(Scaffold)));
}

void main() {
  const double width = 360;

  group('owned row copy — measured ground truth (not golden)', () {
    testWidgets('owned fixture: OFF row keeps a switch + «Вже додано»; ON row '
        'is seeded to 90 with no duration-taken error', (tester) async {
      final l10n = await _pump(tester, _ownedFixture(width));

      expect(
        find.byKey(const Key('setup_row_toggle_$_typeId')),
        findsNWidgets(2),
      );
      expect(find.text(l10n.serviceSetupRowAlreadyAdded), findsNWidgets(2));
      expect(find.text(l10n.serviceSetupDurationTaken), findsNothing);
      final EditableText seeded = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const Key('service-setup-duration')),
          matching: find.byType(EditableText),
        ),
      );
      expect(seeded.controller.text, '90');
    });

    testWidgets('taken fixture renders serviceSetupDurationTaken', (
      tester,
    ) async {
      final l10n = await _pump(tester, _takenFixture(width));
      expect(find.text(l10n.serviceSetupDurationTaken), findsOneWidget);
    });
  });

  group('service setup owned-row copy golden', () {
    for (final double scale in kGoldenTextScales) {
      goldenTest(
        'owned row OFF + ON (seeded free duration) ${width.toInt()}dp x$scale',
        fileName:
            'service_setup_row_copy_owned_${widthScaleSuffix(width, scale)}',
        constraints: BoxConstraints.tight(const Size(width, 520)),
        textScaleFactor: scale,
        pumpWidget: goldenPumpWidget(width: width),
        builder: () => _ownedFixture(width),
      );
      goldenTest(
        'owned row ON at the owned duration (taken) ${width.toInt()}dp x$scale',
        fileName:
            'service_setup_row_copy_duration_taken_${widthScaleSuffix(width, scale)}',
        constraints: BoxConstraints.tight(const Size(width, 360)),
        textScaleFactor: scale,
        pumpWidget: goldenPumpWidget(width: width),
        builder: () => _takenFixture(width),
      );
    }
  });
}

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
//     include switch it gained in phase 468 — above the same type ON with an
//     EMPTY duration (phase 472 dropped the free quick-pick autofill).
//   - `duration_taken`: the owned type ON at the owned duration 60 — red rim +
//     inline `serviceSetupDurationTaken`.
//   - `extra_copy` (phase 471): a type with an extra copy row — the primary at
//     60 and its «+ додати ще» copy at 90, both with the optional name field
//     and «Прибрати»; the primary also shows «+ додати ще».
//   - `rename` (phase 472, decision D2): an owned type owned TWICE (one copy
//     custom-named) — «Вже додано» then one compact line per copy (name,
//     duration, pencil) — above the same row after the second copy's pencil
//     tap, that line turned into the shared name well (labelled with its
//     duration) carrying a custom name; then a not-owned row switched ON with
//     the name pencil after its title.
//
// GOLDENS ARE NOT ACCEPTANCE BY THEMSELVES: the `measured ground truth` group
// below pins the behaviour each picture depends on (seeded value, error copy
// present / absent) so a baseline cannot silently capture the wrong state.

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
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

ServiceRowState _sessionRow({String? name}) {
  final row = ServiceRowState(serviceTypeId: _typeId, nameUk: _typeName);
  row.included = true;
  row.duration.text = '60';
  row.fixed.text = '500';
  if (name != null) row.name.text = name;
  return row;
}

Widget _copyCard(ServiceRowState row) => ServiceTypeRowCard(
  row: row,
  resolveRangeError: (_) => null,
  onAddCopy: () {},
  onRemove: () {},
  showNameField: true,
);

Widget _extraCopyFixture(double width) {
  final primary = _sessionRow();
  final copy = ServiceRowState.copyOf(primary);
  return _frame(width, <Widget>[_copyCard(primary), _copyCard(copy)]);
}

const List<MasterService> _ownedTwice = <MasterService>[
  MasterService(
    id: 'assign-1',
    serviceDefId: 'def-1',
    name: _typeName,
    serviceTypeId: _typeId,
    durationMinutes: 60,
    priceMin: 500,
    priceDisplay: '500 ₴',
  ),
  MasterService(
    id: 'assign-2',
    serviceDefId: 'def-2',
    // i18n-finder-ok: fixture service name, not UI copy
    name: 'Масаж спини',
    serviceTypeId: _typeId,
    durationMinutes: 90,
    priceMin: 700,
    priceDisplay: '700 ₴',
  ),
];

ServiceRowState _renameRow({String? renamed}) {
  final row = ServiceRowState(
    serviceTypeId: _typeId,
    nameUk: _typeName,
    alreadyAdded: true,
    ownedDurations: const <int>{60, 90},
    ownedServices: _ownedTwice,
  );
  if (renamed != null) {
    final OwnedServiceName second = row.ownedServices.last;
    row.beginRename(second);
    second.controller?.text = renamed;
  }
  return row;
}

Widget _renameFixture(double width) => _frame(width, <Widget>[
  _card(_renameRow()),
  // i18n-finder-ok: user-typed service name fixture, not UI copy
  _card(_renameRow(renamed: 'Авторський масаж')),
  ServiceTypeRowCard(
    row: _sessionRow(),
    resolveRangeError: (_) => null,
    offerCustomName: true,
  ),
]);

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
        'has an EMPTY duration (phase 472) and no duration-taken error', (
      tester,
    ) async {
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
      expect(seeded.controller.text, isEmpty);
    });

    testWidgets('taken fixture renders serviceSetupDurationTaken', (
      tester,
    ) async {
      final l10n = await _pump(tester, _takenFixture(width));
      expect(find.text(l10n.serviceSetupDurationTaken), findsOneWidget);
    });
  });

  group('extra copy row — measured ground truth (not golden)', () {
    testWidgets('both rows show the name field, «Прибрати» and «+ додати ще»; '
        'the copy is seeded to 90', (tester) async {
      final l10n = await _pump(tester, _extraCopyFixture(width));
      expect(find.text(l10n.serviceSetupCopyNameHint), findsNWidgets(2));
      expect(find.text(l10n.serviceSetupRemoveCopy), findsNWidgets(2));
      expect(find.text(l10n.serviceSetupAddCopy), findsNWidgets(2));
      expect(
        find.byKey(const Key('setup_row_name_${_typeId}_copy_1')),
        findsOneWidget,
      );
      expect(find.text('90'), findsOneWidget);
    });
  });

  group('rename pencils — measured ground truth (not golden)', () {
    testWidgets('D2: one pencil per owned copy; the tapped copy is the name '
        'well labelled with its duration; a new ON row has the name pencil', (
      tester,
    ) async {
      final l10n = await _pump(tester, _renameFixture(width));
      expect(
        find.byKey(const Key('btn-setup-row-rename-assign-1')),
        findsNWidgets(2),
      );
      expect(
        find.byKey(const Key('btn-setup-row-rename-assign-2')),
        findsOneWidget,
        reason: 'only the untapped card still shows copy 2 as a line',
      );
      expect(
        find.byKey(const Key('setup_row_rename_assign-2')),
        findsOneWidget,
      );
      expect(find.text(l10n.serviceSetupRenameLabel(90)), findsOneWidget);
      expect(
        // i18n-finder-ok: user-typed service name fixture, not UI copy
        find.text('Авторський масаж'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('btn-setup-row-name-$_typeId')),
        findsOneWidget,
      );
    });
  });

  group('service setup owned-row copy golden', () {
    for (final double scale in kGoldenTextScales) {
      goldenTest(
        'owned row OFF + ON (empty duration) ${width.toInt()}dp x$scale',
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
      goldenTest(
        'type with an extra copy row (phase 471) ${width.toInt()}dp x$scale',
        fileName:
            'service_setup_row_copy_extra_copy_${widthScaleSuffix(width, scale)}',
        constraints: BoxConstraints.tight(const Size(width, 880)),
        textScaleFactor: scale,
        pumpWidget: goldenPumpWidget(width: width),
        builder: () => _extraCopyFixture(width),
      );
      goldenTest(
        'rename pencils per owned copy + new-service name pencil (472 D2) '
        '${width.toInt()}dp x$scale',
        fileName:
            'service_setup_row_copy_rename_${widthScaleSuffix(width, scale)}',
        constraints: BoxConstraints.tight(const Size(width, 760)),
        textScaleFactor: scale,
        pumpWidget: goldenPumpWidget(width: width),
        builder: () => _renameFixture(width),
      );
    }
  });
}

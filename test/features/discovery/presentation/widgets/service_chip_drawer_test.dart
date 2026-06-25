// Phase 13.11 — widget tests for [ServiceChipDrawer] (the second-level
// service-chip well + its active-count badge).
//
// The drawer is a pure StatelessWidget: it renders a keyed [ServiceChip] per
// option, reflects the [selectedKeys] set (check glyph + the «Обрано N» count
// badge), and forwards a tap to [onToggle] with the chip's key. The screen
// wiring (clear-on-category-change, push-time snapshot) is proven end to end in
// integration_test/client_search_flow_test.dart; THIS pins the drawer's own
// render/interaction contract the integration flow assumes:
//   • one keyed chip per option (key = `search_service_chip_<slug>`);
//   • the active-count badge is ABSENT at zero selected and PRESENT with the
//     localized «Обрано N» value once a chip is selected (count reflects the set);
//   • tapping a chip forwards EXACTLY that chip's key to onToggle.
//
// Finders are Key-based; the badge's count copy is asserted via the l10n value
// resolved from the pumped tree (never a hardcoded UA string).

import 'package:beautica_mobile/features/discovery/domain/category_service_option.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/service_chip_drawer.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

const List<CategoryServiceOption> _services = <CategoryServiceOption>[
  CategoryServiceOption(key: 'CLASSIC_MANICURE', displayName: 'Класичний манікюр'),
  CategoryServiceOption(key: 'GEL_MANICURE', displayName: 'Манікюр гель-лак'),
];

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(ServiceChipDrawer)));

Future<void> _pump(
  WidgetTester tester, {
  required Set<String> selectedKeys,
  required ValueChanged<String> onToggle,
}) {
  return tester.pumpApp(
    Scaffold(
      body: ServiceChipDrawer(
        label: 'Послуги · Нігті',
        services: _services,
        selectedKeys: selectedKeys,
        onToggle: onToggle,
      ),
    ),
  );
}

void main() {
  testWidgets('renders one keyed chip per service option', (tester) async {
    await _pump(tester, selectedKeys: const <String>{}, onToggle: (_) {});

    expect(
      find.byKey(const Key('search_service_chip_CLASSIC_MANICURE')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('search_service_chip_GEL_MANICURE')),
      findsOneWidget,
    );
  });

  testWidgets('count badge is ABSENT when nothing is selected', (tester) async {
    await _pump(tester, selectedKeys: const <String>{}, onToggle: (_) {});

    expect(
      find.byKey(const Key('search_services_selected_count')),
      findsNothing,
      reason: 'the active-count badge collapses to nothing at zero selected',
    );
  });

  testWidgets('count badge reflects the selection size («Обрано N»)', (
    tester,
  ) async {
    await _pump(
      tester,
      selectedKeys: const <String>{'CLASSIC_MANICURE', 'GEL_MANICURE'},
      onToggle: (_) {},
    );

    expect(
      find.byKey(const Key('search_services_selected_count')),
      findsOneWidget,
    );
    // The badge shows the localized «Обрано 2» value (count == set size).
    expect(find.text(_l10n(tester).searchServicesSelectedCount(2)), findsOneWidget);
  });

  testWidgets('a single selection shows «Обрано 1» and the selected chip carries '
      'the check glyph', (tester) async {
    await _pump(
      tester,
      selectedKeys: const <String>{'CLASSIC_MANICURE'},
      onToggle: (_) {},
    );

    expect(find.text(_l10n(tester).searchServicesSelectedCount(1)), findsOneWidget);
    // The selected chip renders the camel/mocha "on" treatment with a check.
    expect(
      find.descendant(
        of: find.byKey(const Key('search_service_chip_CLASSIC_MANICURE')),
        matching: find.byIcon(Icons.check_rounded),
      ),
      findsOneWidget,
      reason: 'a selected chip surfaces the check glyph (the "on" state)',
    );
    // The unselected chip carries no check.
    expect(
      find.descendant(
        of: find.byKey(const Key('search_service_chip_GEL_MANICURE')),
        matching: find.byIcon(Icons.check_rounded),
      ),
      findsNothing,
    );
  });

  testWidgets('tapping a chip forwards exactly that chip key to onToggle', (
    tester,
  ) async {
    final List<String> toggled = <String>[];
    await _pump(
      tester,
      selectedKeys: const <String>{},
      onToggle: toggled.add,
    );

    await tester.tap(
      find.byKey(const Key('search_service_chip_GEL_MANICURE')),
    );
    await tester.pumpAndSettle();

    expect(
      toggled,
      <String>['GEL_MANICURE'],
      reason: 'the tapped chip must forward its own key, not a sibling',
    );
  });
}

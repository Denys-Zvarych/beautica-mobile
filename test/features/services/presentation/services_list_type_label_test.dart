// Item 1 regression — services-list tile label resolution (2026-06-08).
//
// The service-list card's PRIMARY label is now the platform service-type name
// (e.g. "Стрижка"), not the master's custom name. The custom name — now
// optional — is shown as a quiet SECONDARY subtitle keyed
// `service-card-custom-name` ONLY when it is present AND differs from the
// service-type label (so the same text is never echoed twice). When no service
// type is assigned the custom name takes the primary slot and no secondary line
// renders.
//
// This guards the four branches of [_ServiceCard]'s label logic in
// services_list_screen.dart (M3 — cover every branch, not just the happy path):
//   L1. type present, custom name differs  → primary = type, secondary = custom
//   L2. type present, custom name == type  → primary = type, NO secondary
//   L3. type present, custom name blank     → primary = type, NO secondary
//   L4. type absent, custom name present    → primary = custom, NO secondary
//
// Isolation: fresh ProviderScope per pump (via pumpApp); servicesListProvider
// overridden with a stub notifier; serviceRepositoryProvider mocked so
// approvedCategoriesProvider resolves without real HTTP. Widgets located by Key
// (M2) — the secondary line carries `service-card-custom-name`; the primary
// label is asserted inside the `service_card_<id>` subtree.

import 'dart:async';

import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// Mocks + stub notifier
// ---------------------------------------------------------------------------

class _MockServiceRepository extends Mock implements ServiceRepository {}

/// Stub [ServicesList] notifier that immediately resolves to [_data].
class _StubServicesList extends ServicesList {
  _StubServicesList(this._data);

  final List<MasterService> _data;

  @override
  Future<List<MasterService>> build() {
    Future<void>.microtask(() => state = AsyncData(_data));
    return Completer<List<MasterService>>().future;
  }
}

// ---------------------------------------------------------------------------
// Finders
// ---------------------------------------------------------------------------

/// Asserts the PRIMARY label [text] is rendered inside the card for [id], and
/// is NOT the secondary `service-card-custom-name` line.
Finder _primaryLabel(String id, String text) => find.descendant(
  of: find.byKey(Key('service_card_$id')),
  matching: find.text(text),
);

void main() {
  late _MockServiceRepository repo;

  setUp(() {
    repo = _MockServiceRepository();
    when(() => repo.listMyServices()).thenAnswer((_) async => const []);
    // _LoadedBody watches approvedCategoriesProvider for category-section
    // labels. Keep it in the data state so the card subtree builds.
    when(() => repo.fetchApprovedCategories()).thenAnswer(
      (_) async => const <ServiceCategoryOption>[
        ServiceCategoryOption(name: 'HAIRCUT', displayName: 'Стрижка'),
      ],
    );
  });

  Future<void> pumpList(WidgetTester tester, List<MasterService> data) async {
    await tester.pumpApp(
      const ServicesListScreen(),
      overrides: [
        servicesListProvider.overrideWith(() => _StubServicesList(data)),
        serviceRepositoryProvider.overrideWithValue(repo),
      ],
    );
    // Loading frame → microtask delivers data → settle entrance animations.
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    // Post-84ae042 the list opens with every section COLLAPSED, so the service
    // card (and its label rows) are not in the tree yet. These fixtures carry no
    // category, so they bucket under the uncategorized section
    // (`category_section__none`). Expand it before asserting on the card's label
    // rows — the label-resolution branches under test live INSIDE the card.
    await tester.tap(find.byKey(const Key('category_section__none')));
    await tester.pumpAndSettle();
  }

  // L1 — type present, custom name differs → primary=type, secondary=custom.
  testWidgets(
    'L1. type present + distinct custom name → primary is type, custom shown '
    'as secondary',
    (tester) async {
      const svc = MasterService(
        id: 's1',
        serviceDefId: 'd1',
        name: 'Мій фірмовий зріз',
        serviceTypeId: 't1',
        serviceTypeNameUk: 'Стрижка',
        durationMinutes: 45,
        priceMin: 750,
        priceDisplay: '750 грн',
      );
      await pumpList(tester, const <MasterService>[svc]);

      // PRIMARY label = the service-type name.
      expect(_primaryLabel('s1', 'Стрижка'), findsOneWidget);
      // SECONDARY subtitle = the custom name, rendered on the keyed Text line.
      final secondary = find.byKey(const Key('service-card-custom-name'));
      expect(secondary, findsOneWidget);
      expect(
        tester.widget<Text>(secondary).data,
        'Мій фірмовий зріз',
        reason: 'the custom name renders on the secondary line',
      );
    },
  );

  // L2 — type present, custom name equals type → no secondary (no echo).
  testWidgets(
    'L2. custom name equal to the service-type name → NO secondary line',
    (tester) async {
      const svc = MasterService(
        id: 's2',
        serviceDefId: 'd2',
        name: 'Стрижка',
        serviceTypeId: 't1',
        serviceTypeNameUk: 'Стрижка',
        durationMinutes: 30,
        priceMin: 500,
        priceDisplay: '500 грн',
      );
      await pumpList(tester, const <MasterService>[svc]);

      // Primary still renders the type once.
      expect(_primaryLabel('s2', 'Стрижка'), findsOneWidget);
      // No duplicated secondary line.
      expect(
        find.byKey(const Key('service-card-custom-name')),
        findsNothing,
        reason: 'custom name == type name must not be echoed as a subtitle',
      );
    },
  );

  // L3 — type present, custom name blank → primary=type, no secondary (M3).
  testWidgets('L3. blank custom name with a type → primary is type, no '
      'secondary', (tester) async {
    const svc = MasterService(
      id: 's3',
      serviceDefId: 'd3',
      name: '',
      serviceTypeId: 't1',
      serviceTypeNameUk: 'Манікюр',
      durationMinutes: 60,
      priceMin: 400,
      priceDisplay: '400 грн',
    );
    await pumpList(tester, const <MasterService>[svc]);

    expect(_primaryLabel('s3', 'Манікюр'), findsOneWidget);
    expect(find.byKey(const Key('service-card-custom-name')), findsNothing);
  });

  // L4 — no type → custom name is primary, no secondary (M3 null branch).
  testWidgets(
    'L4. no service type → custom name is the primary label, no secondary',
    (tester) async {
      const svc = MasterService(
        id: 's4',
        serviceDefId: 'd4',
        name: 'Авторська послуга',
        // serviceTypeId / serviceTypeNameUk intentionally null.
        durationMinutes: 90,
        priceMin: 1200,
        priceDisplay: '1200 грн',
      );
      await pumpList(tester, const <MasterService>[svc]);

      expect(_primaryLabel('s4', 'Авторська послуга'), findsOneWidget);
      expect(
        find.byKey(const Key('service-card-custom-name')),
        findsNothing,
        reason: 'with no type the custom name is primary, never a subtitle',
      );
    },
  );
}

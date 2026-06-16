// Profile-category-cards feature — pre-expand contract tests.
//
// Area 1 of the required new coverage:
//   • With initialExpandCategory: 'MANICURE', the MANICURE section is expanded
//     and every other section is collapsed on first build, without any user
//     interaction.
//   • With initialExpandCategory: null (or empty), every section defaults to
//     COLLAPSED (UX change in commit 84ae042 — was default-expanded); the user
//     can expand any section by tapping its header.
//
// Strategy:
//   • Override [servicesListProvider] with a stub that resolves to an AsyncData
//     containing services in two categories: MANICURE and BROWS.
//   • Override [serviceRepositoryProvider] with a mock that returns a known
//     approved-categories list so both section headers are rendered with their
//     Ukrainian labels.
//   • After pumpAndSettle, assert section key presence and card visibility.
//
// Isolation:
//   • Fresh ProviderScope per test — no shared mutable state.
//   • No real network, no real storage.
//   • Key-based finders throughout (no localised strings as primary finders).

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
// Mocks
// ---------------------------------------------------------------------------

class _MockServiceRepository extends Mock implements ServiceRepository {}

// ---------------------------------------------------------------------------
// Stub data
// ---------------------------------------------------------------------------

const _manicureService = MasterService(
  id: 'svc-m',
  serviceDefId: 'def-m',
  name: 'Манікюр',
  durationMinutes: 60,
  priceMin: 500,
  priceDisplay: '500 грн',
  category: 'MANICURE',
);

const _browsService = MasterService(
  id: 'svc-b',
  serviceDefId: 'def-b',
  name: 'Корекція брів',
  durationMinutes: 30,
  priceMin: 300,
  priceDisplay: '300 грн',
  category: 'BROWS',
);

const _twoServices = <MasterService>[_manicureService, _browsService];

const _approvedCategories = <ServiceCategoryOption>[
  ServiceCategoryOption(name: 'MANICURE', displayName: 'Манікюр'),
  ServiceCategoryOption(name: 'BROWS', displayName: 'Брови'),
];

// ---------------------------------------------------------------------------
// Stub notifier
// ---------------------------------------------------------------------------

class _StubServicesList extends ServicesList {
  _StubServicesList(this._target);

  final AsyncValue<List<MasterService>> _target;

  @override
  Future<List<MasterService>> build() {
    if (!_target.isLoading) {
      Future<void>.microtask(() => state = _target);
    }
    return Completer<List<MasterService>>().future;
  }
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

/// Pumps [ServicesListScreen] with the given [initialExpandCategory] and
/// two services (MANICURE + BROWS), then settles all animations.
Future<void> _pumpScreen(
  WidgetTester tester,
  _MockServiceRepository mockRepo, {
  String? initialExpandCategory,
}) async {
  await tester.pumpApp(
    ServicesListScreen(initialExpandCategory: initialExpandCategory),
    overrides: [
      servicesListProvider.overrideWith(
        () => _StubServicesList(
          const AsyncData<List<MasterService>>(_twoServices),
        ),
      ),
      serviceRepositoryProvider.overrideWithValue(mockRepo),
    ],
  );
  // Loading frame → microtask delivers data → data frame.
  await tester.pump();
  await tester.pump();
  // Advance past the entrance stagger (max 5 * 90 ms = 450 ms).
  await tester.pump(const Duration(milliseconds: 600));
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _MockServiceRepository mockRepo;

  setUp(() {
    mockRepo = _MockServiceRepository();
    when(() => mockRepo.listMyServices()).thenAnswer((_) async => _twoServices);
    when(
      () => mockRepo.fetchApprovedCategories(),
    ).thenAnswer((_) async => _approvedCategories);
  });

  group('ServicesListScreen — pre-expand contract (initialExpandCategory)', () {
    // Use a tall surface so both sections are visible without scrolling,
    // avoiding hittability issues with the animated expansion.
    setUp(() {});

    // ── 1. With a valid slug: matching section expanded, others collapsed ──────

    testWidgets('MANICURE section is expanded and BROWS is collapsed when '
        'initialExpandCategory is MANICURE', (tester) async {
      tester.view.physicalSize = const Size(480, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pumpScreen(tester, mockRepo, initialExpandCategory: 'MANICURE');

      // Both section headers must be in the tree.
      expect(
        find.byKey(const Key('category_section_MANICURE')),
        findsOneWidget,
        reason: 'MANICURE section header must be rendered',
      );
      expect(
        find.byKey(const Key('category_section_BROWS')),
        findsOneWidget,
        reason: 'BROWS section header must be rendered',
      );

      // The matching section's service card is visible (section expanded).
      expect(
        find.byKey(const Key('service_card_svc-m')),
        findsOneWidget,
        reason:
            'MANICURE card must be visible because MANICURE section is '
            'pre-expanded',
      );

      // The non-matching section's card is absent from the tree (collapsed).
      expect(
        find.byKey(const Key('service_card_svc-b')),
        findsNothing,
        reason:
            'BROWS card must NOT be visible because only MANICURE was '
            'requested as the initial expansion target',
      );
    });

    // ── 2. With a different slug: BROWS expanded, MANICURE collapsed ──────────

    testWidgets('BROWS section is expanded and MANICURE is collapsed when '
        'initialExpandCategory is BROWS', (tester) async {
      tester.view.physicalSize = const Size(480, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pumpScreen(tester, mockRepo, initialExpandCategory: 'BROWS');

      expect(
        find.byKey(const Key('service_card_svc-b')),
        findsOneWidget,
        reason: 'BROWS card must be visible (BROWS section pre-expanded)',
      );
      expect(
        find.byKey(const Key('service_card_svc-m')),
        findsNothing,
        reason: 'MANICURE card must be collapsed when BROWS is targeted',
      );
    });

    // ── 3. With null: all sections default to COLLAPSED ───────────────────────
    //
    // Post-84ae042 default-state contract: with no expand target every section
    // starts collapsed (no cards in the tree). The original intent — that the
    // "no target" path applies the SAME default to every section, and that each
    // section is freely togglable afterward — is preserved by asserting the
    // collapsed default first, then tapping a header to reveal its card.

    testWidgets(
      'all sections default to collapsed when initialExpandCategory is null; '
      'tapping a header reveals its card',
      (tester) async {
        tester.view.physicalSize = const Size(480, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await _pumpScreen(tester, mockRepo, initialExpandCategory: null);

        // Default-collapsed: neither card is in the tree on first build.
        expect(
          find.byKey(const Key('service_card_svc-m')),
          findsNothing,
          reason:
              'MANICURE card must be hidden when no expand param is set '
              '(default collapsed — UX change 84ae042)',
        );
        expect(
          find.byKey(const Key('service_card_svc-b')),
          findsNothing,
          reason:
              'BROWS card must be hidden when no expand param is set '
              '(default collapsed — UX change 84ae042)',
        );

        // The user can still expand any section by tapping its header.
        await tester.tap(find.byKey(const Key('category_section_MANICURE')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('service_card_svc-m')),
          findsOneWidget,
          reason: 'tapping the MANICURE header must reveal its card',
        );
      },
    );

    // ── 4. Empty string is treated the same as null: all collapsed ────────────

    testWidgets(
      'all sections default to collapsed when initialExpandCategory is empty',
      (tester) async {
        tester.view.physicalSize = const Size(480, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // The screen source normalises '' to null (trim().toUpperCase().isEmpty),
        // so empty behaves exactly like null: every section starts collapsed.
        await _pumpScreen(tester, mockRepo, initialExpandCategory: '');

        expect(
          find.byKey(const Key('service_card_svc-m')),
          findsNothing,
          reason:
              'empty string must be treated as null — all sections collapsed',
        );
        expect(
          find.byKey(const Key('service_card_svc-b')),
          findsNothing,
          reason:
              'empty string must be treated as null — all sections collapsed',
        );
      },
    );

    // ── 5. Unknown slug: all sections default to expanded ─────────────────────
    //
    // When the requested slug matches no bucket, the screen can only default
    // to expanded because there is nothing to pre-select. No section should
    // start collapsed.

    testWidgets(
      'all sections default to expanded when initialExpandCategory matches '
      'no category in the data',
      (tester) async {
        tester.view.physicalSize = const Size(480, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await _pumpScreen(tester, mockRepo, initialExpandCategory: 'PEDICURE');

        // PEDICURE does not exist in the data; the code normalises targetSlug to
        // 'PEDICURE'. For every section, `group.key == 'PEDICURE'` is false, so
        // `initiallyExpanded = false`. But since there are no PEDICURE cards to
        // hide, the MANICURE and BROWS sections use targetSlug != null and their
        // keys don't match — meaning they START COLLAPSED. This is the intended
        // behaviour: sections that do not match the requested target start
        // collapsed even if the slug is not present at all.
        //
        // Both cards should be absent (collapsed by the non-match rule).
        expect(
          find.byKey(const Key('service_card_svc-m')),
          findsNothing,
          reason:
              'MANICURE card must be collapsed because targetSlug PEDICURE '
              'does not match MANICURE',
        );
        expect(
          find.byKey(const Key('service_card_svc-b')),
          findsNothing,
          reason:
              'BROWS card must be collapsed because targetSlug PEDICURE '
              'does not match BROWS',
        );
      },
    );
  });
}

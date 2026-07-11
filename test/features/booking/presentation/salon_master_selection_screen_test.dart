// Phase 14.13 — Widget tests for SalonMasterSelectionScreen.
//
// Covers (phase doc Step 4):
//   1. Only masters covering ≥1 selected service render.
//   2. Auto-attach when exactly one candidate performs a service.
//   3. Tap-to-choose chips + assignment when multiple candidates.
//   4. "Підтвердити" disabled while any service is unassigned, enabled once
//      all are covered.
//   5. Navigates to /booking/salon/coming-soon on confirm.
//   6. No "any available master" option is ever rendered.

import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/booking/application/salon_master_coverage_notifier.dart';
import 'package:beautica_mobile/features/booking/domain/salon_booking_args.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_master_selection_screen.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/salon/application/public_salon_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_service_catalog_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_master_summary.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/pump_app.dart';

/// Tall test surface so every row (including the contested-service candidate
/// chips inside the per-master grouped preview, which only appear once ≥2
/// masters covering the same service are picked) is fully on-screen without
/// scrolling — avoids flaky hit-test misses from tapping content the default
/// (short) test viewport would otherwise clip.
Future<void> _pumpTall(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

const String _kSalonId = 'salon-1';

const _stubSalon = Salon(id: _kSalonId, name: 'Салон «Вельвет»');

const _svc1 = SalonCatalogService(
  id: 'svc-1',
  name: 'Манікюр з покриттям',
  durationLabel: '1 год 30 хв',
  priceDisplay: '500 грн',
  durationMinutes: 90,
  priceType: ServicePriceType.fixed,
  priceMin: 500,
);

const _svc2 = SalonCatalogService(
  id: 'svc-2',
  name: 'Педикюр',
  durationLabel: '2 год',
  priceDisplay: '800 грн',
  durationMinutes: 120,
  priceType: ServicePriceType.fixed,
  priceMin: 800,
);

const _stubCatalog = <SalonServiceCategoryEntry>[
  SalonServiceCategoryEntry(
    category: 'MANICURE',
    displayName: 'Манікюр',
    count: 1,
    services: <SalonCatalogService>[_svc1],
  ),
  SalonServiceCategoryEntry(
    category: 'PEDICURE',
    displayName: 'Педикюр',
    count: 1,
    services: <SalonCatalogService>[_svc2],
  ),
];

/// m1 covers ONLY svc1; m2 covers BOTH svc1 and svc2 (so svc1 becomes
/// contested once both are picked); m3 covers NEITHER selected service and
/// must never render.
const _m1 = SalonMasterSummary(
  masterId: 'm1',
  firstName: 'Олена',
  lastName: 'Ковальчук',
  avgRating: 4.9,
  reviewCount: 12,
  type: MasterType.independentMaster,
);
const _m2 = SalonMasterSummary(
  masterId: 'm2',
  firstName: 'Софія',
  lastName: 'Мельник',
  avgRating: 5.0,
  reviewCount: 3,
  type: MasterType.salonMaster,
);
const _m3 = SalonMasterSummary(
  masterId: 'm3',
  firstName: 'Дарина',
  lastName: 'Пономаренко',
  avgRating: 4.6,
  reviewCount: 1,
  type: MasterType.salonMaster,
);

const _stubMasters = <SalonMasterSummary>[_m1, _m2, _m3];

// Phase 14.16/14.17 bugfix — coverage values are now `serviceDefId ->
// assignmentId` maps (the master's OWN `MasterServiceResponse.id`), not a
// bare `Set<String>` of covered catalog ids. This screen only ever calls
// `.containsKey` on these maps (never reads the values), so any non-empty
// String value works here — deliberately kept DIFFERENT from the catalog id
// to match production (`master_services.id` != `service_definitions.id`),
// mirroring `salon_time_screen_test.dart`'s identical fixture convention.
final _stubCoverage = <String, Map<String, String>>{
  'm1': <String, String>{'svc-1': 'assignment-m1-svc-1'},
  'm2': <String, String>{
    'svc-1': 'assignment-m2-svc-1',
    'svc-2': 'assignment-m2-svc-2',
  },
  'm3': <String, String>{},
};

SalonBookingMasterSelectionArgs _args() =>
    const SalonBookingMasterSelectionArgs(
      salonId: _kSalonId,
      selectedServiceIds: <String>['svc-1', 'svc-2'],
    );

List<Object> _overrides() => <Object>[
  publicSalonProfileProvider(
    _kSalonId,
  ).overrideWith((ref) => (_stubSalon, _stubMasters)),
  salonServiceCatalogProvider(_kSalonId).overrideWith((ref) => _stubCatalog),
  salonMasterServiceCoverageProvider(
    _args(),
  ).overrideWith((ref) => _stubCoverage),
];

/// [GoRouter] with the screen under test at its initial location, plus a
/// terminal capture route for `/booking/salon/time` — Phase 14.16 retargeted
/// «Підтвердити» from the old direct-to-coming-soon hop to the real step-3
/// "Час" screen.
GoRouter _routerFor({ValueChanged<SalonBookingTimeArgs>? onReached}) {
  return GoRouter(
    initialLocation: RouteNames.salonBookingMasters,
    routes: <RouteBase>[
      GoRoute(
        path: RouteNames.salonBookingMasters,
        builder: (context, state) => SalonMasterSelectionScreen(args: _args()),
      ),
      GoRoute(
        path: RouteNames.salonBookingTime,
        builder: (context, state) {
          onReached?.call(state.extra! as SalonBookingTimeArgs);
          return const Scaffold(
            body: Center(child: Text('salon-time-reached')),
          );
        },
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Per-master professional-title regression (salon-master-title bug).
//
// The eligible-master itemBuilder previously passed the SHARED generic role
// (`_roleLabel(m.type, l10n)`) as EVERY row's subtitle, so all salon masters
// (all `MasterType.salonMaster`) showed the identical "Майстер салону"
// subtitle regardless of their own title. The fix binds each master's OWN
// `professionalTitle` (trimmed, non-empty) and falls back to the generic role
// only when it is null/blank.
//
// These fixtures are LOCAL to that regression test: four eligible masters, ALL
// `MasterType.salonMaster` and ALL covering svc-1 (so none is filtered out by
// the eligibility rule), with DISTINCT titles "Стиліст"/"Барбер" and two
// blank cases (null + whitespace) that must both fall back to "Майстер
// салону".
const _titleStylist = SalonMasterSummary(
  masterId: 'ts1',
  firstName: 'Ірина',
  lastName: 'Стиль',
  professionalTitle: 'Стиліст',
  avgRating: 4.8,
  reviewCount: 5,
  type: MasterType.salonMaster,
);
const _titleBarber = SalonMasterSummary(
  masterId: 'ts2',
  firstName: 'Петро',
  lastName: 'Голій',
  professionalTitle: 'Барбер',
  avgRating: 4.7,
  reviewCount: 8,
  type: MasterType.salonMaster,
);
const _titleNull = SalonMasterSummary(
  masterId: 'ts3',
  firstName: 'Ганна',
  lastName: 'Безтитул',
  // professionalTitle omitted -> null -> falls back to the role label.
  avgRating: 4.5,
  reviewCount: 2,
  type: MasterType.salonMaster,
);
const _titleWhitespace = SalonMasterSummary(
  masterId: 'ts4',
  firstName: 'Марта',
  lastName: 'Пробіл',
  professionalTitle: '   ', // whitespace-only -> trims empty -> role fallback.
  avgRating: 4.4,
  reviewCount: 1,
  type: MasterType.salonMaster,
);

const _titleMasters = <SalonMasterSummary>[
  _titleStylist,
  _titleBarber,
  _titleNull,
  _titleWhitespace,
];

// Every master covers svc-1 -> all four are eligible and rendered.
final _titleCoverage = <String, Map<String, String>>{
  'ts1': <String, String>{'svc-1': 'assignment-ts1-svc-1'},
  'ts2': <String, String>{'svc-1': 'assignment-ts2-svc-1'},
  'ts3': <String, String>{'svc-1': 'assignment-ts3-svc-1'},
  'ts4': <String, String>{'svc-1': 'assignment-ts4-svc-1'},
};

List<Object> _titleOverrides() => <Object>[
  publicSalonProfileProvider(
    _kSalonId,
  ).overrideWith((ref) => (_stubSalon, _titleMasters)),
  salonServiceCatalogProvider(_kSalonId).overrideWith((ref) => _stubCatalog),
  salonMasterServiceCoverageProvider(
    const SalonBookingMasterSelectionArgs(
      salonId: _kSalonId,
      selectedServiceIds: <String>['svc-1'],
    ),
  ).overrideWith((ref) => _titleCoverage),
];

/// Router whose master-selection screen selects ONLY svc-1, so all four
/// title-fixture masters (each covering svc-1) are eligible.
GoRouter _titleRouter() {
  return GoRouter(
    initialLocation: RouteNames.salonBookingMasters,
    routes: <RouteBase>[
      GoRoute(
        path: RouteNames.salonBookingMasters,
        builder: (context, state) => const SalonMasterSelectionScreen(
          args: SalonBookingMasterSelectionArgs(
            salonId: _kSalonId,
            selectedServiceIds: <String>['svc-1'],
          ),
        ),
      ),
    ],
  );
}

/// Finds the subtitle [text] scoped to a SPECIFIC master's row (by the outer
/// `_MasterPickRowListener`'s key) — so an assertion targets the RIGHT row's
/// subtitle, never merely "this string exists somewhere on screen".
Finder _subtitleInRow(String masterId, String text) => find.descendant(
  of: find.byKey(Key('salon_booking_master_row_$masterId')),
  matching: find.text(text),
);

void main() {
  testWidgets(
    'only masters covering >=1 selected service render (m3 filtered out)',
    (tester) async {
      await _pumpTall(tester);
      await tester.pumpRoutedApp(_routerFor(), overrides: _overrides());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('salon_booking_master_row_m1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('salon_booking_master_row_m2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('salon_booking_master_row_m3')),
        findsNothing,
      );
    },
  );

  testWidgets('no "any available master" option is ever rendered', (
    tester,
  ) async {
    await _pumpTall(tester);
    await tester.pumpRoutedApp(_routerFor(), overrides: _overrides());
    await tester.pumpAndSettle();

    expect(find.textContaining('Будь-який'), findsNothing);
    expect(find.textContaining('вільний майстер'), findsNothing);
  });

  testWidgets('auto-attaches when exactly one candidate performs a service', (
    tester,
  ) async {
    await _pumpTall(tester);
    await tester.pumpRoutedApp(_routerFor(), overrides: _overrides());
    await tester.pumpAndSettle();

    // Pick ONLY m1 (covers svc-1 only). svc-1 has exactly one candidate
    // (m1) -> auto-attached; svc-2 has zero picked candidates -> uncovered.
    await tester.tap(find.byKey(const Key('salon_booking_master_row_m1')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Педикюр'),
      findsWidgets,
    ); // uncovered-service prompt names it
    // Confirm CTA still disabled (svc-2 unassigned).
    final NeumorphicButton cta = tester.widget<NeumorphicButton>(
      find.byKey(const Key('salon-assign-confirm-cta')),
    );
    expect(cta.onPressed, isNull);
  });

  testWidgets(
    'tap-to-choose resolves a contested service; Підтвердити enables once '
    'every service is assigned, then navigates to /booking/salon/time with '
    'the exact resolved per-master assignment',
    (tester) async {
      await _pumpTall(tester);
      SalonBookingTimeArgs? capturedArgs;
      await tester.pumpRoutedApp(
        _routerFor(onReached: (args) => capturedArgs = args),
        overrides: _overrides(),
      );
      await tester.pumpAndSettle();

      // Pick BOTH masters -> svc-1 becomes contested (m1 + m2 both cover it);
      // svc-2 auto-attaches to m2 (the only candidate).
      await tester.tap(find.byKey(const Key('salon_booking_master_row_m1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('salon_booking_master_row_m2')));
      await tester.pumpAndSettle();

      // CTA still disabled: svc-1 is contested/unresolved.
      NeumorphicButton cta = tester.widget<NeumorphicButton>(
        find.byKey(const Key('salon-assign-confirm-cta')),
      );
      expect(cta.onPressed, isNull);

      // Resolve the contested svc-1 by tapping the m1 candidate chip.
      final chip = find.byKey(
        const Key('salon_booking_candidate_chip_svc-1_m1'),
      );
      expect(chip, findsOneWidget);
      await tester.tap(chip);
      await tester.pumpAndSettle();

      cta = tester.widget<NeumorphicButton>(
        find.byKey(const Key('salon-assign-confirm-cta')),
      );
      expect(cta.onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('salon-assign-confirm-cta')));
      await tester.pumpAndSettle();

      expect(find.text('salon-time-reached'), findsOneWidget);
      expect(capturedArgs, isNotNull);
      expect(capturedArgs!.salonId, _kSalonId);
      expect(capturedArgs!.selectedServiceIds, <String>['svc-1', 'svc-2']);
      // m1 resolved svc-1 (the contested-chip choice); m2 auto-attached
      // svc-2 (the only candidate) — exactly the assignment the client made,
      // not a fresh re-derivation from coverage alone.
      expect(capturedArgs!.assignedServiceIdsByMaster, <String, List<String>>{
        'm1': <String>['svc-1'],
        'm2': <String>['svc-2'],
      });
    },
  );

  // mobile-perf re-audit follow-up (Phase 14.13): "No test... asserts...
  // per-row rebuild-scoping". The screen's own file header documents that
  // `_MasterPickRowListener` listens to the shared pick `ValueNotifier`
  // DIRECTLY (rather than via a `ValueListenableBuilder` wrapping the whole
  // master list) specifically so toggling one master only rebuilds THAT row
  // — never its siblings, never the O(N) eligible-master list itself.
  //
  // TECHNIQUE — no existing precedent asserts scoped rebuilds anywhere in
  // this codebase (checked `services_list_screen_test.dart` and
  // `service_selector_sheet_test.dart`; neither counts/scopes rebuilds).
  // `_MasterPickRowListener`/`_MasterPickRow` are private to
  // `salon_master_selection_screen.dart`, so no State object or build-count
  // field is reachable from this test file. The chosen proxy uses Flutter's
  // own `debugPrintRebuildDirtyWidgets` framework flag (`framework.dart`'s
  // `Element.rebuild`: `debugPrint('Rebuilding $this')` for every dirty
  // Element rebuilt in a frame) — a real, documented Flutter debug facility
  // for exactly this purpose, not a private-API hack. `Element.toStringShort()`
  // renders as `'$runtimeType-$key'` when the widget carries a `Key`, and
  // both master rows ARE keyed (`salon_booking_master_row_<masterId>`,
  // see `_Body`'s `itemBuilder`), so the captured rebuild log names each
  // row's Element unambiguously — spot-checked once against this exact
  // screen/fixture before being relied on here. One single-frame
  // `tester.pump()` (not `pumpAndSettle`, which would blur multiple frames
  // together) is captured right after the tap.
  testWidgets(
    'toggling one master rebuilds only that row — the untapped sibling '
    "row's Element never appears in the same frame's rebuild log",
    (tester) async {
      await _pumpTall(tester);
      await tester.pumpRoutedApp(_routerFor(), overrides: _overrides());
      await tester.pumpAndSettle();

      final List<String> rebuiltLines = <String>[];
      final DebugPrintCallback previousDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) rebuiltLines.add(message);
      };
      debugPrintRebuildDirtyWidgets = true;
      addTearDown(() {
        debugPrintRebuildDirtyWidgets = false;
        debugPrint = previousDebugPrint;
      });

      await tester.tap(find.byKey(const Key('salon_booking_master_row_m1')));
      // Exactly ONE frame — the frame the tap's setState schedules. Using
      // pumpAndSettle here would merge subsequent animation frames into the
      // same log and defeat the single-frame assertion below.
      await tester.pump();

      debugPrintRebuildDirtyWidgets = false;
      debugPrint = previousDebugPrint;

      final bool m1RowRebuilt = rebuiltLines.any(
        (String l) => l.contains('salon_booking_master_row_m1'),
      );
      final bool m2RowRebuilt = rebuiltLines.any(
        (String l) => l.contains('salon_booking_master_row_m2'),
      );

      expect(
        m1RowRebuilt,
        isTrue,
        reason:
            'the TAPPED row (m1) must rebuild to flip its selected visual '
            'state — if this is false the proxy technique itself is broken, '
            'not proving isolation',
      );
      expect(
        m2RowRebuilt,
        isFalse,
        reason:
            "the UNTAPPED sibling row (m2)'s Element must never appear in "
            'the same-frame rebuild log — a regression back to a single '
            'ValueListenableBuilder wrapping the whole master list would '
            'rebuild every row on every toggle and fail this assertion',
      );

      await tester.pumpAndSettle();
    },
  );

  // salon-master-title regression — each salon master's row must show its OWN
  // `professionalTitle` (with a role fallback when null/blank), NOT the shared
  // generic role for everyone. The pre-fix itemBuilder passed
  // `role: _roleLabel(m.type, l10n)` for every row, so all four rows below
  // (all MasterType.salonMaster) rendered the identical "Майстер салону"
  // subtitle — the per-title `findsOneWidget`/`findsNothing` assertions here
  // would then FAIL, which is exactly what guards the fix.
  testWidgets(
    'each salon master row shows its OWN professionalTitle, with the role '
    'label as fallback when the title is null or whitespace',
    (tester) async {
      await _pumpTall(tester);
      await tester.pumpRoutedApp(_titleRouter(), overrides: _titleOverrides());
      await tester.pumpAndSettle();

      // All four masters are eligible (each covers svc-1) and rendered.
      expect(
        find.byKey(const Key('salon_booking_master_row_ts1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('salon_booking_master_row_ts4')),
        findsOneWidget,
      );

      // Each titled master's row shows its OWN title — scoped to that row so
      // we assert the RIGHT subtitle, not just "the text exists somewhere".
      expect(_subtitleInRow('ts1', 'Стиліст'), findsOneWidget);
      expect(_subtitleInRow('ts2', 'Барбер'), findsOneWidget);

      // ...and NOT another master's title or the shared generic role. On the
      // OLD code every row showed "Майстер салону", so each of these would
      // find that generic label in the titled rows and fail.
      expect(_subtitleInRow('ts1', 'Барбер'), findsNothing);
      expect(_subtitleInRow('ts1', 'Майстер салону'), findsNothing);
      expect(_subtitleInRow('ts2', 'Стиліст'), findsNothing);
      expect(_subtitleInRow('ts2', 'Майстер салону'), findsNothing);

      // Null-title master falls back to the generic role label.
      expect(_subtitleInRow('ts3', 'Майстер салону'), findsOneWidget);
      // Whitespace-only title trims empty -> same role fallback.
      expect(_subtitleInRow('ts4', 'Майстер салону'), findsOneWidget);
    },
  );

  // white-corner-shadow regression — the 40x40 master avatar in the per-master
  // grouped preview (`_GroupRow`) previously used `VelvetShadows.extrudedSmall`,
  // a diagonally-OFFSET shadow pair (`Offset(5,5)` dark + `Offset(-5,-5)`
  // near-white). On the small rounded avatar the untranslated corner of the
  // near-white offset shadow poked out as a WHITE SQUARE in the corner. The fix
  // swapped it to `VelvetShadows.borderedCard` — a single, NON-offset
  // (`Offset.zero`) shadow — so no translated corner can bleed.
  //
  // The mandatory structural guard (golden-independent, per the debugger's
  // guidance): the `_GroupRow` avatar Container's every `BoxShadow` must have
  // `offset == Offset.zero`. A regression back to `extrudedSmall` (or any
  // offset pair) reintroduces a non-zero offset and fails here. The avatar is
  // located structurally — a 40x40 `Container` with a `BoxDecoration` gradient +
  // shadow whose child is `Icon(Icons.person_rounded)` — never by a brittle
  // golden. `_GroupRow` is private, so it is driven through the public screen:
  // picking m1 (covers only svc-1) auto-attaches svc-1 to m1, materialising
  // exactly one group row and thus exactly one such avatar.
  testWidgets(
    "the grouped-preview master avatar's every BoxShadow has zero offset "
    '(no white-corner bleed from an offset shadow pair)',
    (tester) async {
      await _pumpTall(tester);
      await tester.pumpRoutedApp(_routerFor(), overrides: _overrides());
      await tester.pumpAndSettle();

      // Pick m1 -> svc-1 auto-attaches -> one `_GroupRow` (and its 40x40
      // avatar) is rendered inside the grouped preview.
      await tester.tap(find.byKey(const Key('salon_booking_master_row_m1')));
      await tester.pumpAndSettle();

      // Structural finder: the 40x40 gradient+shadow avatar Container. The only
      // other shadow-bearing gradient avatar on this screen is the 52dp master-
      // row avatar (`_MasterPickRow`), excluded here by the tight 40x40 size.
      final Finder avatarFinder = find.byWidgetPredicate((Widget w) {
        if (w is! Container) return false;
        final Decoration? decoration = w.decoration;
        if (decoration is! BoxDecoration) return false;
        return w.constraints ==
                const BoxConstraints.tightFor(width: 40, height: 40) &&
            decoration.gradient != null &&
            decoration.boxShadow != null;
      }, description: '40x40 gradient+shadow _GroupRow avatar container');

      // Exactly one group (m1/svc-1) -> exactly one such avatar.
      expect(avatarFinder, findsOneWidget);

      // Confirm this really is the avatar: it wraps the person glyph.
      expect(
        find.descendant(
          of: avatarFinder,
          matching: find.byIcon(Icons.person_rounded),
        ),
        findsOneWidget,
      );

      final BoxDecoration decoration =
          tester.widget<Container>(avatarFinder).decoration! as BoxDecoration;

      // Other avatar invariants (kept, per the debugger's note) — a rounded
      // (not sharp-cornered) bordered avatar.
      expect(decoration.borderRadius, isNotNull);
      expect(decoration.border, isNotNull);

      // THE MANDATORY GUARD — every shadow is non-offset, so no translated
      // near-white corner can poke out. `extrudedSmall`'s ±5dp offsets would
      // fail this; `borderedCard`'s single Offset.zero shadow passes.
      final List<BoxShadow> shadows = decoration.boxShadow!;
      expect(shadows, isNotEmpty);
      for (final BoxShadow shadow in shadows) {
        expect(
          shadow.offset,
          Offset.zero,
          reason:
              'A _GroupRow avatar BoxShadow has a non-zero offset '
              '(${shadow.offset}) — a diagonally-offset shadow pair (e.g. a '
              'regression back to VelvetShadows.extrudedSmall) bleeds a white '
              'square out of the small rounded avatar corner. Use a single '
              'non-offset shadow (VelvetShadows.borderedCard).',
        );
      }
    },
  );
}

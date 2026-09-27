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

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/booking/application/salon_master_coverage_notifier.dart';
import 'package:beautica_mobile/features/booking/domain/salon_booking_args.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_master_selection_screen.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/salon/application/public_salon_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_service_catalog_notifier.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:beautica_mobile/features/salon/domain/bookable_master_assignment.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_master_summary.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/booking_price_labels.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/fake_salon_master_coverage.dart';
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

/// Phase 266 — stubs ONLY `getBookableMasters`, the one repository method
/// `SalonMasterServiceCoverage.retryService` reads. Every other
/// `SalonRepository` member is unstubbed on purpose: no test in this file
/// exercises D4's retry against anything else, and mocktail throws loudly
/// (rather than silently returning null) if one ever did.
class _MockSalonRepository extends Mock implements SalonRepository {}

const String _kSalonId = 'salon-1';

const _stubSalon = Salon(id: _kSalonId, name: 'Салон «Вельвет»');

const _svc1 = SalonCatalogService(
  id: 'svc-1',
  name: 'Манікюр з покриттям',
  durationLabel: '1 год 30 хв',
  priceDisplay: '500 ₴',
  durationMinutes: 90,
  priceType: ServicePriceType.fixed,
  priceMin: 500,
);

const _svc2 = SalonCatalogService(
  id: 'svc-2',
  name: 'Педикюр',
  durationLabel: '2 год',
  priceDisplay: '800 ₴',
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
  salonMasterServiceCoverageProvider(_args()).overrideWith(
    () => FakeSalonMasterServiceCoverage(() => salonCoverageOf(_stubCoverage)),
  ),
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
  ).overrideWith(
    () => FakeSalonMasterServiceCoverage(() => salonCoverageOf(_titleCoverage)),
  ),
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

/// A router with a placeholder initial route + this screen pushed onto it —
/// needed (unlike [_routerFor], which starts ON this screen) so tapping the
/// screen's own back button actually POPS it (and therefore disposes it),
/// letting a test observe `ScreenProtectionManager.release()` firing. Mirrors
/// `salon_booking_confirm_screen_test.dart`'s identical push-then-pop
/// approach for its own ScreenProtectionManager lifecycle group.
GoRouter _pushableRouter() => GoRouter(
  initialLocation: '/start',
  routes: <RouteBase>[
    GoRoute(
      path: '/start',
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('start'))),
    ),
    GoRoute(
      path: RouteNames.salonBookingMasters,
      builder: (context, state) => SalonMasterSelectionScreen(args: _args()),
    ),
  ],
);

/// Counts acquire()/release() calls — mirrors
/// `salon_booking_confirm_screen_test.dart`'s identical
/// `_CountingScreenProtection` (the established pattern for pinning a PII
/// screen's FLAG_SECURE lifecycle).
class _CountingScreenProtection extends ScreenProtectionManager {
  int acquireCount = 0;
  int releaseCount = 0;

  @override
  void acquire() => acquireCount++;

  @override
  void release() => releaseCount++;
}

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

  // ===========================================================================
  // mobile-qa gap (card-unification audit): the picker's rows render the
  // SHARED `MasterStrip(showRating: true)` card (the same widget the
  // calendar/time/confirm/success screens render) — but no test ever
  // asserted the ACTUAL rating digits/review-count render here. Rating on
  // the salon picker is the whole point of the card-unification change (the
  // deleted bespoke `_MasterPickRow` header never showed one). Scoped to
  // each master's own row so a coincidental match elsewhere can't
  // false-pass this.
  // ===========================================================================
  testWidgets(
    "each eligible master's row renders its OWN ★rating(reviewCount) via "
    'the shared MasterStrip card',
    (tester) async {
      await _pumpTall(tester);
      await tester.pumpRoutedApp(_routerFor(), overrides: _overrides());
      await tester.pumpAndSettle();

      final Finder m1Row = find.byKey(const Key('salon_booking_master_row_m1'));
      expect(
        find.descendant(of: m1Row, matching: find.text('4.9')),
        findsOneWidget,
        reason:
            "MasterStrip(showRating: true) must render m1's own "
            'avgRating.toStringAsFixed(1) (4.9) — this is the whole point '
            'of the card-unification change: rating on the salon picker, '
            'which the deleted bespoke row never showed.',
      );
      expect(
        find.descendant(of: m1Row, matching: find.text('(12)')),
        findsOneWidget,
        reason: 'reviewCount (12) > 0 -> the parenthetical suffix must render',
      );

      final Finder m2Row = find.byKey(const Key('salon_booking_master_row_m2'));
      expect(
        find.descendant(of: m2Row, matching: find.text('5.0')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: m2Row, matching: find.text('(3)')),
        findsOneWidget,
      );
    },
  );

  // mobile-qa gap (M2-adjacent, KNOWN COVERAGE GAP): the picker is the ONLY
  // one of the nine `MasterStrip` call sites that sets `showLabel: false` —
  // no master has been chosen yet here, so the muted "Запис до майстра"
  // caption every OTHER booking screen shows would be both untrue and
  // repeated once per row. A regression that dropped (or flipped) the flag
  // would silently reintroduce it.
  testWidgets(
    'the picker\'s master rows never render the "Запис до майстра" caption '
    '(showLabel: false — no master has been chosen yet)',
    (tester) async {
      await _pumpTall(tester);
      await tester.pumpRoutedApp(_routerFor(), overrides: _overrides());
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(SalonMasterSelectionScreen)),
      );
      expect(find.text(l10n.bookingMasterStripLabel), findsNothing);
    },
  );

  // mobile-qa gap-fix — the pinned `_AssignConfirmBar`'s new composition of
  // `SelectedServicesShelf` (the "always show selected services" bottom bar
  // behaviour) had NO coverage: every test above only drives the master-pick
  // interaction, never the shelf pinned above the bar's own "Разом"/assigned-
  // progress/CTA content. The main regression risk is the shelf's own toggle
  // interfering with — or hiding — that pre-existing content, so this group
  // expands the shelf and re-asserts the progress counter + CTA both survive.
  group('selected-services shelf composition (mobile-qa gap-fix)', () {
    const Key toggleKey = Key('booking-summary-expand-toggle');
    const Key expandedListKey = Key('booking-summary-expanded-list');

    // Every eligible master row ALSO renders a "covers: <service names>"
    // subtitle sourced from the SAME [_svc1]/[_svc2] fixture names, so a raw
    // unscoped `find.text(_svc1.name)` would match BOTH that subtitle AND
    // the shelf's own itemized entry — scope every assertion to the shelf's
    // `expanded-list` subtree so it only ever proves the SHELF's own
    // content, never coincides with an unrelated row.
    Finder inShelf(Finder matching) =>
        find.descendant(of: find.byKey(expandedListKey), matching: matching);

    testWidgets('expanding the shelf shows every client-selected service (both '
        'svc-1 and svc-2, regardless of assignment state) while the assign '
        'progress counter and CTA stay in place', (tester) async {
      await _pumpTall(tester);
      await tester.pumpRoutedApp(_routerFor(), overrides: _overrides());
      await tester.pumpAndSettle();

      // Collapsed: the shelf's own itemized list is not built at all yet.
      expect(find.byKey(expandedListKey), findsNothing);

      await tester.tap(find.byKey(toggleKey));
      await tester.pumpAndSettle();

      // i18n-finder-ok: fixture service names (test data), not app UI copy.
      expect(inShelf(find.text(_svc1.name)), findsOneWidget);
      // i18n-finder-ok: fixture service names (test data), not app UI copy.
      expect(inShelf(find.text(_svc2.name)), findsOneWidget);

      // The pre-existing "N assigned" progress counter + CTA must still be
      // present once the shelf is expanded — the regression risk this
      // change introduces.
      final l10n = AppLocalizations.of(
        tester.element(find.byType(SalonMasterSelectionScreen)),
      );
      expect(
        find.text(l10n.salonBookingAssignedProgress(0, 2)),
        findsOneWidget,
      );
      final NeumorphicButton cta = tester.widget<NeumorphicButton>(
        find.byKey(const Key('salon-assign-confirm-cta')),
      );
      expect(cta.onPressed, isNull); // nothing assigned yet
    });

    testWidgets(
      'the assign progress counter updates and the CTA stays reachable '
      'after assigning a master, even with the shelf left expanded',
      (tester) async {
        await _pumpTall(tester);
        await tester.pumpRoutedApp(_routerFor(), overrides: _overrides());
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(toggleKey));
        await tester.pumpAndSettle();
        // i18n-finder-ok: fixture service name (test data), not app UI copy.
        expect(inShelf(find.text(_svc1.name)), findsOneWidget);

        // Pick m1 (covers ONLY svc-1) -> svc-1 auto-attaches; svc-2 stays
        // unassigned (m1 doesn't cover it).
        await tester.tap(find.byKey(const Key('salon_booking_master_row_m1')));
        await tester.pumpAndSettle();

        final l10n = AppLocalizations.of(
          tester.element(find.byType(SalonMasterSelectionScreen)),
        );
        expect(
          find.text(l10n.salonBookingAssignedProgress(1, 2)),
          findsOneWidget,
          reason:
              'the shelf remaining expanded must not prevent the '
              '_ProgressHint from rebuilding with the new assigned count',
        );
        // The itemized shelf list must still be intact after the pick too.
        // i18n-finder-ok: fixture service name (test data), not app UI copy.
        expect(inShelf(find.text(_svc1.name)), findsOneWidget);
      },
    );
  });

  // ===========================================================================
  // ScreenProtectionManager lifecycle (mobile-security MEDIUM fix — this
  // screen now renders the client's selected service names + prices via
  // `SelectedServicesShelf` inside the pinned `_AssignConfirmBar`). Mirrors
  // `salon_booking_confirm_screen_test.dart`'s established acquire/release
  // pattern.
  // ===========================================================================
  group('ScreenProtectionManager lifecycle (mobile-security gap-fix)', () {
    testWidgets(
      'acquire() is called exactly once when the master-selection screen '
      'mounts',
      (tester) async {
        await _pumpTall(tester);
        final GoRouter router = _pushableRouter();
        final _CountingScreenProtection counting = _CountingScreenProtection();

        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[
            ..._overrides(),
            screenProtectionProvider.overrideWithValue(counting),
          ],
        );
        unawaited(router.push(RouteNames.salonBookingMasters));
        await tester.pumpAndSettle();

        expect(
          counting.acquireCount,
          1,
          reason:
              'initState must call acquire() exactly once to enable '
              'FLAG_SECURE now that this screen renders selected service '
              'names + prices via SelectedServicesShelf',
        );
      },
    );

    testWidgets(
      'release() is called exactly once when the master-selection screen is '
      'popped (disposed) — acquire/release stay symmetric',
      (tester) async {
        await _pumpTall(tester);
        final GoRouter router = _pushableRouter();
        final _CountingScreenProtection counting = _CountingScreenProtection();

        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[
            ..._overrides(),
            screenProtectionProvider.overrideWithValue(counting),
          ],
        );
        unawaited(router.push(RouteNames.salonBookingMasters));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('salon-master-selection-back')));
        await tester.pumpAndSettle();

        expect(
          counting.releaseCount,
          1,
          reason:
              'dispose() must call release() exactly once so FLAG_SECURE is '
              'cleared once the master-selection screen is popped',
        );
        expect(counting.acquireCount, counting.releaseCount);
      },
    );
  });

  // ===========================================================================
  // Security MEDIUM — the FOURTH unguarded money-string builder.
  //
  // `_AssignConfirmBar.build` hand-built its own
  // `'${minSum.toStringAsFixed(0)}–${maxSum.toStringAsFixed(0)} ₴'` from
  // `_totals`, which summed `SalonCatalogService.priceMin`/`priceMax` — the
  // same unclamped wire doubles `salon_mapper.dart` passes straight through —
  // with NO `isRenderablePrice` gate at term OR sum level.
  //
  // Verified in Dart against the pre-fix expression:
  //   priceMin: double.infinity  ->  «Infinity ₴»
  //   priceMin: -0.0             ->  «-0 ₴»
  //   priceMin: 1e30             ->  «1e+30 ₴»
  //   priceMin: 1e30 + -1e30     ->  «0 ₴»   (a confident, fictional total)
  //   priceMin: double.nan       ->  «NaN–NaN ₴» (NaN != NaN takes the band)
  //
  // Unlike `BookingRecap`'s int-coercing sibling this NEVER threw — it coerces
  // nothing — which is exactly why it survived three rounds of consolidation:
  // it had no crash to announce itself with. It just quietly stated a
  // fictional price on the screen where the client commits to it.
  //
  // The CONTROL case at the end is what makes this group honest: a blanket
  // "always render —" mutation would satisfy every hostile case above and fail
  // only the control.
  // ===========================================================================

  group('_AssignConfirmBar totals — unrenderable wire prices', () {
    /// A hostile svc-1 whose `priceMin` is [bad]. `priceDisplay` stays a
    /// well-formed string so the only route a garbage figure can take onto the
    /// screen is the confirm bar's own summation — not the shelf echoing a
    /// pre-broken display string back at us.
    SalonCatalogService hostileSvc1(double bad) => SalonCatalogService(
      id: 'svc-1',
      name: 'Манікюр з покриттям',
      durationLabel: '1 год 30 хв',
      priceDisplay: '500 ₴',
      durationMinutes: 90,
      priceType: ServicePriceType.fixed,
      priceMin: bad,
    );

    /// Overrides pinning a single-service selection (svc-1 only, covered by
    /// m1) whose catalogue entry carries [services].
    List<Object> hostileOverrides(List<SalonCatalogService> services) {
      const args = SalonBookingMasterSelectionArgs(
        salonId: _kSalonId,
        selectedServiceIds: <String>['svc-1', 'svc-2'],
      );
      return <Object>[
        publicSalonProfileProvider(
          _kSalonId,
        ).overrideWith((ref) => (_stubSalon, _stubMasters)),
        salonServiceCatalogProvider(_kSalonId).overrideWith(
          (ref) => <SalonServiceCategoryEntry>[
            SalonServiceCategoryEntry(
              category: 'MANICURE',
              displayName: 'Манікюр',
              count: services.length,
              services: services,
            ),
          ],
        ),
        salonMasterServiceCoverageProvider(args).overrideWith(
          () => FakeSalonMasterServiceCoverage(
            () => salonCoverageOf(_stubCoverage),
          ),
        ),
      ];
    }

    /// Every rendered `Text` string in the tree — asserts no garbage figure
    /// leaked into ANY node, not merely the one a scoped finder looked at.
    List<String> renderedTexts(WidgetTester tester) => tester
        .widgetList<Text>(find.byType(Text))
        .map((Text t) => t.data ?? '')
        .toList();

    /// The confirm bar's price `Text`, located structurally (never by a
    /// Cyrillic literal): it is the last `Text` inside the bar's total row,
    /// so scope to the CTA's enclosing bar and read every `Text` there.
    List<String> confirmBarTexts(WidgetTester tester) => tester
        .widgetList<Text>(
          find.descendant(
            of: find
                .ancestor(
                  of: find.byKey(const Key('salon-assign-confirm-cta')),
                  matching: find.byType(Column),
                )
                .last,
            matching: find.byType(Text),
          ),
        )
        .map((Text t) => t.data ?? '')
        .toList();

    Future<void> pumpHostile(
      WidgetTester tester,
      List<SalonCatalogService> services,
    ) async {
      await _pumpTall(tester);
      await tester.pumpRoutedApp(
        _routerFor(),
        overrides: hostileOverrides(services),
      );
      await tester.pumpAndSettle();
    }

    for (final (String name, double bad, String leak)
        in <(String, double, String)>[
          ('double.infinity', double.infinity, 'Infinity'),
          ('double.nan', double.nan, 'NaN'),
          ('1e30 (exponent-notation threshold)', 1e30, 'e+'),
        ]) {
      testWidgets(
        'a $name priceMin off the wire renders the neutral unavailable label, '
        'never «$leak ₴», in the assign confirm bar',
        (tester) async {
          await pumpHostile(tester, <SalonCatalogService>[
            hostileSvc1(bad),
            _svc2,
          ]);

          expect(tester.takeException(), isNull);
          expect(
            confirmBarTexts(tester),
            contains(priceUnavailableLabel),
            reason:
                'an unstatable total must fall back to the shared '
                'priceUnavailableLabel, exactly as every other «Разом» surface '
                'does — the whole band is poisoned rather than the bad term '
                'dropped, because dropping it would UNDERSTATE the price the '
                'client is agreeing to',
          );
          expect(
            renderedTexts(tester).where((String s) => s.contains(leak)),
            isEmpty,
            reason: '«$leak ₴» must never be stringified onto a screen',
          );
        },
      );
    }

    testWidgets(
      'a -0.0 priceMin does not render the leading minus «-0 ₴» — `>= 0` waves '
      'negative zero through, which is why isRenderablePrice uses isNegative',
      (tester) async {
        await pumpHostile(tester, <SalonCatalogService>[
          hostileSvc1(-0.0),
          _svc2,
        ]);

        expect(tester.takeException(), isNull);
        expect(confirmBarTexts(tester), contains(priceUnavailableLabel));
        expect(
          renderedTexts(
            tester,
          ).where((String s) => RegExp(r'-\s*\d').hasMatch(s)),
          isEmpty,
          reason:
              'a leading minus collides with the band en-dash into «-0–800 ₴»; '
              'no negative money figure may render on the commit screen',
        );
      },
    );

    testWidgets(
      'a CANCELLING PAIR (1e30 + -1e30 == 0.0) is poisoned by the PER-TERM '
      'gate — a sum-level check alone would state a confident, fictional «0 ₴»',
      (tester) async {
        await pumpHostile(tester, <SalonCatalogService>[
          hostileSvc1(1e30),
          const SalonCatalogService(
            id: 'svc-2',
            name: 'Педикюр',
            durationLabel: '2 год',
            priceDisplay: '800 ₴',
            durationMinutes: 120,
            priceType: ServicePriceType.fixed,
            priceMin: -1e30,
          ),
        ]);

        expect(tester.takeException(), isNull);
        expect(
          confirmBarTexts(tester),
          contains(priceUnavailableLabel),
          reason:
              'both terms are individually unrenderable but their SUM is '
              'exactly 0.0 and passes isRenderablePrice; only a per-term gate '
              'catches this, which is why the gate is not applied to the sums '
              'alone',
        );
        expect(
          confirmBarTexts(tester).where((String s) => s.contains('0 ₴')),
          isEmpty,
          reason: 'the fictional «0 ₴» total must not be stated',
        );
      },
    );

    testWidgets(
      'CONTROL — well-formed prices still render the real band, so a blanket '
      '"always render —" mutation cannot satisfy this group',
      (tester) async {
        await pumpHostile(tester, const <SalonCatalogService>[_svc1, _svc2]);

        expect(tester.takeException(), isNull);

        final List<String> texts = confirmBarTexts(tester);
        expect(
          texts,
          contains('1300 ₴'),
          reason:
              'svc1 (500) + svc2 (800), both FIXED, collapse to a degenerate '
              'band and must render as the real total',
        );
        expect(
          texts,
          isNot(contains(priceUnavailableLabel)),
          reason:
              'a renderable selection must never fall back to the unavailable '
              'label — this is the mutation guard for the four cases above',
        );
      },
    );
  });

  // ---------------------------------------------------------------------
  // Phase 266 D5 — the degraded-service retry row. Doc test case 6
  // (`phase-266-coverage-degraded-service-set.md`): a service whose OWN
  // coverage fetch failed must render as a RETRYABLE error, never the
  // terminal `_UncoveredRow` a genuine "nobody performs this" gets.
  // ---------------------------------------------------------------------
  group('Phase 266 — degraded-service retry row', () {
    testWidgets('should_renderRetryNotUncovered_when_theServiceIsDegraded', (
      tester,
    ) async {
      await _pumpTall(tester);
      final repo = _MockSalonRepository();
      // NO `salonMasterServiceCoverageProvider` override in this test — the
      // REAL `SalonMasterServiceCoverage` runs against this mocked
      // repository, so this test is sensitive to the SAME mutation
      // `salon_master_coverage_notifier_test.dart`'s case 2 guards (the
      // catch block silently omitting a failed id from
      // `degradedServiceIds`): mutating that catch block would make THIS
      // test render `_UncoveredRow` for svc-2 instead of the retry row,
      // exactly the doc's "cases 2 and 6 go RED" mutation check.
      //
      // svc-1 covered by m1 (real coverage); svc-2's fetch FAILS on the
      // initial load, so `eligible` stays non-empty (m1 qualifies via
      // svc-1) and this exercises the grouping-preview row, not the
      // eligible-empty branch.
      when(
        () =>
            repo.getBookableMasters(salonId: _kSalonId, serviceDefId: 'svc-1'),
      ).thenAnswer(
        (_) async => const <BookableMasterAssignment>[
          (masterId: 'm1', masterServiceId: 'assignment-m1-svc-1'),
        ],
      );
      when(
        () =>
            repo.getBookableMasters(salonId: _kSalonId, serviceDefId: 'svc-2'),
      ).thenThrow(const NetworkFailure());

      await tester.pumpRoutedApp(
        _routerFor(),
        overrides: <Object>[
          publicSalonProfileProvider(
            _kSalonId,
          ).overrideWith((ref) => (_stubSalon, _stubMasters)),
          salonServiceCatalogProvider(
            _kSalonId,
          ).overrideWith((ref) => _stubCatalog),
          salonRepositoryProvider.overrideWithValue(repo),
        ],
      );
      await tester.pumpAndSettle();

      // m1 (real coverage on svc-1) renders; pick it so the grouping
      // preview mounts (it is gated behind `hasPicks`, same as every
      // other row in this preview — see `_MasterGroupingPreview`).
      await tester.tap(find.byKey(const Key('salon_booking_master_row_m1')));
      await tester.pumpAndSettle();

      final Finder degradedRow = find.byKey(
        const Key('salon_booking_degraded_service_svc-2'),
      );
      final Finder retryButton = find.byKey(
        const Key('salon_booking_retry_service_svc-2'),
      );
      expect(
        degradedRow,
        findsOneWidget,
        reason: 'svc-2 is DEGRADED — it must render the retry row',
      );
      expect(retryButton, findsOneWidget);
      // The MUTATION this doc case guards: a degraded service must never
      // ALSO satisfy the terminal uncovered semantics — the two rows are
      // mutually exclusive per service (see `_MasterSelectionDerived
      // .uncovered`/`.degraded`). The exact `_UncoveredRow` text is asserted
      // (not `textContaining`), because "Педикюр" alone legitimately
      // recurs elsewhere on this screen (the selected-services shelf) — a
      // substring match would find those and give a false negative.
      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(SalonMasterSelectionScreen)),
      );
      expect(
        // i18n-finder-ok: locale-coupled by design — this line's ONLY job is
        // proving the two rows are mutually exclusive for the SAME service;
        // an EN build needs the EN copy here, which is fine, not a gap.
        find.text(l10n.salonBookingUncoveredSemantics('Педикюр')),
        findsNothing,
        reason:
            'svc-2 must NOT ALSO render as the terminal _UncoveredRow — '
            'that identical rendering is the exact defect Phase 266 fixes',
      );

      // Re-stub svc-2 to succeed — simulates "the client tapped retry
      // after the transient failure cleared".
      when(
        () =>
            repo.getBookableMasters(salonId: _kSalonId, serviceDefId: 'svc-2'),
      ).thenAnswer(
        (_) async => const <BookableMasterAssignment>[
          (masterId: 'm2', masterServiceId: 'assignment-m2-svc-2'),
        ],
      );

      await tester.tap(retryButton);
      await tester.pumpAndSettle();

      expect(
        degradedRow,
        findsNothing,
        reason: 'the retry resolved — svc-2 is no longer degraded',
      );
      expect(
        find.byKey(const Key('salon_booking_master_row_m2')),
        findsOneWidget,
        reason:
            'the retry revealed m2 as a real, newly-eligible covering '
            'master for svc-2 — proof the retry actually reached the '
            'repository and merged a real result, not a stub no-op',
      );
      // Two calls total for svc-2: the initial failing fetch + the one
      // retry — never a re-fetch of svc-1 (D4: never the whole family).
      verify(
        () =>
            repo.getBookableMasters(salonId: _kSalonId, serviceDefId: 'svc-2'),
      ).called(2);
      verify(
        () =>
            repo.getBookableMasters(salonId: _kSalonId, serviceDefId: 'svc-1'),
      ).called(1);
    });
  });

  // ---------------------------------------------------------------------
  // Phase 266, AUDIT CYCLE 1 — verifier LOW #8 (in-flight UI reflection)
  // and LOW #9 (memoized `_MasterSelectionStatic`). Both against the REAL
  // `SalonMasterServiceCoverage` notifier (never `FakeSalonMasterServiceCoverage`)
  // so the network call actually has an observable in-flight window.
  // ---------------------------------------------------------------------
  group('Phase 266 audit cycle 1 — retry in-flight UI + memoization', () {
    setUp(debugResetResolveMasterSelectionStaticCallCount);

    testWidgets(
      'the retry row shows an in-flight spinner while its own retry is '
      'awaiting the network, and a second tap while retrying issues no '
      'second repo call',
      (tester) async {
        await _pumpTall(tester);
        final repo = _MockSalonRepository();
        when(
          () => repo.getBookableMasters(
            salonId: _kSalonId,
            serviceDefId: 'svc-1',
          ),
        ).thenAnswer(
          (_) async => const <BookableMasterAssignment>[
            (masterId: 'm1', masterServiceId: 'assignment-m1-svc-1'),
          ],
        );
        // svc-2 FAILS on the INITIAL fetch, exactly like the sibling
        // "degraded-service retry row" test above — the Completer below is
        // wired in ONLY for the RETRY call, re-stubbed after the initial
        // settle; using it from the start would stall build() itself (both
        // services fit in one `_kFetchChunkSize` chunk, so `Future.wait`
        // would never resolve).
        when(
          () => repo.getBookableMasters(
            salonId: _kSalonId,
            serviceDefId: 'svc-2',
          ),
        ).thenThrow(const NetworkFailure());

        await tester.pumpRoutedApp(
          _routerFor(),
          overrides: <Object>[
            publicSalonProfileProvider(
              _kSalonId,
            ).overrideWith((ref) => (_stubSalon, _stubMasters)),
            salonServiceCatalogProvider(
              _kSalonId,
            ).overrideWith((ref) => _stubCatalog),
            salonRepositoryProvider.overrideWithValue(repo),
          ],
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('salon_booking_master_row_m1')));
        await tester.pumpAndSettle();

        final Finder retryButton = find.byKey(
          const Key('salon_booking_retry_service_svc-2'),
        );
        expect(retryButton, findsOneWidget);
        expect(
          find.descendant(
            of: retryButton,
            matching: find.byType(CircularProgressIndicator),
          ),
          findsNothing,
          reason: 'not retrying yet — the plain "Retry" link renders',
        );

        final svc2 = Completer<List<BookableMasterAssignment>>();
        when(
          () => repo.getBookableMasters(
            salonId: _kSalonId,
            serviceDefId: 'svc-2',
          ),
        ).thenAnswer((_) => svc2.future);

        await tester.tap(retryButton);
        // ONE pump — lets the in-flight state write land WITHOUT resolving
        // `svc2` (a `pumpAndSettle` here would hang waiting on the never-
        // completed `Completer`).
        await tester.pump();

        expect(
          find.descendant(
            of: retryButton,
            matching: find.byType(CircularProgressIndicator),
          ),
          findsOneWidget,
          reason: 'a request for svc-2 is now in flight',
        );

        // A second tap while retrying: the `GestureDetector`'s `onTap` is
        // `null` while disabled, so this must not issue a second repo call.
        await tester.tap(retryButton);
        await tester.pump();

        // `pump()`, never `pumpAndSettle()`, from here — `pumpAndSettle`
        // never converges while the spinner's INDETERMINATE
        // `CircularProgressIndicator` is still mounted (mirrors
        // `salon_invite_row_test.dart`'s identical "while cancelling"
        // case, which uses only `pump()` for the same reason). Two pumps:
        // one to let the completed Future's continuation (`_settle`'s
        // state write) run, one to let the resulting rebuild remove the
        // now-resolved row from the tree.
        svc2.complete(const <BookableMasterAssignment>[
          (masterId: 'm2', masterServiceId: 'assignment-m2-svc-2'),
        ]);
        await tester.pump();
        await tester.pump();

        verify(
          () => repo.getBookableMasters(
            salonId: _kSalonId,
            serviceDefId: 'svc-2',
          ),
        ).called(2); // the initial failing fetch + the ONE retry — the
        // second tap while retrying issued no third call
      },
    );

    testWidgets('an in-flight retry state change alone does not recompute '
        '_MasterSelectionStatic — only a genuine coverage/master data change '
        'does', (tester) async {
      await _pumpTall(tester);
      final repo = _MockSalonRepository();
      when(
        () =>
            repo.getBookableMasters(salonId: _kSalonId, serviceDefId: 'svc-1'),
      ).thenAnswer(
        (_) async => const <BookableMasterAssignment>[
          (masterId: 'm1', masterServiceId: 'assignment-m1-svc-1'),
        ],
      );
      // svc-2 FAILS on the INITIAL fetch — see the sibling test's identical
      // note on why the Completer below is wired in only for the retry.
      when(
        () =>
            repo.getBookableMasters(salonId: _kSalonId, serviceDefId: 'svc-2'),
      ).thenThrow(const NetworkFailure());

      await tester.pumpRoutedApp(
        _routerFor(),
        overrides: <Object>[
          publicSalonProfileProvider(
            _kSalonId,
          ).overrideWith((ref) => (_stubSalon, _stubMasters)),
          salonServiceCatalogProvider(
            _kSalonId,
          ).overrideWith((ref) => _stubCatalog),
          salonRepositoryProvider.overrideWithValue(repo),
        ],
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('salon_booking_master_row_m1')));
      await tester.pumpAndSettle();

      expect(
        debugResolveMasterSelectionStaticCallCount,
        1,
        reason: 'one recompute for the initial resolved masters/coverage',
      );

      final svc2 = Completer<List<BookableMasterAssignment>>();
      when(
        () =>
            repo.getBookableMasters(salonId: _kSalonId, serviceDefId: 'svc-2'),
      ).thenAnswer((_) => svc2.future);

      await tester.tap(
        find.byKey(const Key('salon_booking_retry_service_svc-2')),
      );
      await tester.pump(); // the in-flight-marking state write only

      expect(
        debugResolveMasterSelectionStaticCallCount,
        1,
        reason:
            "retryService's in-flight write reuses byMaster/"
            'degradedServiceIds BY REFERENCE — must not force a recompute',
      );

      // `pump()`, never `pumpAndSettle()` — see the sibling test's identical
      // note on why `pumpAndSettle` cannot be used while the row's spinner
      // is mounted.
      svc2.complete(const <BookableMasterAssignment>[
        (masterId: 'm2', masterServiceId: 'assignment-m2-svc-2'),
      ]);
      await tester.pump();
      await tester.pump();

      expect(
        debugResolveMasterSelectionStaticCallCount,
        2,
        reason:
            'the merged retry result genuinely changed byMaster/'
            'degradedServiceIds — this recompute is expected, proving the '
            'memo invalidates on REAL data changes, not just always '
            'hitting',
      );
    });
  });

  // ---------------------------------------------------------------------
  // Phase 266, AUDIT CYCLE 2 — MEDIUM #2: the cooldown needs its OWN expiry
  // trigger. Against the REAL `SalonMasterServiceCoverage` notifier (never
  // `FakeSalonMasterServiceCoverage`), so the notifier's cooldown-expiry
  // `Timer` (see `salon_master_coverage_notifier.dart`'s "PHASE 266, AUDIT
  // CYCLE 2" note) is the thing actually under test — `tester.pump(duration)`
  // advances the SAME fake-Timer clock `flutter_test` already runs widget
  // tests under, so no `fakeAsync`/`clockProvider` override is needed here
  // (unlike the notifier-level unit test, which pins `clockProvider` too):
  // the Timer's firing, not any `DateTime` comparison, is what clears the
  // row.
  // ---------------------------------------------------------------------
  group('Phase 266 audit cycle 2 — cooldown re-enable', () {
    testWidgets(
      'after a FAILED retry the row is disabled, and once the cooldown '
      'window elapses on its own it re-enables WITHOUT any other tap or '
      'interaction',
      (tester) async {
        await _pumpTall(tester);
        final repo = _MockSalonRepository();
        when(
          () => repo.getBookableMasters(
            salonId: _kSalonId,
            serviceDefId: 'svc-1',
          ),
        ).thenAnswer(
          (_) async => const <BookableMasterAssignment>[
            (masterId: 'm1', masterServiceId: 'assignment-m1-svc-1'),
          ],
        );
        // svc-2 fails on the initial fetch AND on the retry below — the
        // retry's own failure is what starts the cooldown this test pins.
        when(
          () => repo.getBookableMasters(
            salonId: _kSalonId,
            serviceDefId: 'svc-2',
          ),
        ).thenThrow(const NetworkFailure());

        await tester.pumpRoutedApp(
          _routerFor(),
          overrides: <Object>[
            publicSalonProfileProvider(
              _kSalonId,
            ).overrideWith((ref) => (_stubSalon, _stubMasters)),
            salonServiceCatalogProvider(
              _kSalonId,
            ).overrideWith((ref) => _stubCatalog),
            salonRepositoryProvider.overrideWithValue(repo),
          ],
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('salon_booking_master_row_m1')));
        await tester.pumpAndSettle();

        final Finder retryButton = find.byKey(
          const Key('salon_booking_retry_service_svc-2'),
        );
        expect(retryButton, findsOneWidget);

        // The retry ALSO fails (same stub as the initial fetch) — svc-2
        // stays degraded and its cooldown starts.
        await tester.tap(retryButton);
        await tester.pumpAndSettle();

        GestureDetector row = tester.widget<GestureDetector>(retryButton);
        expect(
          row.onTap,
          isNull,
          reason:
              'a just-failed retry must leave the row disabled for the '
              'cooldown window',
        );

        // Advance PAST the cooldown window with no further interaction —
        // no second tap, no unrelated provider invalidation. If the
        // notifier's cooldown-expiry Timer were never armed (or were
        // scheduled and then not scheduled at all), this row would stay
        // disabled forever, exactly the audit finding.
        // fixed-wait-ok: crossing `_kRetryCooldown` (3s) is the exact TTL
        // this test proves the Timer fires against — 4s is comfortably past
        // it, and the assertion is that the row re-enables, not a race on
        // timing.
        await tester.pump(const Duration(seconds: 4));

        row = tester.widget<GestureDetector>(retryButton);
        expect(
          row.onTap,
          isNotNull,
          reason:
              'the cooldown elapsed on its own — the row must re-enable '
              'without any other interaction triggering the rebuild',
        );
      },
    );
  });

  // ---------------------------------------------------------------------
  // Phase 266, AUDIT CYCLE 3, finding #2 — `FakeSalonMasterServiceCoverage`
  // (`test/helpers/fake_salon_master_coverage.dart`) OVERRIDES `build()`
  // wholesale rather than calling through to the real one (Dart never
  // chains an overridden method to its superclass's body automatically), so
  // before this fix it never registered the real `build()`'s own
  // `ref.onDispose(cancelCooldownTimers)` cleanup. A FAILED `retryService`
  // call still arms a REAL cooldown-expiry `Timer` via the INHERITED
  // `_armCooldownExpiry` (never overridden by the fake either) — so a
  // widget test using the fake that exercises a failing retry used to leave
  // that Timer pending past the widget tree's own teardown. Unlike the
  // cycle-2 test above, this test deliberately never pumps past
  // `_kRetryCooldown` — reaching the end of the test body at all, without
  // `flutter_test` failing it at teardown with "A Timer is still pending",
  // is the proof the fake's cleanup registration works.
  // ---------------------------------------------------------------------
  group('Phase 266 audit cycle 3 — FakeSalonMasterServiceCoverage cooldown-'
      'timer cleanup', () {
    testWidgets('a FAILED retry against the FAKE coverage notifier leaves no '
        'pending cooldown Timer at teardown', (tester) async {
      await _pumpTall(tester);
      final repo = _MockSalonRepository();
      when(
        () =>
            repo.getBookableMasters(salonId: _kSalonId, serviceDefId: 'svc-2'),
      ).thenThrow(const NetworkFailure());

      // svc-2 already degraded on first paint (`salonCoverageOf` always
      // sets an EMPTY degraded set, so this test builds the record by
      // hand) — the retry row renders immediately, no need to reach it
      // via an initial failing fetch first.
      const SalonCoverage initial = (
        byMaster: <String, Map<String, String>>{
          'm1': <String, String>{'svc-1': 'assignment-m1-svc-1'},
        },
        degradedServiceIds: <String>{'svc-2'},
        retryingServiceIds: <String>{},
        retryCooldownUntil: <String, DateTime>{},
      );

      await tester.pumpRoutedApp(
        _routerFor(),
        overrides: <Object>[
          publicSalonProfileProvider(
            _kSalonId,
          ).overrideWith((ref) => (_stubSalon, _stubMasters)),
          salonServiceCatalogProvider(
            _kSalonId,
          ).overrideWith((ref) => _stubCatalog),
          salonRepositoryProvider.overrideWithValue(repo),
          salonMasterServiceCoverageProvider(
            _args(),
          ).overrideWith(() => FakeSalonMasterServiceCoverage(() => initial)),
        ],
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('salon_booking_master_row_m1')));
      await tester.pumpAndSettle();

      final Finder retryButton = find.byKey(
        const Key('salon_booking_retry_service_svc-2'),
      );
      expect(retryButton, findsOneWidget);

      // The retry FAILS again — this reaches the inherited (never
      // overridden by the fake) `retryService`/`_armCooldownExpiry`,
      // arming a real pending `Timer` on the fake notifier instance.
      await tester.tap(retryButton);
      await tester.pumpAndSettle();

      final GestureDetector row = tester.widget<GestureDetector>(retryButton);
      expect(
        row.onTap,
        isNull,
        reason:
            'the failed retry must leave the row disabled — proof the '
            'cooldown Timer was genuinely armed, not skipped entirely',
      );

      // Deliberately NO `tester.pump(Duration(seconds: ...))` here — the
      // cooldown Timer is left PENDING on purpose, unlike the cycle-2
      // test above. If `FakeSalonMasterServiceCoverage` still failed to
      // cancel it on dispose, `flutter_test` would fail this test right
      // here at teardown instead of letting it reach this point clean.
    });
  });
}

// Phase 2.18 — Widget tests for [LocalityCascade] + the bottom-sheet picker.
//
// SOURCE OF TRUTH: docs/signup-designs/sign-up-step-3-address.html (picker-row
// + sheet behaviour).
//
// Covered scenarios (6 minimum per spec Step 7):
//   1. Initial state: only the Oblast row is enabled; City + District disabled.
//   2. After an Oblast is selected: City unlocks; District still disabled.
//   3. After a City WITH districts is selected: District unlocks.
//   4. After a City WITHOUT districts: District is disabled + shows the helper
//      line and is not tappable.
//   5. The bottom sheet shows a search field; typing filters the list.
//   6. Selecting a value pops the sheet and fires the callback.
//
// Strategy: override [locationRepositoryProvider] with a hand-written fake so
// all three list providers resolve through it. A small stateful harness owns
// the selection state and rebuilds the cascade on each callback, mirroring how
// Phase 2.19's Step 3 screen will consume it.

import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/location/data/location_repository.dart';
import 'package:beautica_mobile/features/location/domain/city.dart';
import 'package:beautica_mobile/features/location/domain/city_district.dart';
import 'package:beautica_mobile/features/location/domain/oblast.dart';
import 'package:beautica_mobile/features/location/presentation/widgets/locality_cascade.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _oblast = Oblast(id: 'o1', name: 'Львівська', katotthCode: 'UA46');
const _cityWithDistricts = City(
  id: 'c1',
  oblastId: 'o1',
  name: 'Львів',
  katotthCode: 'UA4610',
  hasDistricts: true,
);
const _cityNoDistricts = City(
  id: 'c2',
  oblastId: 'o1',
  name: 'Дрогобич',
  katotthCode: 'UA4620',
  hasDistricts: false,
);
const _district = CityDistrict(
  id: 'd1',
  cityId: 'c1',
  name: 'Галицький',
  katotthCode: 'UA4610136',
);

// ---------------------------------------------------------------------------
// Fake repository
// ---------------------------------------------------------------------------

class _FakeLocationRepository implements LocationRepository {
  @override
  Future<List<Oblast>> fetchOblasts() async => const [
    _oblast,
    Oblast(id: 'o2', name: 'Київська', katotthCode: 'UA32'),
  ];

  @override
  Future<List<City>> fetchCities(String oblastId) async => const [
    _cityWithDistricts,
    _cityNoDistricts,
  ];

  @override
  Future<List<CityDistrict>> fetchDistricts(String cityId) async => const [
    _district,
    CityDistrict(
      id: 'd2',
      cityId: 'c1',
      name: 'Личаківський',
      katotthCode: 'UA4610137',
    ),
  ];
}

// ---------------------------------------------------------------------------
// Test harness — owns selection state and rebuilds the cascade.
// ---------------------------------------------------------------------------

class _CascadeHarness extends StatefulWidget {
  const _CascadeHarness({
    this.initialCity,
    this.onDistrictSelected,
    this.showDistrictNoneHelper = true,
    this.oblastError,
    this.cityError,
    this.districtError,
  });

  final City? initialCity;
  final ValueChanged<CityDistrict?>? onDistrictSelected;
  final bool showDistrictNoneHelper;
  final String? oblastError;
  final String? cityError;
  final String? districtError;

  @override
  State<_CascadeHarness> createState() => _CascadeHarnessState();
}

class _CascadeHarnessState extends State<_CascadeHarness> {
  Oblast? _oblast;
  City? _city;
  CityDistrict? _district;

  @override
  void initState() {
    super.initState();
    // Allow seeding an already-selected oblast + city for tests 3/4/5/6 so the
    // City and District rows start enabled without driving the sheet flow.
    final city = widget.initialCity;
    if (city != null) {
      _oblast = const Oblast(id: 'o1', name: 'Львівська', katotthCode: 'UA46');
      _city = city;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LocalityCascade(
      selectedOblast: _oblast,
      selectedCity: _city,
      selectedDistrict: _district,
      showDistrictNoneHelper: widget.showDistrictNoneHelper,
      oblastError: widget.oblastError,
      cityError: widget.cityError,
      districtError: widget.districtError,
      onOblast: (o) => setState(() => _oblast = o),
      onCity: (c) => setState(() => _city = c),
      onDistrict: (d) {
        setState(() => _district = d);
        widget.onDistrictSelected?.call(d);
      },
    );
  }
}

Widget _wrap(Widget child) {
  // GoRouter is required so the picker sheet's context.pop() call (go_router)
  // resolves the InheritedGoRouter. A single '/' route is sufficient — the
  // cascade tests never navigate away from the home scaffold.
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(
          body: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    ],
  );

  return ProviderScope(
    retry: beauticaProviderRetry,
    overrides: [
      locationRepositoryProvider.overrideWith((_) => _FakeLocationRepository()),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('uk'),
    ),
  );
}

// Reports whether the LocalityTapRow keyed [rowKey] is currently interactive.
// The VelvetTouch redesign replaced the InkWell(key:…) pattern with
// IgnorePointer(ignoring: !enabled) — check its `ignoring` property instead.
bool _rowEnabled(WidgetTester tester, Key rowKey) {
  final ip = tester.widget<IgnorePointer>(
    find.descendant(
      of: find.byKey(rowKey),
      matching: find.byType(IgnorePointer),
    ),
  );
  return !ip.ignoring;
}

// Resolves localized strings from the live tree so assertions never hard-code
// a UA literal (M2 — Key-less helper line is matched by its l10n value).
AppLocalizations _l10n(WidgetTester tester) => AppLocalizations.of(
  tester.element(find.byKey(const Key('locality_row_oblast'))),
);

// Reads the label text of the picker tile keyed by the item's [id] inside the
// open sheet. Tiles are keyed by the item's stable UUID
// (ValueKey('locality_picker_tile_<id>')) — homonymous settlements share a
// `nameUk`, so the key derives from `id`, not the displayed label. We resolve
// by id, never by index, and assert the rendered label separately.
String _tileText(WidgetTester tester, String id) {
  return tester
      .widget<Text>(
        find.descendant(
          of: find.byKey(ValueKey('locality_picker_tile_$id')),
          matching: find.byType(Text),
        ),
      )
      .data!;
}

void main() {
  group('LocalityCascade', () {
    testWidgets('1. initial: only Oblast enabled', (tester) async {
      await tester.pumpWidget(_wrap(const _CascadeHarness()));
      await tester.pump();

      expect(_rowEnabled(tester, const Key('locality_row_oblast')), isTrue);
      expect(_rowEnabled(tester, const Key('locality_row_city')), isFalse);
      expect(_rowEnabled(tester, const Key('locality_row_district')), isFalse);
    });

    testWidgets('2. selecting an Oblast unlocks City (District stays locked)', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const _CascadeHarness()));
      await tester.pump();

      await tester.tap(find.byKey(const Key('locality_row_oblast')));
      await tester.pumpAndSettle(); // open sheet + resolve list future

      await tester.tap(find.text('Львівська'));
      await tester.pumpAndSettle(); // pop sheet

      expect(_rowEnabled(tester, const Key('locality_row_city')), isTrue);
      expect(_rowEnabled(tester, const Key('locality_row_district')), isFalse);
    });

    testWidgets('3. selecting a City WITH districts unlocks District', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const _CascadeHarness(initialCity: _cityWithDistricts)),
      );
      await tester.pump();

      expect(_rowEnabled(tester, const Key('locality_row_district')), isTrue);
      // No helper line in this state (matched via l10n, not a raw literal).
      expect(find.text(_l10n(tester).localityDistrictNoneHelper), findsNothing);
    });

    testWidgets('4. City WITHOUT districts → District disabled + helper', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const _CascadeHarness(initialCity: _cityNoDistricts)),
      );
      await tester.pump();

      expect(_rowEnabled(tester, const Key('locality_row_district')), isFalse);
      expect(
        find.text(_l10n(tester).localityDistrictNoneHelper),
        findsOneWidget,
      );

      // Tapping the disabled row must not open a sheet (no search field).
      await tester.tap(
        find.byKey(const Key('locality_row_district')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(find.byKey(const Key('locality_picker_search')), findsNothing);
    });

    testWidgets('5. sheet shows a search field that filters the list', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const _CascadeHarness(initialCity: _cityWithDistricts)),
      );
      await tester.pump();

      // Open the city picker (route + list future settle together).
      await tester.tap(find.byKey(const Key('locality_row_city')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('locality_picker_search')), findsOneWidget);
      // Both cities present before filtering (two tiles in the list). Tiles are
      // keyed by the item's stable UUID (ValueKey('locality_picker_tile_<id>'));
      // resolve them via the fixture .id field, never a raw UA literal.
      expect(
        find.byKey(ValueKey('locality_picker_tile_${_cityWithDistricts.id}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('locality_picker_tile_${_cityNoDistricts.id}')),
        findsOneWidget,
      );
      // Within the sheet's tiles, both city names render.
      expect(_tileText(tester, _cityWithDistricts.id), 'Львів');
      expect(_tileText(tester, _cityNoDistricts.id), 'Дрогобич');

      // Type a query that matches only Дрогобич. Explicit pump(Duration) here
      // (not pumpAndSettle) because the 200ms search debounce Timer never
      // "settles" on its own — we must advance virtual time past it.
      await tester.enterText(
        find.byKey(const Key('locality_picker_search')),
        'Дрог',
      );
      await tester.pump(const Duration(milliseconds: 250));

      // Filtering narrows the list to a single tile (Дрогобич).
      expect(
        find.byKey(ValueKey('locality_picker_tile_${_cityNoDistricts.id}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('locality_picker_tile_${_cityWithDistricts.id}')),
        findsNothing,
      );
      expect(_tileText(tester, _cityNoDistricts.id), 'Дрогобич');
    });

    testWidgets('6. selecting a value pops the sheet and fires callback', (
      tester,
    ) async {
      CityDistrict? fired;
      await tester.pumpWidget(
        _wrap(
          _CascadeHarness(
            initialCity: _cityWithDistricts,
            onDistrictSelected: (d) => fired = d,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('locality_row_district')));
      await tester.pumpAndSettle(); // open sheet + resolve list future

      expect(find.byKey(const Key('locality_picker_search')), findsOneWidget);

      await tester.tap(find.text('Галицький'));
      await tester.pumpAndSettle(); // pop animation completes

      // Sheet dismissed.
      expect(find.byKey(const Key('locality_picker_search')), findsNothing);
      // Callback fired with the chosen district.
      expect(fired, _district);
      // Row now shows the selected value.
      expect(
        find.descendant(
          of: find.byKey(const Key('locality_row_district')),
          matching: find.text('Галицький'),
        ),
        findsOneWidget,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // GAP 1 — oblastError / cityError / districtError rendered at cascade level
  // ---------------------------------------------------------------------------
  group('LocalityCascade inline error props (GAP 1)', () {
    testWidgets(
      'oblastError renders one locality_tap_row_error with the expected text',
      (tester) async {
        await tester.pumpWidget(
          _wrap(const _CascadeHarness(oblastError: 'Виберіть область')),
        );
        await tester.pump();

        // Exactly one error widget (only the oblast row has an error here).
        final errorFinder = find.byKey(
          const ValueKey<String>('locality_tap_row_error'),
        );
        expect(errorFinder, findsOneWidget);

        // The rendered text matches the supplied message.
        expect(tester.widget<Text>(errorFinder).data, 'Виберіть область');
      },
    );

    testWidgets(
      'each row renders its own error independently (all three set)',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const _CascadeHarness(
              // Seed a city with districts so all three rows are individually
              // addressable and the districtError is meaningful.
              initialCity: _cityWithDistricts,
              oblastError: 'oblast err',
              cityError: 'city err',
              districtError: 'district err',
            ),
          ),
        );
        await tester.pump();

        // All three tap-rows carry their own error — three error widgets total.
        expect(
          find.byKey(const ValueKey<String>('locality_tap_row_error')),
          findsNWidgets(3),
        );

        // Verify each message is present in the tree.
        expect(find.text('oblast err'), findsOneWidget);
        expect(find.text('city err'), findsOneWidget);
        expect(find.text('district err'), findsOneWidget);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // GAP 2 — showDistrictNoneHelper: false path
  // ---------------------------------------------------------------------------
  group('LocalityCascade showDistrictNoneHelper: false (GAP 2)', () {
    testWidgets(
      'leaf city with showDistrictNoneHelper:false — no helper text, district row still disabled',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const _CascadeHarness(
              initialCity: _cityNoDistricts,
              showDistrictNoneHelper: false,
            ),
          ),
        );
        await tester.pump();

        // The helper text must be absent (feature of showDistrictNoneHelper:false).
        expect(
          find.text(_l10n(tester).localityDistrictNoneHelper),
          findsNothing,
          reason:
              'helper text must not render when showDistrictNoneHelper is false',
        );

        // The district row is still non-interactive — hasDistricts is false.
        expect(
          _rowEnabled(tester, const Key('locality_row_district')),
          isFalse,
          reason:
              'district row must stay disabled even without the helper text',
        );

        // Confirming the district row does NOT open a picker sheet.
        await tester.tap(
          find.byKey(const Key('locality_row_district')),
          warnIfMissed: false,
        );
        await tester.pump();
        expect(
          find.byKey(const Key('locality_picker_search')),
          findsNothing,
          reason: 'disabled district row must not open the picker sheet',
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // VelvetTouch structural regression guard — NeumorphicInset presence
  // ---------------------------------------------------------------------------
  // Ensures that each LocalityTapRow contains exactly one NeumorphicInset.
  // Without this, replacing NeumorphicInset with a plain Container would go
  // undetected by the interaction tests above (they only probe enabled state
  // and tap behaviour). This locks the VelvetTouch neumorphic treatment.
  group('VelvetTouch NeumorphicInset presence (structural regression guard)', () {
    testWidgets(
      'each tap-row contains exactly one NeumorphicInset (enabled + disabled)',
      (tester) async {
        await tester.pumpWidget(
          _wrap(const _CascadeHarness(initialCity: _cityWithDistricts)),
        );
        await tester.pump();

        // All three rows are rendered (oblast enabled, city enabled because
        // initialCity seeds an oblast, district enabled because the seeded city
        // hasDistricts == true). Each must host exactly one NeumorphicInset.
        for (final rowKey in [
          const Key('locality_row_oblast'),
          const Key('locality_row_city'),
          const Key('locality_row_district'),
        ]) {
          expect(
            find.descendant(
              of: find.byKey(rowKey),
              matching: find.byType(NeumorphicInset),
            ),
            findsOneWidget,
            reason: '$rowKey must contain exactly one NeumorphicInset',
          );
        }
      },
    );

    testWidgets(
      'disabled tap-row still contains its NeumorphicInset (opacity + IgnorePointer wrap)',
      (tester) async {
        // Initial state: no oblast selected → city + district rows are disabled.
        await tester.pumpWidget(_wrap(const _CascadeHarness()));
        await tester.pump();

        // Disabled rows must still render their NeumorphicInset (the row is
        // dimmed via Opacity + blocked via IgnorePointer, but structurally
        // unchanged — no conditional removal of NeumorphicInset).
        expect(
          find.descendant(
            of: find.byKey(const Key('locality_row_city')),
            matching: find.byType(NeumorphicInset),
          ),
          findsOneWidget,
          reason: 'disabled city row must still contain its NeumorphicInset',
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('locality_row_district')),
            matching: find.byType(NeumorphicInset),
          ),
          findsOneWidget,
          reason:
              'disabled district row must still contain its NeumorphicInset',
        );
      },
    );
  });
}

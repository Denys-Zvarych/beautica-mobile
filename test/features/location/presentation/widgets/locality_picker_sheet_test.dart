// Phase 2.18 — Widget tests for the locality bottom-sheet picker
// ([locality_picker_sheet.dart]) and the keepAlive memoization of the three
// locality providers.
//
// Closes two MEDIUM QA-audit gaps:
//   * AC#5 — the sheet's empty state and error/retry states were untested.
//   * AC#4 — keepAlive memoization (no refetch when the picker is reopened in
//     the same session) was unverified.
//
// Strategy: open the REAL sheet by tapping a [LocalityCascade] row (so the
// production `provider` + `onRetry: ref.invalidate(provider)` wiring is
// exercised end-to-end), backed by a hand-written fake repository that:
//   * counts calls per fetch method (proves keepAlive memoization), and
//   * can be told to fail its first oblast fetch then succeed (drives the
//     AsyncError → Retry → data path).

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/location/data/location_repository.dart';
import 'package:beautica_mobile/features/location/domain/city.dart';
import 'package:beautica_mobile/features/location/domain/city_district.dart';
import 'package:beautica_mobile/features/location/domain/oblast.dart';
import 'package:beautica_mobile/features/location/presentation/widgets/locality_cascade.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

// ---------------------------------------------------------------------------
// Call-counting fake repository.
// ---------------------------------------------------------------------------

class _CountingLocationRepository implements LocationRepository {
  _CountingLocationRepository({this.failOblastsUntil = 0});

  /// Fail the first [failOblastsUntil] calls to [fetchOblasts] with a
  /// [NetworkFailure], then start succeeding. Used to drive the error→retry
  /// path: a value of 1 fails the initial fetch and succeeds on retry.
  final int failOblastsUntil;

  int oblastCalls = 0;
  int cityCalls = 0;
  int districtCalls = 0;

  @override
  Future<List<Oblast>> fetchOblasts() async {
    oblastCalls++;
    if (oblastCalls <= failOblastsUntil) {
      throw const NetworkFailure();
    }
    return const [
      _oblast,
      Oblast(id: 'o2', name: 'Київська', katotthCode: 'UA32'),
    ];
  }

  @override
  Future<List<City>> fetchCities(String oblastId) async {
    cityCalls++;
    return const [_cityWithDistricts, _cityNoDistricts];
  }

  @override
  Future<List<CityDistrict>> fetchDistricts(String cityId) async {
    districtCalls++;
    return const [
      CityDistrict(
        id: 'd1',
        cityId: 'c1',
        name: 'Галицький',
        katotthCode: 'UA4610136',
      ),
    ];
  }
}

// ---------------------------------------------------------------------------
// Test harness — the same shape as locality_cascade_test, but the parent owns
// selection state so that re-tapping a row reopens the picker.
// ---------------------------------------------------------------------------

class _CascadeHarness extends StatefulWidget {
  const _CascadeHarness({this.initialCity});

  final City? initialCity;

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
      onOblast: (o) => setState(() => _oblast = o),
      onCity: (c) => setState(() => _city = c),
      onDistrict: (d) => setState(() => _district = d),
    );
  }
}

Widget _wrap(Widget child, _CountingLocationRepository repo) => ProviderScope(
  overrides: [locationRepositoryProvider.overrideWith((_) => repo)],
  // Disable Riverpod's automatic failed-build retry so an AsyncError stays put
  // through pumpAndSettle. Without this, the keepAlive providers silently
  // re-run after a backoff delay and we'd never observe the error state (and
  // the call counts would drift). Production keeps the default retry.
  retry: (_, _) => null,
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('uk'),
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  ),
);

/// Resolves the localized strings from any element currently in the tree, so
/// assertions never hard-code a UA literal.
AppLocalizations _l10n(WidgetTester tester) => AppLocalizations.of(
  tester.element(find.byKey(const Key('locality_row_oblast'))),
);

void main() {
  group('locality picker sheet — empty + error/retry (AC#5)', () {
    testWidgets('search query with zero matches renders the empty state', (
      tester,
    ) async {
      final repo = _CountingLocationRepository();
      await tester.pumpWidget(_wrap(const _CascadeHarness(), repo));
      await tester.pump();

      // Open the oblast picker.
      await tester.tap(find.byKey(const Key('locality_row_oblast')));
      await tester.pumpAndSettle();

      // Both oblasts present, no empty state yet. Tiles are keyed by the item's
      // stable UUID (ValueKey('locality_picker_tile_<id>')) — homonymous
      // settlements share a `nameUk`, so the key must derive from `id`, not the
      // label; resolve it via the fixture id rather than a raw literal.
      expect(
        find.byKey(ValueKey('locality_picker_tile_${_oblast.id}')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('locality_picker_empty')), findsNothing);

      // Type a query no oblast matches; wait past the 200 ms debounce.
      await tester.enterText(
        find.byKey(const Key('locality_picker_search')),
        'zzzz-no-match',
      );
      await tester.pump(const Duration(milliseconds: 250)); // debounce only
      await tester.pump();

      // Empty state visible with the localized "Нічого не знайдено" copy
      // (resolved via l10n, never a raw literal).
      final empty = find.byKey(const Key('locality_picker_empty'));
      expect(empty, findsOneWidget);
      expect(
        tester.widget<Text>(empty).data,
        _l10n(tester).localitySearchEmpty,
      );
      // No tiles remain.
      expect(
        find.byKey(ValueKey('locality_picker_tile_${_oblast.id}')),
        findsNothing,
      );
    });

    testWidgets(
      'AsyncError shows the retry button; tapping it refetches and shows data',
      (tester) async {
        // First fetch fails, retry succeeds.
        final repo = _CountingLocationRepository(failOblastsUntil: 1);
        await tester.pumpWidget(_wrap(const _CascadeHarness(), repo));
        await tester.pump();

        // Open the oblast picker → provider resolves to AsyncError.
        await tester.tap(find.byKey(const Key('locality_row_oblast')));
        await tester.pumpAndSettle();

        // Error state: retry button visible, localized network message shown.
        final retry = find.byKey(const Key('locality_picker_retry'));
        expect(retry, findsOneWidget);
        expect(
          find.text(const NetworkFailure().userMessage(tester.element(retry))),
          findsOneWidget,
        );
        expect(repo.oblastCalls, 1); // one (failed) fetch so far

        // Tap retry → ref.invalidate(oblastListProvider) re-runs the provider.
        await tester.tap(retry);
        await tester.pumpAndSettle();

        // Provider was re-invoked (call count climbed) and data now renders.
        expect(repo.oblastCalls, 2);
        expect(find.byKey(const Key('locality_picker_retry')), findsNothing);
        expect(
          find.byKey(ValueKey('locality_picker_tile_${_oblast.id}')),
          findsOneWidget,
        );
        expect(find.text(_oblast.name), findsOneWidget);
      },
    );
  });

  group('Warm-Mocha gradient surface (issue-1 regression guard)', () {
    testWidgets('sheet surface paints a LinearGradient, never a flat color', (
      tester,
    ) async {
      final repo = _CountingLocationRepository();
      await tester.pumpWidget(_wrap(const _CascadeHarness(), repo));
      await tester.pump();

      // Open the oblast picker so the sheet (and its surface) is mounted.
      await tester.tap(find.byKey(const Key('locality_row_oblast')));
      await tester.pumpAndSettle();

      // At least one DecoratedBox in the mounted sheet must carry a
      // BoxDecoration whose `gradient` is a LinearGradient — locking the
      // "reads as pure black" regression where it was a flat near-black fill.
      final gradientBoxes = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .where((box) {
            final d = box.decoration;
            return d is BoxDecoration && d.gradient is LinearGradient;
          });
      expect(
        gradientBoxes,
        isNotEmpty,
        reason: 'picker surface must use a LinearGradient, not a flat color',
      );
    });
  });

  group('sheet shape + dismiss affordances (Defects 1 & 6)', () {
    testWidgets(
      'Defect 1 — sheet body is clipped to a 16px top-radius ClipRRect',
      (tester) async {
        final repo = _CountingLocationRepository();
        await tester.pumpWidget(_wrap(const _CascadeHarness(), repo));
        await tester.pump();

        await tester.tap(find.byKey(const Key('locality_row_oblast')));
        await tester.pumpAndSettle();

        // Structural assertion (NOT a golden re-baseline, per project rule):
        // a ClipRRect with the exact 16px top-radius must wrap the gradient +
        // glass + list stack, so the corners can't show black scrim wedges.
        const expectedRadius = BorderRadius.vertical(top: Radius.circular(16));
        final clips = tester
            .widgetList<ClipRRect>(find.byType(ClipRRect))
            .where((c) => c.borderRadius == expectedRadius);
        expect(
          clips,
          isNotEmpty,
          reason: 'sheet stack must be clipped to the 16px top radius',
        );
      },
    );

    testWidgets('Defect 6 — explicit close (X) button dismisses the sheet', (
      tester,
    ) async {
      final repo = _CountingLocationRepository();
      await tester.pumpWidget(_wrap(const _CascadeHarness(), repo));
      await tester.pump();

      await tester.tap(find.byKey(const Key('locality_row_oblast')));
      await tester.pumpAndSettle();

      // Sheet is open: the close button + a tile are present.
      final close = find.byKey(const Key('locality_picker_close'));
      expect(close, findsOneWidget);
      expect(
        find.byKey(ValueKey('locality_picker_tile_${_oblast.id}')),
        findsOneWidget,
      );

      // Tapping the X pops the sheet without selecting anything.
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('locality_picker_close')), findsNothing);
      expect(
        find.byKey(ValueKey('locality_picker_tile_${_oblast.id}')),
        findsNothing,
      );
    });
  });

  group('keepAlive memoization — no refetch on reopen (AC#4)', () {
    testWidgets(
      'oblast / city / district fetches fire exactly once across reopens',
      (tester) async {
        final repo = _CountingLocationRepository();
        // Seed an oblast + city so all three rows are interactive and all three
        // providers participate in this single session.
        await tester.pumpWidget(
          _wrap(const _CascadeHarness(initialCity: _cityWithDistricts), repo),
        );
        await tester.pump();

        // --- District provider: open + close + reopen ----------------------
        await tester.tap(find.byKey(const Key('locality_row_district')));
        await tester.pumpAndSettle();
        expect(repo.districtCalls, 1);
        // Close without selecting (tap the scrim).
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
        // Reopen — keepAlive must serve the cached result, no second fetch.
        await tester.tap(find.byKey(const Key('locality_row_district')));
        await tester.pumpAndSettle();
        expect(
          repo.districtCalls,
          1,
          reason: 'districtListProvider must be memoized by keepAlive: true',
        );
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();

        // --- City provider: open + close + reopen --------------------------
        await tester.tap(find.byKey(const Key('locality_row_city')));
        await tester.pumpAndSettle();
        expect(repo.cityCalls, 1);
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('locality_row_city')));
        await tester.pumpAndSettle();
        expect(
          repo.cityCalls,
          1,
          reason: 'cityListProvider must be memoized by keepAlive: true',
        );
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();

        // --- Oblast provider: open + close + reopen ------------------------
        await tester.tap(find.byKey(const Key('locality_row_oblast')));
        await tester.pumpAndSettle();
        expect(repo.oblastCalls, 1);
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('locality_row_oblast')));
        await tester.pumpAndSettle();
        expect(
          repo.oblastCalls,
          1,
          reason: 'oblastListProvider must be memoized by keepAlive: true',
        );
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
      },
    );
  });
}

// Regression tests for the Phase 5.6 one-line duration+price layout change.
//
// The change under test (2026-06-13):
//   1. Duration + price render on ONE row:
//        FIXED = [duration | price]        — 2 equal Expanded slots
//        RANGE = [duration | min – max]    — 3 equal Expanded slots (the
//                separator '–' is non-Expanded between min and max)
//   2. hideSuffixWhenActive=true on price fields: "грн" hides while the field
//      is focused OR has text. hideSuffixWhenActive=false on the duration well:
//      "хв" is always visible. (Suffix-absence tests for the "type then gone"
//      path live here; the no-overlap + vertical-growth suite lives in
//      pricing_field_clipping_test.dart.)
//   3. A '–' en-dash separator appears between min and max in RANGE mode.
//   4. A value typed while "грн" is hidden still submits the correct amount.
//
// All tests use PricingField directly (no full ServiceForm pump needed), except
// the submit-value test which pumps a minimal ServiceForm.
//
// Keys and tokens used:
//   Key('pricing-field')          — the PricingField in service_form.dart
//   Key('field-service-duration') — duration NeumorphicInset (compact=false)
//   Key('service-setup-duration') — duration NeumorphicInset (compact=true)
//   Key('pricing-fixed-amount')   — fixed price NeumorphicInset
//   Key('pricing-range-min')      — range min NeumorphicInset
//   Key('pricing-range-max')      — range max NeumorphicInset
//   Key('btn-submit-service')     — ServiceForm submit button
//
// Isolation: no ProviderScope where not needed; real controllers + tearDown.

import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/master_service_input.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/domain/service_type_option.dart';
import 'package:beautica_mobile/features/services/presentation/service_types_provider.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/pricing_field.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_form.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'select_dropdown_test_helpers.dart';

// ---------------------------------------------------------------------------
// Mocks / fakes for the ServiceForm submit tests
// ---------------------------------------------------------------------------

class _MockServiceRepository extends Mock implements ServiceRepository {}

class _FakeMasterServiceCreate extends Fake implements MasterServiceCreate {}

/// Stub MasterService returned by the mock on a successful create call.
const _kStubService = MasterService(
  id: 'svc-layout-test',
  serviceDefId: 'def-layout-test',
  name: 'Тест',
  durationMinutes: 60,
  priceMin: 750,
  priceDisplay: '750 грн',
);

// ---------------------------------------------------------------------------
// Tolerance constants
// ---------------------------------------------------------------------------

/// Sub-pixel tolerance for coordinate comparisons.
const double _kEps = 1.0;

/// Maximum allowed width difference between two "equal" Expanded slots
/// (accounts for odd-pixel rounding on a 360dp canvas).
const double _kWidthTolerance = 2.0;

// ---------------------------------------------------------------------------
// Pump helpers
// ---------------------------------------------------------------------------

/// Pumps a bare [PricingField] with a duration controller (non-compact) inside
/// a 360dp-wide box with UK l10n.
Future<
  ({
    TextEditingController durationCtrl,
    TextEditingController fixedCtrl,
    TextEditingController minCtrl,
    TextEditingController maxCtrl,
  })
>
_pumpPricingField(
  WidgetTester tester, {
  ServicePriceType mode = ServicePriceType.fixed,
  double width = 360,
}) async {
  final durationCtrl = TextEditingController();
  final fixedCtrl = TextEditingController();
  final minCtrl = TextEditingController();
  final maxCtrl = TextEditingController();
  addTearDown(durationCtrl.dispose);
  addTearDown(fixedCtrl.dispose);
  addTearDown(minCtrl.dispose);
  addTearDown(maxCtrl.dispose);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('uk'),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: SingleChildScrollView(
              child: PricingField(
                mode: mode,
                onModeChanged: (_) {},
                fixedController: fixedCtrl,
                minController: minCtrl,
                maxController: maxCtrl,
                // Pass a duration controller so the one-line layout is active.
                durationController: durationCtrl,
                compact: false, // create/edit form layout
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (
    durationCtrl: durationCtrl,
    fixedCtrl: fixedCtrl,
    minCtrl: minCtrl,
    maxCtrl: maxCtrl,
  );
}

// approvedCategoriesProvider is overridden in _pumpServiceForm (it fetches via
// categoryRequestApi, not the repo).
const _kCategories = <ServiceCategoryOption>[
  ServiceCategoryOption(name: 'MANICURE', displayName: 'Манікюр'),
];

/// Pumps a [ServiceForm] inside a ProviderScope (needed for category provider).
Future<void> _pumpServiceForm(
  WidgetTester tester, {
  required Future<void> Function(MasterServiceCreate) onSubmit,
  required _MockServiceRepository repo,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        serviceRepositoryProvider.overrideWithValue(repo),
        approvedCategoriesProvider.overrideWith((ref) async => _kCategories),
        // Selecting a category mounts the service-type picker → stub the
        // provider so no un-mocked repository fetch fires in-tree.
        serviceTypesProvider.overrideWith(
          (ref, String categoryName) async => const <ServiceTypeOption>[],
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
        home: Scaffold(
          body: SingleChildScrollView(child: ServiceForm(onSubmit: onSubmit)),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Selects the mandatory service type (create requires one) via the form State.
/// Call AFTER the category is selected.
Future<void> _selectServiceType(WidgetTester tester) async {
  final dynamic state = tester.state(find.byType(ServiceForm));
  state.onServiceTypeSelected(
    const ServiceTypeOption(
      id: 'stype-manicure',
      slug: 'MANICURE_A',
      nameUk: 'Класичний манікюр',
      categoryName: 'MANICURE',
    ),
  );
  await tester.pump();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() => registerFallbackValue(_FakeMasterServiceCreate()));

  // ==========================================================================
  // 1. ONE-LINE LAYOUT — duration and price field(s) share a single Row.
  //    Assert by verifying the wells are laid out at the same vertical position
  //    (same top coordinate), which is the observable consequence of being
  //    siblings in one Row rather than stacked in a Column.
  // ==========================================================================
  group('one-line layout: duration and price share a horizontal band', () {
    testWidgets(
      'FIXED mode: duration and price wells have the same top coordinate',
      (tester) async {
        await _pumpPricingField(tester, mode: ServicePriceType.fixed);

        const Key durationKey = Key('field-service-duration');
        const Key priceKey = Key('pricing-fixed-amount');

        expect(
          find.byKey(durationKey),
          findsOneWidget,
          reason: 'duration well must be present',
        );
        expect(
          find.byKey(priceKey),
          findsOneWidget,
          reason: 'price well must be present',
        );

        final Rect durationRect = tester.getRect(find.byKey(durationKey));
        final Rect priceRect = tester.getRect(find.byKey(priceKey));

        expect(
          durationRect.top,
          closeTo(priceRect.top, _kEps),
          reason:
              'FIXED: duration and price wells must share the same top — they '
              'are siblings in one Row, not stacked',
        );

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'RANGE mode: duration, range-min, and range-max wells are all present',
      (tester) async {
        await _pumpPricingField(tester, mode: ServicePriceType.range);

        expect(
          find.byKey(const Key('field-service-duration')),
          findsOneWidget,
          reason: 'duration well must be present in RANGE mode',
        );
        expect(
          find.byKey(const Key('pricing-range-min')),
          findsOneWidget,
          reason: 'range-min well must be present in RANGE mode',
        );
        expect(
          find.byKey(const Key('pricing-range-max')),
          findsOneWidget,
          reason: 'range-max well must be present in RANGE mode',
        );

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'RANGE mode: duration well top ≈ range-min well top (same horizontal band)',
      (tester) async {
        await _pumpPricingField(tester, mode: ServicePriceType.range);

        final Rect durationRect = tester.getRect(
          find.byKey(const Key('field-service-duration')),
        );
        final Rect minRect = tester.getRect(
          find.byKey(const Key('pricing-range-min')),
        );

        // Both are in Expanded slots of the outer Row so their tops align.
        // In non-compact mode labels sit above wells; both slots have a label so
        // the tops still match. Allow _kEps for sub-pixel rounding.
        expect(
          durationRect.top,
          closeTo(minRect.top, _kEps),
          reason:
              'RANGE: duration well and range-min well must share the same top '
              '— they are siblings in one outer Row',
        );

        expect(tester.takeException(), isNull);
      },
    );

    // Compact mode (service-setup row) uses Key('service-setup-duration').
    testWidgets(
      'compact RANGE mode: service-setup-duration and range-min wells present',
      (tester) async {
        final durationCtrl = TextEditingController();
        final fixedCtrl = TextEditingController();
        final minCtrl = TextEditingController();
        final maxCtrl = TextEditingController();
        addTearDown(durationCtrl.dispose);
        addTearDown(fixedCtrl.dispose);
        addTearDown(minCtrl.dispose);
        addTearDown(maxCtrl.dispose);

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('uk'),
            home: Scaffold(
              body: SizedBox(
                width: 360,
                child: SingleChildScrollView(
                  child: PricingField(
                    mode: ServicePriceType.range,
                    onModeChanged: (_) {},
                    fixedController: fixedCtrl,
                    minController: minCtrl,
                    maxController: maxCtrl,
                    durationController: durationCtrl,
                    compact: true, // service-setup row
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // compact=true → key is 'service-setup-duration'
        expect(
          find.byKey(const Key('service-setup-duration')),
          findsOneWidget,
          reason: 'compact duration well must use service-setup-duration key',
        );
        expect(find.byKey(const Key('pricing-range-min')), findsOneWidget);
        expect(find.byKey(const Key('pricing-range-max')), findsOneWidget);

        expect(tester.takeException(), isNull);
      },
    );
  });

  // ==========================================================================
  // 2. EQUAL-WIDTH EXPANDED SLOTS
  //    In FIXED mode the duration and price wells are both Expanded(flex:1)
  //    so they must have equal widths (within rounding tolerance).
  //    In RANGE mode all three slots (duration, min, max) are Expanded(flex:1)
  //    so duration ≈ min ≈ max width (the separator is not Expanded).
  // ==========================================================================
  group('equal-width Expanded slots', () {
    testWidgets('FIXED mode: duration well width ≈ price well width', (
      tester,
    ) async {
      await _pumpPricingField(tester, mode: ServicePriceType.fixed);

      final Size durSize = tester.getSize(
        find.byKey(const Key('field-service-duration')),
      );
      final Size priceSize = tester.getSize(
        find.byKey(const Key('pricing-fixed-amount')),
      );

      expect(
        durSize.width,
        closeTo(priceSize.width, _kWidthTolerance),
        reason:
            'FIXED: duration and price wells must have equal width — both '
            'are Expanded(flex:1) inside the outer Row',
      );
    });

    testWidgets(
      'RANGE mode: duration, range-min, and range-max wells all have equal '
      'widths (each ≈ ⅓ of the row)',
      (tester) async {
        await _pumpPricingField(tester, mode: ServicePriceType.range);

        final double durW = tester
            .getSize(find.byKey(const Key('field-service-duration')))
            .width;
        final double minW = tester
            .getSize(find.byKey(const Key('pricing-range-min')))
            .width;
        final double maxW = tester
            .getSize(find.byKey(const Key('pricing-range-max')))
            .width;

        // RANGE layout (flat Row, 2026-06-13):
        //   Row[Expanded(flex:1, dur) | SizedBox(gap) | Expanded(flex:1, min) |
        //       Padding(dash) | Expanded(flex:1, max)]
        //   All three wells are Expanded(flex:1) siblings in the SAME flat Row
        //   so Flutter distributes remaining width equally among all three.
        //   Arithmetic at 360 dp (32 dp screen padding ⇒ 328 dp row):
        //     gap=8 (sm), dash slot ~16 dp; each = (328−8−16)/3 ≈ 104 dp
        //   → duration == min == max (within 1-pixel rounding).
        expect(
          durW,
          closeTo(minW, _kWidthTolerance),
          reason:
              'RANGE: duration well must have the same width as range-min — '
              'the outer Expanded(flex:1) and each inner Expanded both resolve '
              'to (rowW − gap) / 3',
        );
        expect(
          minW,
          closeTo(maxW, _kWidthTolerance),
          reason:
              'RANGE: range-min and range-max wells must have equal width '
              '(both Expanded(flex:1) inside the Stack Row within priceArea)',
        );
        expect(
          durW,
          closeTo(maxW, _kWidthTolerance),
          reason:
              'RANGE: duration well must have the same width as range-max '
              '— all three slots are equal thirds',
        );
      },
    );
  });

  // ==========================================================================
  // 3. HIDE-SUFFIX-ON-TYPE — "грн" hides as soon as the price field has text.
  //    The full cycle: empty → грн present; enter text → absent; clear → present.
  //    Duration "хв" stays present in all three states.
  // ==========================================================================
  group('hide-грн-on-type cycle', () {
    testWidgets(
      'price field FIXED: грн present when empty, absent after typing, '
      'present after clearing; хв always present',
      (tester) async {
        final handles = await _pumpPricingField(
          tester,
          mode: ServicePriceType.fixed,
        );

        const Key priceKey = Key('pricing-fixed-amount');

        final priceSuffixUnder = find.descendant(
          of: find.byKey(priceKey),
          matching: find.text('грн'),
        );
        final durSuffixAll = find.text('хв');

        // ── (a) Empty + unfocused: "грн" must be present ─────────────────────
        expect(
          priceSuffixUnder,
          findsOneWidget,
          reason: 'step a: "грн" must be visible when price field is empty',
        );
        expect(
          durSuffixAll,
          findsOneWidget,
          reason: 'step a: "хв" must always be visible',
        );

        // ── (b) Enter text: "грн" must disappear ─────────────────────────────
        await tester.enterText(
          find.descendant(
            of: find.byKey(priceKey),
            matching: find.byType(TextField),
          ),
          '300',
        );
        await tester.pump();

        expect(
          priceSuffixUnder,
          findsNothing,
          reason: 'step b: "грн" must be HIDDEN once the price field has text',
        );
        expect(
          durSuffixAll,
          findsOneWidget,
          reason:
              'step b: "хв" must still be visible after price field has text',
        );

        // ── (c) Clear text: "грн" must return ────────────────────────────────
        handles.fixedCtrl.clear();
        // Unfocus so hideSuffixWhenActive sees !_focused && !_hasText.
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        expect(
          priceSuffixUnder,
          findsOneWidget,
          reason:
              'step c: "грн" must be VISIBLE again after the price field is '
              'cleared and unfocused',
        );
        expect(
          durSuffixAll,
          findsOneWidget,
          reason: 'step c: "хв" must still be visible after field is cleared',
        );
      },
    );
  });

  // ==========================================================================
  // 4. EN-DASH SEPARATOR IN RANGE MODE
  //    Exactly one '–' (U+2013 EN DASH) appears between min and max.
  // ==========================================================================
  group('en-dash separator in RANGE mode', () {
    testWidgets('RANGE mode: exactly one "–" separator is present', (
      tester,
    ) async {
      await _pumpPricingField(tester, mode: ServicePriceType.range);

      // The en-dash must appear exactly once — between min and max wells.
      expect(
        find.text('–'),
        findsOneWidget,
        reason:
            'RANGE mode must render exactly one "–" (en-dash) separator '
            'between the min and max price wells',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('FIXED mode: no "–" separator is present', (tester) async {
      await _pumpPricingField(tester, mode: ServicePriceType.fixed);

      expect(
        find.text('–'),
        findsNothing,
        reason: 'FIXED mode must not render the "–" en-dash separator',
      );
    });

    testWidgets('RANGE mode: "–" is a real in-flow element between min and max '
        '(not a Stack overlay) — dash sits strictly in the gap, not adjacent', (
      tester,
    ) async {
      await _pumpPricingField(tester, mode: ServicePriceType.range, width: 360);

      final Rect minRect = tester.getRect(
        find.byKey(const Key('pricing-range-min')),
      );
      final Rect maxRect = tester.getRect(
        find.byKey(const Key('pricing-range-max')),
      );
      final Rect dashRect = tester.getRect(find.text('–'));

      // The '–' is a REAL layout element (Padding(horizontal:xs) + Text)
      // between min and max in the flat Row:
      //   Expanded(duration) | SizedBox(gap) | Expanded(min) | Padding(dash) | Expanded(max)
      // This means min and max are NOT adjacent — the dash slot occupies real
      // horizontal dp between them.

      // (a) The gap between min and max is larger than 4 dp (the dash element
      //     has at least 2×xs = 8 dp padding alone, plus text width).
      expect(
        maxRect.left,
        greaterThan(minRect.right + 4.0),
        reason:
            'RANGE: max left must be more than 4 dp past min right — the '
            '"–" is a real in-flow Row child with horizontal padding, not a '
            'zero-width Stack overlay',
      );

      // (b) The dash center is in the middle of the gap between min and max.
      final double gapCenter = (minRect.right + maxRect.left) / 2;
      expect(
        dashRect.center.dx,
        closeTo(gapCenter, 4.0),
        reason:
            '"–" center must be halfway between min right edge and max left '
            'edge — dash is centred by its Padding in the gap',
      );

      // (c) Dash is strictly between the two wells (no overlap with either).
      expect(
        dashRect.left,
        greaterThanOrEqualTo(minRect.right),
        reason: '"–" must not overlap the min well on the right',
      );
      expect(
        dashRect.right,
        lessThanOrEqualTo(maxRect.left),
        reason: '"–" must not overlap the max well on the left',
      );

      expect(tester.takeException(), isNull);
    });
  });

  // ==========================================================================
  // 5. SUBMIT VALUE INTACT — a value typed while "грн" is hidden submits the
  //    correct amount. The suffix hide is purely visual; the controller text
  //    (and therefore the submitted payload) must carry the typed price.
  // ==========================================================================
  group('submit value intact when "грн" is hidden', () {
    late _MockServiceRepository repo;

    setUp(() {
      repo = _MockServiceRepository();
      when(() => repo.create(any())).thenAnswer((_) async => _kStubService);
    });

    testWidgets(
      'FIXED: price typed while "грн" is hidden submits the correct amount',
      (tester) async {
        MasterServiceCreate? captured;
        await _pumpServiceForm(
          tester,
          onSubmit: (input) async => captured = input,
          repo: repo,
        );

        // Enter duration so validation passes.
        await tester.enterText(
          find.descendant(
            of: find.byKey(const Key('field-service-duration')),
            matching: find.byType(TextField),
          ),
          '60',
        );

        // Enter price — at this point "грн" hides (field has text).
        final priceFieldFinder = find.descendant(
          of: find.byKey(const Key('pricing-fixed-amount')),
          matching: find.byType(TextField),
        );
        await tester.enterText(priceFieldFinder, '750');
        await tester.pump();

        // Verify "грн" is hidden now (confirming hideSuffixWhenActive is active).
        expect(
          find.descendant(
            of: find.byKey(const Key('pricing-fixed-amount')),
            matching: find.text('грн'),
          ),
          findsNothing,
          reason:
              'precondition: "грн" must be hidden while the price field has '
              'text (otherwise the suffix-hide feature is not exercised)',
        );

        // Select category to pass the category validator.
        await selectCategoryOption(tester, 'MANICURE');
        await _selectServiceType(tester);

        // Tap submit.
        await tester.ensureVisible(find.byKey(const Key('btn-submit-service')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('btn-submit-service')));
        await tester.pumpAndSettle();

        // The submitted payload must carry the typed price — the suffix hide is
        // purely visual and must not affect the value in the controller.
        expect(
          captured,
          isNotNull,
          reason: 'onSubmit must be called when the form is valid',
        );
        expect(
          captured!.price,
          750.0,
          reason:
              'the submitted price must be 750 regardless of whether "грн" '
              'was visible at the time of submission',
        );
      },
    );

    testWidgets(
      'RANGE: prices typed while "грн" is hidden submit correct min/max amounts',
      (tester) async {
        MasterServiceCreate? captured;
        await _pumpServiceForm(
          tester,
          onSubmit: (input) async => captured = input,
          repo: repo,
        );

        // Switch to RANGE mode.
        await tester.tap(find.byKey(const Key('pricing-toggle-range')));
        await tester.pumpAndSettle();

        // Enter duration.
        await tester.enterText(
          find.descendant(
            of: find.byKey(const Key('field-service-duration')),
            matching: find.byType(TextField),
          ),
          '90',
        );

        // Enter min price.
        await tester.enterText(
          find.descendant(
            of: find.byKey(const Key('pricing-range-min')),
            matching: find.byType(TextField),
          ),
          '400',
        );
        // Enter max price.
        await tester.enterText(
          find.descendant(
            of: find.byKey(const Key('pricing-range-max')),
            matching: find.byType(TextField),
          ),
          '800',
        );
        await tester.pump();

        // Select category.
        await selectCategoryOption(tester, 'MANICURE');
        await _selectServiceType(tester);

        // Submit.
        await tester.ensureVisible(find.byKey(const Key('btn-submit-service')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('btn-submit-service')));
        await tester.pumpAndSettle();

        expect(
          captured,
          isNotNull,
          reason: 'onSubmit must be called for a valid RANGE form',
        );
        expect(
          captured!.priceMin,
          400.0,
          reason:
              'submitted priceMin must be 400 — suffix hiding must not alter '
              'the controller value',
        );
        expect(
          captured!.priceMax,
          800.0,
          reason:
              'submitted priceMax must be 800 — suffix hiding must not alter '
              'the controller value',
        );
      },
    );
  });

  // ==========================================================================
  // 6. NO-OVERLAP GUARD — dash must not intersect either price well.
  //    This directly guards the regression the user reported: the old Stack
  //    overlay could render on top of adjacent well borders. The flat-Row
  //    layout fixes this; this test asserts the invariant permanently.
  // ==========================================================================
  group('no-overlap guard: dash rect does not intersect min or max wells', () {
    testWidgets('RANGE mode: dash left edge ≥ min right edge and '
        'dash right edge ≤ max left edge (no pixel overlap)', (tester) async {
      await _pumpPricingField(tester, mode: ServicePriceType.range, width: 360);

      final Rect minRect = tester.getRect(
        find.byKey(const Key('pricing-range-min')),
      );
      final Rect maxRect = tester.getRect(
        find.byKey(const Key('pricing-range-max')),
      );
      final Rect dashRect = tester.getRect(find.text('–'));

      expect(
        dashRect.left,
        greaterThanOrEqualTo(minRect.right),
        reason:
            'no-overlap guard: "–" left edge must be at or past min right '
            'edge — dash must not paint over the min price well',
      );
      expect(
        dashRect.right,
        lessThanOrEqualTo(maxRect.left),
        reason:
            'no-overlap guard: "–" right edge must be at or before max left '
            'edge — dash must not paint over the max price well',
      );

      expect(tester.takeException(), isNull);
    });
  });

  // ==========================================================================
  // 7. TOGGLE PRESERVES DURATION VALUE
  //    The durationController is parent-owned. A FIXED↔RANGE toggle changes
  //    only the price fields visible; it must NOT reset the duration well.
  //    This guards against flatten regressions that might drop the duration
  //    controller or re-create the state on toggle.
  // ==========================================================================
  group('toggle preserves duration value', () {
    testWidgets(
      'duration value typed in FIXED mode survives a toggle to RANGE and back',
      (tester) async {
        // Use a StatefulWidget wrapper to hold mode so we can drive the toggle
        // externally via setState, keeping PricingField stateless.
        ServicePriceType currentMode = ServicePriceType.fixed;
        late StateSetter outerSetState;

        final durationCtrl = TextEditingController();
        final fixedCtrl = TextEditingController();
        final minCtrl = TextEditingController();
        final maxCtrl = TextEditingController();
        addTearDown(durationCtrl.dispose);
        addTearDown(fixedCtrl.dispose);
        addTearDown(minCtrl.dispose);
        addTearDown(maxCtrl.dispose);

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('uk'),
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  outerSetState = setState;
                  return SizedBox(
                    width: 360,
                    child: SingleChildScrollView(
                      child: PricingField(
                        mode: currentMode,
                        onModeChanged: (m) => outerSetState(() {
                          currentMode = m;
                        }),
                        fixedController: fixedCtrl,
                        minController: minCtrl,
                        maxController: maxCtrl,
                        durationController: durationCtrl,
                        compact: false,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // ── (a) Type a duration value while in FIXED mode ─────────────────────
        await tester.enterText(
          find.descendant(
            of: find.byKey(const Key('field-service-duration')),
            matching: find.byType(TextField),
          ),
          '45',
        );
        await tester.pump();
        expect(
          durationCtrl.text,
          '45',
          reason: 'precondition: duration controller must hold the typed value',
        );

        // ── (b) Toggle to RANGE — duration field must still show '45' ─────────
        await tester.tap(find.byKey(const Key('pricing-toggle-range')));
        await tester.pumpAndSettle();

        expect(
          durationCtrl.text,
          '45',
          reason:
              'toggle to RANGE must not reset the duration controller — the '
              'parent owns it and the flat-Row layout must keep the same '
              '_PricingInputField state alive',
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('field-service-duration')),
            matching: find.text('45'),
          ),
          findsOneWidget,
          reason: 'duration well must render "45" after toggle to RANGE',
        );

        // ── (c) Toggle back to FIXED — duration value still intact ────────────
        await tester.tap(find.byKey(const Key('pricing-toggle-fixed')));
        await tester.pumpAndSettle();

        expect(
          durationCtrl.text,
          '45',
          reason: 'toggle back to FIXED must not reset the duration controller',
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('field-service-duration')),
            matching: find.text('45'),
          ),
          findsOneWidget,
          reason:
              'duration well must still render "45" after toggle back to FIXED',
        );

        expect(tester.takeException(), isNull);
      },
    );
  });
}

// Regression — unrenderable STORED prices seeding the service-edit form's
// price controllers (`ServiceForm.initState`).
//
// THE DEFECT
// ----------
// `initState` used to seed the three price controllers with a bare
// `initial!.priceMin.toInt().toString()`. `double.toInt()` fails the identical
// two ways `double.round()` did on the discovery search cards (see
// `master_result_card_test.dart` / `salon_result_card_test.dart`):
//
//   1. `double.infinity.toInt()` / `double.nan.toInt()` THROW
//      `UnsupportedError: Infinity or NaN toInt`. Here that throw is in
//      `initState()`, so the master's OWN service-edit screen does not build at
//      all — it is replaced by an error widget before a single field renders.
//      This is the distinguishing failure mode, hence the explicit
//      `tester.takeException()` assertion in every case below.
//   2. `(1e30).toInt()` / `(1e20).toInt()` do NOT throw — they SATURATE to
//      `9223372036854775807`, pre-filling the master's price field with a
//      fabricated 9.2-quintillion-hryvnia figure. `1e20` matters specifically
//      because it clears `isRenderablePrice` (whose ceiling is calibrated for
//      `toStringAsFixed(0)`, i.e. 1e21) and saturates anyway — which is why the
//      gate is `renderableWholePrice` and not `isRenderablePrice` alone.
//
// Reachable from the wire: `MasterServiceMapper` passes the decoded `num`
// through as `.toDouble()` unclamped and by documented design, and
// `jsonDecode('1e400')` yields `double.infinity` WITHOUT throwing.
//
// THE FIX, AND WHY THE FALLBACK IS EMPTY
// --------------------------------------
// Every figure now passes the shared `renderableWholePrice` gate, and an
// unstatable one seeds the field EMPTY. This is an EDITABLE controller, not a
// read-only label: anything printed here is a value the master can save back
// verbatim, so `0` would silently overwrite the server's real price with a
// fabricated one and `priceUnavailableLabel` («—») would sit in a numeric field
// looking like data. Empty is the one seed the form already refuses to submit
// (`_pricingValid` requires a non-blank, in-bounds amount), so the save path
// and the display agree: nothing is shown, and nothing can be sent until the
// master retypes a clean figure. Each hostile case below asserts BOTH halves —
// the empty seed AND the blocked submit.
//
// The two CONTROL cases at the end are what make this group honest: a blanket
// "always seed empty" mutation would satisfy every hostile case and fail them.
//
// Isolation: fresh ProviderScope per pump; serviceRepositoryProvider and
// approvedCategoriesProvider overridden so no real HTTP fires. Fields located
// by Key (M2); every asserted message resolved from AppLocalizations off the
// pumped tree — never a hard-coded Cyrillic literal.

import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/master_service_input.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/domain/service_type_option.dart';
import 'package:beautica_mobile/features/services/presentation/service_types_provider.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_form.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

// ---------------------------------------------------------------------------
// Mocks + fallbacks
// ---------------------------------------------------------------------------

class _MockServiceRepository extends Mock implements ServiceRepository {}

class _FakeMasterServiceCreate extends Fake implements MasterServiceCreate {}

// ---------------------------------------------------------------------------
// Finders (by Key — M2)
// ---------------------------------------------------------------------------

final _fixedPriceField = find.descendant(
  of: find.byKey(const Key('pricing-fixed-amount')),
  matching: find.byType(TextField),
);
final _rangeMinField = find.descendant(
  of: find.byKey(const Key('pricing-range-min')),
  matching: find.byType(TextField),
);
final _rangeMaxField = find.descendant(
  of: find.byKey(const Key('pricing-range-max')),
  matching: find.byType(TextField),
);

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(ServiceForm)));

/// A FIXED-priced service already on the server, loaded into the edit form.
/// Category + service type are pre-set so the ONLY thing that can block submit
/// is the price — which is exactly what each hostile case asserts.
MasterService _fixedService(double priceMin) => MasterService(
  id: 'svc-edit-1',
  serviceDefId: 'def-edit-1',
  name: 'Manicure',
  category: 'MANICURE',
  serviceTypeId: 'stype-manicure',
  serviceTypeNameUk: 'Manicure',
  durationMinutes: 60,
  priceType: ServicePriceType.fixed,
  priceMin: priceMin,
  priceDisplay: '',
);

/// A RANGE-priced service already on the server, loaded into the edit form.
MasterService _rangeService({required double priceMin, double? priceMax}) =>
    MasterService(
      id: 'svc-edit-2',
      serviceDefId: 'def-edit-2',
      name: 'Manicure',
      category: 'MANICURE',
      serviceTypeId: 'stype-manicure',
      serviceTypeNameUk: 'Manicure',
      durationMinutes: 60,
      priceType: ServicePriceType.range,
      priceMin: priceMin,
      priceMax: priceMax,
      priceDisplay: '',
    );

const _manicureType = ServiceTypeOption(
  id: 'stype-manicure',
  slug: 'MANICURE_CLASSIC',
  nameUk: 'Manicure',
  categoryName: 'MANICURE',
);

/// The five wire values this group is about. `1e20` and `1e30` are the
/// int64-saturation window; `1e20` additionally clears `isRenderablePrice`.
const List<(String, double)> _hostilePrices = <(String, double)>[
  ('double.infinity', double.infinity),
  ('double.nan', double.nan),
  ('1e30 (int64-saturating)', 1e30),
  ('1e20 (int64-saturating, but under the isRenderablePrice ceiling)', 1e20),
  ('a negative price', -500.0),
];

void main() {
  setUpAll(() => registerFallbackValue(_FakeMasterServiceCreate()));

  late _MockServiceRepository repo;

  const categories = <ServiceCategoryOption>[
    ServiceCategoryOption(name: 'MANICURE', displayName: 'Manicure'),
  ];

  setUp(() {
    repo = _MockServiceRepository();
  });

  Future<void> pumpForm(
    WidgetTester tester, {
    required Future<void> Function(MasterServiceCreate) onSubmit,
    required MasterService initial,
  }) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        retry: beauticaProviderRetry,
        overrides: [
          serviceRepositoryProvider.overrideWithValue(repo),
          approvedCategoriesProvider.overrideWith((ref) async => categories),
          serviceTypesProvider.overrideWith(
            (ref, String categoryName) async => categoryName == 'MANICURE'
                ? const <ServiceTypeOption>[_manicureType]
                : const <ServiceTypeOption>[],
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('uk'),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ServiceForm(initial: initial, onSubmit: onSubmit),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> tapSubmit(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('btn-submit-service')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('btn-submit-service')));
    await tester.pump();
  }

  /// onSubmit that must never fire — an unstatable seeded price has to block
  /// the save, not send a saturated / negative / empty figure to the backend.
  Future<void> shouldNotSubmit(MasterServiceCreate _) async {
    fail('onSubmit must not fire while a price field is unstatable');
  }

  /// Every rendered `Text` string in the tree — so a garbage figure is caught
  /// wherever it leaked, not only in the node a scoped finder looked at.
  List<String> renderedTexts(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((Text t) => t.data ?? '')
      .toList();

  /// The stringifications a broken seed would produce.
  Iterable<String> garbageIn(WidgetTester tester) =>
      renderedTexts(tester).where(
        (String s) =>
            s.contains('Infinity') ||
            s.contains('NaN') ||
            s.contains('9223372036854775807') ||
            s.contains('-500'),
      );

  group('ServiceForm edit seed — unrenderable stored prices', () {
    for (final (String name, double bad) in _hostilePrices) {
      testWidgets(
        'a $name FIXED price seeds the amount field EMPTY instead of throwing '
        'out of initState',
        (tester) async {
          await pumpForm(
            tester,
            onSubmit: shouldNotSubmit,
            initial: _fixedService(bad),
          );

          expect(
            tester.takeException(),
            isNull,
            reason:
                '$name must never reach a bare `.toInt()` — that throws '
                'UnsupportedError inside initState(), so the whole '
                'service-edit screen becomes an error widget',
          );
          expect(
            tester.widget<TextField>(_fixedPriceField).controller?.text,
            '',
            reason:
                'an unstatable stored price must seed EMPTY — never a '
                'saturated, negative or placeholder value the master could '
                'save back verbatim',
          );
          expect(
            garbageIn(tester),
            isEmpty,
            reason: 'no such figure may be stringified into the edit form',
          );

          // …and the empty seed genuinely blocks the save (shouldNotSubmit
          // fails the test if the form submits anyway).
          await tapSubmit(tester);
          expect(
            find.text(_l10n(tester).errRequired),
            findsAtLeastNWidgets(1),
            reason:
                'the master must be told to retype the price, not allowed to '
                'save a blank / fabricated one',
          );
        },
      );

      testWidgets(
        'a $name RANGE ceiling seeds the max field EMPTY and leaves the known '
        'floor intact',
        (tester) async {
          await pumpForm(
            tester,
            onSubmit: shouldNotSubmit,
            initial: _rangeService(priceMin: 300, priceMax: bad),
          );

          expect(tester.takeException(), isNull);
          expect(
            tester.widget<TextField>(_rangeMinField).controller?.text,
            '300',
            reason:
                'a garbage CEILING says nothing about the floor — the '
                'statable half of the band is still seeded honestly',
          );
          expect(tester.widget<TextField>(_rangeMaxField).controller?.text, '');
          expect(garbageIn(tester), isEmpty);

          await tapSubmit(tester);
          expect(
            find.text(_l10n(tester).errPriceMaxRequired),
            findsAtLeastNWidgets(1),
          );
        },
      );
    }

    testWidgets(
      'CONTROL — a well-formed FIXED price still seeds the field and still '
      'saves (a blanket "always seed empty" mutation fails here)',
      (tester) async {
        MasterServiceCreate? submitted;
        await pumpForm(
          tester,
          onSubmit: (MasterServiceCreate input) async => submitted = input,
          initial: _fixedService(500),
        );

        expect(tester.takeException(), isNull);
        expect(
          tester.widget<TextField>(_fixedPriceField).controller?.text,
          '500',
        );

        await tapSubmit(tester);
        expect(
          submitted?.price,
          500,
          reason:
              'the ordinary edit flow must still round-trip the stored price '
              'untouched',
        );
      },
    );

    testWidgets('CONTROL — a well-formed RANGE band seeds both bounds', (
      tester,
    ) async {
      await pumpForm(
        tester,
        onSubmit: shouldNotSubmit,
        initial: _rangeService(priceMin: 300, priceMax: 900),
      );

      expect(tester.takeException(), isNull);
      expect(tester.widget<TextField>(_rangeMinField).controller?.text, '300');
      expect(tester.widget<TextField>(_rangeMaxField).controller?.text, '900');
    });

    testWidgets(
      'CONTROL — a fractional stored price seeds the ROUNDED whole figure, '
      'matching what ServicePriceDisplay already shows for the same service',
      (tester) async {
        // `renderableWholePrice` rounds, exactly as `ServicePriceDisplay`
        // renders the same double with `toStringAsFixed(0)`. The old bare
        // `.toInt()` truncated to '300' here, disagreeing with the '301' the
        // read-only service card displayed.
        await pumpForm(
          tester,
          onSubmit: shouldNotSubmit,
          initial: _fixedService(300.99),
        );

        expect(tester.takeException(), isNull);
        expect(
          tester.widget<TextField>(_fixedPriceField).controller?.text,
          '301',
        );
      },
    );
  });
}

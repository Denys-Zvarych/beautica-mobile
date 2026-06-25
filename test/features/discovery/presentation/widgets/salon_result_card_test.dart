// Search-page change (items 2, 5, 6, 7) — widget tests for [SalonResultCard].
//
// Pins the salon-card contract the golden cannot assert behaviourally:
//   • Item 2/5 — price label «від» decision (salon side). priceMin == priceMax
//     renders an EXACT fixed price «N грн» with NO «від»; priceMin < priceMax
//     renders a «N–M грн» range; a single bound renders the open-ended «від»;
//     both null hides the line. Item 5 also asserts the price line RENDERS at
//     all when data is present (the "salon price renders" confirmation).
//   • Item 6 — the (auth-gated) precomputed `addressLine` renders in place of
//     the locality line when present; falls back to the locality when null.
//   • Item 7 — the salon's `servicesLine` (built from serviceNames) renders.
//
// Harness: `pumpApp` (UK l10n + ProviderScope). The favourite heart watches
// favoriteToggleProvider → authProvider, so it is overridden with the auth-free
// notifier to keep the card render synchronous and network-free. Assertions key
// off the l10n value resolved from the pumped tree — never a hardcoded UA
// string for the price labels.

import 'package:beautica_mobile/features/discovery/domain/salon_search_item.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/result_address_block.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/salon_result_card.dart';
import 'package:beautica_mobile/features/favorites/application/favorite_toggle_notifier.dart';
import 'package:beautica_mobile/features/favorites/domain/favorite_target.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

class _AuthFreeFavoriteToggleNotifier extends FavoriteToggleNotifier {
  @override
  Map<FavoriteTarget, FavoriteEntry> build() =>
      const <FavoriteTarget, FavoriteEntry>{};
}

SalonSearchItem _salon({
  double? priceMin = 300,
  double? priceMax = 1200,
  String? cityLabel = 'Київ',
  String? districtLabel = 'Печерський',
  String? street,
  String? buildingNo,
  String? locationNote,
  String? addressLine,
  List<String> serviceNames = const <String>[],
  String? servicesLine,
}) => SalonSearchItem(
  salonId: 'salon-1',
  name: 'Студія Краси «Камелія»',
  avatarUrl: null,
  avgRating: null,
  cityLabel: cityLabel,
  districtLabel: districtLabel,
  priceMin: priceMin,
  priceMax: priceMax,
  street: street,
  buildingNo: buildingNo,
  locationNote: locationNote,
  addressLine: addressLine,
  serviceNames: serviceNames,
  servicesLine: servicesLine,
);

Future<void> _pump(WidgetTester tester, SalonSearchItem salon) {
  return tester.pumpApp(
    Scaffold(body: SalonResultCard(salon: salon)),
    overrides: <Object>[
      favoriteToggleProvider.overrideWith(_AuthFreeFavoriteToggleNotifier.new),
    ],
  );
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(SalonResultCard)));

void main() {
  // -------------------------------------------------------------------------
  // Item 2/5 — price label «від» decision + the price line renders.
  // -------------------------------------------------------------------------
  group('SalonResultCard price label (item 2/5)', () {
    testWidgets('priceMin == priceMax → EXACT price «N грн», NO «від» prefix', (
      tester,
    ) async {
      await _pump(tester, _salon(priceMin: 500, priceMax: 500));

      final l10n = _l10n(tester);
      expect(find.text(l10n.searchResultPriceExact(500)), findsOneWidget);
      expect(
        find.text(l10n.searchPriceFrom(500)),
        findsNothing,
        reason:
            'equal min/max bounds are a single fixed price — «від» must NOT '
            'appear (the salon-side regression guard).',
      );
    });

    testWidgets(
      'priceMin < priceMax → «N–M грн» range label (item 5 renders)',
      (tester) async {
        await _pump(tester, _salon(priceMin: 300, priceMax: 1200));

        final l10n = _l10n(tester);
        // The price line is present (item 5: salon price renders) …
        expect(
          find.text(l10n.searchResultPriceRange(300, 1200)),
          findsOneWidget,
        );
        // … and it is a range, not a single exact price.
        expect(find.text(l10n.searchResultPriceExact(300)), findsNothing);
      },
    );

    testWidgets('a single bound (max only) keeps the open-ended «від» prefix', (
      tester,
    ) async {
      await _pump(tester, _salon(priceMin: null, priceMax: 900));

      final l10n = _l10n(tester);
      expect(find.text(l10n.searchPriceFrom(900)), findsOneWidget);
    });

    testWidgets('both bounds null → no price line at all', (tester) async {
      await _pump(tester, _salon(priceMin: null, priceMax: null));

      expect(find.textContaining('грн'), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // Item 7 — salon services preview line renders.
  // -------------------------------------------------------------------------
  group('SalonResultCard services line (item 7)', () {
    testWidgets('renders the pre-joined servicesLine with maxLines: 2', (
      tester,
    ) async {
      await _pump(
        tester,
        _salon(
          serviceNames: const <String>['Манікюр', 'Стрижка'],
          servicesLine: 'Манікюр · Стрижка',
        ),
      );

      final Finder line = find.byKey(const Key('salon_card_services'));
      expect(line, findsOneWidget);
      final Text text = tester.widget<Text>(line);
      expect(text.data, 'Манікюр · Стрижка');
      expect(text.maxLines, 2);
    });

    testWidgets('omits the services line when servicesLine is null', (
      tester,
    ) async {
      await _pump(tester, _salon(servicesLine: null));

      expect(find.byKey(const Key('salon_card_services')), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // Item 6 — full two-line address (locality + street·note) via
  // [ResultAddressBlock]. BOTH lines render together for an authed caller; the
  // street line collapses for an anonymous one. Region/oblast is NOT in the
  // contract and is never rendered.
  // -------------------------------------------------------------------------
  group('SalonResultCard address block (item 6)', () {
    testWidgets(
      'authed FULL address: locality line AND street·note line both render',
      (tester) async {
        await _pump(
          tester,
          _salon(
            street: 'вул. Сагайдачного',
            buildingNo: '10А',
            locationNote: '2 поверх',
            addressLine: 'вул. Сагайдачного, 10А · 2 поверх',
            cityLabel: 'Київ',
            districtLabel: 'Печерський',
          ),
        );

        // Two-line contract: locality PRESENT …
        expect(
          find.text('Печерський, Київ'),
          findsOneWidget,
          reason:
              'the two-line layout keeps the locality line even when an '
              'auth-gated street line is present.',
        );
        // … AND the full street·note line PRESENT below it.
        expect(find.text('вул. Сагайдачного, 10А · 2 поверх'), findsOneWidget);
      },
    );

    testWidgets(
      'authed WITHOUT note: street line renders with NO trailing « · »',
      (tester) async {
        await _pump(
          tester,
          _salon(
            street: 'вул. Сагайдачного',
            buildingNo: '10А',
            locationNote: null,
            addressLine: 'вул. Сагайдачного, 10А',
            cityLabel: 'Київ',
            districtLabel: 'Печерський',
          ),
        );

        expect(find.text('Печерський, Київ'), findsOneWidget);
        expect(find.text('вул. Сагайдачного, 10А'), findsOneWidget);
        expect(
          find.textContaining(' · '),
          findsNothing,
          reason: 'a missing note must not leave a dangling « · » suffix.',
        );
      },
    );

    testWidgets(
      'anonymous (null street): ONLY the locality line renders — no street, '
      'no oblast',
      (tester) async {
        await _pump(
          tester,
          _salon(
            street: null,
            buildingNo: null,
            locationNote: null,
            addressLine: null,
            cityLabel: 'Київ',
            districtLabel: 'Печерський',
          ),
        );

        expect(find.text('Печерський, Київ'), findsOneWidget);
        expect(find.textContaining('вул.'), findsNothing);
        // Region/oblast is NEVER rendered (not in the search contract).
        expect(find.textContaining('Київська'), findsNothing);
        expect(find.textContaining('область'), findsNothing);
      },
    );

    testWidgets(
      'both locality AND street null → the address block collapses to nothing',
      (tester) async {
        await _pump(
          tester,
          _salon(
            street: null,
            buildingNo: null,
            locationNote: null,
            addressLine: null,
            cityLabel: null,
            districtLabel: null,
          ),
        );

        expect(
          find.descendant(
            of: find.byType(ResultAddressBlock),
            matching: find.byIcon(Icons.place_outlined),
          ),
          findsNothing,
          reason:
              'with no locality and no street the block must not show a '
              'lone place-pin glyph.',
        );
      },
    );
  });
}

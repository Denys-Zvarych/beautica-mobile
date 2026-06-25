// Search-page change (items 2, 3, 6) — widget tests for [MasterResultCard].
//
// Pins the result-card contract the golden cannot assert behaviourally:
//   • Item 2 — price label «від» decision. A master whose priceMax equals the
//     minEffectivePrice (or whose priceMax is null) renders an EXACT fixed price
//     «N грн» with NO «від» prefix; a master with priceMax > min renders a
//     «N–M грн» range. This is the regression-prone branch: the old code always
//     prefixed «від», so a single-price master read «від 500 грн» instead of
//     «500 грн».
//   • Item 3 — the services preview line opts into maxLines: 2 (was 1).
//   • Item 6 — the (auth-gated) precomputed `addressLine` renders as the
//     locality line when present; when it is null the card falls back to the
//     city/district locality.
//
// Harness: `pumpApp` (UK l10n + ProviderScope). The favourite heart watches
// favoriteToggleProvider → authProvider, so it is overridden with the auth-free
// notifier (the same pattern as search_results_screen_test.dart) to keep the
// card render synchronous and network-free. All assertions key off the l10n
// value resolved from the pumped tree — never a hardcoded UA string.

import 'package:beautica_mobile/features/discovery/domain/master_search_item.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/master_result_card.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/result_address_block.dart';
import 'package:beautica_mobile/features/favorites/application/favorite_toggle_notifier.dart';
import 'package:beautica_mobile/features/favorites/domain/favorite_target.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// Auth-free favourite toggle — skips the production build()'s
// ref.watch(authProvider) so the heart renders without an auth graph.
// ---------------------------------------------------------------------------
class _AuthFreeFavoriteToggleNotifier extends FavoriteToggleNotifier {
  @override
  Map<FavoriteTarget, FavoriteEntry> build() =>
      const <FavoriteTarget, FavoriteEntry>{};
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

MasterSearchItem _master({
  double? minEffectivePrice = 500,
  double? priceMax,
  String? cityLabel = 'Київ',
  String? districtLabel = 'Печерський',
  String? street,
  String? buildingNo,
  String? locationNote,
  String? addressLine,
  List<String> serviceNames = const <String>[],
  String? servicesLine,
  String? matchedServicesLine,
}) => MasterSearchItem(
  masterId: 'master-1',
  firstName: 'Олена',
  lastName: 'Коваль',
  avatarUrl: null,
  avgRating: 4.8,
  reviewCount: 12,
  cityLabel: cityLabel,
  districtLabel: districtLabel,
  minEffectivePrice: minEffectivePrice,
  priceMax: priceMax,
  street: street,
  buildingNo: buildingNo,
  locationNote: locationNote,
  addressLine: addressLine,
  serviceNames: serviceNames,
  servicesLine: servicesLine,
  matchedServicesLine: matchedServicesLine,
);

Future<void> _pump(WidgetTester tester, MasterSearchItem master) {
  return tester.pumpApp(
    Scaffold(body: MasterResultCard(master: master)),
    overrides: <Object>[
      favoriteToggleProvider.overrideWith(_AuthFreeFavoriteToggleNotifier.new),
    ],
  );
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(MasterResultCard)));

void main() {
  // -------------------------------------------------------------------------
  // Item 2 — price label «від» decision.
  // -------------------------------------------------------------------------
  group('MasterResultCard price label (item 2)', () {
    testWidgets(
      'priceMax == minEffectivePrice → EXACT price «N грн», NO «від» prefix',
      (tester) async {
        await _pump(tester, _master(minEffectivePrice: 500, priceMax: 500));

        final l10n = _l10n(tester);
        // Exact-price label is rendered verbatim …
        expect(find.text(l10n.searchResultPriceExact(500)), findsOneWidget);
        // … and the «від N грн» open-ended label is NOT.
        expect(
          find.text(l10n.searchPriceFrom(500)),
          findsNothing,
          reason:
              'an equal min/max bound is a single fixed price — the «від» '
              'prefix must NOT appear (the regression this test guards).',
        );
      },
    );

    testWidgets('priceMax == null → EXACT price «N грн», NO «від» prefix', (
      tester,
    ) async {
      await _pump(tester, _master(minEffectivePrice: 350, priceMax: null));

      final l10n = _l10n(tester);
      expect(find.text(l10n.searchResultPriceExact(350)), findsOneWidget);
      expect(find.text(l10n.searchPriceFrom(350)), findsNothing);
    });

    testWidgets('priceMax > minEffectivePrice → «N–M грн» range label', (
      tester,
    ) async {
      await _pump(tester, _master(minEffectivePrice: 350, priceMax: 900));

      final l10n = _l10n(tester);
      expect(find.text(l10n.searchResultPriceRange(350, 900)), findsOneWidget);
      // The single-price exact label must NOT appear for a genuine range.
      expect(find.text(l10n.searchResultPriceExact(350)), findsNothing);
    });

    testWidgets('minEffectivePrice == null → no price line at all', (
      tester,
    ) async {
      await _pump(tester, _master(minEffectivePrice: null, priceMax: null));

      final l10n = _l10n(tester);
      expect(find.text(l10n.searchResultPriceExact(0)), findsNothing);
      // No «грн» fragment renders for a priceless master (line omitted).
      expect(find.textContaining('грн'), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // Item 3 — services preview line wraps to 2 lines.
  // -------------------------------------------------------------------------
  group('MasterResultCard services line (item 3)', () {
    testWidgets('renders the pre-joined services line with maxLines: 2', (
      tester,
    ) async {
      await _pump(
        tester,
        _master(
          serviceNames: const <String>['Манікюр', 'Педикюр'],
          servicesLine: 'Манікюр · Педикюр',
        ),
      );

      final Finder line = find.byKey(const Key('master_card_services'));
      expect(line, findsOneWidget);
      final Text text = tester.widget<Text>(line);
      expect(text.data, 'Манікюр · Педикюр');
      expect(
        text.maxLines,
        2,
        reason: 'the services preview line wraps onto a second line (item 3)',
      );
    });

    testWidgets('omits the services line when servicesLine is null', (
      tester,
    ) async {
      await _pump(tester, _master(servicesLine: null));

      expect(find.byKey(const Key('master_card_services')), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // Phase 13.12 — the card PREFERS matchedServicesLine over servicesLine.
  // -------------------------------------------------------------------------
  group('MasterResultCard matched-service line (Phase 13.12)', () {
    testWidgets(
      'with a per-service filter active → renders matchedServicesLine, NOT the '
      'generic servicesLine',
      (tester) async {
        await _pump(
          tester,
          _master(
            serviceNames: const <String>['Манікюр', 'Педикюр', 'Брови'],
            servicesLine: 'Манікюр · Педикюр · Брови',
            matchedServicesLine: 'Брови',
          ),
        );

        final Text text = tester.widget<Text>(
          find.byKey(const Key('master_card_services')),
        );
        expect(text.data, 'Брови');
        // The generic top-3 line must NOT appear when a match is present.
        expect(find.text('Манікюр · Педикюр · Брови'), findsNothing);
      },
    );

    testWidgets(
      'no filter (matchedServicesLine null) → falls back to servicesLine',
      (tester) async {
        await _pump(
          tester,
          _master(
            serviceNames: const <String>['Манікюр', 'Педикюр'],
            servicesLine: 'Манікюр · Педикюр',
            matchedServicesLine: null,
          ),
        );

        final Text text = tester.widget<Text>(
          find.byKey(const Key('master_card_services')),
        );
        expect(text.data, 'Манікюр · Педикюр');
      },
    );
  });

  // -------------------------------------------------------------------------
  // Item 6 — full two-line address (locality + street·note) via
  // [ResultAddressBlock]. The card renders BOTH the locality line and the
  // auth-gated street line together; the street line collapses to nothing for
  // an anonymous caller. Region/oblast is NOT in the contract and is never
  // rendered.
  // -------------------------------------------------------------------------
  group('MasterResultCard address block (item 6)', () {
    testWidgets(
      'authed FULL address: locality line AND street·note line both render',
      (tester) async {
        await _pump(
          tester,
          _master(
            street: 'вул. Хрещатик',
            buildingNo: '22',
            locationNote: 'вхід з двору',
            // The mapper precomputes «street, buildingNo · note».
            addressLine: 'вул. Хрещатик, 22 · вхід з двору',
            cityLabel: 'Київ',
            districtLabel: 'Печерський',
          ),
        );

        // Two-line contract: the locality line is PRESENT …
        expect(
          find.text('Печерський, Київ'),
          findsOneWidget,
          reason:
              'the two-line layout keeps the «district, city» locality line as '
              'line 1 even when an auth-gated street line is present.',
        );
        // … AND the full street·note line is PRESENT below it.
        expect(
          find.text('вул. Хрещатик, 22 · вхід з двору'),
          findsOneWidget,
          reason:
              'the precomputed addressLine (street, buildingNo · note) renders '
              'as the second line beneath the locality.',
        );
      },
    );

    testWidgets(
      'authed WITHOUT note: street line renders with NO trailing « · »',
      (tester) async {
        await _pump(
          tester,
          _master(
            street: 'вул. Хрещатик',
            buildingNo: '22',
            locationNote: null,
            addressLine: 'вул. Хрещатик, 22',
            cityLabel: 'Київ',
            districtLabel: 'Печерський',
          ),
        );

        expect(find.text('Печерський, Київ'), findsOneWidget);
        expect(find.text('вул. Хрещатик, 22'), findsOneWidget);
        // No dangling separator slipped onto the street line.
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
          _master(
            street: null,
            buildingNo: null,
            locationNote: null,
            addressLine: null,
            cityLabel: 'Київ',
            districtLabel: 'Печерський',
          ),
        );

        // Anonymous caller → null address → only the locality line shows.
        expect(find.text('Печерський, Київ'), findsOneWidget);
        // No street fragment leaked onto the card …
        expect(find.textContaining('вул.'), findsNothing);
        // … and the region/oblast is NEVER rendered (it is not in the search
        // contract). This guards the "no oblast" requirement.
        expect(find.textContaining('Київська'), findsNothing);
        expect(find.textContaining('область'), findsNothing);
      },
    );

    testWidgets(
      'both locality AND street null → the address block collapses to nothing',
      (tester) async {
        await _pump(
          tester,
          _master(
            street: null,
            buildingNo: null,
            locationNote: null,
            addressLine: null,
            cityLabel: null,
            districtLabel: null,
          ),
        );

        // The whole block renders SizedBox.shrink() — no pin, no orphan line.
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

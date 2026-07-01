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

import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/discovery/domain/master_search_item.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/master_result_card.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/result_address_block.dart';
import 'package:beautica_mobile/features/favorites/application/favorite_toggle_notifier.dart';
import 'package:beautica_mobile/features/favorites/domain/favorite_target.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  String firstName = 'Олена',
  String lastName = 'Коваль',
}) => MasterSearchItem(
  masterId: 'master-1',
  firstName: firstName,
  lastName: lastName,
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

Future<void> _pump(
  WidgetTester tester,
  MasterSearchItem master, {
  double? width,
  double? textScaleFactor,
}) {
  return tester.pumpApp(
    Scaffold(body: MasterResultCard(master: master)),
    overrides: <Object>[
      favoriteToggleProvider.overrideWith(_AuthFreeFavoriteToggleNotifier.new),
    ],
    width: width,
    textScaleFactor: textScaleFactor,
  );
}

/// The [RenderParagraph] backing the name [Text] (the card's name has no key,
/// so it is located by its fixture data — a fixture literal, not a UI string).
RenderParagraph _nameParagraph(WidgetTester tester, String name) =>
    tester.renderObject<RenderParagraph>(find.text(name));

/// Number of lines the paragraph actually laid out, reproduced from its own
/// span + style + the width it was given. [RenderParagraph] exposes no line
/// count directly, so re-run the layout in a [TextPainter] (which does expose
/// [TextPainter.computeLineMetrics]) at the paragraph's incoming max width.
int _lineCount(RenderParagraph p) {
  final painter = TextPainter(
    text: p.text,
    textAlign: p.textAlign,
    textDirection: p.textDirection,
    textScaler: p.textScaler,
    maxLines: p.maxLines,
  )..layout(maxWidth: p.constraints.maxWidth);
  final int lines = painter.computeLineMetrics().length;
  painter.dispose();
  return lines;
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
  // Phase 13.5 navigation — the card body is a button that navigates to
  // RouteNames.masterPublicProfile (/masters/:id, registered in Phase 13.5).
  // It is wrapped in Semantics(button: true, label: name) so screen readers
  // announce it as a tappable element carrying the master's name.
  // -------------------------------------------------------------------------
  group('MasterResultCard navigation (Phase 13.5)', () {
    testWidgets(
      'card body is a button: Semantics carries the name label AND the button '
      'flag',
      (tester) async {
        await _pump(tester, _master());

        // The fixture's display name (firstName + lastName) — the card's own
        // data label, not a localised UI string.
        const String name = 'Олена Коваль';

        final Finder cardSemantics = find.ancestor(
          of: find.byType(NeumorphicCard),
          matching: find.byWidgetPredicate(
            (Widget w) => w is Semantics && w.properties.label == name,
          ),
        );
        expect(
          cardSemantics,
          findsOneWidget,
          reason:
              'the card body wraps NeumorphicCard in Semantics(label: name)',
        );

        final Semantics semantics = tester.widget<Semantics>(cardSemantics);
        expect(
          semantics.properties.button,
          isTrue,
          reason:
              'the card body navigates to /masters/:id on tap (Phase 13.5), so '
              'it must be announced as a button carrying the master name.',
        );
      },
    );
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
        // i18n-finder-ok: service names are fixture data, not UI copy
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
          // i18n-finder-ok: district/city labels are fixture data, not UI copy
          find.text('Печерський, Київ'),
          findsOneWidget,
          reason:
              'the two-line layout keeps the «district, city» locality line as '
              'line 1 even when an auth-gated street line is present.',
        );
        // … AND the full street·note line is PRESENT below it.
        expect(
          // i18n-finder-ok: street/note address text is fixture data, not UI copy
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

        // i18n-finder-ok: district/city labels are fixture data, not UI copy
        expect(find.text('Печерський, Київ'), findsOneWidget);
        // i18n-finder-ok: street address text is fixture data, not UI copy
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
        // i18n-finder-ok: district/city labels are fixture data, not UI copy
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

  // -------------------------------------------------------------------------
  // Long-name wrapping — guards the name `maxLines: 2` fix on a narrow card.
  //
  // In the unconstrained production list a long master name must wrap to two
  // lines rather than be single-line ellipsis-truncated. The card's name has no
  // key, so it is located by its fixture data and inspected via the backing
  // [RenderParagraph]: a revert to maxLines: 1 caps the layout at one line and
  // sets didExceedMaxLines == true.
  // -------------------------------------------------------------------------
  group('MasterResultCard long-name wrapping (320dp)', () {
    const String longName = 'Олександра Зварич-Пономаренко';

    testWidgets('long name wraps to two lines, fully shown, at 320dp x1.0', (
      tester,
    ) async {
      await _pump(
        tester,
        _master(firstName: 'Олександра', lastName: 'Зварич-Пономаренко'),
        width: 320,
        textScaleFactor: 1.0,
      );

      final paragraph = _nameParagraph(tester, longName);
      expect(
        _lineCount(paragraph),
        2,
        reason:
            'the long name wraps onto a second line in the narrow card column — '
            'maxLines: 1 would cap it to a single line. (Two lines hold the full '
            'name in the production font; the wider test font may need ellipsis '
            'past two lines, so the deterministic guard is the 2-line layout.)',
      );
    });

    testWidgets(
      'long name still wraps to two lines at 320dp x1.3 (no overflow)',
      (tester) async {
        // pumpApp's overflow guard fails the test in tearDown on any RenderFlex
        // overflow at this stress size, so no explicit overflow assertion needed.
        await _pump(
          tester,
          _master(firstName: 'Олександра', lastName: 'Зварич-Пономаренко'),
          width: 320,
          textScaleFactor: 1.3,
        );

        final paragraph = _nameParagraph(tester, longName);
        expect(
          _lineCount(paragraph),
          2,
          reason: 'the name uses both allowed lines at the larger text scale.',
        );
      },
    );
  });
}

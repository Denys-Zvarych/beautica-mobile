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

import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/discovery/domain/salon_search_item.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/result_address_block.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/salon_result_card.dart';
import 'package:beautica_mobile/features/favorites/application/favorite_toggle_notifier.dart';
import 'package:beautica_mobile/features/favorites/domain/favorite_target.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

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
  String? matchedServicesLine,
  String name = 'Студія Краси «Камелія»',
}) => SalonSearchItem(
  salonId: 'salon-1',
  name: name,
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
  matchedServicesLine: matchedServicesLine,
);

Future<void> _pump(
  WidgetTester tester,
  SalonSearchItem salon, {
  double? width,
  double? textScaleFactor,
}) {
  return tester.pumpApp(
    Scaffold(body: SalonResultCard(salon: salon)),
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
  // Phase 13.6 navigation — the card body is a button that navigates to
  // RouteNames.salonPublicProfile (/salons/:id, registered in Phase 13.6). It
  // is wrapped in Semantics(button: true, label: name) so screen readers
  // announce it as a tappable element carrying the salon's name — mirrors
  // MasterResultCard's identical Phase 13.5 navigation contract.
  // -------------------------------------------------------------------------
  group('SalonResultCard navigation (Phase 13.6)', () {
    testWidgets(
      'card body is a button: Semantics carries the name label AND the button '
      'flag',
      (tester) async {
        await _pump(tester, _salon());

        // The fixture's salon name — the card's own data label, not a
        // localised UI string.
        const String name = 'Студія Краси «Камелія»';

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
              'the card body navigates to /salons/:id on tap (Phase 13.6), so '
              'it must be announced as a button carrying the salon name.',
        );
      },
    );

    testWidgets('tapping the card pushes RouteNames.salonPublicProfile', (
      tester,
    ) async {
      final router = GoRouter(
        initialLocation: '/search/results',
        routes: <RouteBase>[
          GoRoute(
            path: '/search/results',
            builder: (context, state) =>
                Scaffold(body: SalonResultCard(salon: _salon())),
          ),
          GoRoute(
            path: '/salons/:salonId',
            builder: (context, state) => Scaffold(
              body: Text('salon-profile-${state.pathParameters['salonId']}'),
            ),
          ),
        ],
      );

      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[
          favoriteToggleProvider.overrideWith(
            _AuthFreeFavoriteToggleNotifier.new,
          ),
        ],
      );
      await tester.pumpAndSettle();

      // i18n-finder-ok: the salon fixture's own data label, not UI copy.
      await tester.tap(find.text('Студія Краси «Камелія»'));
      await tester.pumpAndSettle();

      expect(find.text('salon-profile-salon-1'), findsOneWidget);
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
  // Phase 13.12 — the card PREFERS matchedServicesLine over servicesLine.
  // -------------------------------------------------------------------------
  group('SalonResultCard matched-service line (Phase 13.12)', () {
    testWidgets(
      'with a per-service filter active → renders matchedServicesLine, NOT the '
      'generic servicesLine',
      (tester) async {
        await _pump(
          tester,
          _salon(
            serviceNames: const <String>['Манікюр', 'Стрижка', 'Брови'],
            servicesLine: 'Манікюр · Стрижка · Брови',
            matchedServicesLine: 'Стрижка',
          ),
        );

        final Text text = tester.widget<Text>(
          find.byKey(const Key('salon_card_services')),
        );
        expect(text.data, 'Стрижка');
        // i18n-finder-ok: service names are fixture data, not UI copy
        expect(find.text('Манікюр · Стрижка · Брови'), findsNothing);
      },
    );

    testWidgets(
      'no filter (matchedServicesLine null) → falls back to servicesLine',
      (tester) async {
        await _pump(
          tester,
          _salon(
            serviceNames: const <String>['Манікюр', 'Стрижка'],
            servicesLine: 'Манікюр · Стрижка',
            matchedServicesLine: null,
          ),
        );

        final Text text = tester.widget<Text>(
          find.byKey(const Key('salon_card_services')),
        );
        expect(text.data, 'Манікюр · Стрижка');
      },
    );
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
          // i18n-finder-ok: district/city labels are fixture data, not UI copy
          find.text('Печерський, Київ'),
          findsOneWidget,
          reason:
              'the two-line layout keeps the locality line even when an '
              'auth-gated street line is present.',
        );
        // … AND the full street·note line PRESENT below it.
        // i18n-finder-ok: street/note address text is fixture data, not UI copy
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

        // i18n-finder-ok: district/city labels are fixture data, not UI copy
        expect(find.text('Печерський, Київ'), findsOneWidget);
        // i18n-finder-ok: street address text is fixture data, not UI copy
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

        // i18n-finder-ok: district/city labels are fixture data, not UI copy
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

  // -------------------------------------------------------------------------
  // Long-name wrapping — guards the name `maxLines: 2` fix on a narrow card.
  //
  // A long salon name must wrap to two lines in the unconstrained production
  // list rather than be single-line ellipsis-truncated. The name has no key, so
  // it is located by fixture data and inspected via the backing
  // [RenderParagraph]: a revert to maxLines: 1 caps the layout at one line.
  // -------------------------------------------------------------------------
  group('SalonResultCard long-name wrapping (320dp)', () {
    const String longName = 'Студія Краси та Естетики «Прекрасна Камелія»';

    testWidgets('long name wraps to two lines, fully shown, at 320dp x1.0', (
      tester,
    ) async {
      await _pump(
        tester,
        _salon(name: longName),
        width: 320,
        textScaleFactor: 1.0,
      );

      final paragraph = _nameParagraph(tester, longName);
      expect(
        _lineCount(paragraph),
        2,
        reason:
            'the long salon name wraps onto a second line in the narrow card '
            'column — maxLines: 1 would cap it to a single line. (Two lines hold '
            'the full name in the production font; the wider test font may need '
            'ellipsis past two lines, so the deterministic guard is the 2-line '
            'layout.)',
      );
    });

    testWidgets(
      'long name still wraps to two lines at 320dp x1.3 (no overflow)',
      (tester) async {
        // pumpApp's overflow guard fails the test in tearDown on any RenderFlex
        // overflow at this stress size, so no explicit overflow assertion needed.
        await _pump(
          tester,
          _salon(name: longName),
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

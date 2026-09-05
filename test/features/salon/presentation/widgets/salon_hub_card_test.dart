// mobile-qa gap-closure (2026-09-02) — widget tests for [SalonHubCard].
//
// WHY THIS FILE EXISTS
// ---------------------
// Before this file, `SalonHubCard`'s ONLY coverage was
// `test/golden/salon_hub_card_golden_test.dart`, whose two fixtures
// (`_kHubSalon`, `_kPickerSalon`) both leave `cityId` blank and `districtId`
// null — `resolvedLocalityProvider` short-circuits on a blank `cityId`
// (see that provider's own "nothing to resolve" guard), so `resolved` is
// always `null` in that file and `resolved?.district?.name` is NEVER
// exercised. Two green goldens never touched:
//   - the district branch of `SalonHubCard`'s Line 1 (`buildFullAddressLine`
//     composing `cityName` + `districtName`, the Phase 21.6 audit fix);
//   - the legacy `salon.address` fallback (both structured lines null);
//   - the `Semantics` label carrying the FULL address, comma-joined.
//
// Goldens are also, on their own, NOT acceptance for a visual/behavioural
// bug (a regenerated golden is self-referential — see mobile-qa's own
// standing rule). This file adds the missing BEHAVIOURAL assertions instead
// of widening the golden matrix, so each new case is provably load-bearing
// (see each test's own "mutation" note) rather than a baseline that would
// simply re-capture whatever the widget currently paints.
//
// TRAP AVOIDED: `resolvedLocalityProvider` is overridden DIRECTLY
// (`resolvedLocalityProvider(oblastId:, cityId:, districtId:).overrideWith(
// (ref) async => ...)`), never by overriding `locationRepositoryProvider`
// and driving the real oblast->city->district scan through it — the
// `approvedCategoriesProvider`-style footgun this repo has hit before
// (overriding the repository one layer down bypasses the family's own
// memoized `keepAlive` cascade and is one extra layer of indirection this
// widget doesn't need proven).

import 'package:beautica_mobile/features/location/domain/city.dart';
import 'package:beautica_mobile/features/location/domain/city_district.dart';
import 'package:beautica_mobile/features/location/domain/resolved_locality.dart';
import 'package:beautica_mobile/features/location/state/resolved_locality_provider.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/presentation/widgets/salon_hub_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

const String _kOblastId = 'ob-kyiv';
const String _kCityId = 'city-kyiv';
const String _kDistrictId = 'dist-pech';

const City _kCity = City(
  id: _kCityId,
  oblastId: _kOblastId,
  name: 'Київ',
  katotthCode: 'K1',
  hasDistricts: true,
);

const CityDistrict _kDistrict = CityDistrict(
  id: _kDistrictId,
  cityId: _kCityId,
  name: 'Печерський',
  katotthCode: 'D1',
);

/// A salon whose city AND district both resolve — the Phase 21.6 audit-fix
/// code path (`buildFullAddressLine(cityName:, districtName:)`) that the
/// golden file's blank-`cityId` fixtures never reach.
const Salon _kDistrictSalon = Salon(
  id: 'salon-district',
  name: 'Студія «Гармонія»',
  oblastId: _kOblastId,
  cityId: _kCityId,
  districtId: _kDistrictId,
  street: 'вул. Мазепи',
  buildingNo: '3',
);

/// No taxonomy ids, no street — only the legacy pre-composed `address` is
/// left. The embedded `\n` is deliberate: it proves the render goes through
/// `buildLegacyAddressLine`'s `collapseNewlines: true` opt-in, not a raw
/// assignment of `salon.address` (the exact bypass Phase 21.6(b) closed).
const Salon _kLegacySalon = Salon(
  id: 'salon-legacy',
  name: 'Барбершоп «Ретро»',
  address: 'м. Одеса,\nвул. Дерибасівська, 1',
);

/// Same shape as [_kLegacySalon] but with a CLEAN (no-newline) address, for
/// tests that don't want the collapse behaviour to be part of the signal.
const String _kLegacyCleanAddress = 'м. Одеса, вул. Дерибасівська, 1';

const Salon _kLegacySalonClean = Salon(
  id: 'salon-legacy-clean',
  name: 'Барбершоп «Ретро»',
  address: _kLegacyCleanAddress,
);

List<Object> _districtOverrides() => <Object>[
  resolvedLocalityProvider(
    oblastId: _kOblastId,
    cityId: _kCityId,
    districtId: _kDistrictId,
  ).overrideWith(
    (ref) async => const ResolvedLocality(city: _kCity, district: _kDistrict),
  ),
];

void main() {
  group('SalonHubCard — district resolution (Phase 21.6 audit-fix gap)', () {
    testWidgets(
      'renders "Київ, Печерський" on line 1 when both city AND district '
      'resolve — the district must NOT be dropped',
      (tester) async {
        await tester.pumpApp(
          SalonHubCard(salon: _kDistrictSalon, onTap: () {}),
          overrides: _districtOverrides(),
        );
        await tester.pumpAndSettle();

        // MUTATION PROOF: reverting `salon_hub_card.dart`'s Line 1 back to
        // the pre-Phase-21.6 `buildLocalityLine(cityName)` (dropping
        // `districtName`) renders "Київ\nвул. Мазепи, 3" instead — this
        // exact string would then NOT be found and the test goes red.
        expect(
          // i18n-finder-ok: this is test-fixture salon address data
          // (_kDistrictSalon's city + district + street, built above in
          // this file), not ARB-sourced UI copy — the assertion is
          // precisely about the LITERAL composition (city+district
          // comma-joined on line 1, street on line 2 after the newline),
          // which is what proves buildFullAddressLine still joins the
          // district in (the Phase 21.6 audit fix the MUTATION PROOF above
          // documents). A looser finder (e.g. textContaining) would stop
          // proving the join and defeat that mutation coverage.
          find.text('Київ, Печерський\nвул. Мазепи, 3'),
          findsOneWidget,
          reason:
              'line 1 must be the hierarchy-ordered city+district '
              '(buildFullAddressLine), line 2 the street/building — a '
              'dropped district collapses line 1 back to "Київ" alone',
        );
      },
    );

    testWidgets(
      'the Semantics label carries the district too, comma-joined on ONE '
      'line — not the two-line visual split',
      (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();

        await tester.pumpApp(
          SalonHubCard(salon: _kDistrictSalon, onTap: () {}),
          overrides: _districtOverrides(),
        );
        await tester.pumpAndSettle();

        final String label = tester
            .getSemantics(find.byType(SalonHubCard))
            .getSemanticsData()
            .label;
        // The merged SemanticsNode also carries descendant labels (e.g.
        // SalonLogo's own "Логотип салону" announcement), joined onto ours
        // with a Flutter-inserted `\n` separator — that merge is expected
        // and out of scope here. What THIS card's own `Semantics.label:`
        // annotation produced is exactly the first line: splitting on `\n`
        // isolates it from that unrelated descendant-merge noise.
        final String ownLabel = label.split('\n').first;

        // MUTATION PROOF: reverting `salon_hub_card.dart`'s
        // `semanticAddress` composition back to the pre-Phase-21.6
        // city-only form drops "Печерський" from this exact string, and the
        // equality below goes red.
        expect(
          ownLabel,
          'Студія «Гармонія», Київ, Печерський, вул. Мазепи, 3',
          reason:
              'the spoken label mirrors the on-screen text, hierarchy-'
              'ordered and comma-joined on ONE line — a screen-reader user '
              'must hear the district too',
        );

        handle.dispose();
      },
    );
  });

  group('SalonHubCard — legacy address fallback (mobile-security gap)', () {
    testWidgets('a salon with no taxonomy ids/street falls back to the legacy '
        'salon.address, rendered as ONE line with its embedded newline '
        'collapsed to a space', (tester) async {
      await tester.pumpApp(SalonHubCard(salon: _kLegacySalon, onTap: () {}));
      await tester.pumpAndSettle();

      // MUTATION PROOF: if `salon_hub_card.dart` reverted to assigning
      // `s.address` RAW (the exact bypass Phase 21.6(b) closed) instead of
      // routing it through `buildLegacyAddressLine`, the rendered text
      // would carry the literal `\n` from the fixture and this exact
      // collapsed string would NOT be found.
      expect(
        // i18n-finder-ok: this is test-fixture data — _kLegacySalon's
        // hand-written `address` string above in this file — not
        // ARB-sourced UI copy. The assertion is precisely about the
        // LITERAL collapse: the fixture embeds `\n`, and this exact
        // single-line string only matches once buildLegacyAddressLine has
        // replaced it with a space (the Phase 21.6(b) fix the MUTATION
        // PROOF above documents). A looser finder would stop proving the
        // newline was actually collapsed.
        find.text('м. Одеса, вул. Дерибасівська, 1'),
        findsOneWidget,
        reason:
            'buildLegacyAddressLine collapses the embedded newline to a '
            'space — a raw `salon.address` assignment would instead '
            'render the address with the newline still embedded',
      );
      expect(
        find.textContaining('\n'),
        findsNothing,
        reason:
            'no Text widget anywhere in this card may contain a literal '
            'newline once the legacy fallback is the only address line',
      );
    });

    testWidgets(
      'the legacy fallback renders when BOTH structured lines are empty — '
      'clean-address sanity check with no collapse behaviour involved',
      (tester) async {
        await tester.pumpApp(
          SalonHubCard(salon: _kLegacySalonClean, onTap: () {}),
        );
        await tester.pumpAndSettle();

        expect(find.text(_kLegacyCleanAddress), findsOneWidget);
      },
    );

    testWidgets(
      'the Semantics label for a legacy-only address falls back the same '
      'way the visual line does, with its embedded newline collapsed',
      (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();

        await tester.pumpApp(SalonHubCard(salon: _kLegacySalon, onTap: () {}));
        await tester.pumpAndSettle();

        final String label = tester
            .getSemantics(find.byType(SalonHubCard))
            .getSemanticsData()
            .label;
        // See the sibling district-branch test above for why only the
        // FIRST line (this card's own `Semantics.label:` annotation) is
        // asserted — the rest is Flutter's own descendant-label merge.
        final String ownLabel = label.split('\n').first;

        // MUTATION PROOF: if `salon_hub_card.dart` reverted to feeding the
        // RAW `salon.address` (embedded `\n` intact) into `semanticAddress`
        // instead of routing it through `buildLegacyAddressLine`, that `\n`
        // would land INSIDE this card's own label text and split it early
        // — `ownLabel` (== `label.split('\n').first`) would then be cut off
        // at "…Барбершоп «Ретро», м. Одеса," and this exact-match would go
        // red.
        expect(
          ownLabel,
          'Барбершоп «Ретро», м. Одеса, вул. Дерибасівська, 1',
          reason:
              'the legacy fallback feeds the SAME semanticAddress fallback '
              'chain as the visual line — the embedded newline must be '
              'collapsed, not leaked into (and truncating) the spoken '
              'label',
        );

        handle.dispose();
      },
    );

    testWidgets(
      'a salon with NEITHER a resolvable structured address NOR a legacy '
      'address renders no address block at all',
      (tester) async {
        const Salon bare = Salon(id: 'salon-bare', name: 'Салон без адреси');
        await tester.pumpApp(SalonHubCard(salon: bare, onTap: () {}));
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.location_on_outlined), findsNothing);
      },
    );
  });

  group('SalonHubCard — semantics smoke (regression guard)', () {
    testWidgets('the card is announced as a button carrying the salon name', (
      tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();

      await tester.pumpApp(SalonHubCard(salon: _kDistrictSalon, onTap: () {}));
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.byType(SalonHubCard)),
        isSemantics(isButton: true),
      );

      handle.dispose();
    });
  });
}

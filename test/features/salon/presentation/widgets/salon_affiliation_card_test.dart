// mobile-qa Phase 21.16 gap closure (2026-09-05) — widget tests for
// [SalonAffiliationCard], the ONE genuinely new widget the phase introduced.
//
// WHY THIS FILE EXISTS
// --------------------
// `grep -a -rln "SalonAffiliationCard" test/` returned exactly ONE hit before
// this file: `admin_own_profile_screen_test.dart`, which only ever asserts the
// card is PRESENT (`salon-affiliation-card-name` findsOneWidget) with a
// `Salon(id:, name:)` fixture carrying no locality at all. Three behaviours the
// widget actually has were therefore unpinned:
//
//   1. THE LOCALITY LINE, which the admin-screen fixture cannot reach because
//      `Salon(id: …, name: 'Вельвет')` leaves `cityId`/`oblastId` blank and
//      `resolvedLocalityProvider` short-circuits on a blank pair. So the
//      widget's whole `resolvedLocalityProvider` -> `buildFullAddressLine`
//      chain — the reason it is a `ConsumerWidget` at all — ran only its
//      "nothing to resolve" arm anywhere in the suite.
//   2. THE UNRESOLVED WINDOW, where the card must show the name with NO
//      locality line rather than a blank one (the header's "an empty line
//      would leave the card visibly lopsided" rule).
//   3. INERT vs TAPPABLE. `onTap: null` is the STAND-ALONE route's
//      configuration and the approved preview's default; the shell passes a
//      handler. The shell test proves the tappable half; nothing proved the
//      inert half, and per M14 a bare "no GestureDetector" assertion can pass
//      for the wrong reason forever — so the tappable case is asserted in the
//      SAME file with the SAME fixture, which is what makes the negative one
//      real (the only thing that differs between them is `onTap`).
//
// TRAP AVOIDED (the `approvedCategoriesProvider` footgun this repo has hit):
// `resolvedLocalityProvider` is overridden DIRECTLY, never by overriding
// `locationRepositoryProvider` one layer down — the same rule
// `salon_hub_card_test.dart` records for the identical locality chain.
//
// FINDERS: the two Text assertions read FIXTURE data (this file's own salon
// name / city / district), never ARB-sourced UI copy — i18n-finder-ok.

import 'dart:async';

import 'package:beautica_mobile/features/location/domain/city.dart';
import 'package:beautica_mobile/features/location/domain/city_district.dart';
import 'package:beautica_mobile/features/location/domain/resolved_locality.dart';
import 'package:beautica_mobile/features/location/state/resolved_locality_provider.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/presentation/widgets/salon_affiliation_card.dart';
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

/// A salon whose city AND district both resolve.
///
/// `city:` carries a DIFFERENT, deliberately wrong legacy value: the widget
/// must prefer the resolved taxonomy name over the frozen free-text field
/// whenever a real `cityId` is present, and a fixture where the two agreed
/// could not tell the two branches apart (fixture-defangs-assertion trap).
const Salon _kResolvingSalon = Salon(
  id: 'salon-affiliation-1',
  name: 'Студія «Гармонія»',
  city: 'ЛЕГАСІ-МІСТО',
  oblastId: _kOblastId,
  cityId: _kCityId,
  districtId: _kDistrictId,
);

List<Object> _resolvedOverrides() => <Object>[
  resolvedLocalityProvider(
    oblastId: _kOblastId,
    cityId: _kCityId,
    districtId: _kDistrictId,
  ).overrideWith(
    (ref) async => const ResolvedLocality(city: _kCity, district: _kDistrict),
  ),
];

/// The locality read parked mid-flight — the frame the card is first painted
/// on inside the admin shell, before the taxonomy cascade has answered.
List<Object> _pendingOverrides() => <Object>[
  resolvedLocalityProvider(
    oblastId: _kOblastId,
    cityId: _kCityId,
    districtId: _kDistrictId,
  ).overrideWith((ref) => Completer<ResolvedLocality>().future),
];

Finder get _name => find.byKey(const Key('salon-affiliation-card-name'));
Finder get _locality =>
    find.byKey(const Key('salon-affiliation-card-locality'));

void main() {
  group('SalonAffiliationCard — the locality line', () {
    testWidgets('renders the RESOLVED city and district, comma-joined, not the '
        'legacy free-text city', (tester) async {
      await tester.pumpApp(
        const SalonAffiliationCard(salon: _kResolvingSalon),
        overrides: _resolvedOverrides(),
      );
      await tester.pumpAndSettle();

      expect(_name, findsOneWidget);
      // i18n-finder-ok: fixture salon NAME, composed in this file — it is
      // data echoed straight back from `Salon.name`, never UI copy, so it
      // reads identically under EN.
      expect(find.text('Студія «Гармонія»'), findsOneWidget);
      expect(_locality, findsOneWidget);
      // The key sits ON the `Text`, so read its `data` rather than searching
      // for a descendant — a `find.descendant(of: _locality, …)` excludes the
      // root and would report zero matches for the very string that IS there.
      expect(
        tester.widget<Text>(_locality).data,
        'Київ, Печерський',
        reason:
            'the district must be joined in, not dropped — the same '
            'buildFullAddressLine contract SalonHubCard\'s own Phase 21.6 '
            'audit fix pins.',
      );
      expect(
        // i18n-finder-ok: fixture value of the legacy free-text `Salon.city`
        // column, composed in this file — data, not UI copy, and the
        // assertion is a DENIAL either way.
        find.text('ЛЕГАСІ-МІСТО'),
        findsNothing,
        reason:
            'Salon.city is legacy free-text frozen since Phase 10.6 and is '
            'consulted ONLY when the salon carries no cityId. This fixture '
            'HAS one, so a card that read the legacy field would print a '
            'stale — possibly wrong — city here.',
      );
    });

    testWidgets('while the locality is still resolving the line is OMITTED, '
        'not rendered blank — and the name still shows', (tester) async {
      await tester.pumpApp(
        const SalonAffiliationCard(salon: _kResolvingSalon),
        overrides: _pendingOverrides(),
      );
      await tester.pump();

      expect(
        _name,
        findsOneWidget,
        reason:
            'sanity: the card really is painted in the unresolved window — '
            'without this the absence below could just be an unmounted card.',
      );
      expect(
        _locality,
        findsNothing,
        reason:
            'an empty second line would leave the card visibly lopsided '
            'against the logo, and showing the legacy city first would flash a '
            'possibly-wrong locality that then changes under the reader.',
      );
      expect(
        // i18n-finder-ok: same fixture `Salon.city` value as above — data,
        // not UI copy.
        find.text('ЛЕГАСІ-МІСТО'),
        findsNothing,
        reason:
            'and the unresolved window must NOT fall back to the legacy field '
            '— the fallback is gated on having no cityId at all, not on the '
            'read being slow.',
      );
    });

    testWidgets('a salon with NO taxonomy ids falls back to the legacy city '
        'string', (tester) async {
      // No override needed: `resolvedLocalityProvider` short-circuits on a
      // blank oblast/city pair without touching the repository.
      await tester.pumpApp(
        const SalonAffiliationCard(
          salon: Salon(id: 'salon-legacy', name: 'Барбершоп', city: 'Одеса'),
        ),
      );
      await tester.pumpAndSettle();

      expect(_locality, findsOneWidget);
      // i18n-finder-ok — fixture data.
      expect(tester.widget<Text>(_locality).data, 'Одеса');
    });

    testWidgets('a salon with neither taxonomy ids nor a legacy city renders '
        'the name alone', (tester) async {
      await tester.pumpApp(
        const SalonAffiliationCard(
          salon: Salon(id: 'salon-bare', name: 'Вельвет'),
        ),
      );
      await tester.pumpAndSettle();

      expect(_name, findsOneWidget);
      expect(_locality, findsNothing);
    });
  });

  group('SalonAffiliationCard — inert vs tappable', () {
    // M14: a bare "the card is not tappable" assertion can pass for the wrong
    // reason indefinitely. The two tests below use the IDENTICAL fixture and
    // differ ONLY by `onTap`, so the positive one is what proves the negative
    // one is observing `onTap` and not, say, a card that failed to build.

    testWidgets('onTap == null — no gesture detector and no Semantics button; '
        'the card is orientation, not an action', (tester) async {
      // Disposed explicitly at the END of the body, not via addTearDown:
      // `_verifySemanticsHandlesWereDisposed` runs BEFORE tear-downs.
      final SemanticsHandle handle = tester.ensureSemantics();

      await tester.pumpApp(
        const SalonAffiliationCard(salon: _kResolvingSalon),
        overrides: _resolvedOverrides(),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(SalonAffiliationCard),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
      expect(
        tester.getSemantics(find.byType(SalonAffiliationCard)),
        isNot(isSemantics(isButton: true)),
        reason:
            'a screen-reader user must not be told this is a button when '
            'nothing happens on activation — the stand-alone /profile/admin '
            'route is exactly this configuration.',
      );

      handle.dispose();
    });

    testWidgets('onTap non-null — the card is tappable and announces itself as '
        'a button', (tester) async {
      // Disposed explicitly at the END of the body, not via addTearDown:
      // `_verifySemanticsHandlesWereDisposed` runs BEFORE tear-downs.
      final SemanticsHandle handle = tester.ensureSemantics();

      int taps = 0;
      await tester.pumpApp(
        SalonAffiliationCard(salon: _kResolvingSalon, onTap: () => taps++),
        overrides: _resolvedOverrides(),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.byType(SalonAffiliationCard)),
        isSemantics(isButton: true),
        reason:
            'and this is what makes the isNot() assertion above load-bearing: '
            'the ONLY difference between the two cases is `onTap`.',
      );

      await tester.tap(find.byType(SalonAffiliationCard));
      await tester.pump();
      expect(taps, 1);

      handle.dispose();
    });
  });
}

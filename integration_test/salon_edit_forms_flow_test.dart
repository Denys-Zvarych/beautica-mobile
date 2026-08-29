// Phase 21.10 QA follow-up — E2E: the three new salon edit-form routes
// («Назва та опис» / «Локація» / «Контакти») against a REAL (fake) HTTP
// boundary.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b)
// ----------------------------------------
// `test/features/salon/presentation/salon_edit_forms_test.dart` proves all
// three screens against a hand-rolled mini `GoRouter` with
// [salonRepositoryProvider] STUBBED by `FakeSalonRepository` — every
// read/write is an in-memory fake, never a real HTTP round trip, and that
// mini router never wires `salonManageGuard`. That cannot catch:
//   • the three ROUTES actually registered in the REAL `app_router.dart` —
//     `salonManageGuard` admitting a real, fully-authenticated SALON_OWNER
//     session at each of them (see the go_router literal-vs-dynamic
//     shadowing incident this project has already hit once — declaration
//     order bugs are invisible to a mini router that only declares the
//     routes under test);
//   • [SalonManagementProfile.saveAddress]'s cityId/districtId handling
//     surviving a REAL wire round-trip (JSON serialization included, not
//     just the Dart-level request object a fake repository never encodes);
//   • THE LOCALITY-PAIR CONTRACT — the one this file exists to pin. Backend
//     `LocalityWriteValidator` treats cityId/districtId as a UNIT: a district
//     is required iff the resolved city has urban districts, AND cityId
//     itself is unconditionally required on every PATCH regardless of which
//     field changed. `SalonAddressEditScreen._validateLocality()` mirrors
//     `lib/features/master/presentation/location_edit_screen.dart`'s
//     `_validateLocation()` for exactly this: a city that HAS districts must
//     also have a district picked before Save proceeds, and a missing city
//     is refused outright (`l10n.errRequired` on the city row) rather than
//     ever reaching `saveAddress()`. `LocalityCascade`'s own
//     `districtRequired`/`districtError` pair (reserved "for the consuming
//     screen's validation" per its own doc) is wired here for that.
//
//     CORRECTION (2026-08-29) — an earlier revision of this file described
//     `saveAddress` as diffing cityId/districtId INDEPENDENTLY against the
//     loaded snapshot (`cityId != current.cityId ? cityId : null`) and named
//     Test 2 below as "EXPECTED TO FAIL until mobile-dev fixes the missing
//     district guard". Both are STALE: the district-required guard already
//     landed (Test 2 passes today — it is a live regression pin, not a
//     documented-but-broken one), and a SEPARATE, since-fixed bug
//     (Finding, 2026-08-29 — see `salon_management_profile_notifier.dart`'s
//     header doc) meant `saveAddress` used to diff `cityId` itself the same
//     way, which folded an UNCHANGED city selection to `null` and 400'd
//     "City is required" on every locality-untouched save. `saveAddress` now
//     sends `cityId` UNCONDITIONALLY (a `required String` parameter, never
//     diffed) — `districtId` stays nullable/diffed-by-omission-of-null since
//     a leaf city legitimately has none to send. See the 4th test below for
//     the real-wire pin of that fix.
//
// The widget tier's own fixture (`_city` in `salon_edit_forms_test.dart`) has
// `hasDistricts: false`, so it CANNOT reach this branch at all — this is the
// "fixture defangs the assertion" trap the QA brief flagged. This file adds
// the only `hasDistricts: true` city fixture in the whole fake-backend file
// (`city-with-districts`, `support/fake_backend.dart`) specifically to make
// the branch reachable.
//
// Test 2 below asserts the CORRECT contract (Save must be blocked — no wire
// call — mirroring `LocationEditScreen`'s guard); Test 3 is the contrasting
// POSITIVE pin — proving the dirty-diff itself is not fundamentally broken
// when both fields are genuinely touched together. Test 4 pins the
// 2026-08-29 cityId fix over the real wire: editing ONLY the street field,
// without ever re-touching the city row after picking it once, still
// carries cityId on the PATCH body.
//
// NO PATROL FLOW: nothing here touches an OS permission dialog, deep link,
// notification, WebView, or biometric.
//
// No UI entry point reaches any of the three routes yet (Phase 21.9's
// settings hub is unbuilt), so — exactly like
// `salon_management_profile_flow_test.dart` and
// `edit_profile_flow_test.dart`'s `professionalTitle` case — this flow drives
// the router directly via `router.go(...)` after a REAL login, and pins the
// RESOLVED SCREEN TYPE at each destination rather than trusting the location
// string alone (recorded project trap: a `router.go`/`context.push` mismatch
// or a shadowed route can leave the location string looking right while the
// wrong screen is mounted).
//
// Fixture: `salon-xyz`, the SAME salon `salon_management_profile_flow_test.dart`
// already exercises.

import 'dart:async';

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_address_edit_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_contacts_edit_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_profile_edit_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

const String _kSalonId = 'salon-xyz';

/// A `FakeBackend` seeded as SALON_OWNER, with `GET /salons/mine` carrying
/// [_kSalonId] itself (not the default `salon-owner-1` row).
///
/// mobile-qa fix (2026-08-28, discovered while authoring this file):
/// `salonManageGuard`'s "not resolved yet -> ADMIT" cold-deep-link fallback
/// (`app_router.dart`) is NOT actually reachable against a live app boot —
/// `AppHarness.loginAs`'s own `pumpAndSettle` already lets the SALON_OWNER
/// post-login landing (`SalonHomeResolverScreen`) resolve `mySalonsProvider`
/// (to redirect to the owner's primary salon shell) before a flow's own
/// `router.go(...)` ever runs. So a flow driving a `salonId` NOT in
/// `FakeBackend.mySalons` (the default seeds only `salon-owner-1`) is bounced
/// to `roleHomePath` by the "genuinely resolved, salon absent" branch, not
/// admitted by the fallback — this is a REAL SALON_OWNER's shape too (they
/// can only ever reach `/manage` for a salon `GET /salons/mine` actually
/// lists), so seeding it here is the correct fixture, not a workaround.
FakeBackend _salonOwnerBackend() => FakeBackend()
  ..currentRole = UserRole.salonOwner
  ..mySalons = <Map<String, dynamic>>[
    <String, dynamic>{
      'id': _kSalonId,
      'ownerId': 'user-owner-1',
      'name': 'Студія Краси «Камелія»',
      'city': 'Київ',
      'street': 'Хрещатик',
      'buildingNo': '12',
      'isActive': true,
      'isPrimary': true,
    },
  ];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'all three Phase 21.10 edit routes are reachable by a REAL SALON_OWNER '
    'session — salonManageGuard admits each and resolves the correct screen',
    (tester) async {
      final fb = _salonOwnerBackend();
      final GoRouter router = await AppHarness.boot(tester, fb);

      await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
      // fixed-wait-ok: settles the real async login/route-transition step.
      await tester.pumpAndSettle(const Duration(seconds: 1));

      router.go(RouteNames.salonProfileEdit(_kSalonId));
      // fixed-wait-ok: settles the real async route-push step.
      await tester.pumpAndSettle(const Duration(seconds: 1));
      AppHarness.expectLocation(
        router,
        '/salons/$_kSalonId/manage/settings/profile-edit',
      );
      expect(
        find.byType(SalonProfileEditScreen),
        findsOneWidget,
        reason:
            'salonManageGuard must ADMIT a real SALON_OWNER at the '
            'profile-edit route and resolve THIS screen type, not just a '
            'matching location string',
      );

      router.go(RouteNames.salonAddressEdit(_kSalonId));
      // fixed-wait-ok: settles the real async route-push step.
      await tester.pumpAndSettle(const Duration(seconds: 1));
      AppHarness.expectLocation(
        router,
        '/salons/$_kSalonId/manage/settings/address-edit',
      );
      expect(find.byType(SalonAddressEditScreen), findsOneWidget);

      router.go(RouteNames.salonContactsEdit(_kSalonId));
      // fixed-wait-ok: settles the real async route-push step.
      await tester.pumpAndSettle(const Duration(seconds: 1));
      AppHarness.expectLocation(
        router,
        '/salons/$_kSalonId/manage/settings/contacts-edit',
      );
      expect(find.byType(SalonContactsEditScreen), findsOneWidget);
    },
  );

  testWidgets('REGRESSION PIN — SalonAddressEditScreen: '
      'changing the city to one that REQUIRES a district without picking one '
      'must block Save, never reach the wire with an invalid locality pair', (
    tester,
  ) async {
    final fb = _salonOwnerBackend();
    final GoRouter router = await AppHarness.boot(tester, fb);

    await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
    // fixed-wait-ok: settles the real async login/route-transition step.
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // PUSH, not go: `_save()` calls `context.pop()` on success (it is
    // designed to be reached from the Phase 21.9 hub, which does not exist
    // yet). `router.go` REPLACES the whole stack, so a Save tap after a
    // bare `go` to the leaf throws "There is nothing to pop" — go to the
    // real `/manage` base first (same as `salon_management_profile_flow_
    // test.dart`) so the pushed leaf has something beneath it to return to.
    router.go(RouteNames.salonManage(_kSalonId));
    // fixed-wait-ok: settles the real async route-push step.
    await tester.pumpAndSettle(const Duration(seconds: 1));
    unawaited(router.push(RouteNames.salonAddressEdit(_kSalonId)));
    // fixed-wait-ok: settles the real async route-push step.
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.byType(SalonAddressEditScreen), findsOneWidget);

    // salon-xyz's real GET response carries a valid `cityId` (`city-kyiv`,
    // Finding 5) but NO `oblastId` — the PUBLIC `GET /salons/{salonId}`
    // path this screen loads through never carries one (see [Salon.
    // oblastId]'s doc), so `_prePopulateLocality` bails out before ever
    // reading `cityId` and the cascade opens fully unresolved regardless —
    // pick a fresh Oblast → City pair through the REAL picker sheets.
    await tester.tap(find.byKey(const Key('locality_row_oblast')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('locality_picker_tile_oblast-kyiv')),
    );
    await tester.pumpAndSettle();

    // Pick the ONLY seeded hasDistricts:true city — this is the fixture the
    // widget-tier suite cannot reach (its own city fixture is
    // hasDistricts:false, so it never exercises this branch at all).
    await tester.tap(find.byKey(const Key('locality_row_city')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey<String>('locality_picker_tile_city-with-districts'),
      ),
    );
    await tester.pumpAndSettle();

    // Deliberately do NOT touch the district row — this is the untouched
    // "unchanged-per-field" state the notifier's diff cannot tell apart
    // from "genuinely still null".
    expect(find.byKey(const Key('locality_row_district')), findsOneWidget);

    await tester.tap(find.byKey(const Key('save_salon_address')));
    await tester.pumpAndSettle();
    // fixed-wait-ok: gives a real async PATCH round-trip a chance to land
    // before the assertion below, so a false-negative "it never fired
    // anyway because pumpAndSettle didn't wait long enough" is ruled out.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    // ── THE CONTRACT ─────────────────────────────────────────────────
    // A city that requires a district, with no district picked, must
    // never reach the wire. `LocationEditScreen._validateLocation()`
    // enforces exactly this for masters; `SalonAddressEditScreen` must
    // enforce the same rule for salons — LocalityWriteValidator rejects
    // the mismatched pair server-side regardless, so a client-side gap
    // here means the viewer's Save silently no-ops behind an opaque
    // server error (or worse, a validator gap in some future backend
    // build would make it a persisted invalid locality).
    expect(
      fb.updateSalonCalls,
      0,
      reason:
          'a city with hasDistricts:true and NO district selected must be '
          'blocked client-side, exactly like LocationEditScreen — '
          'SalonAddressEditScreen wires LocalityCascade.districtRequired/'
          'districtError and _validateLocality() checks '
          '_selectedCity?.hasDistricts before calling saveAddress(), so '
          'this must never reach the wire with cityId=city-with-districts '
          'and districtId omitted (an invalid pair).',
    );
  });

  testWidgets(
    'SalonAddressEditScreen: picking a city AND its district together sends '
    'BOTH fields in the same real PATCH body (the dirty-diff pair, done '
    'correctly, survives the real wire)',
    (tester) async {
      final fb = _salonOwnerBackend();
      final GoRouter router = await AppHarness.boot(tester, fb);

      await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
      // fixed-wait-ok: settles the real async login/route-transition step.
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // PUSH, not go — see the previous test's identical comment: `_save()`
      // pops on success, so the leaf needs a real base beneath it.
      router.go(RouteNames.salonManage(_kSalonId));
      // fixed-wait-ok: settles the real async route-push step.
      await tester.pumpAndSettle(const Duration(seconds: 1));
      unawaited(router.push(RouteNames.salonAddressEdit(_kSalonId)));
      // fixed-wait-ok: settles the real async route-push step.
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.byType(SalonAddressEditScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('locality_row_oblast')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('locality_picker_tile_oblast-kyiv')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('locality_row_city')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey<String>('locality_picker_tile_city-with-districts'),
        ),
      );
      await tester.pumpAndSettle();

      // This time DO pick the district — the valid, complete pair.
      await tester.tap(find.byKey(const Key('locality_row_district')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey<String>('locality_picker_tile_district-podil'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('save_salon_address')));
      await tester.pumpAndSettle();
      // fixed-wait-ok: settles the real async PATCH round-trip + the
      // notifier's state-merge/pop sequence before the next assertion.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(
        fb.updateSalonCalls,
        1,
        reason: 'a COMPLETE valid locality pair must reach the wire',
      );
      final Map<String, dynamic> body = fb.lastUpdateSalonBody!;
      expect(
        body['cityId'],
        'city-with-districts',
        reason: 'the picked city must reach the real PATCH body',
      );
      expect(
        body['districtId'],
        'district-podil',
        reason:
            'the picked district must reach the real PATCH body ALONGSIDE '
            'the city — proving the dirty-diff itself sends a genuinely '
            'touched pair together, not that saveAddress is broken '
            'wholesale (only the missing client-side required-ness guard '
            'is, per the previous test).',
      );

      // Success pops back — no in-app entry point exists yet, so the pop
      // lands wherever go_router's stack resolves once the standalone route
      // is popped (the browser-back-equivalent one level up).
      expect(find.byType(SalonAddressEditScreen), findsNothing);
    },
  );

  testWidgets('REGRESSION PIN — editing ONLY the street field, without ever '
      're-touching the city row after picking it once, still carries cityId '
      'on the real PATCH body', (tester) async {
    // WHY THIS TEST, AND WHY IT PICKS THE CITY FIRST RATHER THAN RELYING
    // ON PRE-POPULATION: `salon-xyz`'s PUBLIC salon-detail envelope
    // (`_publicSalonDetailEnvelope`, `support/fake_backend.dart`) carries
    // a real `cityId` ('city-kyiv') but deliberately NO `oblastId`
    // (Finding 5, 2026-08-28 — a separate, older fixture decision that
    // predates backend `dbe27a5`'s oblastId-on-the-public-path fix and is
    // reused by other flows that assume an unresolved cascade for this
    // salon). `_prePopulateLocality` needs `oblastId` to resolve the
    // cascade, so it bails out and the screen opens with NO city visibly
    // selected regardless of the real `cityId` on file — meaning the
    // exact shipped-bug shape ("GET already resolved a city, viewer edits
    // only street") is not reachable through THIS fixture without editing
    // the shared envelope (used by several other flows that depend on its
    // unresolved-cascade shape — out of this fix's scope).
    //
    // This test instead picks the city ONCE via the real picker sheets
    // (unavoidable given the fixture), then edits ONLY the street field —
    // never re-opening the city/oblast rows again — and confirms the real
    // wire body still carries `cityId`. This exercises the exact notifier
    // code path the shipped bug broke (`saveAddress`'s unconditional,
    // never-diffed `cityId` parameter) through the REAL OpenAPI JSON
    // serializer and the real `FakeBackend` PATCH handler, which the
    // widget tier (a hand-rolled `FakeSalonRepository` that never
    // serializes anything) cannot exercise.
    final fb = _salonOwnerBackend();
    final GoRouter router = await AppHarness.boot(tester, fb);

    await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
    // fixed-wait-ok: settles the real async login/route-transition step.
    await tester.pumpAndSettle(const Duration(seconds: 1));

    router.go(RouteNames.salonManage(_kSalonId));
    // fixed-wait-ok: settles the real async route-push step.
    await tester.pumpAndSettle(const Duration(seconds: 1));
    unawaited(router.push(RouteNames.salonAddressEdit(_kSalonId)));
    // fixed-wait-ok: settles the real async route-push step.
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.byType(SalonAddressEditScreen), findsOneWidget);

    // Pick Oblast → City ONCE (leaf city, no district row to worry about).
    await tester.tap(find.byKey(const Key('locality_row_oblast')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('locality_picker_tile_oblast-kyiv')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('locality_row_city')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('locality_picker_tile_city-kyiv')),
    );
    await tester.pumpAndSettle();

    // From here on, ONLY the street field is touched — the city row is
    // never opened again, mirroring a viewer who edits an unrelated field
    // on a salon whose locality was already set.
    await tester.enterText(
      find.byKey(const Key('salon_street')),
      'вул. Хрещатик, 22',
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('save_salon_address')));
    await tester.pumpAndSettle();
    // fixed-wait-ok: gives a real async PATCH round-trip a chance to land
    // before the assertion below.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(
      fb.updateSalonCalls,
      1,
      reason: 'a street-only edit must still reach the wire',
    );
    final Map<String, dynamic> body = fb.lastUpdateSalonBody!;
    expect(
      body['street'],
      'вул. Хрещатик, 22',
      reason: 'the edited field must be present',
    );
    expect(
      body['cityId'],
      isNotNull,
      reason:
          'THE REGRESSION: a street-only edit must still carry cityId on '
          'the real wire body. Before the 2026-08-29 fix, saveAddress '
          'diffed cityId against the loaded snapshot and folded an '
          'unchanged selection to null, which the real backend '
          '(LocalityWriteValidator) 400s with "City is required" — this '
          'is the exact failure mode the shipped bug produced, now '
          'confirmed absent over a real JSON-serialized PATCH body.',
    );
    expect(body['cityId'], 'city-kyiv');
  });
}

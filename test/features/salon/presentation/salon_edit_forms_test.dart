// Phase 21.10 — Widget tests for the three salon edit-form screens
// (SalonProfileEditScreen / SalonAddressEditScreen / SalonContactsEditScreen).
//
// Each group covers:
//   1. Pre-population — fields seed from the loaded Salon.
//   2. Save sends the correct dirty-field payload through the (mocked)
//      repository — untouched sibling fields are OMITTED.
//   3. Success pops back to the previous route and shows a VelvetSnack.
//   4. A repository failure shows an error VelvetSnack WITHOUT popping.
//
// Strategy mirrors `salon_management_profile_screen_test.dart`: a real
// GoRouter (via `pumpRoutedApp`) with `salonRepositoryProvider` overridden by
// the shared `FakeSalonRepository` fake. Each edit screen is reached via
// `router.push(...)` directly (no in-app entry point exists yet — Phase 21.9,
// the settings hub, is what will wire a row to each route).

import 'dart:async';

import 'package:beautica_api/beautica_api.dart' show UpdateSalonRequest;
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/location/domain/city.dart';
import 'package:beautica_mobile/features/location/domain/city_district.dart';
import 'package:beautica_mobile/features/location/domain/oblast.dart';
import 'package:beautica_mobile/features/location/presentation/widgets/locality_tap_row.dart';
import 'package:beautica_mobile/features/location/state/location_providers.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_address_edit_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_contacts_edit_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_profile_edit_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes/fake_salon_repository.dart';
import '../../../helpers/pump_app.dart';
import '../../../helpers/velvet_snack_matchers.dart';

const String _kSalonId = 'salon-1';

const _stubOwner = User(
  id: 'owner-1',
  email: 'owner@beautica.ua',
  role: UserRole.salonOwner,
  firstName: 'Оксана',
  lastName: 'Швець',
);

const _stubSalon = Salon(
  id: _kSalonId,
  name: 'Салон «Вельвет»',
  description: 'Затишний салон краси в серці Печерська.',
  cityId: 'city-01',
  // Finding 3 (2026-08-28) — pre-population now reads [Salon.oblastId]
  // directly (targeted lookup) instead of scanning every oblast's city list.
  oblastId: 'oblast-01',
  street: 'вул. Велика Васильківська',
  buildingNo: '44',
  locationNote: '2 поверх',
  phone: '+380501234567',
  instagramUrl: 'velvet_salon',
  avgRating: 4.9,
  reviewCount: 128,
);

// mobile-qa Priority 2 (2026-08-28) — a salon with NO city set at all. The
// SAME shape `SalonMapper.fromDto` produces before a salon has ever been
// located, and (before the `oblastId` mapping fix) the shape it wrongly
// produced for EVERY salon regardless of whether it had a real city.
// `_prePopulateLocality` must return early on this without touching any
// locality provider — see `no fan-out` test below.
const _stubSalonNoCity = Salon(
  id: _kSalonId,
  name: 'Салон «Вельвет»',
  description: 'Затишний салон краси в серці Печерська.',
  cityId: null,
  oblastId: null,
  street: 'вул. Велика Васильківська',
  buildingNo: '44',
  locationNote: '2 поверх',
  phone: '+380501234567',
  instagramUrl: 'velvet_salon',
  avgRating: 4.9,
  reviewCount: 128,
);

const _oblast = Oblast(id: 'oblast-01', name: 'Київська', katotthCode: 'UA1');
const _city = City(
  id: 'city-01',
  oblastId: 'oblast-01',
  name: 'Київ',
  katotthCode: 'UA1-1',
  hasDistricts: false,
);

// Finding 4 (2026-08-28) — the ONLY hasDistricts:true city fixture in this
// suite. Without it the widget tier can never reach the Finding 1
// district-required guard (`_city` above is hasDistricts:false) — this is
// the exact "fixture defangs the assertion" trap the audit flagged. Distinct
// name/katotthCode from `_city` so a wrong id-vs-name mapping would surface
// as a visibly wrong rendered value, not a coincidental pass.
const _cityWithDistricts = City(
  id: 'city-02-districts',
  oblastId: 'oblast-01',
  name: 'Дніпро',
  katotthCode: 'UA1-2',
  hasDistricts: true,
);
const _district = CityDistrict(
  id: 'district-01',
  cityId: 'city-02-districts',
  name: 'Соборний',
  katotthCode: 'UA1-2-1',
);

class _StubAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async =>
      const AuthSession.authenticated(user: _stubOwner, accessToken: 'tok');
}

GoRouter _router() => GoRouter(
  initialLocation: RouteNames.salonManage(_kSalonId),
  routes: <RouteBase>[
    GoRoute(
      path: '/salons/:salonId/manage',
      builder: (context, state) => const Scaffold(key: Key('manage-marker')),
    ),
    GoRoute(
      path: '/salons/:salonId/manage/settings/profile-edit',
      builder: (context, state) =>
          SalonProfileEditScreen(salonId: state.pathParameters['salonId']!),
    ),
    GoRoute(
      path: '/salons/:salonId/manage/settings/address-edit',
      builder: (context, state) =>
          SalonAddressEditScreen(salonId: state.pathParameters['salonId']!),
    ),
    GoRoute(
      path: '/salons/:salonId/manage/settings/contacts-edit',
      builder: (context, state) =>
          SalonContactsEditScreen(salonId: state.pathParameters['salonId']!),
    ),
  ],
);

List<Object> _overrides(FakeSalonRepository repo) => <Object>[
  authProvider.overrideWith(_StubAuthNotifier.new),
  salonRepositoryProvider.overrideWithValue(repo),
  oblastListProvider.overrideWith((ref) async => const <Oblast>[_oblast]),
  cityListProvider(
    'oblast-01',
  ).overrideWith((ref) async => const <City>[_city, _cityWithDistricts]),
  districtListProvider(
    _cityWithDistricts.id,
  ).overrideWith((ref) async => const <CityDistrict>[_district]),
];

void main() {
  group('SalonProfileEditScreen', () {
    testWidgets(
      'pre-populates name/description and Save sends only the dirty field',
      (tester) async {
        final repo = FakeSalonRepository(salon: _stubSalon);
        final router = _router();
        await tester.pumpRoutedApp(router, overrides: _overrides(repo));
        await tester.pumpAndSettle();

        unawaited(router.push(RouteNames.salonProfileEdit(_kSalonId)));
        await tester.pumpAndSettle();

        expect(
          tester
              .widget<TextField>(find.byKey(const Key('salon_name')))
              .controller!
              .text,
          _stubSalon.name,
        );
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('salon_description')))
              .controller!
              .text,
          _stubSalon.description,
        );

        await tester.enterText(
          find.byKey(const Key('salon_name')),
          'Нова назва салону',
        );
        await tester.pump();

        await tester.tap(find.byKey(const Key('save_salon_profile')));
        await tester.pump();
        await pumpVelvetSnackIn(tester);

        expect(repo.updateRequests, hasLength(1));
        final UpdateSalonRequest sent = repo.updateRequests.single;
        expect(sent.name, 'Нова назва салону');
        // Untouched fields are OMITTED, not re-sent verbatim.
        expect(sent.description, isNull);
        expect(sent.phone, isNull);
        expect(sent.instagramUrl, isNull);
        // Backend-required on every PATCH — always threaded through.
        expect(sent.street, _stubSalon.street);
        expect(sent.buildingNo, _stubSalon.buildingNo);

        // Success pops back to the marker screen.
        expect(find.byKey(const Key('manage-marker')), findsOneWidget);
        await pumpPastVelvetSnack(tester);
      },
    );

    testWidgets('a repository failure shows an error snack without popping', (
      tester,
    ) async {
      final repo = FakeSalonRepository(salon: _stubSalon)
        ..updateError = const ServerFailure(statusCode: 500);
      final router = _router();
      await tester.pumpRoutedApp(router, overrides: _overrides(repo));
      await tester.pumpAndSettle();

      unawaited(router.push(RouteNames.salonProfileEdit(_kSalonId)));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('salon_name')),
        'Ще одна назва',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('save_salon_profile')));
      await tester.pump();
      await pumpVelvetSnackIn(tester);

      // Still on the edit screen — the pop never happened.
      expect(find.byKey(const Key('salon_name')), findsOneWidget);
      expect(find.byKey(const Key('manage-marker')), findsNothing);
      await pumpPastVelvetSnack(tester);
    });
  });

  group('SalonContactsEditScreen', () {
    testWidgets('pre-populates phone/instagram and Save sends only dirty '
        'fields', (tester) async {
      final repo = FakeSalonRepository(salon: _stubSalon);
      final router = _router();
      await tester.pumpRoutedApp(router, overrides: _overrides(repo));
      await tester.pumpAndSettle();

      unawaited(router.push(RouteNames.salonContactsEdit(_kSalonId)));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextField>(find.byKey(const Key('salon_instagram')))
            .controller!
            .text,
        _stubSalon.instagramUrl,
      );

      await tester.enterText(
        find.byKey(const Key('salon_instagram')),
        'new_handle',
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('save_salon_contacts')));
      await tester.pump();
      await pumpVelvetSnackIn(tester);

      expect(repo.updateRequests, hasLength(1));
      final UpdateSalonRequest sent = repo.updateRequests.single;
      expect(sent.instagramUrl, 'new_handle');
      // Phone was pre-populated but not re-typed by the test — the mask
      // formatter reformats the seeded value, so it may still differ from
      // the raw seed text; either way name/description stay omitted.
      expect(sent.name, isNull);
      expect(sent.description, isNull);
      expect(sent.street, _stubSalon.street);
      expect(sent.buildingNo, _stubSalon.buildingNo);

      expect(find.byKey(const Key('manage-marker')), findsOneWidget);
      await pumpPastVelvetSnack(tester);
    });

    testWidgets('a blank phone blocks Save and shows an inline error', (
      tester,
    ) async {
      final repo = FakeSalonRepository(salon: _stubSalon);
      final router = _router();
      await tester.pumpRoutedApp(router, overrides: _overrides(repo));
      await tester.pumpAndSettle();

      unawaited(router.push(RouteNames.salonContactsEdit(_kSalonId)));
      await tester.pumpAndSettle();

      // Clear the (pre-populated) phone field — required, must block Save.
      // The real GET path always seeds this field blank (Phase 21.2 gap —
      // see `Salon.phone`'s doc); the fake repository echoes the fixture's
      // phone verbatim instead, so the field must be cleared explicitly here
      // to exercise the same empty-phone guard.
      await tester.enterText(find.byKey(const Key('salon_phone')), '');
      await tester.pump();
      await tester.tap(find.byKey(const Key('save_salon_contacts')));
      await tester.pumpAndSettle();

      expect(repo.updateRequests, isEmpty);
      expect(find.byKey(const Key('manage-marker')), findsNothing);
    });
  });

  group('SalonAddressEditScreen', () {
    testWidgets(
      'pre-populates street/building/note and resolves the locality cascade',
      (tester) async {
        final repo = FakeSalonRepository(salon: _stubSalon);
        final router = _router();
        await tester.pumpRoutedApp(router, overrides: _overrides(repo));
        await tester.pumpAndSettle();

        unawaited(router.push(RouteNames.salonAddressEdit(_kSalonId)));
        await tester.pumpAndSettle();

        expect(
          tester
              .widget<TextField>(find.byKey(const Key('salon_street')))
              .controller!
              .text,
          _stubSalon.street,
        );
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('salon_building')))
              .controller!
              .text,
          _stubSalon.buildingNo,
        );
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('salon_location_note')))
              .controller!
              .text,
          _stubSalon.locationNote,
        );
        // The cascade resolved the city from `salon.oblastId`/`salon.cityId`
        // via the targeted lookup chain (Finding 3 — see the screen's own
        // `_prePopulateLocality` doc).
        expect(find.text(_city.name), findsOneWidget);
        expect(find.text(_oblast.name), findsOneWidget);
      },
    );

    testWidgets('Save sends the edited street and omits unchanged locality', (
      tester,
    ) async {
      final repo = FakeSalonRepository(salon: _stubSalon);
      final router = _router();
      await tester.pumpRoutedApp(router, overrides: _overrides(repo));
      await tester.pumpAndSettle();

      unawaited(router.push(RouteNames.salonAddressEdit(_kSalonId)));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('salon_street')),
        'вул. Хрещатик',
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('save_salon_address')));
      await tester.pump();
      await pumpVelvetSnackIn(tester);

      expect(repo.updateRequests, hasLength(1));
      final UpdateSalonRequest sent = repo.updateRequests.single;
      expect(sent.street, 'вул. Хрещатик');
      // buildingNo is unchanged but backend-required — always sent.
      expect(sent.buildingNo, _stubSalon.buildingNo);
      // cityId resolved to the SAME salon.cityId — omitted as unchanged.
      expect(sent.cityId, isNull);

      expect(find.byKey(const Key('manage-marker')), findsOneWidget);
      await pumpPastVelvetSnack(tester);
    });

    testWidgets('a repository failure shows an error snack without popping', (
      tester,
    ) async {
      final repo = FakeSalonRepository(salon: _stubSalon)
        ..updateError = const NetworkFailure();
      final router = _router();
      await tester.pumpRoutedApp(router, overrides: _overrides(repo));
      await tester.pumpAndSettle();

      unawaited(router.push(RouteNames.salonAddressEdit(_kSalonId)));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('salon_street')),
        'вул. Хрещатик',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('save_salon_address')));
      await tester.pump();
      await pumpVelvetSnackIn(tester);

      expect(find.byKey(const Key('salon_street')), findsOneWidget);
      expect(find.byKey(const Key('manage-marker')), findsNothing);
      await pumpPastVelvetSnack(tester);
    });

    // Finding 4 (2026-08-28) — widget-tier coverage of the Finding 1
    // district-required guard, using the new `_cityWithDistricts` fixture
    // (`_city` above is hasDistricts:false and can never reach this branch).
    testWidgets(
      'picking a district-requiring city with NO district selected blocks '
      'Save and shows an inline error on the district row',
      (tester) async {
        final repo = FakeSalonRepository(salon: _stubSalon);
        final router = _router();
        await tester.pumpRoutedApp(router, overrides: _overrides(repo));
        await tester.pumpAndSettle();

        unawaited(router.push(RouteNames.salonAddressEdit(_kSalonId)));
        await tester.pumpAndSettle();

        // Switch the pre-populated city (city-01, no districts) to the
        // district-requiring fixture.
        await tester.tap(find.byKey(const Key('locality_row_city')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            ValueKey<String>('locality_picker_tile_${_cityWithDistricts.id}'),
          ),
        );
        await tester.pumpAndSettle();

        // Deliberately do NOT pick a district.
        await tester.tap(find.byKey(const Key('save_salon_address')));
        await tester.pumpAndSettle();

        expect(
          repo.updateRequests,
          isEmpty,
          reason:
              'a district-requiring city with no district picked must never '
              'reach saveAddress() — mirrors LocationEditScreen\'s guard.',
        );
        expect(find.byKey(const Key('manage-marker')), findsNothing);
        final LocalityTapRow districtRow = tester.widget<LocalityTapRow>(
          find.byKey(const Key('locality_row_district')),
        );
        expect(
          districtRow.errorText,
          isNotNull,
          reason: 'the district row must show an inline required-field error.',
        );
      },
    );

    testWidgets(
      'picking a district-requiring city AND its district allows Save to '
      'proceed with both fields set',
      (tester) async {
        final repo = FakeSalonRepository(salon: _stubSalon);
        final router = _router();
        await tester.pumpRoutedApp(router, overrides: _overrides(repo));
        await tester.pumpAndSettle();

        unawaited(router.push(RouteNames.salonAddressEdit(_kSalonId)));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('locality_row_city')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            ValueKey<String>('locality_picker_tile_${_cityWithDistricts.id}'),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('locality_row_district')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(ValueKey<String>('locality_picker_tile_${_district.id}')),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('save_salon_address')));
        await tester.pump();
        await pumpVelvetSnackIn(tester);

        expect(repo.updateRequests, hasLength(1));
        final UpdateSalonRequest sent = repo.updateRequests.single;
        expect(sent.cityId, _cityWithDistricts.id);
        expect(sent.districtId, _district.id);

        expect(find.byKey(const Key('manage-marker')), findsOneWidget);
        await pumpPastVelvetSnack(tester);
      },
    );

    // mobile-qa Priority 2 (2026-08-28) — regression guard for the shipped-
    // broken cascade: `SalonMapper.fromDto` hardcoded `oblastId` to `null`
    // (fixed in this changeset), so the cascade pre-populated with nothing
    // for EVERY salon, city set or not. The positive case above (a salon
    // WITH oblastId/cityId) already covers the fix; this covers the OTHER
    // half `_prePopulateLocality` must get right — a salon that genuinely
    // has no city must leave the cascade empty and must NOT fan out to the
    // locality providers at all (its early-return guard,
    // `salon_address_edit_screen.dart`'s own doc names the deleted
    // alternative: scanning every oblast's city list to find a match).
    testWidgets(
      'a salon with no city leaves the cascade empty and fires no locality '
      'lookups at all',
      (tester) async {
        int oblastListCalls = 0;
        final repo = FakeSalonRepository(salon: _stubSalonNoCity);
        final router = _router();
        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[
            authProvider.overrideWith(_StubAuthNotifier.new),
            salonRepositoryProvider.overrideWithValue(repo),
            oblastListProvider.overrideWith((ref) async {
              oblastListCalls++;
              return const <Oblast>[_oblast];
            }),
            cityListProvider('oblast-01').overrideWith(
              (ref) async => const <City>[_city, _cityWithDistricts],
            ),
            districtListProvider(
              _cityWithDistricts.id,
            ).overrideWith((ref) async => const <CityDistrict>[_district]),
          ],
        );
        await tester.pumpAndSettle();

        unawaited(router.push(RouteNames.salonAddressEdit(_kSalonId)));
        await tester.pumpAndSettle();

        // Street/building/note still pre-populate regardless — only the
        // cascade is affected by a missing city.
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('salon_street')))
              .controller!
              .text,
          _stubSalonNoCity.street,
        );

        final LocalityTapRow oblastRow = tester.widget<LocalityTapRow>(
          find.byKey(const Key('locality_row_oblast')),
        );
        final LocalityTapRow cityRow = tester.widget<LocalityTapRow>(
          find.byKey(const Key('locality_row_city')),
        );
        expect(
          oblastRow.value,
          isNull,
          reason: 'no city on the salon -> oblast row stays unselected.',
        );
        expect(
          cityRow.value,
          isNull,
          reason: 'no city on the salon -> city row stays unselected.',
        );
        expect(
          oblastListCalls,
          0,
          reason:
              '_prePopulateLocality must early-return on a null cityId — no '
              'fan-out lookup across oblasts. A reintroduced scan-every-'
              'oblast resolver (the pattern this field replaced) would fire '
              'this at least once.',
        );
      },
    );
  });
}

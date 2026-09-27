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
import 'package:beautica_mobile/features/location/data/location_repository.dart';
import 'package:beautica_mobile/features/location/domain/city.dart';
import 'package:beautica_mobile/features/location/domain/city_district.dart';
import 'package:beautica_mobile/features/location/domain/oblast.dart';
import 'package:beautica_mobile/features/location/domain/settlement.dart';
import 'package:beautica_mobile/features/location/presentation/widgets/settlement_locality_field.dart';
import 'package:beautica_mobile/features/location/presentation/widgets/settlement_select_field.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_address_edit_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_contacts_edit_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_profile_edit_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
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

// Phase 346 — [Salon.oblastId]/the oblast->city cascade pre-population this
// fixture used to exercise are GONE. [_settlementId] below is now the whole
// story for locality pre-population; `city` is the denormalised NAME
// (`SalonResponse.city`) the screen seeds the closed settlement field with
// directly (phase-346 D7) — see the "shows that name... WITHOUT any
// settlement request" test.
const _stubSalon = Salon(
  id: _kSalonId,
  name: 'Салон «Вельвет»',
  description: 'Затишний салон краси в серці Печерська.',
  cityId: 'city-01',
  city: 'Київ',
  street: 'вул. Велика Васильківська',
  buildingNo: '44',
  locationNote: '2 поверх',
  phone: '+380501234567',
  instagramUrl: 'velvet_salon',
  avgRating: 4.9,
  reviewCount: 128,
);

// mobile-qa Priority 2 (2026-08-28, updated for phase 346) — a salon with NO
// city set at all. `_settlementId` seeds from `salon.cityId.isEmpty ? null :
// salon.cityId`, so omitting `cityId` here reproduces the exact same "unset"
// shape a real backend read cannot produce any more but a fixture still can.
// `_initControllers` must leave `_settlementId` null on this without touching
// the location repository at all — see the `no fan-out` test below.
//
// [Salon.cityId]/[Salon.oblastId] are `String` with `@Default('')` (the
// backend now guarantees every REAL salon has a city); simply omitting the
// field below is the direct equivalent of the old `cityId: null`.
const _stubSalonNoCity = Salon(
  id: _kSalonId,
  name: 'Салон «Вельвет»',
  description: 'Затишний салон краси в серці Печерська.',
  street: 'вул. Велика Васильківська',
  buildingNo: '44',
  locationNote: '2 поверх',
  phone: '+380501234567',
  instagramUrl: 'velvet_salon',
  avgRating: 4.9,
  reviewCount: 128,
);

// Phase 346 — settlement fixtures replace the retired Oblast/City ones.
// `_settlementCity` is the leaf settlement `_stubSalon.cityId` resolves to —
// it deliberately has NO entry in `_FakeLocationRepository`'s district map,
// so `districtsOf` reads back empty and the «Район» row must not render at
// all (rule 1 — the district row is now CONDITIONAL, not a disabled
// placeholder).
const _settlementCity = Settlement(
  id: 'city-01',
  name: 'Київ',
  oblastName: 'Київська',
);

// The ONLY settlement fixture with districts in this suite. Without it the
// widget tier can never reach the district-required guard (`_settlementCity`
// above has none) — the exact "fixture defangs the assertion" trap a prior
// audit flagged. Distinct name from `_settlementCity` so a wrong id-vs-name
// mapping would surface as a visibly wrong rendered value, not a
// coincidental pass.
const _settlementWithDistricts = Settlement(
  id: 'city-02-districts',
  name: 'Дніпро',
  oblastName: 'Дніпропетровська',
);
const _district = CityDistrict(
  id: 'district-01',
  cityId: 'city-02-districts',
  name: 'Соборний',
  katotthCode: 'UA1-2-1',
);

/// Fake [LocationRepository] backing both the settlement autocomplete and the
/// district row. Records every query/id it is asked for so a test can assert
/// a call COUNT rather than merely rendering — see the "no city -> no
/// fan-out" and "D7" tests below.
class _FakeLocationRepository implements LocationRepository {
  static const List<Settlement> _settlements = <Settlement>[
    _settlementCity,
    _settlementWithDistricts,
  ];
  static const Map<String, List<CityDistrict>> _districtsBySettlement =
      <String, List<CityDistrict>>{
        'city-02-districts': <CityDistrict>[_district],
      };

  /// Every `query` [searchSettlements] was called with, in order.
  final List<String> searchQueries = <String>[];

  /// Every `cityId` [fetchDistricts] was called with, in order.
  final List<String> districtQueries = <String>[];

  /// When non-null, [fetchDistricts] holds on this before answering — keeps a
  /// district lookup IN FLIGHT so a test can submit against it.
  Completer<void>? districtsGate;

  @override
  Future<List<Settlement>> searchSettlements(
    String query, {
    CancelToken? cancelToken,
  }) async {
    searchQueries.add(query);
    if (query.isEmpty) return _settlements;
    final String needle = query.toLowerCase();
    return _settlements
        .where((Settlement s) => s.name.toLowerCase().contains(needle))
        .toList();
  }

  @override
  Future<List<CityDistrict>> fetchDistricts(String cityId) async {
    districtQueries.add(cityId);
    final Completer<void>? gate = districtsGate;
    if (gate != null) await gate.future;
    return _districtsBySettlement[cityId] ?? const <CityDistrict>[];
  }

  @override
  Future<List<Oblast>> fetchOblasts() => throw UnimplementedError();

  @override
  Future<List<City>> fetchCities(String oblastId) => throw UnimplementedError();
}

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

List<Object> _overrides(
  FakeSalonRepository repo, [
  _FakeLocationRepository? location,
]) => <Object>[
  authProvider.overrideWith(_StubAuthNotifier.new),
  salonRepositoryProvider.overrideWithValue(repo),
  locationRepositoryProvider.overrideWithValue(
    location ?? _FakeLocationRepository(),
  ),
];

/// Drives [SettlementSelectField]: opens the sheet, types [query] (letting the
/// LOAD-BEARING debounce elapse — `pumpAndSettle` fires no `Timer`, so
/// skipping this pump would measure the pre-keystroke blank-query list), then
/// taps the row for [settlementId].
Future<void> _pickSettlement(
  WidgetTester tester, {
  required String query,
  required String settlementId,
}) async {
  await tester.tap(find.byKey(const Key('settlement_select_field')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('select-menu-search')), query);
  await tester.pump(kSettlementSearchDebounce);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('settlement_option_$settlementId')));
  await tester.pumpAndSettle();
}

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
        // Finding (2026-08-29) — cityId/districtId ride along UNCONDITIONALLY
        // too, even though this screen never edits locality; omitting them
        // is what made every «Про салон» save 400 with "City is required".
        expect(sent.cityId, _stubSalon.cityId);

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
      // Finding (2026-08-29) — same unconditional locality echo as the
      // profile-edit screen above.
      expect(sent.cityId, _stubSalon.cityId);

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
    // Phase-330 — the settlement field is seeded with the picker label
    // , never the bare
    // denormalised `salon.city`.
    testWidgets('a typed saved settlement seeds the PICKER label', (
      tester,
    ) async {
      final AppLocalizations uk = lookupAppLocalizations(const Locale('uk'));
      final repo = FakeSalonRepository(
        salon: _stubSalon.copyWith(
          city: 'Бориспіль',
          region: 'Київська',
          citySettlementType: 'CITY',
        ),
      );
      final router = _router();
      await tester.pumpRoutedApp(router, overrides: _overrides(repo));
      await tester.pumpAndSettle();

      unawaited(router.push(RouteNames.salonAddressEdit(_kSalonId)));
      await tester.pumpAndSettle();
      expect(
        find.text(
          '${uk.settlementCityPrefix} Бориспіль, Київська ${uk.settlementOblastAbbrev}',
        ),
        findsOneWidget,
      );
      // i18n-finder-ok: settlement NAME is reference data, identical in every locale.
      expect(find.text('Бориспіль'), findsNothing);
    });

    testWidgets(
      'pre-populates street/building/note and shows the settlement field '
      'with no oblast control anywhere',
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
        // Phase 346 — there is no «Область» row any more; the ONE settlement
        // autocomplete carries the denormalised `salon.city` name.
        expect(
          find.byKey(const Key('settlement_select_field')),
          findsOneWidget,
        );
        expect(find.text(_stubSalon.city!), findsOneWidget);
        expect(find.byKey(const Key('locality_row_oblast')), findsNothing);
        expect(find.byKey(const Key('locality_row_city')), findsNothing);
        // `city-01` (`_settlementCity`) has no districts — the row must be
        // ABSENT, not a disabled placeholder (rule 1: it used to render
        // disabled with a helper caption; now it renders nothing at all).
        expect(find.byKey(const Key('locality_row_district')), findsNothing);
      },
    );

    testWidgets('N1 — a double tap on Save while the district lookup is still '
        'in flight saves ONCE', (tester) async {
      final repo = FakeSalonRepository(salon: _stubSalon);
      final location = _FakeLocationRepository()
        ..districtsGate = Completer<void>();
      final router = _router();
      await tester.pumpRoutedApp(router, overrides: _overrides(repo, location));
      await tester.pumpAndSettle();

      unawaited(router.push(RouteNames.salonAddressEdit(_kSalonId)));
      await tester.pumpAndSettle();
      expect(location.districtQueries, isNotEmpty, reason: 'lookup in flight');

      await tester.enterText(
        find.byKey(const Key('salon_street')),
        'вул. Хрещатик',
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('save_salon_address')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('save_salon_address')));
      await tester.pump();

      location.districtsGate!.complete();
      await tester.pump();
      await pumpVelvetSnackIn(tester);

      expect(repo.updateRequests, hasLength(1));
      await pumpPastVelvetSnack(tester);
    });

    testWidgets('Save sends the edited street and the echoed locality', (
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
      // Finding (2026-08-29) — cityId is now sent UNCONDITIONALLY (the
      // screen owns locality and always echoes its resolved selection; see
      // `SalonManagementProfile.saveAddress`'s doc). The prior assertion
      // here (`isNull`, "omitted as unchanged") was pinning the very bug
      // that made every `PATCH /salons/{id}` 400 with `City is required`
      // whenever the city dropdown itself wasn't touched.
      expect(sent.cityId, _stubSalon.cityId);

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

    // Phase 346 — widget-tier coverage of the district-required guard, using
    // `_settlementWithDistricts` (`_settlementCity` above has none and can
    // never reach this branch — the "fixture defangs the assertion" trap).
    testWidgets(
      'picking a district-requiring settlement with NO district selected '
      'blocks Save and shows an inline error on the district row',
      (tester) async {
        final repo = FakeSalonRepository(salon: _stubSalon);
        final router = _router();
        await tester.pumpRoutedApp(router, overrides: _overrides(repo));
        await tester.pumpAndSettle();

        unawaited(router.push(RouteNames.salonAddressEdit(_kSalonId)));
        await tester.pumpAndSettle();

        // Switch the pre-populated settlement (city-01, no districts) to the
        // district-requiring fixture.
        await _pickSettlement(
          tester,
          query: 'дніп',
          settlementId: _settlementWithDistricts.id,
        );

        // Deliberately do NOT pick a district.
        await tester.tap(find.byKey(const Key('save_salon_address')));
        await tester.pumpAndSettle();

        expect(
          repo.updateRequests,
          isEmpty,
          reason:
              'a district-requiring settlement with no district picked must '
              'never reach saveAddress() — mirrors LocationEditScreen\'s '
              'guard.',
        );
        expect(find.byKey(const Key('manage-marker')), findsNothing);
        expect(find.byKey(const Key('locality_row_district')), findsOneWidget);
        final SettlementLocalityField field = tester
            .widget<SettlementLocalityField>(
              find.byType(SettlementLocalityField),
            );
        expect(
          field.districtError,
          isNotNull,
          reason: 'the district row must show an inline required-field error.',
        );
      },
    );

    testWidgets(
      'picking a district-requiring settlement AND its district allows Save '
      'to proceed with both fields set',
      (tester) async {
        final repo = FakeSalonRepository(salon: _stubSalon);
        final router = _router();
        await tester.pumpRoutedApp(router, overrides: _overrides(repo));
        await tester.pumpAndSettle();

        unawaited(router.push(RouteNames.salonAddressEdit(_kSalonId)));
        await tester.pumpAndSettle();

        await _pickSettlement(
          tester,
          query: 'дніп',
          settlementId: _settlementWithDistricts.id,
        );

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
        expect(sent.cityId, _settlementWithDistricts.id);
        expect(sent.districtId, _district.id);

        expect(find.byKey(const Key('manage-marker')), findsOneWidget);
        await pumpPastVelvetSnack(tester);
      },
    );

    // mobile-qa Priority 2 (rewritten for phase 346) — a salon that genuinely
    // has no city must leave the settlement field unselected and must NOT
    // fan out to the location repository at all before the user touches it:
    // no settlement search (the field never preloads a query) and no
    // district read (`districtsOf` short-circuits on a null settlement id
    // before it ever watches `districtListProvider`).
    testWidgets(
      'a salon with no city leaves the settlement field empty and fires no '
      'locality lookups at all',
      (tester) async {
        final repo = FakeSalonRepository(salon: _stubSalonNoCity);
        final location = _FakeLocationRepository();
        final router = _router();
        await tester.pumpRoutedApp(
          router,
          overrides: _overrides(repo, location),
        );
        await tester.pumpAndSettle();

        unawaited(router.push(RouteNames.salonAddressEdit(_kSalonId)));
        await tester.pumpAndSettle();

        // Street/building/note still pre-populate regardless — only the
        // settlement field is affected by a missing city.
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('salon_street')))
              .controller!
              .text,
          _stubSalonNoCity.street,
        );

        // No oblast control exists any more, and the district row cannot
        // render without a chosen settlement.
        expect(find.byKey(const Key('locality_row_oblast')), findsNothing);
        expect(find.byKey(const Key('locality_row_city')), findsNothing);
        expect(find.byKey(const Key('locality_row_district')), findsNothing);
        expect(
          find.byKey(const Key('settlement_select_field')),
          findsOneWidget,
        );

        expect(
          location.searchQueries,
          isEmpty,
          reason:
              'no cityId on the salon -> the settlement field must not issue '
              'a settlement search before the user opens it.',
        );
        expect(
          location.districtQueries,
          isEmpty,
          reason:
              '_prePopulateDistrict must early-return on a null settlement '
              'id, and districtsOf must short-circuit before watching '
              'districtListProvider — no fan-out lookup at all.',
        );
      },
    );

    // Mirrors `location_edit_screen_test.dart`'s "validation blocks save
    // when street is filled but no city is selected" — the master's
    // equivalent guard, and the test whose ABSENCE on this screen let the
    // Finding (2026-08-29) ship: no client-side "city is required" check at
    // all meant Save always reached `saveAddress`, and the wire either
    // carried a stale/null cityId or relied entirely on the backend's 400.
    testWidgets(
      'Save is blocked with no city selected at all, and the settlement '
      'field shows an inline error',
      (tester) async {
        final repo = FakeSalonRepository(salon: _stubSalonNoCity);
        final router = _router();
        await tester.pumpRoutedApp(
          router,
          overrides: _overrides(repo, _FakeLocationRepository()),
        );
        await tester.pumpAndSettle();

        unawaited(router.push(RouteNames.salonAddressEdit(_kSalonId)));
        await tester.pumpAndSettle();

        // Street/building are already valid (pre-populated from the
        // fixture) — the missing city must be the ONLY thing blocking Save.
        await tester.tap(find.byKey(const Key('save_salon_address')));
        await tester.pumpAndSettle();

        expect(
          repo.updateRequests,
          isEmpty,
          reason:
              'no city selected at all must block Save client-side — this '
              'is the exact guard whose absence let saveAddress() reach the '
              'wire relying solely on an opaque backend 400 instead of an '
              'inline field error.',
        );
        expect(find.byKey(const Key('manage-marker')), findsNothing);
        final SettlementLocalityField field = tester
            .widget<SettlementLocalityField>(
              find.byType(SettlementLocalityField),
            );
        expect(
          field.settlementError,
          isNotNull,
          reason:
              'the settlement field must show an inline required-field '
              'error.',
        );
      },
    );

    // Phase 346 removed the concept the DELETED test here covered —
    // "changing the oblast resets the previously pre-populated city and
    // re-blocks Save": the «Область» row no longer exists, so there is
    // nothing left to change independently of the settlement itself. Its
    // replacement invariant DOES still hold and is covered below: picking a
    // NEW settlement always clears whatever district was previously chosen,
    // because a `CityDistrict` belongs to exactly one settlement and
    // carrying one across would submit a district that is not a child of the
    // submitted city.
    testWidgets(
      'picking a new settlement clears a previously-picked district and '
      're-blocks Save',
      (tester) async {
        final repo = FakeSalonRepository(salon: _stubSalon);
        final router = _router();
        await tester.pumpRoutedApp(router, overrides: _overrides(repo));
        await tester.pumpAndSettle();

        unawaited(router.push(RouteNames.salonAddressEdit(_kSalonId)));
        await tester.pumpAndSettle();

        // Pick the district-requiring settlement and its district first.
        await _pickSettlement(
          tester,
          query: 'дніп',
          settlementId: _settlementWithDistricts.id,
        );
        await tester.tap(find.byKey(const Key('locality_row_district')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(ValueKey<String>('locality_picker_tile_${_district.id}')),
        );
        await tester.pumpAndSettle();
        expect(find.text(_district.name), findsOneWidget);

        // Now switch to the leaf settlement (no districts) — the district
        // selection must be gone, and its row must disappear entirely since
        // `city-01` has none.
        await _pickSettlement(
          tester,
          query: 'киї',
          settlementId: _settlementCity.id,
        );
        expect(find.text(_district.name), findsNothing);
        expect(find.byKey(const Key('locality_row_district')), findsNothing);

        // Save must proceed cleanly — the leaf settlement needs no district.
        await tester.tap(find.byKey(const Key('save_salon_address')));
        await tester.pump();
        await pumpVelvetSnackIn(tester);

        expect(repo.updateRequests, hasLength(1));
        final UpdateSalonRequest sent = repo.updateRequests.single;
        expect(sent.cityId, _settlementCity.id);
        expect(
          sent.districtId,
          isNull,
          reason:
              'switching to the leaf settlement must have cleared the '
              'previously-picked district — a stale districtId here would '
              'submit a district that does not belong to the submitted city.',
        );
        expect(find.byKey(const Key('manage-marker')), findsOneWidget);
        await pumpPastVelvetSnack(tester);
      },
    );

    // Phase 346 D7 — a salon carrying `cityId` + the denormalised `city` NAME
    // shows that name on the closed field WITHOUT the field ever issuing a
    // settlement search: `SalonResponse.city` supplies the label directly, so
    // there is no id -> name lookup to make. (A district read for `city-01`
    // still fires — see `districtsOf`'s doc — but that is a separate,
    // always-issued read that decides whether the district row renders, not
    // a settlement search.)
    testWidgets(
      'a salon with cityId + denormalised city name shows that name without '
      'issuing a settlement search',
      (tester) async {
        final repo = FakeSalonRepository(salon: _stubSalon);
        final location = _FakeLocationRepository();
        final router = _router();
        await tester.pumpRoutedApp(
          router,
          overrides: _overrides(repo, location),
        );
        await tester.pumpAndSettle();

        unawaited(router.push(RouteNames.salonAddressEdit(_kSalonId)));
        await tester.pumpAndSettle();

        expect(find.text(_stubSalon.city!), findsOneWidget);
        expect(
          location.searchQueries,
          isEmpty,
          reason:
              'the salon already carries the denormalised settlement name '
              '(`salon.city`) — showing it must never cost a settlement '
              'search.',
        );
      },
    );
  });
}

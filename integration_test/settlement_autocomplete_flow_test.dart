// E2E: Phase 346 — the «Населений пункт» autocomplete, end to end on a
// provider surface (INDEPENDENT_MASTER → «Налаштування» → «Локація»).
//
// The other settlement flows were CONVERTED from the retired Область → Місто
// cascade and pick a big city straight off the pre-typing list. These two
// flows exist for what only the new field can do, and for the one surface
// (`master/presentation/location_edit_screen.dart`) no E2E drove at all:
//
//   1. A VILLAGE is TYPED for, picked off a row carrying the hromada
//      disambiguation label, and saved. The PATCH carries the settlement ID
//      (never its text, D3), the typed term — and only the debounced one —
//      reached `GET /settlements`, and RE-OPENING the screen shows the saved
//      settlement (D7) off the denormalised `/masters/me` `city`.
//   2. A city WITH districts: the «Район» row appears only after the pick,
//      Save is BLOCKED client-side without a district (no PATCH, inline
//      error), then succeeds with one; re-opening shows the district too.
//
//   3. SALON address edit (owner): the same village, saved and re-opened. The
//      re-opened field reads the salon's `city`, which the backend derives
//      from `cityId` since Phase 328 (`f3720365`) — before that it opened
//      BLANK (or on the OLD city) for every post-10.6 salon.
//
// NO PATROL FLOW: nothing here touches a native interaction.
//
// Run: flutter test -d flutter-tester integration_test/settlement_autocomplete_flow_test.dart

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/location/domain/settlement.dart';
import 'package:beautica_mobile/features/location/presentation/widgets/settlement_select_field.dart';
import 'dart:async';

import 'package:beautica_mobile/features/master/presentation/location_edit_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_address_edit_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

const Key _kField = Key('settlement_select_field');
const Key _kDistrictRow = Key('locality_row_district');
const Key _kSave = Key('btn-save-location');

/// An INDEPENDENT_MASTER whose profile already carries a complete address in
/// Kyiv, so street/building validate and the only thing a flow changes is
/// the locality.
FakeBackend _masterBackend() => FakeBackend()
  ..currentRole = UserRole.independentMaster
  ..masterCity = 'Київ'
  ..masterCityId = 'city-kyiv'
  ..masterStreet = 'Хрещатик'
  ..masterBuildingNo = '1';

const String _kSalonId = 'salon-xyz';

/// A SALON_OWNER whose `GET /salons/mine` lists [_kSalonId] (in Kyiv), so
/// `salonManageGuard` admits the owner to its address screen.
FakeBackend _salonOwnerBackend() => FakeBackend()
  ..currentRole = UserRole.salonOwner
  ..mySalons = <Map<String, dynamic>>[
    <String, dynamic>{
      'id': _kSalonId,
      'ownerId': 'user-owner-1',
      'name': 'Студія Краси «Камелія»',
      'cityId': 'city-kyiv',
      'oblastId': 'oblast-kyiv',
      'street': 'Хрещатик',
      'buildingNo': '12',
      'isActive': true,
      'isPrimary': true,
    },
  ];

/// PUSHES the salon address screen over `/manage` (its Save pops, so it needs
/// a real route beneath it).
Future<void> _openSalonAddress(WidgetTester tester, GoRouter router) async {
  router.go(RouteNames.salonManage(_kSalonId));
  await AppHarness.settle(tester);
  unawaited(router.push(RouteNames.salonAddressEdit(_kSalonId)));
  await AppHarness.settle(tester);
  await AppHarness.pumpUntilFound(tester, find.byKey(_kField));
  expect(find.byType(SalonAddressEditScreen), findsOneWidget);
}

Future<AppLocalizations> _uk() =>
    AppLocalizations.delegate.load(const Locale('uk'));

/// «м. Київ» — Kyiv's region is the city itself, so no oblast segment.
String _kyivLabel(AppLocalizations l10n) => '${l10n.settlementCityPrefix} Київ';

/// Text rendered inside the widget keyed [key] (read, never `find.text` on
/// Cyrillic — see the cyrillic-finder guard).
String _textIn(WidgetTester tester, Key key) => tester
    .widget<Text>(
      find.descendant(of: find.byKey(key), matching: find.byType(Text)).first,
    )
    .data!;

Future<GoRouter> _openLocationScreen(
  WidgetTester tester,
  FakeBackend fb,
) async {
  final GoRouter router = await AppHarness.boot(tester, fb);
  await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
  // fixed-wait-ok: settles the real async login/route-transition step.
  await tester.pumpAndSettle(const Duration(seconds: 1));
  await _reopenLocationScreen(tester, router);
  return router;
}

/// The REAL entry point: the settings hub's «Локація» row.
Future<void> _reopenLocationScreen(WidgetTester tester, GoRouter router) async {
  router.go(RouteNames.masterMenu);
  await AppHarness.settle(tester);
  await AppHarness.tapVisible(tester, find.byKey(const Key('row-location')));
  await AppHarness.settle(tester);
  await AppHarness.pumpUntilFound(tester, find.byKey(_kField));
  expect(find.byType(LocationEditScreen), findsOneWidget);
}

Future<void> _save(WidgetTester tester) async {
  await AppHarness.tapVisible(tester, find.byKey(_kSave));
  await AppHarness.settle(tester);
  // fixed-wait-ok: lets the real async PATCH round-trip land before asserting.
  await tester.pump(const Duration(milliseconds: 500));
  await AppHarness.settle(tester);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets('master TYPES for a village, picks the row carrying the hromada '
      'label, saves: the PATCH carries the settlement ID and re-opening shows '
      'the saved settlement (D3, D4, D7)', (tester) async {
    final fb = _masterBackend();
    final GoRouter router = await _openLocationScreen(tester, fb);
    final AppLocalizations uk = await _uk();
    expect(
      _textIn(tester, _kField),
      _kyivLabel(uk),
      reason: 'seeded label (D7) — composed from the phase-330 type',
    );

    // Open the sheet and TYPE — the debounce pump is load-bearing
    // (pumpAndSettle fires no Timer).
    await AppHarness.tapVisible(tester, find.byKey(_kField));
    await AppHarness.settle(tester);
    await tester.enterText(find.byKey(const Key('select-menu-search')), 'Іва');
    await tester.pump(kSettlementSearchDebounce);
    await AppHarness.settle(tester);

    const Key villageRow = Key('settlement_option_village-ivanivka');
    await AppHarness.pumpUntilFound(tester, find.byKey(villageRow));
    final AppLocalizations l10n = AppLocalizations.of(
      tester.element(find.byKey(villageRow)),
    );
    final String expectedLabel = composeSettlementLabel(
      const Settlement(
        id: 'village-ivanivka',
        name: 'Іванівка',
        oblastName: 'Полтавська',
        hromadaName: 'Шишацька',
        settlementType: kSettlementTypeVillage,
      ),
      hromadaWord: l10n.settlementHromadaWord,
      oblastWord: l10n.settlementOblastAbbrev,
      cityPrefix: l10n.settlementCityPrefix,
      villagePrefix: l10n.settlementVillagePrefix,
    );
    expect(
      _textIn(tester, villageRow),
      expectedLabel,
      reason: 'the ambiguous village row renders the 3-part hromada label',
    );
    expect(expectedLabel, contains('Шишацька'));
    expect(expectedLabel, startsWith('с. Іванівка'));
    expect(expectedLabel, endsWith('Полтавська обл.'));

    await tester.tap(find.byKey(villageRow));
    await AppHarness.settle(tester);
    expect(_textIn(tester, _kField), expectedLabel);
    expect(
      find.byKey(_kDistrictRow),
      findsNothing,
      reason: 'a village has no districts — no «Район» row',
    );

    await _save(tester);

    expect(fb.patchMasterLocalityCalls, 1);
    final Map<String, dynamic> body = fb.lastPatchMasterLocalityBody!;
    expect(body['cityId'], 'village-ivanivka', reason: 'the ID is the value');
    expect(body.containsKey('districtId'), isFalse);
    expect(
      body.values.whereType<String>().where(
        (String v) => v.contains('Іванівка') || v.contains('Шишацька'),
      ),
      isEmpty,
      reason: 'the settlement label is never round-tripped to the server (D3)',
    );
    expect(
      fb.settlementQueries,
      <String>['', 'Іва'],
      reason:
          'the blank major-list read, then exactly ONE search for the '
          'debounced term',
    );
    expect(find.byType(LocationEditScreen), findsNothing, reason: 'saved');

    // ── D7: re-open the address ────────────────────────────────────────
    await _reopenLocationScreen(tester, router);
    expect(
      _textIn(tester, _kField),
      expectedLabel,
      reason:
          're-opening shows the saved settlement, seeded from /masters/me '
          'city + region + the phase-330 type/hromada — the SAME label the '
          'picked row carried, not the previous «Київ» and not a bare name',
    );
  });

  testWidgets('a city WITH districts: the «Район» row appears, Save is blocked '
      'without a district, then succeeds with one (and re-opens with it)', (
    tester,
  ) async {
    final fb = _masterBackend();
    final GoRouter router = await _openLocationScreen(tester, fb);
    expect(
      find.byKey(_kDistrictRow),
      findsNothing,
      reason: 'Kyiv (a leaf in the fixture) renders no district row',
    );

    await AppHarness.pickSettlement(
      tester,
      'city-with-districts',
      query: 'Дні',
    );
    await AppHarness.pumpUntilFound(tester, find.byKey(_kDistrictRow));

    // ── Blocked without a district ──────────────────────────────────────
    await _save(tester);
    expect(
      fb.patchMasterLocalityCalls,
      0,
      reason: 'a settlement with districts and none picked never hits the wire',
    );
    expect(find.byType(LocationEditScreen), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(_kDistrictRow),
        matching: find.byKey(const ValueKey<String>('locality_tap_row_error')),
      ),
      findsOneWidget,
      reason: 'the block is explained inline on the «Район» row',
    );

    // ── Pick the district, save succeeds ────────────────────────────────
    await AppHarness.tapVisible(tester, find.byKey(_kDistrictRow));
    await AppHarness.settle(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('locality_picker_tile_district-podil')),
    );
    await AppHarness.settle(tester);
    expect(
      find.byKey(const ValueKey<String>('locality_tap_row_error')),
      findsNothing,
    );

    await _save(tester);
    expect(fb.patchMasterLocalityCalls, 1);
    final Map<String, dynamic> body = fb.lastPatchMasterLocalityBody!;
    expect(body['cityId'], 'city-with-districts');
    expect(body['districtId'], 'district-podil');

    // ── Re-open: settlement AND district come back ──────────────────────
    await _reopenLocationScreen(tester, router);
    final AppLocalizations uk = await _uk();
    expect(
      _textIn(tester, _kField),
      '${uk.settlementCityPrefix} Дніпро, Дніпропетровська '
      '${uk.settlementOblastAbbrev}',
    );
    await AppHarness.pumpUntilFound(tester, find.byKey(_kDistrictRow));
    expect(
      tester
          .widget<Text>(
            find
                .descendant(
                  of: find.byKey(_kDistrictRow),
                  matching: find.byType(Text),
                )
                .last,
          )
          .data,
      'Подільський район',
    );
  });

  testWidgets('Phase 347 — instant autocomplete: 1–2 chars refine the majors '
      'with NO request, the 3rd char sends ONE debounced search, and '
      'backspace + retype is served from the client cache', (tester) async {
    final fb = _masterBackend();
    await _openLocationScreen(tester, fb);
    await AppHarness.tapVisible(tester, find.byKey(_kField));
    await AppHarness.settle(tester);

    const Key search = Key('select-menu-search');
    const Key kyivRow = Key('settlement_option_city-kyiv');
    const Key lvivRow = Key('settlement_option_city-lviv');
    const Key minimumHint = Key('select-menu-minimum');
    List<String> typedQueries() =>
        fb.settlementQueries.where((String q) => q.isNotEmpty).toList();

    // ── 1–2 chars: majors refined locally, above the hint, no request ─────
    await tester.enterText(find.byKey(search), 'ки');
    await tester.pump(kSettlementSearchDebounce);
    await AppHarness.settle(tester);
    expect(find.byKey(kyivRow), findsOneWidget, reason: 'major prefix match');
    expect(find.byKey(lvivRow), findsNothing, reason: 'prefix-filtered out');
    expect(find.byKey(minimumHint), findsOneWidget);
    expect(typedQueries(), isEmpty, reason: '1–2 chars never hit the wire');

    // ── 3rd char: provisional rows at once, then ONE debounced search ─────
    await tester.enterText(find.byKey(search), 'льв');
    await tester.pump();
    expect(find.byKey(lvivRow), findsOneWidget, reason: 'provisional, 0 ms');
    expect(typedQueries(), isEmpty, reason: 'debounce not yet elapsed');
    await tester.pump(kSettlementSearchDebounce);
    await AppHarness.settle(tester);
    await AppHarness.pumpUntilFound(tester, find.byKey(lvivRow));
    expect(typedQueries(), <String>['льв'], reason: 'exactly one search');

    // ── Backspace below the minimum, let the «льв» member dispose ─────────
    await tester.enterText(find.byKey(search), 'ль');
    await tester.pump(kSettlementSearchDebounce);
    await AppHarness.settle(tester);
    expect(find.byKey(minimumHint), findsOneWidget);
    expect(find.byKey(lvivRow), findsOneWidget, reason: 'majors, locally');

    // ── Retype: served from the LRU, no new request ───────────────────────
    await tester.enterText(find.byKey(search), 'льв');
    await tester.pump(kSettlementSearchDebounce);
    await AppHarness.settle(tester);
    expect(find.byKey(lvivRow), findsOneWidget, reason: 'rows still show');
    expect(find.byKey(minimumHint), findsNothing);
    expect(
      typedQueries(),
      <String>['льв'],
      reason: 'the repeat query is a client-cache hit — no second search',
    );
  });

  testWidgets('SALON owner picks the village, saves, re-opens: the PATCH '
      'carries the settlement ID and the re-opened field shows the NEW '
      'settlement — not blank, not the old city (D7, backend Phase 328)', (
    tester,
  ) async {
    final fb = _salonOwnerBackend();
    final GoRouter router = await AppHarness.boot(tester, fb);
    await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
    // fixed-wait-ok: settles the real async login/route-transition step.
    await tester.pumpAndSettle(const Duration(seconds: 1));

    await _openSalonAddress(tester, router);
    final AppLocalizations uk = await _uk();
    expect(
      _textIn(tester, _kField),
      _kyivLabel(uk),
      reason: 'the saved city seeds',
    );

    await AppHarness.pickSettlement(tester, 'village-ivanivka', query: 'Іва');
    final String pickedLabel = _textIn(tester, _kField);
    expect(pickedLabel, contains('Шишацька'));

    await AppHarness.tapVisible(
      tester,
      find.byKey(const Key('save_salon_address')),
    );
    await AppHarness.settle(tester);
    // fixed-wait-ok: lets the real async PATCH round-trip + pop land.
    await tester.pump(const Duration(milliseconds: 500));
    await AppHarness.settle(tester);

    expect(fb.updateSalonCalls, 1);
    final Map<String, dynamic> body = fb.lastUpdateSalonBody!;
    expect(body['cityId'], 'village-ivanivka', reason: 'the ID is the value');
    expect(
      body.values.whereType<String>().where(
        (String v) => v.contains('Іванівка') || v.contains('Шишацька'),
      ),
      isEmpty,
      reason: 'the settlement label is never round-tripped (D3)',
    );
    expect(find.byType(SalonAddressEditScreen), findsNothing, reason: 'left');

    // ── D7: re-open ────────────────────────────────────────────────────
    await _openSalonAddress(tester, router);
    expect(
      _textIn(tester, _kField),
      pickedLabel,
      reason:
          'the re-opened field shows the salon city the backend derived from '
          'the SAVED cityId, labelled exactly as the picked row — neither '
          'blank, nor the previous «Київ», nor a bare name',
    );
  });
}

// E2E: Phase 348 — saved-settlement labels (mobile consumer of backend Phase
// 330 `a9992eba`), end to end against the fake backend.
//
// Backend Phase 330 put the settlement's own `citySettlementType` (and, only
// for an ambiguous name, `cityHromadaNameUk`) on every SAVED-locality read.
// The app now labels a saved locality exactly as the «Населений пункт» picker
// labels a row. What only this tier can prove is the WIRE → mapper → provider
// → screen chain on the real app, including the one failure mode the widget
// tier fakes away entirely: a `citySettlementType` this build predates.
//
//   1. CLIENT, saved VILLAGE (ambiguous → hromada): the Home profile card
//      reads «с. Іванівка, Шишацька громада, Полтавська обл.», and opening
//      Пошук shows the SAME label prefilled in the settlement filter.
//   2. SALON_OWNER, salon in a VILLAGE: the «Мої салони» hub card and the
//      management hero read the SHORT label «с. Іванівка», with NO oblast
//      (the 2026-08-29 address-line rule). Before phase 330 the city-only
//      taxonomy lookup rendered NO locality at all for a village salon.
//   3. Unknown enum resilience: `/users/me` answers
//      `citySettlementType: "HAMLET"`. Both a fresh LOGIN and a COLD START
//      (stored refresh token) land on Home with the bare name, and the stored
//      session is never wiped. Before the generated `unknownDefaultOpenApi`
//      fallback, that one value failed the whole `/users/me` decode.
//
// Expected labels are assembled from the fake's settlement fixture maps and
// the four `AppLocalizations` words — never from raw Cyrillic finders, and
// never by calling the production composer under test.
//
// NO PATROL FLOW: nothing here touches a native interaction.
//
// Run: flutter test -d flutter-tester integration_test/saved_settlement_label_flow_test.dart

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/fakes/fake_secure_storage.dart';
import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';
import 'support/fake_backend.dart'
    show
        kSeededSettlementHromadaNames,
        kSeededSettlementNames,
        kSeededSettlementOblastNames;

const String _kVillageId = 'village-ivanivka';
const String _kSalonId = 'salon-xyz';

const Key _kHomeCity = Key('home_profile_city');
const Key _kSearchCity = Key('search_city_value');
const Key _kHeroAddress = Key('salon-manage-address');

String get _villageName => kSeededSettlementNames[_kVillageId]!;

/// «с. Іванівка, Шишацька громада, Полтавська обл.» — from the fixture maps
/// and the localised words, so an EN locale changes only the words.
String _fullVillageLabel(AppLocalizations l10n) =>
    '${l10n.settlementVillagePrefix} $_villageName, '
    '${kSeededSettlementHromadaNames[_kVillageId]} '
    '${l10n.settlementHromadaWord}, '
    '${kSeededSettlementOblastNames[_kVillageId]} '
    '${l10n.settlementOblastAbbrev}';

/// «с. Іванівка» — the salon address-line form (no hromada, no oblast).
String _shortVillageLabel(AppLocalizations l10n) =>
    '${l10n.settlementVillagePrefix} $_villageName';

Future<AppLocalizations> _l10n() =>
    AppLocalizations.delegate.load(const Locale('uk'));

String _textOf(WidgetTester tester, Key key) =>
    tester.widget<Text>(find.byKey(key)).data!;

/// Re-derives the ACTUAL laid-out line count from the [RenderParagraph]
/// backing the [Text] at [key] — mirrors the pattern used across the widget
/// tier (`home_profile_card_test.dart`, `master_address_block_test.dart`,
/// `salon_affiliation_card_test.dart`, `public_salon_profile_screen_test
/// .dart`, `passport_screen_test.dart`). This E2E reproduces the user report
/// ("in client own profile the location is cut") end to end: a full
/// village+hromada+oblast label reaching the Home profile card through the
/// REAL wire → mapper → provider → screen chain must actually WRAP to 2
/// lines, not just contain the right text — a one-line ellipsis truncation
/// would still satisfy a plain string-equality check on a short label, but
/// not this one, since the fixture label is long enough to need the second
/// line.
int _lineCount(WidgetTester tester, Key key) {
  final RenderParagraph p = tester.renderObject<RenderParagraph>(
    find.byKey(key),
  );
  final TextPainter painter = TextPainter(
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

/// A CLIENT whose saved locality is the ambiguous seeded village.
FakeBackend _clientInVillage() => FakeBackend()
  ..currentRole = UserRole.client
  ..clientCityId = _kVillageId
  ..clientCityName = _villageName;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets('CLIENT with a saved VILLAGE: the Home profile card shows '
      '«с. …, … громада, … обл.» and Пошук opens with the SAME label '
      'prefilled', (tester) async {
    // A real narrow-phone surface. `-d flutter-tester`'s default 800×600
    // window is wide enough that this exact label fits on one line — it
    // would NOT reproduce the user-reported bug at all. The wrap/no-wrap
    // decision is a genuine function of the width the card is given (same
    // reasoning as `master_profile_address_block_flow_test.dart`), so a
    // narrow surface is the correct end-to-end reproduction, not decoration.
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppLocalizations l10n = await _l10n();
    final String expected = _fullVillageLabel(l10n);
    final fb = _clientInVillage();

    final GoRouter router = await AppHarness.boot(tester, fb);
    await AppHarness.loginAs(tester, fb, UserRole.client);
    await AppHarness.settle(tester);
    AppHarness.expectLocation(router, RouteNames.clientHome);

    await AppHarness.pumpUntilFound(tester, find.byKey(_kHomeCity));
    expect(
      _textOf(tester, _kHomeCity),
      expected,
      reason:
          'the saved village is labelled from /users/me citySettlementType + '
          'cityHromadaNameUk + oblastName — the picker label, not a bare name',
    );
    expect(
      _lineCount(tester, _kHomeCity),
      2,
      reason:
          'user-reported bug — the full village/hromada/oblast label must '
          'WRAP onto a second line on the real Home profile card, not be '
          'silently collapsed to one ellipsised line ('
          '«с. Іванівка (Шишацька гром…»)',
    );

    await tester.tap(find.byKey(const Key('client-nav-search-center')));
    await AppHarness.settle(tester);
    AppHarness.expectLocation(router, RouteNames.clientSearch);
    await AppHarness.pumpUntilFound(tester, find.byKey(_kSearchCity));
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(_kSearchCity),
              matching: find.byType(Text),
            ),
          )
          .data,
      expected,
      reason: 'the search prefill composes the SAME saved label as the card',
    );
  });

  testWidgets('SALON_OWNER whose salon is in a VILLAGE: the hub card and the '
      'management hero show the SHORT label «с. …» with no oblast', (
    tester,
  ) async {
    final AppLocalizations l10n = await _l10n();
    final String short = _shortVillageLabel(l10n);
    final fb = FakeBackend()
      ..currentRole = UserRole.salonOwner
      ..salonManageCityId = _kVillageId
      ..mySalons = <Map<String, dynamic>>[
        <String, dynamic>{
          'id': _kSalonId,
          'ownerId': 'user-owner-1',
          'name': 'Салон у селі',
          'cityId': _kVillageId,
          'oblastId': 'oblast-kyiv',
          'street': 'вул. Хрещатик',
          'buildingNo': '12',
          'isActive': true,
          'isPrimary': true,
        },
      ];

    final GoRouter router = await AppHarness.boot(tester, fb);
    await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
    await AppHarness.settle(tester);

    // ── «Мої салони» hub card ────────────────────────────────────────────
    router.go(RouteNames.mySalons);
    await AppHarness.settle(tester);
    AppHarness.expectLocation(router, RouteNames.mySalons);
    final Finder card = find.byKey(
      const ValueKey<String>('my_salons_card_$_kSalonId'),
    );
    await AppHarness.pumpUntilFound(tester, card);
    // The card renders its address as ONE Text, one line per `\n`.
    final List<String> cardLines = tester
        .widgetList<Text>(
          find.descendant(of: card, matching: find.byType(Text)),
        )
        .expand((Text t) => (t.data ?? '').split('\n'))
        .toList();
    expect(
      cardLines,
      contains(short),
      reason:
          'the hub card locality line is the settlement short label — before '
          'phase 330 a village salon rendered no locality line at all',
    );
    expect(
      cardLines.where(
        (String line) => line.contains(l10n.settlementOblastAbbrev),
      ),
      isEmpty,
      reason: 'salon address lines never carry the oblast (2026-08-29 rule)',
    );

    // ── Management hero ──────────────────────────────────────────────────
    router.go(RouteNames.salonManage(_kSalonId));
    await AppHarness.settle(tester);
    await AppHarness.pumpUntilFound(tester, find.byKey(_kHeroAddress));
    expect(
      _textOf(tester, _kHeroAddress),
      '$short, вул. Хрещатик, 12',
      reason: 'the hero address line opens with the village short label',
    );
  });

  group('unknown citySettlementType on /users/me ("HAMLET")', () {
    FakeBackend hamletClient() =>
        _clientInVillage()..clientCitySettlementTypeOverride = 'HAMLET';

    Future<void> expectHomeWithBareName(
      WidgetTester tester,
      GoRouter router,
    ) async {
      AppHarness.expectLocation(router, RouteNames.clientHome);
      await AppHarness.pumpUntilFound(tester, find.byKey(_kHomeCity));
      expect(
        _textOf(tester, _kHomeCity),
        _villageName,
        reason:
            'an unknown type decodes to the fallback, which maps to NO type: '
            'the bare name — never a guessed prefix or a hromada/oblast tail',
      );
    }

    testWidgets('LOGIN still lands on Home with the bare name, and the '
        'session is stored (no logout)', (tester) async {
      final storage = FakeSecureStorage();
      final fb = hamletClient();

      final GoRouter router = await AppHarness.boot(
        tester,
        fb,
        storage: storage,
      );
      await AppHarness.loginAs(tester, fb, UserRole.client);
      await AppHarness.settle(tester);

      await expectHomeWithBareName(tester, router);
      expect(fb.getMeCalls, greaterThanOrEqualTo(1));
      expect(await storage.readRefreshToken(), isNotNull);
    });

    testWidgets('COLD START with a stored session restores it: Home with the '
        'bare name, and the stored token is KEPT', (tester) async {
      final storage = FakeSecureStorage();
      await storage.writeRefreshToken('fake-refresh-token');
      final fb = hamletClient();

      final GoRouter router = await AppHarness.boot(
        tester,
        fb,
        storage: storage,
      );
      await AppHarness.settle(tester);

      await expectHomeWithBareName(tester, router);
      expect(
        fb.getMeCalls,
        greaterThanOrEqualTo(1),
        reason: 'the session was restored through the real /users/me read',
      );
      expect(
        await storage.readRefreshToken(),
        isNotNull,
        reason: 'an unparseable-looking 200 must never wipe the session',
      );
    });
  });
}

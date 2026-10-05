// Phase 369 (9.8) QA — fake-backed E2E for the READ surfaces of the salon logo
// and cover, closing the role × surface × state gaps the phase's own
// `salon_logo_cover_owner_test.dart` leaves (that file drives the owner's
// upload / remove and the admin 403; it only ever looks at the management hero
// and the public profile):
//
//   • SEED CONTRACT — the backend seed (`seed-demo-fleet.sh`) uploads the
//     cover, then the logo, through `POST /salons/{id}/media/{cover|logo}`;
//     the app is built with `BEAUTICA_MEDIA_ORIGIN` = the HOST of the R2
//     public URL (`scripts/_media_origin.sh`). A salon whose `coverImageUrl`
//     / `avatarUrl` sit on that host must PAINT (decoded pixels, not just a
//     widget holding a URL) on the «Мої салони» hub card, the salon settings
//     context row, the management hero and the public profile.
//   • SALON_ADMIN — a real logo / cover on the affiliation card (own profile),
//     the settings context row and the hero; no surface offers an edit control.
//   • DISALLOWED HOST — every surface keeps the monogram / gradient and the
//     URL never reaches the cache manager (owner + client).
//   • LOAD ERROR — every surface falls back to the monogram / gradient
//     (owner + admin + client).
//
//   • ROTATE-ADMIN PICKER — `SiblingSalonOption.avatarUrl` (backend, 369
//     audit) reaches the destination card's logo over the real wire.
//
// Runs headless: `flutter test integration_test/salon_logo_surfaces_flow_test.dart
// -d flutter-tester`.

import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/media/media_config.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/salon/presentation/public_salon_profile_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_management_profile_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/widgets/salon_cover_widgets.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/fake_media_cache.dart';
import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

const String _ownerSalon = FakeBackend.kOwnerSalonId;
const String _adminSalon = FakeBackend.kAdminSalonId;

/// What `R2StorageService.buildPublicUrl` returns for the seed's uploads
/// (backend 343 D4 keys `salons/{id}/{cover|logo}/{uuid}.{ext}`).
const String _r2PublicUrl = 'https://pub-369seed.r2.dev';
String _seedUrl(String salonId, String slot) =>
    '$_r2PublicUrl/salons/$salonId/$slot/0f5e2a6c-3c1d-4b7e-9a51-1d2c3b4a5e6f.jpg';

const String _evilLogo = 'https://evil.test/salons/logo.jpg';
const String _evilCover = 'https://evil.test/salons/cover.jpg';

/// Both fixture salons are named «Салон …».
// i18n-finder-ok: the salon-name initial is fixture data, not UI copy.
const String _monogram = 'С';

const Key _hero = Key('salon-manage-hero-card');
const Key _settingsRow = Key('salon-settings-context');
const Key _affiliation = Key('admin-own-profile-salon-card');

/// Scoped per screen: a route pushed over the owner's shell can leave the
/// management screen (and ITS editors) mounted offstage underneath.
final Finder _publicScreen = find.byType(PublicSalonProfileScreen);
final Finder _manageScreen = find.byType(SalonManagementProfileScreen);
Finder _coverIn(Finder screen) =>
    find.descendant(of: screen, matching: find.byType(SalonCover));
Finder _publicLogo(String url) => find.descendant(
  of: _publicScreen,
  matching: find.byWidgetPredicate(
    (Widget w) => w is SalonLogo && w.imageUrl == url,
  ),
);
Key _hubCard(String id) => ValueKey<String>('my_salons_card_$id');

/// Every owner-only edit control 369 adds — none may exist on a read surface.
const List<Key> _editKeys = <Key>[
  Key('salon-logo-edit-badge'),
  Key('salon-logo-editor'),
  Key('salon-cover-edit'),
  Key('salon-cover-editor'),
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late List<String> fetched;
  late FakeMediaCacheManager cache;

  void useResponder(Stream<FileResponse> Function(String url) respond) {
    cache.responder = (String url) {
      fetched.add(url);
      return respond(url);
    };
  }

  setUp(() {
    installOverflowGuard();
    fetched = <String>[];
    MediaConfig.debugAllowedHosts = <String>{'media.test'};
    cache = FakeMediaCacheManager(mediaLoadingForever);
    useResponder(mediaLoaded);
    debugMediaCacheManager = cache;
  });
  tearDown(() async {
    debugMediaCacheManager = null;
    MediaConfig.debugAllowedHosts = null;
    await AppHarness.tearDownHarness();
  });

  Future<GoRouter> bootAs(
    WidgetTester tester,
    FakeBackend fb,
    UserRole role,
  ) async {
    final GoRouter router = await AppHarness.boot(tester, fb);
    await AppHarness.loginAs(tester, fb, role);
    return router;
  }

  Future<void> go(WidgetTester tester, GoRouter router, String path) async {
    router.go(path);
    await AppHarness.settle(tester);
  }

  /// A [RemoteImage] for [url] under [scope] whose [RawImage] holds DECODED
  /// pixels — the photo is actually on screen, not merely requested.
  bool painted(Finder scope, String url) {
    final Finder remote = find.descendant(
      of: scope,
      matching: find.byWidgetPredicate(
        (Widget w) => w is RemoteImage && w.url == url,
      ),
    );
    if (remote.evaluate().isEmpty) return false;
    return find
        .descendant(of: remote, matching: find.byType(RawImage))
        .evaluate()
        .any((Element e) => (e.widget as RawImage).image != null);
  }

  Future<void> expectPainted(
    WidgetTester tester,
    Finder scope,
    String url,
    String what,
  ) async {
    await AppHarness.pumpUntilFound(tester, scope);
    await AppHarness.pumpUntilCondition(
      tester,
      () => painted(scope, url),
      description: '$what to paint $url',
    );
  }

  /// The monogram is on screen inside [scope] and NO photo pixels are.
  Future<void> expectMonogram(
    WidgetTester tester,
    Finder scope,
    String what,
  ) async {
    await AppHarness.pumpUntilFound(tester, scope);
    await AppHarness.pumpUntilCondition(
      tester,
      () => find
          .descendant(of: scope, matching: find.text(_monogram))
          .evaluate()
          .isNotEmpty,
      description: '$what to show the monogram',
    );
    expect(
      find
          .descendant(of: scope, matching: find.byType(RawImage))
          .evaluate()
          .any((Element e) => (e.widget as RawImage).image != null),
      isFalse,
      reason: '$what paints no photo',
    );
  }

  /// The cover's no-photo state on [screen]: the gradient placeholder glyph.
  Future<void> expectGradientCover(
    WidgetTester tester,
    Finder screen,
    String what,
  ) => AppHarness.pumpUntilCondition(
    tester,
    () =>
        find
            .descendant(of: screen, matching: find.byType(SalonCover))
            .evaluate()
            .isNotEmpty &&
        find
            .descendant(
              of: _coverIn(screen),
              matching: find.byIcon(Icons.photo_camera_back_outlined),
            )
            .evaluate()
            .isNotEmpty,
    description: '$what to show the gradient cover',
  );

  void expectNoEditControls(Finder scope, String what) {
    for (final Key k in _editKeys) {
      expect(
        find.descendant(of: scope, matching: find.byKey(k)),
        findsNothing,
        reason: '$what carries no $k',
      );
    }
    expect(
      find.descendant(of: scope, matching: find.byType(PhotoEditBadge)),
      findsNothing,
      reason: '$what carries no camera badge',
    );
  }

  Future<void> switchTo(
    WidgetTester tester,
    FakeBackend fb,
    UserRole role,
  ) async {
    await ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).first),
    ).read(authProvider.notifier).logout();
    await AppHarness.pumpUntilFound(
      tester,
      find.byKey(const ValueKey<String>('login_email')),
    );
    await AppHarness.loginAs(tester, fb, role);
  }

  testWidgets('SEED CONTRACT: a salon seeded cover-then-logo on the R2 public '
      'host paints on the hub card, the settings row, the management hero and '
      'the public profile (SALON_OWNER surfaces, then a CLIENT)', (
    tester,
  ) async {
    // Exactly what `deploy_apk.sh` compiles in: the HOST of the public URL.
    MediaConfig.debugAllowedHosts = MediaConfig.parseForTest(
      Uri.parse(_r2PublicUrl).host,
    );
    final String cover = _seedUrl(_ownerSalon, 'cover');
    final String logo = _seedUrl(_ownerSalon, 'logo');
    final FakeBackend fb = FakeBackend();
    // Seed order: cover first (the probe), then the logo.
    fb.mySalons.first['coverImageUrl'] = cover;
    fb.mySalons.first['avatarUrl'] = logo;
    final GoRouter router = await bootAs(tester, fb, UserRole.salonOwner);

    // «Мої салони» hub card.
    await go(tester, router, RouteNames.mySalons);
    final Finder hub = find.byKey(_hubCard(_ownerSalon));
    await expectPainted(tester, hub, logo, 'the hub card logo');
    expectNoEditControls(hub, 'the hub card');

    // Salon settings context row.
    await go(tester, router, RouteNames.salonManageSettings(_ownerSalon));
    final Finder row = find.byKey(_settingsRow);
    await expectPainted(tester, row, logo, 'the settings context row');
    expectNoEditControls(row, 'the settings context row');

    // Management hero: logo + cover (the owner's editors wrap them).
    await go(tester, router, RouteNames.salonManage(_ownerSalon));
    await expectPainted(tester, find.byKey(_hero), logo, 'the hero logo');
    await expectPainted(
      tester,
      _coverIn(_manageScreen),
      cover,
      'the hero cover',
    );
    expect(find.byKey(const Key('salon-cover-edit')), findsOneWidget);

    // The public profile is CLIENT-only (`clientOnlyGuard`) — a CLIENT.
    await switchTo(tester, fb, UserRole.client);
    await go(tester, router, RouteNames.salonPublicProfile(_ownerSalon));
    await expectPainted(
      tester,
      _coverIn(_publicScreen),
      cover,
      'the public cover (client)',
    );
    await expectPainted(
      tester,
      find.byWidgetPredicate(
        (Widget w) => w is SalonLogo && w.imageUrl == logo,
      ),
      logo,
      'the public logo (client)',
    );
    expectNoEditControls(_publicScreen, 'the public profile');
    expect(
      fetched.toSet(),
      containsAll(<String>[cover, logo]),
      reason: 'both seeded URLs went through the disk cache',
    );
  });

  testWidgets('SALON_ADMIN: a real logo / cover paint on the affiliation card, '
      'the settings row and the hero — no surface offers an edit control', (
    tester,
  ) async {
    const String logo = 'https://media.test/salons/admin/logo.jpg';
    const String cover = 'https://media.test/salons/admin/cover.jpg';
    final FakeBackend fb = FakeBackend()
      ..salonAdminOneAvatarUrl = logo
      ..salonAdminOneCoverImageUrl = cover;
    final GoRouter router = await bootAs(tester, fb, UserRole.salonAdmin);

    await go(tester, router, RouteNames.adminOwnProfile);
    final Finder card = find.byKey(_affiliation);
    await expectPainted(tester, card, logo, 'the affiliation card');
    expectNoEditControls(card, 'the affiliation card');

    await go(tester, router, RouteNames.salonManageSettings(_adminSalon));
    final Finder row = find.byKey(_settingsRow);
    await expectPainted(tester, row, logo, 'the settings context row');
    expectNoEditControls(row, 'the settings context row');

    await go(tester, router, RouteNames.salonManage(_adminSalon));
    await expectPainted(tester, find.byKey(_hero), logo, 'the hero logo');
    await expectPainted(
      tester,
      _coverIn(_manageScreen),
      cover,
      'the hero cover',
    );
    expectNoEditControls(_manageScreen, 'the admin hero');
  });

  testWidgets('ROTATE-ADMIN PICKER: a sibling salon\'s logo paints on its '
      'destination card; a sibling with no logo keeps the monogram', (
    tester,
  ) async {
    const String logo = 'https://media.test/salons/sibling/logo.jpg';
    final FakeBackend fb = FakeBackend();
    fb.salonAdminOneSiblingSalons.first['avatarUrl'] = logo;
    fb.salonAdminOneSiblingSalons.add(<String, dynamic>{
      'id': 'salon-admin-sibling-2',
      'name': 'Салон без логотипу',
      'street': 'вул. Січова',
      'buildingNo': '3',
      'avatarUrl': null,
    });
    final GoRouter router = await bootAs(tester, fb, UserRole.salonAdmin);

    await go(
      tester,
      router,
      RouteNames.salonManageAdminMove(_adminSalon, 'admin-peer-1'),
    );
    final Finder withLogo = find.byKey(
      const ValueKey<String>('move-admin-target-salon-admin-sibling-1'),
    );
    await expectPainted(tester, withLogo, logo, 'the picker card logo');
    expectNoEditControls(withLogo, 'the picker card');
    await expectMonogram(
      tester,
      find.byKey(
        const ValueKey<String>('move-admin-target-salon-admin-sibling-2'),
      ),
      'the logo-less picker card',
    );
    expect(fetched, contains(logo));
  });

  testWidgets('DISALLOWED HOST: hub card, settings row, hero and public '
      'profile keep the monogram / gradient and never fetch the URL '
      '(SALON_OWNER, then CLIENT)', (tester) async {
    final FakeBackend fb = FakeBackend();
    fb.mySalons.first['coverImageUrl'] = _evilCover;
    fb.mySalons.first['avatarUrl'] = _evilLogo;
    final GoRouter router = await bootAs(tester, fb, UserRole.salonOwner);

    await go(tester, router, RouteNames.mySalons);
    await expectMonogram(tester, find.byKey(_hubCard(_ownerSalon)), 'hub');

    await go(tester, router, RouteNames.salonManageSettings(_ownerSalon));
    await expectMonogram(tester, find.byKey(_settingsRow), 'settings row');

    await go(tester, router, RouteNames.salonManage(_ownerSalon));
    await expectMonogram(tester, find.byKey(_hero), 'the hero logo');
    await expectGradientCover(tester, _manageScreen, 'the hero');

    await switchTo(tester, fb, UserRole.client);
    await go(tester, router, RouteNames.salonPublicProfile(_ownerSalon));
    await expectGradientCover(tester, _publicScreen, 'the public profile');
    await expectMonogram(tester, _publicLogo(_evilLogo), 'the public logo');

    expect(fetched, isNot(contains(_evilLogo)));
    expect(fetched, isNot(contains(_evilCover)));
  });

  testWidgets('LOAD ERROR: every surface falls back to the monogram / '
      'gradient (SALON_OWNER, SALON_ADMIN, CLIENT)', (tester) async {
    useResponder(mediaFetchError);
    const String logo = 'https://media.test/salons/owner/broken-logo.jpg';
    const String cover = 'https://media.test/salons/owner/broken-cover.jpg';
    const String adminLogo = 'https://media.test/salons/admin/broken-logo.jpg';
    const String adminCover = 'https://media.test/salons/admin/broken-cvr.jpg';
    final FakeBackend fb = FakeBackend()
      ..salonAdminOneAvatarUrl = adminLogo
      ..salonAdminOneCoverImageUrl = adminCover;
    fb.mySalons.first['coverImageUrl'] = cover;
    fb.mySalons.first['avatarUrl'] = logo;
    final GoRouter router = await bootAs(tester, fb, UserRole.salonOwner);

    await go(tester, router, RouteNames.mySalons);
    await expectMonogram(tester, find.byKey(_hubCard(_ownerSalon)), 'hub');

    await go(tester, router, RouteNames.salonManageSettings(_ownerSalon));
    await expectMonogram(tester, find.byKey(_settingsRow), 'settings row');

    await go(tester, router, RouteNames.salonManage(_ownerSalon));
    await expectMonogram(tester, find.byKey(_hero), 'the owner hero logo');
    await expectGradientCover(tester, _manageScreen, 'the owner hero');
    expect(fetched, containsAll(<String>[logo, cover]));

    await switchTo(tester, fb, UserRole.salonAdmin);
    await go(tester, router, RouteNames.adminOwnProfile);
    await expectMonogram(tester, find.byKey(_affiliation), 'affiliation');
    await go(tester, router, RouteNames.salonManage(_adminSalon));
    await expectMonogram(tester, find.byKey(_hero), 'the admin hero logo');
    await expectGradientCover(tester, _manageScreen, 'the admin hero');
    expect(fetched, containsAll(<String>[adminLogo, adminCover]));

    await switchTo(tester, fb, UserRole.client);
    await go(tester, router, RouteNames.salonPublicProfile(_ownerSalon));
    await expectGradientCover(tester, _publicScreen, 'the public profile');
    await expectMonogram(
      tester,
      find.byWidgetPredicate(
        (Widget w) => w is SalonLogo && w.imageUrl == logo,
      ),
      'the public logo',
    );
  });
}

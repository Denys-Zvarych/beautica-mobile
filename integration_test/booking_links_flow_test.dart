// Phase 414 — «Посилання для запису» end to end (headless: `-d flutter-tester`).
//
// Real HttpBookingLinksRepository + generated client + Dio against the
// FakeBackend `GET /booking-links/mine` route; fake clipboard / share
// services (no platform channel).
//
//   • INDEPENDENT_MASTER: hub → row → screen → one MASTER card → Copy →
//     clipboard gets the utm_source=copy URL + success snack.
//   • SALON_OWNER: hub → screen → one SALON card per salon, NO master card
//     even though the server still sends one (client-side role scoping).
//   • SALON_ADMIN: hub → screen → its salon card.
//   • SALON_MASTER: hub has no row and the links are never fetched.
//   • SALON_MASTER / CLIENT deep link to the route → redirected to their
//     own home; the screen never renders and the links are never fetched.
//   • kill-switch off: the master hub shows no row.

import 'package:beautica_mobile/core/config/app_config.dart';
import 'package:beautica_mobile/core/share/clipboard_service.dart';
import 'package:beautica_mobile/core/share/share_service.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking_links/presentation/booking_link_screen.dart';
import 'package:beautica_mobile/features/booking_links/presentation/widgets/booking_link_card.dart';
import 'package:beautica_mobile/features/master/presentation/settings_hub_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/role_home.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import '../test/helpers/velvet_snack_matchers.dart';
import 'support/app_harness.dart';

class _FakeClipboard implements ClipboardService {
  final List<String> copied = <String>[];

  @override
  Future<bool> copyText(String text) async {
    copied.add(text);
    return true;
  }
}

class _FakeShare implements ShareService {
  final List<String> shared = <String>[];

  @override
  Future<ShareOutcome> shareText(String text, {String? subject}) async {
    shared.add(text);
    return ShareOutcome.shared;
  }
}

const Key _row = Key('row-booking-links');

Map<String, dynamic> _link({
  required String kind,
  required String slug,
  required String name,
  String? salonId,
}) => <String, dynamic>{
  'kind': kind,
  'slug': slug,
  'url': kind == 'MASTER'
      ? '${AppConfig.publicWebOrigin}/book/$slug'
      : '${AppConfig.publicWebOrigin}/book/s/$slug',
  'displayName': name,
  'salonId': salonId,
  'bookable': true,
};

final Map<String, dynamic> _masterLink = _link(
  kind: 'MASTER',
  slug: 'olena-koval-x7k2',
  name: 'Олена Коваль',
);
final Map<String, dynamic> _salonA = _link(
  kind: 'SALON',
  slug: 'lumiere-kyiv',
  name: 'Lumière',
  salonId: 'salon-owner-1',
);
final Map<String, dynamic> _salonB = _link(
  kind: 'SALON',
  slug: 'beauty-loft-8r2c',
  name: 'Beauty Loft',
  salonId: 'salon-owner-2',
);

Map<String, dynamic> _enabled(List<Map<String, dynamic>> links) =>
    <String, dynamic>{'shareEnabled': true, 'links': links};

Future<GoRouter> _bootAs(
  WidgetTester tester,
  FakeBackend fb,
  UserRole role, {
  required _FakeClipboard clipboard,
  required _FakeShare share,
}) async {
  fb.currentRole = role;
  final GoRouter router = await AppHarness.boot(
    tester,
    fb,
    extraOverrides: <Object>[
      clipboardServiceProvider.overrideWithValue(clipboard),
      shareServiceProvider.overrideWithValue(share),
    ],
  );
  await AppHarness.loginAs(tester, fb, role);
  await AppHarness.settle(tester);
  return router;
}

Future<void> _openHub(
  WidgetTester tester,
  GoRouter router,
  String hubLocation,
) async {
  router.go(hubLocation);
  await AppHarness.settle(tester);
  expect(find.byType(SettingsHubScreen), findsOneWidget);
}

Future<void> _openLinks(WidgetTester tester, GoRouter router) async {
  await AppHarness.tapVisible(tester, find.byKey(_row));
  await AppHarness.settle(tester);
  AppHarness.expectLocation(router, RouteNames.bookingLinks);
  expect(find.byType(BookingLinkScreen), findsOneWidget);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets('INDEPENDENT_MASTER: hub row → screen → Copy → clipboard + '
      'snack', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()
        ..bookingLinksMine = _enabled(<Map<String, dynamic>>[_masterLink]);
      final _FakeClipboard clipboard = _FakeClipboard();
      final GoRouter router = await _bootAs(
        tester,
        fb,
        UserRole.independentMaster,
        clipboard: clipboard,
        share: _FakeShare(),
      );

      await _openHub(tester, router, RouteNames.masterMenu);
      await _openLinks(tester, router);

      expect(find.byType(BookingLinkCard), findsOneWidget);
      final Key copy = Key('btn-booking-link-copy-${_masterLink['slug']}');
      await AppHarness.tapVisible(tester, find.byKey(copy));
      await pumpVelvetSnackIn(tester);

      expect(clipboard.copied, <String>[
        '${_masterLink['url']}'
            '?utm_source=copy&utm_medium=social&utm_campaign=master_link',
      ]);
      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(BookingLinkScreen)),
      );
      expectVelvetSnack(
        l10n.bookingLinkCopied,
        variant: VelvetSnackVariant.success,
      );
      await pumpPastVelvetSnack(tester);
    });
  });

  testWidgets('INDEPENDENT_MASTER: not-bookable link with no schedule → '
      'readiness hint → schedule page → back returns', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()
        ..bookingLinksMine = _enabled(<Map<String, dynamic>>[
          <String, dynamic>{..._masterLink, 'bookable': false},
        ])
        ..seedNoWeeklySchedule();
      final GoRouter router = await _bootAs(
        tester,
        fb,
        UserRole.independentMaster,
        clipboard: _FakeClipboard(),
        share: _FakeShare(),
      );

      await _openHub(tester, router, RouteNames.masterMenu);
      await _openLinks(tester, router);

      final Key schedule = Key(
        'link-booking-link-hint-schedule-${_masterLink['slug']}',
      );
      final Key services = Key(
        'link-booking-link-hint-services-${_masterLink['slug']}',
      );
      expect(find.byKey(schedule), findsOneWidget);
      expect(find.byKey(services), findsNothing, reason: 'services seeded');

      await AppHarness.tapVisible(tester, find.byKey(schedule));
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.masterSchedule);

      router.pop();
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.bookingLinks);
      expect(find.byType(BookingLinkScreen), findsOneWidget);
    });
  });

  testWidgets('SALON_OWNER: one SALON card per salon, no master card even if '
      'the server sends one', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()
        ..bookingLinksMine = _enabled(<Map<String, dynamic>>[
          _masterLink,
          _salonA,
          _salonB,
        ]);
      final GoRouter router = await _bootAs(
        tester,
        fb,
        UserRole.salonOwner,
        clipboard: _FakeClipboard(),
        share: _FakeShare(),
      );

      await _openHub(tester, router, RouteNames.ownerSettings);
      await _openLinks(tester, router);

      expect(find.byType(BookingLinkCard), findsNWidgets(2));
      expect(
        find.byKey(Key('booking-link-card-${_masterLink['slug']}')),
        findsNothing,
      );
      expect(
        find.byKey(Key('booking-link-card-${_salonA['slug']}')),
        findsOneWidget,
      );
      expect(
        find.byKey(Key('booking-link-card-${_salonB['slug']}')),
        findsOneWidget,
      );
    });
  });

  testWidgets('SALON_ADMIN: its salon card only', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()
        ..bookingLinksMine = _enabled(<Map<String, dynamic>>[_salonA]);
      final GoRouter router = await _bootAs(
        tester,
        fb,
        UserRole.salonAdmin,
        clipboard: _FakeClipboard(),
        share: _FakeShare(),
      );

      await _openHub(tester, router, RouteNames.adminSettings);
      await _openLinks(tester, router);

      expect(find.byType(BookingLinkCard), findsOneWidget);
      expect(
        find.byKey(Key('booking-link-card-${_salonA['slug']}')),
        findsOneWidget,
      );
    });
  });

  testWidgets('SALON_MASTER: no row, links never fetched', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()
        ..bookingLinksMine = _enabled(<Map<String, dynamic>>[_masterLink]);
      final GoRouter router = await _bootAs(
        tester,
        fb,
        UserRole.salonMaster,
        clipboard: _FakeClipboard(),
        share: _FakeShare(),
      );

      await _openHub(tester, router, RouteNames.salonMasterSettings);

      expect(find.byKey(_row), findsNothing);
      expect(fb.bookingLinksMineCalls, 0);
    });
  });

  for (final UserRole role in <UserRole>[
    UserRole.salonMaster,
    UserRole.client,
  ]) {
    testWidgets('${role.name}: deep link to ${RouteNames.bookingLinks} is '
        'redirected home, links never fetched', (tester) async {
      await mockNetworkImagesFor(() async {
        final FakeBackend fb = FakeBackend()
          ..bookingLinksMine = _enabled(<Map<String, dynamic>>[
            _masterLink,
            _salonA,
          ]);
        final GoRouter router = await _bootAs(
          tester,
          fb,
          role,
          clipboard: _FakeClipboard(),
          share: _FakeShare(),
        );

        router.go(RouteNames.bookingLinks);
        await AppHarness.settle(tester);

        AppHarness.expectLocation(router, roleHomePath(role));
        expect(find.byType(BookingLinkScreen), findsNothing);
        expect(fb.bookingLinksMineCalls, 0);
      });
    });
  }

  testWidgets('kill-switch off: the master hub shows no row', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend(); // default: shareEnabled false
      final GoRouter router = await _bootAs(
        tester,
        fb,
        UserRole.independentMaster,
        clipboard: _FakeClipboard(),
        share: _FakeShare(),
      );

      await _openHub(tester, router, RouteNames.masterMenu);

      expect(fb.bookingLinksMineCalls, greaterThan(0));
      expect(find.byKey(_row), findsNothing);
    });
  });
}

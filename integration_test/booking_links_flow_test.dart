// Phase 414 — «Посилання для запису» end to end (headless: `-d flutter-tester`).
//
// Real HttpBookingLinksRepository + generated client + Dio against the
// FakeBackend `GET /booking-links/mine` route; fake clipboard / share
// services (no platform channel).
//
//   • INDEPENDENT_MASTER: hub → row → screen → one MASTER card → Copy →
//     clipboard gets the bare link (418: no utm_*) + success snack; Share →
//     share text carries the same bare link.
//   • SALON_OWNER: salon card Copy + Share → bare /book/s/<slug> (418).
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
import '../test/helpers/pump_app.dart';
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

// The links repository drops any non-UUID `salonId`, so hint flows need real
// UUIDs (the shared fixtures above deliberately keep their legacy ids).
const String _uuidA = '11111111-1111-4111-8111-111111111111';
const String _uuidB = '22222222-2222-4222-8222-222222222222';

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

/// Phase 418: what reaches the clipboard / share sheet carries no query —
/// neither a `?` nor any `utm_*` key.
void _expectBareLink(String sent) {
  expect(sent, isNot(contains('?')), reason: 'no query on the shared link');
  expect(sent, isNot(contains('utm_')), reason: 'no utm_* on the link');
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

      expect(clipboard.copied, <String>['${_masterLink['url']}']);
      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(BookingLinkScreen)),
      );
      expectVelvetSnack(
        l10n.bookingLinkCopied,
        variant: VelvetSnackVariant.success,
      );
      await pumpPastVelvetSnack(tester);
      _expectBareLink(clipboard.copied.single);
    });
  });

  testWidgets('INDEPENDENT_MASTER: Share → share text carries the bare link '
      '(418: no "?" / utm_*)', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()
        ..bookingLinksMine = _enabled(<Map<String, dynamic>>[_masterLink]);
      final _FakeShare share = _FakeShare();
      final GoRouter router = await _bootAs(
        tester,
        fb,
        UserRole.independentMaster,
        clipboard: _FakeClipboard(),
        share: share,
      );

      await _openHub(tester, router, RouteNames.masterMenu);
      await _openLinks(tester, router);
      final Key btn = Key('btn-booking-link-share-${_masterLink['slug']}');
      await AppHarness.tapVisible(tester, find.byKey(btn));
      await AppHarness.settle(tester);

      final String url = '${_masterLink['url']}';
      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(BookingLinkScreen)),
      );
      expect(share.shared, <String>[l10n.bookingLinkShareTextMaster(url)]);
      _expectBareLink(share.shared.single);
    });
  });

  testWidgets('SALON_OWNER: salon card Copy + Share → bare /book/s/<slug> '
      '(418: no "?" / utm_*)', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()
        ..bookingLinksMine = _enabled(<Map<String, dynamic>>[_salonA]);
      final _FakeClipboard clipboard = _FakeClipboard();
      final _FakeShare share = _FakeShare();
      final GoRouter router = await _bootAs(
        tester,
        fb,
        UserRole.salonOwner,
        clipboard: clipboard,
        share: share,
      );

      await _openHub(tester, router, RouteNames.ownerSettings);
      await _openLinks(tester, router);
      final String slug = '${_salonA['slug']}';
      await AppHarness.tapVisible(
        tester,
        find.byKey(Key('btn-booking-link-copy-$slug')),
      );
      await pumpVelvetSnackIn(tester);
      await pumpPastVelvetSnack(tester);
      await AppHarness.tapVisible(
        tester,
        find.byKey(Key('btn-booking-link-share-$slug')),
      );
      await AppHarness.settle(tester);

      final String url = '${AppConfig.publicWebOrigin}/book/s/$slug';
      expect(clipboard.copied, <String>[url]);
      expect(share.shared, hasLength(1));
      expect(share.shared.single, endsWith(url));
      _expectBareLink(clipboard.copied.single);
      _expectBareLink(share.shared.single);
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

  testWidgets('INDEPENDENT_MASTER: services hint → services page → add a '
      'service → back → hint gone, links refetched, card bookable', (
    tester,
  ) async {
    await mockNetworkImagesFor(() async {
      const String typeId = 'type-nails-gel';
      final FakeBackend fb = FakeBackend()
        ..bookingLinksMine = _enabled(<Map<String, dynamic>>[
          <String, dynamic>{..._masterLink, 'bookable': false},
        ])
        ..bookingLinksMasterBookableFollowsServices = true
        ..bulkCreatePersists = true
        ..clearServices();
      final GoRouter router = await _bootAs(
        tester,
        fb,
        UserRole.independentMaster,
        clipboard: _FakeClipboard(),
        share: _FakeShare(),
      );

      await _openHub(tester, router, RouteNames.masterMenu);
      await _openLinks(tester, router);

      final String slug = '${_masterLink['slug']}';
      final Finder services = find.byKey(
        Key('link-booking-link-hint-services-$slug'),
      );
      final Finder schedule = find.byKey(
        Key('link-booking-link-hint-schedule-$slug'),
      );
      expect(services, findsOneWidget);
      expect(schedule, findsNothing, reason: 'schedule is seeded');
      final int callsBefore = fb.bookingLinksMineCalls;

      await AppHarness.tapVisible(tester, services);
      await AppHarness.settle(tester);
      final Finder emptyCta = find.byKey(const Key('btn-create-service-empty'));
      await tester.pumpUntilFound(emptyCta.hitTestable());
      await tester.tap(emptyCta);

      final Finder nailsChip = find.byKey(const ValueKey<String>('cat_NAILS'));
      await tester.pumpUntilFound(nailsChip.hitTestable());
      await tester.tap(nailsChip);
      final Finder row = find.byKey(const Key('setup_row_$typeId'));
      await tester.pumpUntilFound(row);
      final Finder toggle = find.byKey(const Key('setup_row_toggle_$typeId'));
      await tester.ensureVisible(toggle);
      await tester.pumpUntilFound(toggle.hitTestable());
      await tester.tap(toggle);
      final Finder duration = find.descendant(
        of: row,
        matching: find.byKey(const Key('service-setup-duration')),
      );
      final Finder price = find.descendant(
        of: row,
        matching: find.byKey(const Key('pricing-fixed-amount')),
      );
      await tester.pumpUntilFound(duration);
      await tester.pumpUntilFound(price);
      await tester.enterText(duration, '60');
      await tester.pump();
      await tester.enterText(price, '400');
      await tester.pump();
      final Finder save = find.byKey(const Key('btn-setup-save'));
      await tester.pumpUntilFound(save.hitTestable());
      await tester.tap(save);
      await AppHarness.pumpUntilCondition(
        tester,
        () => fb.bulkCreateCalls >= 1,
        description: 'the bulk service POST',
      );
      await AppHarness.settle(tester);

      // Back from the services page (it may still be on top of the stack).
      if (find.byType(BookingLinkScreen).evaluate().isEmpty) {
        router.pop();
        await AppHarness.settle(tester);
      }

      expect(find.byType(BookingLinkScreen), findsOneWidget);
      expect(services, findsNothing, reason: 'service added → hint cleared');
      expect(
        fb.bookingLinksMineCalls,
        greaterThan(callsBefore),
        reason: 'the readiness answer changed → links refetched',
      );
      expect(
        find.byKey(Key('booking-link-card-$slug')),
        findsOneWidget,
        reason: 'card still rendered after the refetch',
      );
      expect(
        find.byKey(Key('link-booking-link-setup-$slug'), skipOffstage: false),
        findsNothing,
        reason: 'refetched verdict is bookable → no generic not-bookable note',
      );
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

  testWidgets('SALON_OWNER: multi-salon → hints only on the primary-salon '
      'card (and push the owner master pages); the other keeps the generic '
      'note', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend();
      fb.mySalons = <Map<String, dynamic>>[
        <String, dynamic>{...fb.mySalons.single, 'id': _uuidA},
        <String, dynamic>{
          ...fb.mySalons.single,
          'id': _uuidB,
          'name': 'Beauty Loft',
          'isPrimary': false,
        },
      ];
      fb
        ..wireBookingLinkSalonNotReady(_uuidA)
        ..wireBookingLinkSalonNotReady(_uuidB)
        ..bookingLinksMine = _enabled(<Map<String, dynamic>>[
          <String, dynamic>{..._salonA, 'salonId': _uuidA, 'bookable': false},
          <String, dynamic>{..._salonB, 'salonId': _uuidB, 'bookable': false},
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

      final String primary = '${_salonA['slug']}';
      final String other = '${_salonB['slug']}';
      final Finder schedule = find.byKey(
        Key('link-booking-link-hint-schedule-$primary'),
      );
      expect(schedule, findsOneWidget);
      expect(
        find.byKey(Key('link-booking-link-hint-services-$primary')),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(Key('link-booking-link-setup-$other'), skipOffstage: false),
      );
      await tester.pump();
      expect(
        find.byKey(Key('link-booking-link-hint-schedule-$other')),
        findsNothing,
        reason: 'non-primary salon: owner targets act on the primary only',
      );
      expect(
        find.byKey(Key('link-booking-link-hint-services-$other')),
        findsNothing,
      );
      expect(
        find.byKey(Key('link-booking-link-setup-$other')),
        findsOneWidget,
        reason: 'the generic 414 note stays on the non-primary card',
      );

      await AppHarness.tapVisible(tester, schedule);
      await AppHarness.settle(tester);
      // The owner-master gate (not the links screen) is now on top. The fake
      // serves no roster for a UUID salon, so the gate parks on its error
      // state — the OWNER page was pushed (an owner-only subtree; the schedule
      // vs services split is pinned by the widget tests).
      expect(
        find.byType(BookingLinkScreen),
        findsNothing,
        reason: 'the pushed owner page covers the links screen',
      );
      expect(
        find.byKey(const Key('salon_master_own_services_error')),
        findsOneWidget,
      );
    });
  });

  testWidgets('SALON_ADMIN: hint target is the salon «Команда» tab', (
    tester,
  ) async {
    await mockNetworkImagesFor(() async {
      adminSalonIdOverride = _uuidA;
      addTearDown(() => adminSalonIdOverride = null);
      final FakeBackend fb = FakeBackend()
        ..wireBookingLinkSalonNotReady(_uuidA)
        ..bookingLinksMine = _enabled(<Map<String, dynamic>>[
          <String, dynamic>{..._salonA, 'salonId': _uuidA, 'bookable': false},
        ]);
      final GoRouter router = await _bootAs(
        tester,
        fb,
        UserRole.salonAdmin,
        clipboard: _FakeClipboard(),
        share: _FakeShare(),
      );

      await _openHub(tester, router, RouteNames.adminSettings);
      await _openLinks(tester, router);

      final Finder services = find.byKey(
        Key('link-booking-link-hint-services-${_salonA['slug']}'),
      );
      expect(services, findsOneWidget);
      await AppHarness.tapVisible(tester, services);
      await AppHarness.settle(tester);

      AppHarness.expectLocation(
        router,
        RouteNames.salonShell(_uuidA, openTeam: true),
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

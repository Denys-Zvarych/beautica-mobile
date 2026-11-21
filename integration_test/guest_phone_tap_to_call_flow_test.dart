// Phase 417 — E2E: «Деталі запису» shows the GUEST's phone with tap-to-call.
//
// Drives a real independent-master login through the real router against the
// fake HTTP backend: the detail GET serves `guestPhone`, the row renders under
// the client strip, and a tap launches the `tel:` URI (platform launcher
// mocked — there is no dialer under flutter-tester). The negative case seeds a
// phone onto a REGISTERED client's booking: the app must still render no row.
//
// M519 (GST-81) — a REGISTERED client's verified phone arrives as `clientPhone`
// (B518): an independent master / salon owner / salon admin sees the row
// («Телефон клієнта») and can call; an old server (no `clientPhone`) falls back
// to the guest phone; a salon master and the CLIENT viewing their own booking
// never see it, even when the fake wrongly serves it.

import 'dart:async';

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'support/app_harness.dart';

const String _phone = '+380671234567';
const String _clientPhone = '+380501112233';
const Key _rowKey = Key('booking-detail-guest-phone');

class _MockUrlLauncher extends Mock
    with MockPlatformInterfaceMixin
    implements UrlLauncherPlatform {}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late _MockUrlLauncher launcher;
  late UrlLauncherPlatform original;

  setUp(() {
    original = UrlLauncherPlatform.instance;
    launcher = _MockUrlLauncher();
    UrlLauncherPlatform.instance = launcher;
    registerFallbackValue(const LaunchOptions());
    when(() => launcher.launchUrl(any(), any())).thenAnswer((_) async => true);
  });
  tearDown(() => UrlLauncherPlatform.instance = original);

  Future<void> openDetail(
    WidgetTester tester,
    FakeBackend fb, {
    UserRole role = UserRole.independentMaster,
    String? path,
  }) async {
    final GoRouter router = await AppHarness.boot(tester, fb);
    await AppHarness.loginAs(tester, fb, role);
    unawaited(router.push(path ?? RouteNames.masterBookingDetail('booking-1')));
    await AppHarness.settle(tester);
    expect(find.byType(BookingDetailScreen), findsOneWidget);
  }

  testWidgets('guest booking: phone row renders and a tap opens the dialer', (
    tester,
  ) async {
    final fb = FakeBackend()
      ..currentRole = UserRole.independentMaster
      ..bookingClientIsGuest = true
      ..bookingGuestPhone = _phone;
    await openDetail(tester, fb);

    expect(find.byKey(_rowKey), findsOneWidget);
    expect(find.text(_phone), findsOneWidget);

    await tester.tap(find.byKey(_rowKey));
    await tester.pump();

    final String launched =
        verify(() => launcher.launchUrl(captureAny(), any())).captured.single
            as String;
    expect(launched, 'tel:$_phone');
  });

  testWidgets(
    'HARD RULE: a registered client booking shows no phone row even if the '
    'payload wrongly carries a guestPhone',
    (tester) async {
      final fb = FakeBackend()
        ..currentRole = UserRole.independentMaster
        ..bookingGuestPhone = _phone;
      await openDetail(tester, fb);

      expect(find.byKey(_rowKey), findsNothing);
      expect(find.text(_phone), findsNothing);
    },
  );

  // Phase 417 QA — the salon roles. Each journey logs in through the real
  // router, pushes that role's own detail route and reads the fake's detail
  // GET (`guestPhone` served verbatim, as the backend would for the audience).
  final Map<UserRole, String> staffPaths = <UserRole, String>{
    UserRole.salonOwner: RouteNames.salonStaffBookingDetail('booking-1'),
    UserRole.salonAdmin: RouteNames.salonStaffBookingDetail('booking-1'),
  };
  for (final MapEntry<UserRole, String> e in staffPaths.entries) {
    testWidgets('${e.key.name}: guest LINK booking shows the phone row and a '
        'tap opens the dialer', (tester) async {
      final fb = FakeBackend()
        ..currentRole = e.key
        ..bookingClientIsGuest = true
        ..bookingGuestPhone = _phone;
      await openDetail(tester, fb, role: e.key, path: e.value);

      expect(find.byKey(_rowKey), findsOneWidget);
      await tester.tap(find.byKey(_rowKey));
      await tester.pump();

      final String launched =
          verify(() => launcher.launchUrl(captureAny(), any())).captured.single
              as String;
      expect(launched, 'tel:$_phone');
    });

    testWidgets('${e.key.name}: a registered-client booking shows no row even '
        'if the payload wrongly carries a phone', (tester) async {
      final fb = FakeBackend()
        ..currentRole = e.key
        ..bookingGuestPhone = _phone;
      await openDetail(tester, fb, role: e.key, path: e.value);

      expect(find.byKey(_rowKey), findsNothing);
      expect(find.text(_phone), findsNothing);
    });
  }

  testWidgets('salonMaster: the backend sends null → no row', (tester) async {
    final fb = FakeBackend()
      ..currentRole = UserRole.salonMaster
      ..bookingClientIsGuest = true;
    await openDetail(
      tester,
      fb,
      role: UserRole.salonMaster,
      path: RouteNames.salonMasterBookingDetail('booking-1'),
    );

    expect(find.byKey(_rowKey), findsNothing);
  });

  testWidgets(
    'salonMaster DEFENCE IN DEPTH: the fake wrongly sends a guest phone → '
    'still no row, the number is never rendered',
    (tester) async {
      final fb = FakeBackend()
        ..currentRole = UserRole.salonMaster
        ..bookingClientIsGuest = true
        ..bookingGuestPhone = _phone;
      await openDetail(
        tester,
        fb,
        role: UserRole.salonMaster,
        path: RouteNames.salonMasterBookingDetail('booking-1'),
      );

      expect(find.byKey(_rowKey), findsNothing);
      expect(find.text(_phone), findsNothing);
      verifyNever(() => launcher.launchUrl(any(), any()));
    },
  );

  testWidgets('M519 salonOwner: a registered client\'s verified phone '
      '(clientPhone) shows the row and a tap opens the dialer', (tester) async {
    final fb = FakeBackend()
      ..currentRole = UserRole.salonOwner
      ..bookingClientPhone = _clientPhone;
    await openDetail(
      tester,
      fb,
      role: UserRole.salonOwner,
      path: RouteNames.salonStaffBookingDetail('booking-1'),
    );

    final AppLocalizations l10n = AppLocalizations.of(
      tester.element(find.byType(BookingDetailScreen)),
    );
    expect(find.byKey(_rowKey), findsOneWidget);
    expect(find.text(_clientPhone), findsOneWidget);
    expect(find.text(l10n.bookingDetailClientPhone), findsOneWidget);
    await tester.tap(find.byKey(_rowKey));
    await tester.pump();

    final String launched =
        verify(() => launcher.launchUrl(captureAny(), any())).captured.single
            as String;
    expect(launched, 'tel:$_clientPhone');
  });

  // M519 QA — the other two allowed roles, each on its own detail route, also
  // pin the «Телефон клієнта» caption (a registered client is not a guest).
  final Map<UserRole, String> registeredPaths = <UserRole, String>{
    UserRole.independentMaster: RouteNames.masterBookingDetail('booking-1'),
    UserRole.salonAdmin: RouteNames.salonStaffBookingDetail('booking-1'),
  };
  for (final MapEntry<UserRole, String> e in registeredPaths.entries) {
    testWidgets('M519 ${e.key.name}: a registered client\'s clientPhone shows '
        'the «Телефон клієнта» row and a tap opens the dialer', (tester) async {
      final fb = FakeBackend()
        ..currentRole = e.key
        ..bookingClientPhone = _clientPhone;
      await openDetail(tester, fb, role: e.key, path: e.value);

      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(BookingDetailScreen)),
      );
      expect(find.byKey(_rowKey), findsOneWidget);
      expect(find.text(_clientPhone), findsOneWidget);
      expect(find.text(l10n.bookingDetailClientPhone), findsOneWidget);
      expect(find.text(l10n.bookingDetailGuestPhone), findsNothing);

      await tester.tap(find.byKey(_rowKey));
      await tester.pump();

      final String launched =
          verify(() => launcher.launchUrl(captureAny(), any())).captured.single
              as String;
      expect(launched, 'tel:$_clientPhone');
    });
  }

  testWidgets('M519 old server: a guest booking without clientPhone falls back '
      'to guestPhone with the «Телефон гостя» caption', (tester) async {
    final fb = FakeBackend()
      ..currentRole = UserRole.independentMaster
      ..bookingClientIsGuest = true
      ..bookingGuestPhone = _phone;
    await openDetail(tester, fb);

    final AppLocalizations l10n = AppLocalizations.of(
      tester.element(find.byType(BookingDetailScreen)),
    );
    expect(find.text(_phone), findsOneWidget);
    expect(find.text(l10n.bookingDetailGuestPhone), findsOneWidget);
    expect(find.text(l10n.bookingDetailClientPhone), findsNothing);
  });

  testWidgets('M519 client: viewing their own booking never shows a '
      'client-phone row, even if the fake wrongly sends clientPhone', (
    tester,
  ) async {
    final fb = FakeBackend()
      ..currentRole = UserRole.client
      ..bookingClientPhone = _clientPhone;
    await openDetail(
      tester,
      fb,
      role: UserRole.client,
      path: RouteNames.bookingDetail('booking-1'),
    );

    expect(find.byKey(_rowKey), findsNothing);
    expect(find.text(_clientPhone), findsNothing);
    verifyNever(() => launcher.launchUrl(any(), any()));
  });

  testWidgets('M519 salonMaster DEFENCE IN DEPTH: the fake wrongly sends a '
      'registered client\'s clientPhone → no row, never rendered', (
    tester,
  ) async {
    final fb = FakeBackend()
      ..currentRole = UserRole.salonMaster
      ..bookingClientPhone = _clientPhone;
    await openDetail(
      tester,
      fb,
      role: UserRole.salonMaster,
      path: RouteNames.salonMasterBookingDetail('booking-1'),
    );

    expect(find.byKey(_rowKey), findsNothing);
    expect(find.text(_clientPhone), findsNothing);
    verifyNever(() => launcher.launchUrl(any(), any()));
  });
}

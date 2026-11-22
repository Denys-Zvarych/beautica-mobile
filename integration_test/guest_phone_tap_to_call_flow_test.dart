// Phase 417 / M519 — E2E: the client's phone and tap-to-call.
//
// 2026-11-21 (user): «Деталі запису» shows NO client phone for any role. The
// provider's client strip opens the M510 client card instead, and the phone
// lives there (phone chip → call / copy sheet).
//
// Drives a real login through the real router against the fake HTTP backend
// (platform launcher mocked — there is no dialer under flutter-tester):
//   • independent master, registered client → detail has no phone → tap the
//     client → `/master/clients/user/:id` → phone chip → «Зателефонувати» →
//     the canonical `tel:` URI;
//   • independent master, guest → `/master/clients/guest/:bookingId`;
//   • salon owner → the salon-scoped card (the booking's own salon);
//   • salon master → `/staff/clients/…`, and the card shows no phone even
//     when the fake wrongly serves one;
//   • a client viewing their own booking: no phone, nothing to open.

import 'dart:async';

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_client_strip.dart';
import 'package:beautica_mobile/features/clients/presentation/client_card_screen.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/phone_link.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:network_image_mock/network_image_mock.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'support/app_harness.dart';

const String _phone = '+380671234567';

/// [_phone] as DISPLAYED (UA input mask); tel: keeps the canonical value.
const String _phoneShown = '+380 67 123 45 67';
const Key _oldRowKey = Key('booking-detail-guest-phone');
const String _userId = 'u-client';

class _MockUrlLauncher extends Mock
    with MockPlatformInterfaceMixin
    implements UrlLauncherPlatform {}

/// Card bodies for the registered client ([_userId]) and the guest anchored
/// on the seeded `booking-1`, both carrying [_phone]; wired for `/masters/me`
/// and [salonId].
void _seedCards(FakeBackend fb, {String salonId = 'salon-owner-1'}) {
  fb.clientCards
    ..clear()
    ..[_userId] = <String, dynamic>{
      'kind': 'REGISTERED',
      'userId': _userId,
      'displayName': 'Дмитро Клієнт',
      'phone': _phone,
      'blocked': false,
      'ratingCount': 0,
      'ratingDistribution': <Map<String, int>>[],
    }
    ..['booking-1'] = <String, dynamic>{
      'kind': 'GUEST',
      'guestBookingId': 'booking-1',
      'displayName': 'Дмитро Гість',
      'phone': _phone,
      'blocked': false,
      'ratingCount': 0,
      'ratingDistribution': <Map<String, int>>[],
    };
  fb.wireClientCard(salonIds: <String>[salonId]);
}

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

  Future<GoRouter> openDetail(
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
    return router;
  }

  /// The detail renders no phone at all — row, number, or launch.
  void expectNoPhoneOnDetail() {
    expect(find.byKey(_oldRowKey), findsNothing);
    expect(find.text(_phoneShown), findsNothing);
    expect(find.text(_phone), findsNothing);
  }

  Future<void> openCardFromDetail(WidgetTester tester) async {
    await AppHarness.tapVisible(
      tester,
      find.byKey(BookingClientStrip.defaultShellKey),
    );
    await AppHarness.pumpUntilFound(
      tester,
      find.byKey(ClientCardScreen.nameKey),
    );
    await AppHarness.settle(tester);
  }

  Future<void> callFromCard(WidgetTester tester) async {
    final Finder chip = find.byKey(ClientCardScreen.phoneChipKey);
    expect(
      find.descendant(of: chip, matching: find.text(_phoneShown)),
      findsOneWidget,
    );
    await AppHarness.tapVisible(tester, chip);
    await AppHarness.pumpUntilFound(tester, find.byKey(kPhoneSheetCallKey));
    await AppHarness.tapVisible(tester, find.byKey(kPhoneSheetCallKey));
    await AppHarness.settle(tester);
    expect(
      verify(() => launcher.launchUrl(captureAny(), any())).captured.single,
      'tel:$_phone',
    );
  }

  testWidgets('independent master, registered client: no phone on the detail; '
      'the client strip opens the card, whose phone chip calls', (
    tester,
  ) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.independentMaster
        ..bookingRegisteredClientId = _userId
        ..bookingClientPhone = _phone
        ..bookingGuestPhone = _phone;
      _seedCards(fb);
      final GoRouter router = await openDetail(tester, fb);

      expectNoPhoneOnDetail();
      await openCardFromDetail(tester);
      AppHarness.expectLocation(router, '/master/clients/user/$_userId');
      await callFromCard(tester);
    });
  });

  testWidgets('independent master, guest: the strip opens the guest card '
      '(`…/guest/:bookingId`), whose phone chip calls', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.independentMaster
        ..bookingClientIsGuest = true
        ..bookingGuestPhone = _phone;
      _seedCards(fb);
      final GoRouter router = await openDetail(tester, fb);

      expectNoPhoneOnDetail();
      await openCardFromDetail(tester);
      AppHarness.expectLocation(router, '/master/clients/guest/booking-1');
      await callFromCard(tester);
    });
  });

  testWidgets('salon owner: no phone on the detail; the strip opens the '
      'salon-scoped card of the booking\'s own salon', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.salonOwner
        ..bookingSalonId = 'salon-owner-1'
        ..bookingSalonName = 'Салон'
        ..bookingRegisteredClientId = _userId
        ..bookingClientPhone = _phone;
      _seedCards(fb);
      final GoRouter router = await openDetail(
        tester,
        fb,
        role: UserRole.salonOwner,
        path: RouteNames.salonStaffBookingDetail('booking-1'),
      );

      expectNoPhoneOnDetail();
      await openCardFromDetail(tester);
      AppHarness.expectLocation(
        router,
        '/salons/salon-owner-1/clients/user/$_userId',
      );
      await callFromCard(tester);
    });
  });

  testWidgets('salon master: no phone on the detail; the strip opens '
      '`/staff/clients/…`, and the card shows no phone even when served', (
    tester,
  ) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.salonMaster
        ..bookingRegisteredClientId = _userId
        ..bookingClientPhone = _phone;
      _seedCards(fb);
      final GoRouter router = await openDetail(
        tester,
        fb,
        role: UserRole.salonMaster,
        path: RouteNames.salonMasterBookingDetail('booking-1'),
      );

      expectNoPhoneOnDetail();
      await openCardFromDetail(tester);
      AppHarness.expectLocation(router, '/staff/clients/user/$_userId');
      expect(find.byKey(ClientCardScreen.phoneChipKey), findsNothing);
      expect(find.text(_phoneShown), findsNothing);
      verifyNever(() => launcher.launchUrl(any(), any()));
    });
  });

  testWidgets('client viewing their own booking: no phone, no client strip '
      'to open', (tester) async {
    final FakeBackend fb = FakeBackend()
      ..currentRole = UserRole.client
      ..bookingClientPhone = _phone;
    await openDetail(
      tester,
      fb,
      role: UserRole.client,
      path: RouteNames.bookingDetail('booking-1'),
    );

    expectNoPhoneOnDetail();
    expect(find.byKey(BookingClientStrip.defaultShellKey), findsNothing);
    verifyNever(() => launcher.launchUrl(any(), any()));
  });
}

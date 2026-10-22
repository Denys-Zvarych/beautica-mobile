// Phase 417 — E2E: «Деталі запису» shows the GUEST's phone with tap-to-call.
//
// Drives a real independent-master login through the real router against the
// fake HTTP backend: the detail GET serves `guestPhone`, the row renders under
// the client strip, and a tap launches the `tel:` URI (platform launcher
// mocked — there is no dialer under flutter-tester). The negative case seeds a
// phone onto a REGISTERED client's booking: the app must still render no row.

import 'dart:async';

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
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

  Future<void> openDetail(WidgetTester tester, FakeBackend fb) async {
    final GoRouter router = await AppHarness.boot(tester, fb);
    await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
    unawaited(router.push(RouteNames.masterBookingDetail('booking-1')));
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
}

// Phase 417 — the guest phone row (tap-to-call) on «Деталі запису».
//
// HARD RULE: the row exists ONLY for a guest booking (`clientId == null`) with
// a non-null `guestPhone`, viewed by an independent master / salon owner /
// salon admin. Never for a salon master, a client, or a registered client's
// booking — even when a fixture WRONGLY carries a phone.

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booking_detail_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_display_x.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../../../helpers/booking_fixture_dates.dart';
import '../../../helpers/pump_app.dart';

const String _phone = '+380671234567';
const Key _rowKey = Key('booking-detail-guest-phone');

class _MockBookingRepository extends Mock implements BookingRepository {}

class _MockUrlLauncher extends Mock
    with MockPlatformInterfaceMixin
    implements UrlLauncherPlatform {}

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

class _StubAuth extends AuthNotifier {
  _StubAuth(this._session);
  final AuthSession _session;
  @override
  Future<AuthSession> build() async => _session;
}

Booking _booking({String? clientId, String? guestPhone = _phone}) {
  final DateTime start = futureBookingStart();
  return Booking(
    id: 'b1',
    masterId: 'm1',
    masterFirstName: 'Марія',
    masterLastName: 'Іванюк',
    masterType: 'INDEPENDENT_MASTER',
    clientId: clientId,
    clientFirstName: 'Ірина',
    clientLastName: 'Гість',
    guestPhone: guestPhone,
    serviceId: 's1',
    serviceName: 'Манікюр',
    categoryName: 'NAIL_SERVICE',
    cityLabel: 'Львів',
    durationMinutes: 90,
    price: 650,
    startAt: start,
    endAt: start.add(const Duration(minutes: 90)),
    status: BookingStatus.confirmed,
    canReview: false,
  );
}

Future<void> _pump(WidgetTester tester, Booking booking, UserRole role) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpApp(
    BookingDetailScreen(bookingId: booking.id),
    overrides: <Object>[
      screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
      bookingRepositoryProvider.overrideWithValue(_MockBookingRepository()),
      bookingDetailProvider(booking.id).overrideWith((ref) async => booking),
      authProvider.overrideWith(
        () => _StubAuth(
          AuthSession.authenticated(
            user: User(id: 'u1', email: 'u@e.com', role: role),
            accessToken: 't',
          ),
        ),
      ),
    ],
  );
  await tester.pumpAndSettle();
}

void main() {
  const List<UserRole> allowed = <UserRole>[
    UserRole.independentMaster,
    UserRole.salonOwner,
    UserRole.salonAdmin,
  ];
  const List<UserRole> denied = <UserRole>[
    UserRole.salonMaster,
    UserRole.client,
  ];

  group('guest phone row — role matrix on a guest booking', () {
    for (final UserRole role in allowed) {
      testWidgets('$role sees the phone row', (tester) async {
        await _pump(tester, _booking(), role);
        expect(find.byKey(_rowKey), findsOneWidget);
        expect(find.text(_phone), findsOneWidget);
      });
    }
    for (final UserRole role in denied) {
      testWidgets('$role never sees it, even if the data carries a phone', (
        tester,
      ) async {
        await _pump(tester, _booking(), role);
        expect(find.byKey(_rowKey), findsNothing);
        expect(find.text(_phone), findsNothing);
      });
    }
  });

  group('guest phone row — absent cases', () {
    testWidgets('anonymised guest booking (guestPhone null): no row', (
      tester,
    ) async {
      await _pump(
        tester,
        _booking(guestPhone: null),
        UserRole.independentMaster,
      );
      expect(find.byKey(_rowKey), findsNothing);
    });

    for (final UserRole role in <UserRole>[...allowed, ...denied]) {
      testWidgets(
        'HARD RULE: registered-client booking shows no row for $role even '
        'when the fixture wrongly carries a guestPhone',
        (tester) async {
          await _pump(tester, _booking(clientId: 'c1'), role);
          expect(find.byKey(_rowKey), findsNothing);
          expect(find.text(_phone), findsNothing);
        },
      );
    }
  });

  test('guestPhoneFor fails closed on an unresolved (null) role', () {
    expect(_booking().guestPhoneFor(null), isNull);
    expect(_booking().guestPhoneFor(UserRole.salonOwner), _phone);
    expect(_booking(clientId: 'c1').guestPhoneFor(UserRole.salonOwner), isNull);
  });

  group('tap-to-call', () {
    late _MockUrlLauncher launcher;
    late UrlLauncherPlatform original;

    setUp(() {
      original = UrlLauncherPlatform.instance;
      launcher = _MockUrlLauncher();
      UrlLauncherPlatform.instance = launcher;
      registerFallbackValue(const LaunchOptions());
    });
    tearDown(() => UrlLauncherPlatform.instance = original);

    testWidgets('tapping launches the tel: URI', (tester) async {
      when(
        () => launcher.launchUrl(any(), any()),
      ).thenAnswer((_) async => true);
      await _pump(tester, _booking(), UserRole.independentMaster);

      await tester.tap(find.byKey(_rowKey));
      await tester.pumpAndSettle();

      final String launched =
          verify(() => launcher.launchUrl(captureAny(), any())).captured.single
              as String;
      expect(launched, 'tel:$_phone');
    });

    testWidgets('launch failure shows the generic error snack', (tester) async {
      when(
        () => launcher.launchUrl(any(), any()),
      ).thenAnswer((_) async => false);
      await _pump(tester, _booking(), UserRole.independentMaster);

      await tester.tap(find.byKey(_rowKey));
      await tester.pumpAndSettle();

      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(BookingDetailScreen)),
      );
      expect(find.text(l10n.errUnknown), findsOneWidget);
    });
  });
}

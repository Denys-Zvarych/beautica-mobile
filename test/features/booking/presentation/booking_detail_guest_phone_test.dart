// Phase 417 — the guest phone row (tap-to-call) on «Деталі запису».
//
// HARD RULE: the row exists ONLY for a guest booking (`clientId == null`) with
// a non-null `guestPhone`, viewed by an independent master / salon owner /
// salon admin. Never for a salon master, a client, or a registered client's
// booking — even when a fixture WRONGLY carries a phone.
//
// M519 (GST-81) — a registered client's VERIFIED phone now arrives as
// `clientPhone` (B518) and renders in the same row, captioned «Телефон
// клієнта», for the same three roles only. `guestPhone` alone on a registered
// booking (a buggy/old payload) still renders nothing.

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

const String _clientPhone = '+380501112233';

Booking _booking({
  String? clientId,
  String? guestPhone = _phone,
  String? clientPhone,
}) {
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
    clientPhone: clientPhone,
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

  group('M519 — registered client verified phone (clientPhone)', () {
    Booking registered() =>
        _booking(clientId: 'c1', guestPhone: null, clientPhone: _clientPhone);

    for (final UserRole role in allowed) {
      testWidgets('$role sees the registered client\'s phone row', (
        tester,
      ) async {
        await _pump(tester, registered(), role);
        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byType(BookingDetailScreen)),
        );
        expect(find.byKey(_rowKey), findsOneWidget);
        expect(find.text(_clientPhone), findsOneWidget);
        expect(find.text(l10n.bookingDetailClientPhone), findsOneWidget);
        expect(find.text(l10n.bookingDetailGuestPhone), findsNothing);
      });
    }
    for (final UserRole role in denied) {
      testWidgets('$role never sees it, even if the data carries it', (
        tester,
      ) async {
        await _pump(tester, registered(), role);
        expect(find.byKey(_rowKey), findsNothing);
        expect(find.text(_clientPhone), findsNothing);
      });
    }

    testWidgets('a guest booking served by a B518 server (both fields) keeps '
        'the «Телефон гостя» caption', (tester) async {
      await _pump(
        tester,
        _booking(clientPhone: _phone),
        UserRole.independentMaster,
      );
      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(BookingDetailScreen)),
      );
      expect(find.text(_phone), findsOneWidget);
      expect(find.text(l10n.bookingDetailGuestPhone), findsOneWidget);
      expect(find.text(l10n.bookingDetailClientPhone), findsNothing);
    });
  });

  group('clientPhoneFor — clientPhone first, guestPhone fallback', () {
    test('prefers clientPhone over guestPhone', () {
      expect(
        _booking(clientPhone: _clientPhone).clientPhoneFor(UserRole.salonOwner),
        _clientPhone,
      );
    });

    test('old server (clientPhone null) falls back to the guest phone', () {
      expect(_booking().clientPhoneFor(UserRole.salonAdmin), _phone);
    });

    test('an empty clientPhone also falls back to the guest phone', () {
      expect(
        _booking(clientPhone: '').clientPhoneFor(UserRole.independentMaster),
        _phone,
      );
    });

    test('fallback keeps the Phase 417 guest-only rule: registered booking '
        'with only a guestPhone → null', () {
      expect(
        _booking(clientId: 'c1').clientPhoneFor(UserRole.salonOwner),
        isNull,
      );
    });

    test('role gate fails closed for salon master, client and null', () {
      final Booking b = _booking(clientId: 'c1', clientPhone: _clientPhone);
      expect(b.clientPhoneFor(UserRole.salonMaster), isNull);
      expect(b.clientPhoneFor(UserRole.client), isNull);
      expect(b.clientPhoneFor(null), isNull);
      expect(_booking().clientPhoneFor(UserRole.salonMaster), isNull);
    });
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

// «Деталі запису» — the client's phone and the route into the client card.
//
// 2026-11-21 (user): the detail shows NO client phone (no row, no number, no
// tap-to-call) for ANY role, guest or registered, even when the payload
// carries `guestPhone` / `clientPhone`. The provider's client strip opens the
// M510 client card instead (the phone lives there):
//   • registered → `<base>/user/{clientId}`, guest → `<base>/guest/{bookingId}`;
//   • base per mount: `/master/clients` (independent master),
//     `/salons/{salonId}/clients` (owner / admin — the board's salon, else the
//     booking's own), `/staff/clients` (salon master);
//   • inert for a CLIENT viewer, a mount with no card base, and an
//     anonymised («Гість») or detached («Видалений клієнт») guest-shaped row.

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
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_client_strip.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/booking_fixture_dates.dart';
import '../../../helpers/pump_app.dart';

const String _phone = '+380671234567';
const String _phoneShown = '+380 67 123 45 67';
const String _clientPhone = '+380501112233';
const String _clientPhoneShown = '+380 50 111 22 33';
const Key _oldRowKey = Key('booking-detail-guest-phone');
const Key _cardMarker = Key('test-client-card');
Finder _strip() => find.byKey(BookingClientStrip.defaultShellKey);

class _MockBookingRepository extends Mock implements BookingRepository {}

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

Booking _booking({
  String? clientId,
  String? guestPhone = _phone,
  String? clientPhone = _clientPhone,
  String? firstName = 'Ірина',
  String? lastName = 'Коваль',
  String? salonId,
}) {
  final DateTime start = futureBookingStart();
  return Booking(
    id: 'b1',
    masterId: 'm1',
    masterFirstName: 'Марія',
    masterLastName: 'Іванюк',
    masterType: 'INDEPENDENT_MASTER',
    salonId: salonId,
    clientId: clientId,
    clientFirstName: firstName,
    clientLastName: lastName,
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

/// The `clientCardBase` each production mount passes (`app_router.dart`).
String? Function(String?)? _baseFor(UserRole role) => switch (role) {
  UserRole.independentMaster => (_) => RouteNames.masterClients,
  UserRole.salonOwner || UserRole.salonAdmin =>
    (String? salonId) =>
        salonId == null ? null : RouteNames.salonClients(salonId),
  UserRole.salonMaster => (_) => RouteNames.salonMasterClients,
  UserRole.client => null,
};

/// Mounts the detail at `/detail` with [role]'s card base (or [base]); every
/// card path renders a marker carrying the matched location.
Future<GoRouter> _pump(
  WidgetTester tester,
  Booking booking,
  UserRole role, {
  String? boardSalonId,
  bool useRoleBase = true,
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final GoRouter router = GoRouter(
    initialLocation: '/detail',
    routes: <RouteBase>[
      GoRoute(
        path: '/detail',
        builder: (_, _) => BookingDetailScreen(
          bookingId: booking.id,
          salonId: boardSalonId,
          clientCardBase: useRoleBase ? _baseFor(role) : null,
        ),
      ),
      GoRoute(
        path: '/:a/:b/:c/:d',
        builder: (_, GoRouterState s) => Text(s.uri.path, key: _cardMarker),
      ),
      GoRoute(
        path: '/:a/:b/:c/:d/:e',
        builder: (_, GoRouterState s) => Text(s.uri.path, key: _cardMarker),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpRoutedApp(
    router,
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
  return router;
}

Future<String?> _tapStrip(WidgetTester tester) async {
  await tester.tap(_strip());
  await tester.pumpAndSettle();
  final Finder marker = find.byKey(_cardMarker);
  if (marker.evaluate().isEmpty) return null;
  return tester.widget<Text>(marker).data;
}

void main() {
  const List<UserRole> allRoles = UserRole.values;

  group('no phone on «Деталі запису» for any role', () {
    for (final UserRole role in allRoles) {
      testWidgets('$role, guest booking carrying guestPhone + clientPhone', (
        tester,
      ) async {
        await _pump(tester, _booking(clientPhone: _phone), role);
        expect(find.byKey(_oldRowKey), findsNothing);
        expect(find.text(_phoneShown), findsNothing);
        expect(find.text(_phone), findsNothing);
      });
      testWidgets('$role, registered booking carrying clientPhone', (
        tester,
      ) async {
        await _pump(tester, _booking(clientId: 'c1'), role);
        expect(find.byKey(_oldRowKey), findsNothing);
        expect(find.text(_clientPhoneShown), findsNothing);
        expect(find.text(_clientPhone), findsNothing);
      });
    }
  });

  group('the client strip opens the client card', () {
    final Map<UserRole, String> registered = <UserRole, String>{
      UserRole.independentMaster: '/master/clients/user/c1',
      UserRole.salonOwner: '/salons/s1/clients/user/c1',
      UserRole.salonAdmin: '/salons/s1/clients/user/c1',
      UserRole.salonMaster: '/staff/clients/user/c1',
    };
    for (final MapEntry<UserRole, String> e in registered.entries) {
      testWidgets('${e.key}: registered → ${e.value}', (tester) async {
        await _pump(tester, _booking(clientId: 'c1', salonId: 's1'), e.key);
        expect(await _tapStrip(tester), e.value);
      });
    }

    final Map<UserRole, String> guest = <UserRole, String>{
      UserRole.independentMaster: '/master/clients/guest/b1',
      UserRole.salonOwner: '/salons/s1/clients/guest/b1',
      UserRole.salonAdmin: '/salons/s1/clients/guest/b1',
      UserRole.salonMaster: '/staff/clients/guest/b1',
    };
    for (final MapEntry<UserRole, String> e in guest.entries) {
      testWidgets('${e.key}: guest → ${e.value}', (tester) async {
        await _pump(tester, _booking(salonId: 's1'), e.key);
        expect(await _tapStrip(tester), e.value);
      });
    }

    testWidgets('salon mount: the board salon (extra) wins over the '
        'booking\'s own salonId', (tester) async {
      await _pump(
        tester,
        _booking(clientId: 'c1', salonId: 's1'),
        UserRole.salonOwner,
        boardSalonId: 'board-s',
      );
      expect(await _tapStrip(tester), '/salons/board-s/clients/user/c1');
    });

    testWidgets('salon mount with no salon id at all → inert strip', (
      tester,
    ) async {
      await _pump(tester, _booking(clientId: 'c1'), UserRole.salonOwner);
      expect(await _tapStrip(tester), isNull);
      expect(find.byType(BookingDetailScreen), findsOneWidget);
    });

    testWidgets('a mount with no card base (client mounts) → inert', (
      tester,
    ) async {
      await _pump(
        tester,
        _booking(clientId: 'c1'),
        UserRole.independentMaster,
        useRoleBase: false,
      );
      expect(await _tapStrip(tester), isNull);
    });

    testWidgets('a CLIENT viewer sees the master strip, never the client '
        'strip', (tester) async {
      await _pump(tester, _booking(clientId: 'c1'), UserRole.client);
      expect(_strip(), findsNothing);
    });

    for (final String sentinel in <String>[
      kAnonymisedGuestName,
      kDetachedClientName,
    ]) {
      testWidgets('«$sentinel» guest row (no card can exist) → inert', (
        tester,
      ) async {
        await _pump(
          tester,
          _booking(firstName: sentinel, lastName: null, guestPhone: null),
          UserRole.independentMaster,
        );
        expect(_strip(), findsOneWidget);
        expect(await _tapStrip(tester), isNull);
      });
    }
  });

  group('BookingDisplayX.clientCardReachable', () {
    test('registered client is always reachable', () {
      expect(
        _booking(
          clientId: 'c1',
          firstName: kAnonymisedGuestName,
          lastName: null,
        ).clientCardReachable,
        isTrue,
      );
    });
    test('named guest is reachable; sentinel guests are not', () {
      expect(_booking().clientCardReachable, isTrue);
      expect(
        _booking(
          firstName: kAnonymisedGuestName,
          lastName: null,
        ).clientCardReachable,
        isFalse,
      );
      expect(
        _booking(
          firstName: kDetachedClientName,
          lastName: null,
        ).clientCardReachable,
        isFalse,
      );
    });
  });
}

// Phase 259 — DIRECT unit coverage for `isBookingWalkInSeed` /
// `isBookingProviderSeed`, plus mounted-router pins for the master's own
// WALK-IN («Новий запис») admission onto `/booking/slots`.
//
// Mirrors `booking_reschedule_seed_test.dart`'s pure-function coverage for
// the sibling predicate this phase adds, and `booking_route_guard_test.dart`'s
// mounted-router pattern for the guard's mounted-route pins — resolved page
// TYPE, never a path string
// (`project_gorouter_literal_before_dynamic_shadowing`: declaration order,
// not the assertion shape, is the only thing making a literal route win over
// a `:param` sibling, so a path-string assertion here would prove nothing).
//
// `isBookingRescheduleSeed`'s OWN test file (`booking_reschedule_seed_test.dart`)
// is intentionally left untouched by this phase — see phase-259 D2 and its
// acceptance criteria.

import 'package:beautica_mobile/core/app_start_time.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/domain/booking_confirm_args.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot_picker_args.dart';
import 'package:beautica_mobile/features/booking/domain/booking_success_args.dart';
import 'package:beautica_mobile/features/booking/domain/create_master_booking_request.dart';
import 'package:beautica_mobile/features/booking/presentation/slot_picker_screen.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/routing/booking_reschedule_seed.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fakes/fake_auth_repository.dart';
import '../helpers/fakes/fake_master_repository.dart';
import '../helpers/fakes/fake_secure_storage.dart';
import '../helpers/fakes/fake_service_repository.dart';
import '../helpers/fakes/fake_slot_repository.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const String _kMasterId = 'master-1';

const _kMaster = Master(
  id: _kMasterId,
  firstName: 'Test',
  lastName: 'Master',
  avgRating: 0,
  reviewCount: 0,
  type: MasterType.independentMaster,
);

const _kService = MasterService(
  id: 'svc-1',
  serviceDefId: 'def-1',
  name: 'Манікюр з покриттям',
  durationMinutes: 60,
  priceMin: 500,
  priceDisplay: '500 ₴',
  category: 'NAILS',
);

const WalkInGuest _kGuest = WalkInGuest(
  name: 'Іван',
  surname: 'Петренко',
  phone: '+380501234567',
);

BookingSlotPickerArgs _walkInArgs() => const BookingSlotPickerArgs(
  masterId: _kMasterId,
  master: _kMaster,
  services: <MasterService>[_kService],
  guest: _kGuest,
  hideMasterIdentity: true,
);

BookingConfirmArgs _walkInConfirmArgs() => BookingConfirmArgs(
  masterId: _kMasterId,
  master: _kMaster,
  services: const <MasterService>[_kService],
  startAt: DateTime.utc(2026, 7, 20, 10),
  idempotencyKey: 'walkin-key-1',
  guest: _kGuest,
  hideMasterIdentity: true,
);

BookingSuccessArgs _walkInSuccessArgs() => BookingSuccessArgs(
  master: _kMaster,
  services: const <MasterService>[_kService],
  startAt: DateTime.utc(2026, 7, 20, 10),
  isWalkIn: true,
);

/// A CREATE-shaped client seed — no guest, `hideMasterIdentity` unset. Must
/// still bounce a non-client viewer.
BookingSlotPickerArgs _createArgs() => const BookingSlotPickerArgs(
  masterId: _kMasterId,
  master: _kMaster,
  services: <MasterService>[_kService],
);

const String _kRescheduleBookingId = 'bkg-reschedule-1';

/// The pre-existing reschedule-shaped seed — regression pin for D2 (the
/// admission this phase must NOT break while adding the walk-in sibling).
BookingSlotPickerArgs _rescheduleArgs() => const BookingSlotPickerArgs(
  masterId: _kMasterId,
  master: _kMaster,
  services: <MasterService>[_kService],
  rescheduleBookingId: _kRescheduleBookingId,
);

const _masterUser = User(
  id: 'm1',
  email: 'master@example.com',
  role: UserRole.independentMaster,
  firstName: 'Master',
  lastName: 'User',
);
const _masterSession = AsyncData<AuthSession>(
  AuthSession.authenticated(user: _masterUser, accessToken: 'token'),
);

/// [AuthNotifier] stub that immediately settles to a fixed [AsyncValue] —
/// mirrors `booking_route_guard_test.dart`'s `_FixedAuthNotifier`.
class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this._fixed);

  final AsyncValue<AuthSession> _fixed;

  @override
  Future<AuthSession> build() async {
    state = _fixed;
    return _fixed.value ?? const AuthSession.unauthenticated();
  }
}

/// [MasterProfile] stub that resolves immediately — same leaked-timer
/// regression `booking_route_guard_test.dart` documents for the
/// INDEPENDENT_MASTER redirect target (`/master/profile`, `roleHomePath`'s
/// landing for that role).
class _SettledMasterProfileNotifier extends MasterProfile {
  @override
  Future<Master> build() async => const Master(
    id: 'm1',
    firstName: 'Master',
    lastName: 'User',
    avgRating: 0,
    reviewCount: 0,
    type: MasterType.independentMaster,
  );
}

/// [MaterialApp.router] wrapper for the real [appRouter] with l10n delegates.
class _RouterApp extends StatelessWidget {
  const _RouterApp({required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    routerConfig: router,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('uk', 'UA'),
  );
}

void main() {
  group('isBookingWalkInSeed', () {
    test('should_returnTrue_when_extraIsSlotPickerArgsWithGuest', () {
      expect(isBookingWalkInSeed(_walkInArgs()), isTrue);
    });

    test('should_returnFalse_when_extraIsSlotPickerArgsWithoutGuest', () {
      expect(isBookingWalkInSeed(_createArgs()), isFalse);
    });

    test('should_returnFalse_when_extraIsNull', () {
      expect(isBookingWalkInSeed(null), isFalse);
    });

    test('should_returnFalse_when_extraIsAForeignType', () {
      expect(isBookingWalkInSeed('bkg-1'), isFalse);
    });

    test('should_returnTrue_when_successArgsIsWalkIn', () {
      expect(isBookingWalkInSeed(_walkInSuccessArgs()), isTrue);
    });

    test('should_returnTrue_when_confirmArgsHasGuest', () {
      expect(isBookingWalkInSeed(_walkInConfirmArgs()), isTrue);
    });

    test('should_returnFalse_when_successArgsIsNotWalkIn', () {
      expect(
        isBookingWalkInSeed(
          BookingSuccessArgs(
            master: _kMaster,
            services: const <MasterService>[_kService],
            startAt: DateTime.utc(2026, 7, 20, 10),
          ),
        ),
        isFalse,
      );
    });
  });

  group('isBookingProviderSeed', () {
    test('is true for a reschedule-shaped seed', () {
      expect(isBookingProviderSeed(_rescheduleArgs()), isTrue);
    });

    test('is true for a walk-in-shaped seed', () {
      expect(isBookingProviderSeed(_walkInArgs()), isTrue);
    });

    test('is false for a CREATE-shaped client seed', () {
      expect(isBookingProviderSeed(_createArgs()), isFalse);
    });

    test('is false for a null extra (the deep-link case)', () {
      expect(isBookingProviderSeed(null), isFalse);
    });

    test('is false for a foreign type', () {
      expect(isBookingProviderSeed(42), isFalse);
    });
  });

  group('mounted-router admission onto /booking/slots', () {
    // Park the splash gate in the past so authRedirect does not pin the
    // router on /splash waiting for AppStartTime.minSplashDuration to elapse
    // — mirrors booking_route_guard_test.dart's setUp.
    setUp(
      () => AppStartTime.setStartForTest(
        DateTime.now().subtract(const Duration(seconds: 5)),
      ),
    );
    tearDown(AppStartTime.resetForTest);

    ProviderContainer makeContainer(AsyncValue<AuthSession> session) {
      final container = ProviderContainer(
        // Disables Riverpod's default retry backoff — mirrors
        // booking_route_guard_test.dart's rationale (avoids a leaked Timer
        // from unrelated failed reads on the bounce target's screen tree).
        retry: (_, _) => null,
        overrides: [
          authProvider.overrideWith(() => _FixedAuthNotifier(session)),
          authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
          secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
          // Settles the INDEPENDENT_MASTER redirect target (/master/profile)
          // synchronously — leaked-timer regression, see
          // booking_route_guard_test.dart's identical override.
          masterProfileProvider.overrideWith(_SettledMasterProfileNotifier.new),
          masterRepositoryProvider.overrideWith((_) => FakeMasterRepository()),
          // /master/profile also watches servicesListProvider ->
          // serviceRepositoryProvider — same leaked-timer shape.
          serviceRepositoryProvider.overrideWith(
            (_) => FakeServiceRepository(),
          ),
          // SlotDateScreen unconditionally watches workingDaysProvider ->
          // slotRepositoryProvider — settling it avoids a real Dio call
          // leaking a connection-timeout Timer past teardown.
          slotRepositoryProvider.overrideWith((_) => FakeSlotRepository()),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    // Every call site below drives router.go(...), never context.push — the
    // go_router push-drop trap (raw read reporting the PRE-push location
    // forever) only applies to ImperativeRouteMatch, which .go() never
    // produces. Mirrors booking_route_guard_test.dart's own locationOf,
    // grandfathered for the identical reason.
    String locationOf(GoRouter router) =>
        // router-location-ok: .go()-only call sites, see comment above.
        router.routerDelegate.currentConfiguration.uri.toString();

    Future<GoRouter> pumpRouterAs(
      WidgetTester tester,
      AsyncValue<AuthSession> session,
    ) async {
      final container = makeContainer(session);
      final router = container.read(appRouterProvider);
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _RouterApp(router: router),
        ),
      );
      await tester.pumpAndSettle();
      return router;
    }

    testWidgets('should_admitMaster_when_walkInSeedPushedToBookingSlots', (
      tester,
    ) async {
      final router = await pumpRouterAs(tester, _masterSession);

      router.go(RouteNames.bookingSlots, extra: _walkInArgs());
      await tester.pumpAndSettle();

      // Pinned by page TYPE, never by path string
      // (project_gorouter_literal_before_dynamic_shadowing).
      expect(find.byType(SlotDateScreen), findsOneWidget);
    });

    testWidgets('should_stillBounceMaster_when_createSeedHasNoGuest', (
      tester,
    ) async {
      final router = await pumpRouterAs(tester, _masterSession);

      router.go(RouteNames.bookingSlots, extra: _createArgs());
      await tester.pumpAndSettle();

      expect(find.byType(SlotDateScreen), findsNothing);
      expect(locationOf(router), equals(RouteNames.masterProfile));
    });

    testWidgets('should_stillBounceMaster_when_pushingBookingNew', (
      tester,
    ) async {
      final router = await pumpRouterAs(tester, _masterSession);

      // /booking/new stays fully CLIENT-only regardless of extra (D4) — a
      // walk-in-shaped extra would not even parse as the String masterId
      // that route expects, but the point pinned here is the ROLE bounce,
      // which fires before the extra shape is even inspected.
      router.go(RouteNames.bookingNew, extra: _kMasterId);
      await tester.pumpAndSettle();

      expect(locationOf(router), equals(RouteNames.masterProfile));
    });

    testWidgets('should_admitMaster_when_rescheduleSeedPushedToBookingSlots', (
      tester,
    ) async {
      final router = await pumpRouterAs(tester, _masterSession);

      router.go(RouteNames.bookingSlots, extra: _rescheduleArgs());
      await tester.pumpAndSettle();

      expect(find.byType(SlotDateScreen), findsOneWidget);
    });
  });
}

// Sentry 162160464 (prod 1.9.1+13) — `TypeError: Null check operator used on
// a null value` in the `/booking/new` builder (`extra! as String`).
//
// WHY
// ---------------------------------------------------------------------------
// A `refreshListenable` tick makes go_router re-parse the last reported route
// stack. The router has no `extraCodec`, so that restore hands every pushed
// page a `null` in place of its non-JSON `extra`, and route-level `redirect:`
// guards (which would bounce a bad `extra`) do not run on it. Each booking
// builder then crashed on `state.extra! as X`.
//
// Since the M517 port (`authRouterKey`) a profile-only auth emission no
// longer refreshes the router, but a REAL key change still does. This file
// fires one (the CLIENT's `salonId` — a key field no CLIENT redirect reads,
// so the top-level redirect keeps the stack instead of parking on /splash
// the way an `isLoading` toggle would) over the full typed client booking
// stack and asserts that:
//   * no builder throws — every page whose `extra` was dropped renders the
//     `_MissingRouteExtra` fallback instead;
//   * the broken pages unwind one pop at a time (success → time → slots →
//     /booking/new → the page the flow was opened from) without throwing.
// A control case pins that a profile-only emission (new token) leaves the
// stack and its typed args untouched.
//
// HARNESS: the REAL `appRouterProvider` + the same synchronous data overrides
// as `booking_route_guard_test.dart` (see its header for the leaked-timer
// rationale behind each one), with an `AuthNotifier` whose state the test
// assigns directly.
//
// FALSIFIED (2026-11-18): with the `/booking/*` builders put back to
// `state.extra! as X`, the key-change case goes RED on the null check.

import 'dart:async';

import 'package:beautica_mobile/core/app_start_time.dart';
import 'package:beautica_mobile/core/media/portfolio/portfolio_notifier.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/slot_picker_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/domain/booking_confirm_args.dart';
import 'package:beautica_mobile/features/booking/domain/booking_entry_args.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot_picker_args.dart';
import 'package:beautica_mobile/features/booking/domain/booking_success_args.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_success_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/service_selector_sheet.dart';
import 'package:beautica_mobile/features/booking_links/presentation/booking_link_setup_hints_provider.dart';
import 'package:beautica_mobile/features/booking_links/presentation/master_nav_setup_hints_provider.dart';
import 'package:beautica_mobile/features/master/application/public_master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/rating/application/my_rating_notifier.dart';
import 'package:beautica_mobile/features/rating/domain/client_rating.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/wishlist/application/wishlist_notifier.dart';
import 'package:beautica_mobile/features/wishlist/domain/wishlist_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fakes/fake_auth_repository.dart';
import '../helpers/fakes/fake_master_repository.dart';
import '../helpers/fakes/fake_media_upload_repository.dart';
import '../helpers/fakes/fake_secure_storage.dart';
import '../helpers/fakes/fake_service_repository.dart';
import '../helpers/fakes/fake_slot_repository.dart';
import '../helpers/test_container.dart';

const String _kMasterId = 'master-1';

const Master _kMaster = Master(
  id: _kMasterId,
  firstName: 'Test',
  lastName: 'Master',
  avgRating: 0,
  reviewCount: 0,
  type: MasterType.independentMaster,
);

const MasterService _kService = MasterService(
  id: 'svc-1',
  serviceDefId: 'def-1',
  name: 'Манікюр з покриттям',
  durationMinutes: 60,
  priceMin: 500,
  priceDisplay: '500 ₴',
  category: 'NAILS',
);

const BookingEntryArgs _entryArgs = BookingEntryArgs(
  masterId: _kMasterId,
  preselectedServiceId: 'svc-1',
  autoAdvance: false,
);

const BookingSlotPickerArgs _slotArgs = BookingSlotPickerArgs(
  masterId: _kMasterId,
  master: _kMaster,
  services: <MasterService>[_kService],
);

BookingConfirmArgs _confirmArgs() => BookingConfirmArgs(
  masterId: _kMasterId,
  master: _kMaster,
  services: const <MasterService>[_kService],
  startAt: DateTime.utc(2026, 7, 20, 10),
  idempotencyKey: 'refresh-key-1',
);

BookingSuccessArgs _successArgs() => BookingSuccessArgs(
  master: _kMaster,
  services: const <MasterService>[_kService],
  startAt: DateTime.utc(2026, 7, 20, 10),
);

const User _client = User(
  id: 'c1',
  email: 'client@example.com',
  role: UserRole.client,
  firstName: 'Client',
  lastName: 'User',
);

AuthSession _session(User user, {String token = 'token-0'}) =>
    AuthSession.authenticated(user: user, accessToken: token);

/// Settles to the CLIENT session; the test then assigns `state` directly, the
/// way production `AuthNotifier` does after a token refresh.
class _SettableAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async => _session(_client);

  void emit(AuthSession session) => state = AsyncData<AuthSession>(session);
}

class _SettledWishlistNotifier extends Wishlist {
  @override
  Future<List<WishlistService>> build() async => const <WishlistService>[];
}

/// Pre-seeds a selected date so `SlotTimeScreen` mounts (its broken-flow
/// self-pop guard fires on a null date) — see `booking_route_guard_test.dart`.
class _SettledSlotPickerNotifier extends SlotPicker {
  @override
  SlotPickerState build() =>
      SlotPickerState(selectedDate: kyivToday(DateTime.now));
}

const Key _fallbackKey = Key('route_missing_extra_fallback');

void main() {
  setUp(
    () => AppStartTime.setStartForTest(
      DateTime.now().subtract(const Duration(seconds: 5)),
    ),
  );
  tearDown(AppStartTime.resetForTest);

  late _SettableAuthNotifier auth;

  Future<GoRouter> pumpRouter(WidgetTester tester) async {
    auth = _SettableAuthNotifier();
    final ProviderContainer container = makeTestContainer(
      retry: (_, _) => null,
      overrides: [
        masterNavSetupHintsProvider.overrideWithValue(
          BookingLinkSetupHints.none,
        ),
        portfolioProvider.overrideWith2((_) => FixedPortfolioNotifier()),
        authProvider.overrideWith(() => auth),
        authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
        secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
        publicMasterProfileProvider(
          _kMasterId,
        ).overrideWith((ref) => (_kMaster, const <MasterService>[_kService])),
        approvedCategoriesProvider.overrideWith(
          (ref) async => const <ServiceCategoryOption>[],
        ),
        wishlistProvider.overrideWith(_SettledWishlistNotifier.new),
        masterRepositoryProvider.overrideWith((_) => FakeMasterRepository()),
        serviceRepositoryProvider.overrideWith((_) => FakeServiceRepository()),
        slotRepositoryProvider.overrideWith((_) => FakeSlotRepository()),
        slotPickerProvider.overrideWith(_SettledSlotPickerNotifier.new),
        myRatingProvider.overrideWith((ref) async => const ClientRating()),
      ],
    );
    final GoRouter router = container.read(appRouterProvider);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('uk', 'UA'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(router.state.matchedLocation, RouteNames.clientHome);
    return router;
  }

  /// entry → slots → time → confirm, then the real `pushReplacement` of
  /// confirm by success — the exact client booking stack.
  Future<void> pushBookingStack(WidgetTester tester, GoRouter router) async {
    unawaited(router.push<void>(RouteNames.bookingNew, extra: _entryArgs));
    await tester.pumpAndSettle();
    expect(find.byType(ServiceSelectorSheet), findsOneWidget);
    unawaited(router.push<void>(RouteNames.bookingSlots, extra: _slotArgs));
    await tester.pumpAndSettle();
    unawaited(router.push<void>(RouteNames.bookingSlotsTime, extra: _slotArgs));
    await tester.pumpAndSettle();
    unawaited(
      router.push<void>(RouteNames.bookingConfirm, extra: _confirmArgs()),
    );
    await tester.pumpAndSettle();
    unawaited(
      router.pushReplacement<void>(
        RouteNames.bookingSuccess,
        extra: _successArgs(),
      ),
    );
    await tester.pumpAndSettle();
    expect(router.state.matchedLocation, RouteNames.bookingSuccess);
    expect(find.byType(BookingSuccessScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  }

  testWidgets(
    'redirect-key change over the typed booking stack: no builder throws and '
    'the extra-less pages unwind past /booking/new',
    (tester) async {
      final GoRouter router = await pumpRouter(tester);
      await pushBookingStack(tester, router);

      // A REAL router-key change (salonId) — the refreshListenable fires and
      // go_router restores the stack with every non-JSON `extra` dropped.
      auth.emit(_session(_client.copyWith(salonId: 'salon-x')));

      // Frame by frame, so a throw on any page of the unwind — including the
      // pop that lands on /booking/new — is caught at the frame it happens.
      final List<String> visited = <String>[];
      for (int i = 0; i < 200; i++) {
        // fixed-wait-ok: a frame-step clock, not a guess at completion — the
        // loop exits on the settled state; the step only advances the pop
        // transitions so each frame's exception is checked where it happens.
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull, reason: 'frame $i');
        final String loc = router.state.matchedLocation;
        if (visited.isEmpty || visited.last != loc) visited.add(loc);
        if (!tester.binding.hasScheduledFrame && loc == RouteNames.clientHome) {
          break;
        }
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // The fallback stood in for the dropped args and popped each broken
      // page in turn, through /booking/new, back to where the flow began.
      expect(visited, contains(RouteNames.bookingNew));
      expect(visited.last, RouteNames.clientHome);
      expect(router.state.matchedLocation, RouteNames.clientHome);
      expect(find.byKey(_fallbackKey), findsNothing);
      expect(find.byType(ServiceSelectorSheet), findsNothing);
    },
  );

  testWidgets(
    'profile-only emission (new token) leaves the booking stack and its '
    'typed args intact',
    (tester) async {
      final GoRouter router = await pumpRouter(tester);
      await pushBookingStack(tester, router);

      auth.emit(_session(_client, token: 'token-refreshed'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(router.state.matchedLocation, RouteNames.bookingSuccess);
      expect(find.byType(BookingSuccessScreen), findsOneWidget);
      expect(find.byKey(_fallbackKey), findsNothing);
    },
  );
}

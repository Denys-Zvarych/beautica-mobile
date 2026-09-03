// mobile-qa (swipe-to-delete audit, 2026-09-03) — E2E: owner swipes a salon
// card on «Мої салони» to delete it.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b)
// ----------------------------------------
// The security re-audit that promoted `isSalonOwnerProvider`
// (`auth/presentation/auth_selectors.dart`) also introduced swipe-to-delete
// on `MySalonsScreen` (`_HubContent`'s `Dismissible`). Before this file,
// NOTHING exercised the gesture against a REAL router + a REAL (fake) DELETE
// round trip: `my_salons_screen_test.dart` covers the widget in isolation
// with a stubbed `mySalonsProvider`/`salonRepositoryProvider`, never a real
// `Dio` request through `FakeBackend`. This flow drives: owner swipes a
// card -> confirms -> the salon is genuinely deleted server-side (a real
// `DELETE /api/v1/salons/salon-xyz` round trip) -> the hub re-fetches and
// renders the remaining salon.
//
// NO PATROL FLOW: nothing here touches an OS permission dialog, deep link,
// notification, WebView, or biometric — this is a pure screen/route/
// gesture/DELETE surface, so Step 2.7 Rule 3b's `integration_test/patrol/`
// requirement does not apply (mobile-qa explicit statement, mirrors
// `salon_management_profile_flow_test.dart`'s own header on this point).
//
// FIXED (mobile-qa CRITICAL finding, 2026-09-03) — this flow used to be
// unable to complete: `SalonManagementProfile.deleteSalon()`
// (`salon_management_profile_notifier.dart`) calls
// `ref.invalidate(mySalonsProvider)` on its own `Ref`, but
// `salonManagementProfileProvider(salonId)` is an `@riverpod` (autoDispose)
// family that NOTHING in `MySalonsScreen`'s tree watches. Once the real
// `Dio` round trip spans more than a single frame (every real HTTP call
// does), Riverpod used to dispose the unwatched family element before
// `deleteSalon()` resumed, and `ref.invalidate` threw
// `UnmountedRefException` — crashing the delete. Every OTHER caller of
// `runDeleteSalonFlow` (`SettingsScreen`, `SalonSettingsScreen`) reaches it
// from a screen that already watches that same family member for display,
// which incidentally keeps it alive; the swipe path was the FIRST caller
// that did not. See `test/features/salon/presentation/my_salons_screen_test
// .dart`'s in-flight-overlay test for the widget-tier reproduction
// (deterministic there via a gated `FakeSalonRepository`).
//
// `deleteSalon()` now calls `ref.keepAlive()` before the awaited repository
// call (closed in `finally`), pinning the element alive for the mutation
// regardless of who is watching. This flow is un-skipped and wired into
// `all_tests.dart` / `all_tests_part2.dart` (see those files' headers for
// the part1/part2 split convention — this flow was added to part2,
// alongside the other salon/support flows).

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/salon/presentation/my_salons_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

/// The default single-primary salon `FakeBackend` seeds `GET /salons/mine`
/// with (`fake_backend.dart`'s `mySalons` fixture).
const String _primarySalonId = 'salon-owner-1';

/// `FakeBackend`'s `DELETE /api/v1/salons/{salonId}` handler is registered
/// against this EXACT literal path (`fake_backend.dart` — no `salonId`
/// regex), so the salon being swiped away must carry this id.
const String _deletableSalonId = 'salon-xyz';

/// Seeds a second, non-primary salon (`salon-xyz`) into `mySalons` — see
/// `salon_management_profile_flow_test.dart`'s own `_seedSalonXyzIntoMySalons`
/// for the identical rationale (that file's private helper cannot be
/// imported, so this is a deliberate, minimal duplicate of the SAME
/// fixture shape, not a fork of behaviour).
void _seedDeletableSalon(FakeBackend fb) {
  fb.mySalons.add(<String, dynamic>{
    'id': _deletableSalonId,
    'ownerId': 'user-owner-1',
    'name': 'Студія Краси «Камелія»',
    'city': 'Київ',
    'cityId': 'city-kyiv',
    'oblastId': 'oblast-kyiv',
    'street': 'вул. Хрещатик',
    'buildingNo': '12',
    'isActive': true,
    'isPrimary': false,
  });
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'owner swipes a salon card -> confirms -> the salon is deleted -> lands '
    'on «Мої салони» with the remaining salon',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.salonOwner;
      _seedDeletableSalon(fb);
      final GoRouter router = await AppHarness.boot(tester, fb);

      await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
      await AppHarness.settle(tester);

      // Fresh login lands the owner on the primary salon's shell
      // (`salon_owner_landing_flow_test.dart` owns that assertion) — drive
      // straight to the hub, mirroring
      // `salon_management_profile_flow_test.dart`'s own `router.go(...)`
      // convention for entering a surface this flow does not itself own the
      // navigation path to.
      router.go(RouteNames.mySalons);
      await tester.pumpAndSettle();
      AppHarness.expectLocation(router, RouteNames.mySalons);
      expect(find.byType(MySalonsScreen), findsOneWidget);

      final Finder dismissible = find.byKey(
        const ValueKey<String>('my_salons_dismissible_$_deletableSalonId'),
      );
      expect(
        dismissible,
        findsOneWidget,
        reason:
            'the seeded non-primary salon must render as a swipeable '
            'card for an owner',
      );

      await tester.fling(dismissible, const Offset(-500, 0), 1000);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('delete-salon-dialog')),
        findsOneWidget,
        reason: 'the swipe must land on the confirm dialog before deleting',
      );
      expect(fb.deleteSalonCalls, 0);

      await tester.tap(find.byKey(const Key('btn-confirm-delete-salon')));
      await tester.pumpAndSettle();

      expect(
        fb.deleteSalonCalls,
        1,
        reason:
            'the real DELETE /api/v1/salons/$_deletableSalonId must '
            'have fired',
      );
      expect(
        fb.mySalons.any(
          (Map<String, dynamic> s) => s['id'] == _deletableSalonId,
        ),
        isFalse,
        reason: 'the fake backend removes the salon on a successful delete',
      );

      AppHarness.expectLocation(router, RouteNames.mySalons);
      expect(
        find.byKey(const ValueKey<String>('my_salons_card_$_deletableSalonId')),
        findsNothing,
        reason: 'the deleted salon must stop rendering',
      );
      expect(
        find.byKey(const ValueKey<String>('my_salons_card_$_primarySalonId')),
        findsOneWidget,
        reason: 'the remaining (primary) salon must still render',
      );
    },
  );
}

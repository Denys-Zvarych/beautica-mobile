// Phase 264 — `WalkInGuestStepScreen` must acquire/release the app-wide
// `ScreenProtectionManager` (mobile-security audit finding, MEDIUM).
//
// WHY THIS FILE EXISTS
// --------------------
// This screen collects a walk-in guest's name and phone — third-party PII
// typed by the MASTER, not the guest — via the shared `ClientStep`. The fix
// added `ref.read(screenProtectionProvider)..acquire()` in `initState` and
// `_screenProtection.release()` as the first statement in `dispose()`
// (`walk_in_guest_step_screen.dart`). Every existing test for this screen
// (`walk_in_guest_step_screen_test.dart`) pumps through `pumpRoutedApp`
// WITHOUT overriding `screenProtectionProvider`, so it silently rides the
// real (no-op-on-non-Android/iOS-test-harness) manager — none of those 6
// tests would fail if `acquire()`/`release()` were deleted tomorrow. This
// file is the one that would.
//
// Mirrors `booking_detail_screen_protection_test.dart`'s
// `_CountingScreenProtection` shape exactly — asserted directly against the
// call, not inferred from a rendering side effect, per the backlog's
// race/guard trap (a test that branches on the thing under test cannot
// fail).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/booking/presentation/walk_in_guest_step_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';

import '../../../helpers/pump_app.dart';

class _CountingScreenProtection extends ScreenProtectionManager {
  int acquires = 0;
  int releases = 0;

  @override
  void acquire() => acquires++;

  @override
  void release() => releases++;
}

GoRouter _router() => GoRouter(
  initialLocation: RouteNames.masterBookingNew,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.masterBookingNew,
      builder: (context, state) => const WalkInGuestStepScreen(),
    ),
  ],
);

void main() {
  testWidgets(
    '«Новий запис» guest step acquires screen protection on mount and '
    'releases it on dispose',
    (tester) async {
      final _CountingScreenProtection protection = _CountingScreenProtection();

      await tester.pumpRoutedApp(
        _router(),
        overrides: <Object>[
          screenProtectionProvider.overrideWithValue(protection),
        ],
      );
      await tester.pumpAndSettle();

      expect(
        protection.acquires,
        1,
        reason:
            'the guest step collects a third-party (the walk-in guest, not '
            'the master) name and phone number — it must hold protection '
            'for its lifetime, same as the booking detail screen',
      );
      expect(protection.releases, 0, reason: 'nothing has been disposed yet');

      // Tear the screen down the way a pop back to the caller does.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      expect(
        protection.releases,
        1,
        reason:
            'a leaked acquire leaves the app-switcher blur on for the rest '
            'of the session, app-wide, long after the PII surface is gone',
      );
    },
  );
}

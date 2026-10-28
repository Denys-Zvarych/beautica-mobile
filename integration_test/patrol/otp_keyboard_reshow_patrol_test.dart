// Branch fix/login-unverified-403 — native E2E: OTP keyboard re-show.
//
// THE BUG
// -------
// On Android the user hides the soft keyboard (system back, or the IME's own
// hide key) on an OTP screen. The hidden OTP TextField KEEPS focus, so a tap on
// a code cell used to call `focusNode.requestFocus()` — a no-op on an already
// focused node — and the keyboard never came back. The fix is
// `OtpCodeField._onTap` (lib/features/auth/presentation/widgets/
// otp_code_field.dart): when the field already has focus it invokes
// `TextInput.show` instead.
//
// The headless sibling (integration_test/legal_links_and_otp_keyboard_flow_test
// .dart, Test 3) drives the framework's TestTextInput MOCK, so it proves the
// Dart call is made, not that a real Android IME reappears. This flow is the
// real-IME half.
//
// WHAT THIS FLOW DOES
// -------------------
//   1. Boots the fake-backend app (PatrolHarness), logs in as an UNVERIFIED
//      account (FakeBackend(loginEmailNotVerified: true) → real 403 body
//      through the real ErrorMapperInterceptor) and takes the banner action
//      to /verification. Credentials are typed while the TestTextInput mock
//      is still registered (the shared boot policy needs it for enterText in
//      profile mode); the mock is then UNREGISTERED before navigating, so the
//      VerificationScreen's autofocus attaches to the REAL Android IME.
//   2. Asserts the real IME is up on arrival.
//   3. `$.platform.android.pressBack()` — a real system back. Back closes the IME first
//      and must NOT pop the route: asserts IME down, focus kept, still on
//      /verification. This is exactly the bug's starting state.
//   4. Taps the FIRST visible code cell (not the row centre, which is the 1x1
//      hidden TextField).
//   5. Asserts the real IME is up again.
//
// HOW "THE IME IS UP" IS OBSERVED — AND THE LIMITATION
// ----------------------------------------------------
// patrol 4.7.1 (pubspec.lock) has NO keyboard-visibility API: there is no
// `$.native.isKeyboardVisible` / `$.platform.*` equivalent. Its native typing
// (`$.native.enterText` / `enterTextByIndex`) is UiAutomator
// `UiObject.setText`, i.e. accessibility ACTION_SET_TEXT — it writes the
// field directly and BYPASSES the IME (Automator.kt `enterText`), so it would
// pass with the keyboard hidden and proves nothing here. The only key-event
// call is `sendKeyboardEnter`; there is no way to press digit keys. So digits
// CANNOT be typed through the real IME in this patrol version.
//
// The signal used instead is the engine-reported IME inset:
// `$.tester.view.viewInsets.bottom`. TestFlutterView passes the REAL
// FlutterView's insets through (nothing here fakes them), and on Android those
// come from the IME WindowInsets the OS reports for the soft keyboard window.
// It is a native signal, not the TestTextInput mock: it is > 0 only while the
// OS actually shows a soft keyboard over the app.
//
// It is asserted TWO-SIDED (0 after back, > 0 after the tap), so the final
// assertion cannot pass on an inset that simply never went away.
//
// NOT MUTATION-VERIFIED LOCALLY: patrol runs only on the CI emulator. The
// expected red on reverting `_onTap` to plain `focusNode.requestFocus()` is
// step 5 timing out with inset 0; confirm on CI before trusting a green.
//
// CI PREREQUISITE: an emulator with a HARDWARE keyboard (AVD default) hides
// the soft IME unless `settings secure show_ime_with_hard_keyboard` is 1. The
// patrol job sets it (pr-validate.yml, docs/ci/patrol.md#patrol-soft-ime).
// Step 2 fails loudly, with that hint, if the soft keyboard never appears.
//
// HOW TO RUN (native instrumentation — NOT `flutter test`):
//   patrol test --target integration_test/patrol/otp_keyboard_reshow_patrol_test.dart
// Android only; skipped elsewhere.

import 'dart:io' show Platform;

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:patrol/patrol.dart';

import '../support/app_harness.dart' show AppHarness;
import 'support/patrol_harness.dart';

const ValueKey<String> _otpInput = ValueKey<String>('verify_code_input');
const ValueKey<String> _bannerAction = ValueKey<String>('auth_banner_action');

/// Polls the engine-reported IME inset until it matches [visible] or ~8 s
/// pass. Returns the last observed inset (physical px). Bounded by an
/// iteration count, not a clock read.
Future<double> _awaitImeInset(
  PatrolIntegrationTester $, {
  required bool visible,
}) async {
  double inset = $.tester.view.viewInsets.bottom;
  for (int i = 0; i < 80 && (inset > 0) != visible; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await $.tester.pump();
    inset = $.tester.view.viewInsets.bottom;
  }
  return inset;
}

void main() {
  const config = PatrolTesterConfig(settlePolicy: SettlePolicy.trySettle);

  tearDown(PatrolHarness.tearDownHarness);

  patrolTest(
    'OTP verification: after a native back hides the soft keyboard, '
    'tapping a code cell brings the real IME back',
    config: config,
    skip: !Platform.isAndroid,
    ($) async {
      final fb = FakeBackend(loginEmailNotVerified: true);
      final GoRouter router = await PatrolHarness.boot($, fb);

      await PatrolHarness.loginAs($, fb, UserRole.independentMaster);
      AppHarness.expectLocation(router, RouteNames.login);

      // From here on every TextInput call goes to the REAL platform IME.
      $.tester.binding.testTextInput.unregister();

      await AppHarness.tapVisible($.tester, find.byKey(_bannerAction));
      await AppHarness.settle($.tester);
      AppHarness.expectLocation(router, RouteNames.verification);

      final FocusNode otpFocus = $.tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(_otpInput),
              matching: find.byType(EditableText),
            ),
          )
          .focusNode;
      expect(otpFocus.hasFocus, isTrue, reason: 'autofocus on arrival');

      // 2. Real IME up on arrival.
      expect(
        await _awaitImeInset($, visible: true),
        greaterThan(0),
        reason:
            'the soft keyboard never appeared on arrival — if the emulator has '
            'a hardware keyboard, show_ime_with_hard_keyboard must be 1',
      );

      // 3. Native back closes the IME, keeps focus, does not pop the route.
      await $.platform.android.pressBack();
      expect(
        await _awaitImeInset($, visible: false),
        0,
        reason: 'system back must dismiss the soft keyboard',
      );
      AppHarness.expectLocation(router, RouteNames.verification);
      expect(
        otpFocus.hasFocus,
        isTrue,
        reason: 'the bug state: IME hidden while the OTP field keeps focus',
      );

      // 4. Tap the first visible code CELL — not the row centre (the 1x1
      // hidden TextField) and not the row's blank padding.
      final Finder otpRow = find
          .ancestor(
            of: find.byKey(_otpInput),
            matching: find.byType(GestureDetector),
          )
          .first;
      final Finder firstCell = find
          .descendant(of: otpRow, matching: find.byType(AnimatedContainer))
          .first;
      await $.tester.tap(firstCell);
      await $.tester.pump();

      // 5. Real IME back.
      expect(
        await _awaitImeInset($, visible: true),
        greaterThan(0),
        reason: 'tapping a code cell must re-show the real soft keyboard',
      );
      expect(otpFocus.hasFocus, isTrue);
      AppHarness.expectLocation(router, RouteNames.verification);
    },
  );
}

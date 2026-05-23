# Mobile QA Backlog

Low and Info severity findings that do not block merge. Address in next iteration or when the affected file is next touched.

---

## LOW — Stale comment in auth_gradient_background_test.dart

**File:** `test/features/auth/presentation/auth_gradient_background_test.dart` (lines 1–12, file header)

**Finding:** The file header comment still describes the painter as using `canvas.drawCircle() + RadialGradient.createShader()` — the previous implementation. The current painter uses `canvas.drawRect()` only. The test code itself is correct; only the prose comment is stale.

**Fix:** Update the comment to say `canvas.drawRect()` (already partially done in the header rewrite during QA audit 2026-05-17; the body comment on line 8 in the original was the specific stale line).

**Pattern:** M2-adjacent (comment accuracy, not a test gap).

**Added:** 2026-05-17 | **Audit:** auth_gradient_background drawRect redesign

---

## LOW — No sigma-value assertion existed when _RegGlassCard._kBlur changed from 20 to 12

**File:** `lib/features/auth/presentation/register_screen.dart` — `_RegGlassCard._kBlur` (line 1048)
`test/features/auth/presentation/register_screen_test.dart`

**Finding:** The sigmaX/sigmaY reduction (20 → 12) shipped with no test that would have caught a future reversion. The existing 31-case suite covered all functional flows but had zero assertions on render-budget elements. A future commit could silently restore sigma 20 (or add a fifth `BackdropFilter` layer) and all tests would stay green.

**Fix applied:** Test case 32 added to `register_screen_test.dart` — asserts `find.byType(BackdropFilter).evaluate().length <= 4` on the role-selection step. This acts as a ceiling: any new glassmorphism layer on that view will fail the test and force an explicit budget decision.

**Pattern:** M8-adjacent (render-budget regression path via BackdropFilter count, not golden device coverage).

**Added:** 2026-05-17 | **Audit:** register_screen _kBlur sigma 20→12 QA pass

---

## LOW — scripts/run_local.sh MODE argument has no whitelist guard (mobile-security)

**File:** `scripts/run_local.sh:22`

**Finding:** `MODE="${1:-debug}"` is interpolated directly as `flutter run --$MODE` with no validation. A caller passing a malformed arg (e.g. `"debug --dart-define=KEY=evil"`) could inject additional flags. Development-only script; attack surface is limited to shell-access developers. Flutter rejects unknown flags, so production impact is nil.

**Fix:** Add a `case` guard immediately after the assignment:
```bash
case "$MODE" in
  debug|profile|release) ;;
  *) echo "Usage: $0 [debug|profile|release]" >&2; exit 1 ;;
esac
```

**Pattern:** MS-adjacent (arg injection, dev script only).

**Added:** 2026-05-17 | **Audit:** run_local.sh MODE flag security audit

---

## LOW — login_screen.dart _GlassCard sigma=20 (single layer, intentional) (mobile-perf)

**File:** `lib/features/auth/presentation/login_screen.dart:716`

**Finding:** `_GlassCard._kBlur` sigmaX/Y=20 is the only BackdropFilter on the login screen. A prior reduction to 12 under-blurred visually. No action needed unless DevTools frame profiling shows drops on the login route.

**Pattern:** MP-adjacent (blur budget, single-layer screen — acceptable).

**Added:** 2026-05-17 | **Audit:** BackdropFilter inventory scan

---

## LOW — settings_screen.dart AppBar + tile both sigma=20; monitor when tile list grows (mobile-perf)

**File:** `lib/features/settings/presentation/settings_screen.dart:52,191`

**Finding:** AppBar blur (sigma=20) and list tile card blur (sigma=20) are two concurrent BackdropFilter layers. Current tile count is 1 — acceptable. If Phase 5+ adds 3-4+ tiles, reduce tile sigma to 12.

**Pattern:** MP-adjacent (blur budget, scale-dependent).

**Added:** 2026-05-17 | **Audit:** BackdropFilter inventory scan

---

## LOW — verification_screen_test.dart uses tester.pump(Duration(seconds: 91)) for timer test

**File:** `test/features/auth/presentation/verification_screen_test.dart:197` (Test 3)

**Finding:** Pattern M6-adjacent — fixed-duration pump rather than `pumpAndSettle`. However this is the only correct approach because the resend countdown `Timer` fires `setState` every second, permanently preventing `pumpAndSettle` from settling. The inline comment documents this rationale. No change required; flagged for awareness when the timer implementation changes.

**Pattern:** M6-adjacent (justified exception — documented inline).

**Added:** 2026-05-17 | **Audit:** Phase 2.11 email verification screen re-audit

---

## LOW — No test asserts email masking in VerificationScreen

**File:** `test/features/auth/presentation/verification_screen_test.dart`

**Finding:** The `email` value passed via `GoRouterState.extra` is displayed in masked form (e.g., `a***@example.com`). No test asserts the masking widget (`Key('verification-email-hint')`) renders the correct masked value. If the masking logic regresses silently, all tests remain green.

**Fix (next iteration):** Add a test that pumps `_makeRouter(email: 'alice@example.com')` and asserts the masked-email widget renders the expected string (or asserts the widget is present via its key). Requires adding `Key('verification-email-hint')` to the source widget if not already present.

**Pattern:** M3-adjacent (data-binding assertion gap on the loaded state).

**Added:** 2026-05-17 | **Audit:** Phase 2.11 email verification screen re-audit

---

## LOW — verification_screen_test.dart does not assert the OTP value passed to repo.verifyEmail

**File:** `test/features/auth/presentation/verification_screen_test.dart` (Test 4 — verify success)

**Finding:** Test 4 confirms that a successful `verifyEmail` call navigates to `/done`, but never asserts what OTP value was forwarded to the repository. `FakeAuthRepository.verifyEmailCalls` captures the `(email, otp)` pair on every call. A future regression where the notifier passes an empty string or the wrong box values would still navigate successfully and leave all 10 tests green.

**Fix (next iteration):** After the tap in Test 4, add:
```dart
expect(repo.verifyEmailCalls, hasLength(1));
expect(repo.verifyEmailCalls.first.otp, equals('654321'));
expect(repo.verifyEmailCalls.first.email, equals(_testEmail));
```

**Pattern:** M4-adjacent (missing strict argument assertion on a domain-significant value — the OTP itself).

**Added:** 2026-05-17 | **Audit:** Phase 2.11 backlog fix pass re-audit

---

## LOW — verification_screen_test.dart has no test for resend failure path

**File:** `test/features/auth/presentation/verification_screen_test.dart`

**Finding:** Test 3b asserts that tapping `btn-resend` clears the OTP boxes and hides the button (timer restarts). It does not simulate a failure from `resendVerificationCode`. If `_resend()` catches a `Failure` and sets `_inlineError`, that error state is untested. `FakeAuthRepository.resendVerificationResult` supports this scenario via `resendVerificationResult = const NetworkFailure()`.

**Fix (next iteration):** Add a test that advances the timer to 0, taps `btn-resend`, and asserts an inline error is rendered (matching `l10n.verificationError` or `l10n.verificationServiceUnavailable`).

**Pattern:** M3-adjacent (error state of the resend action untested).

**Added:** 2026-05-17 | **Audit:** Phase 2.11 backlog fix pass re-audit

---

## LOW — VelvetLogo compact-size test uses an indirect Container height filter (M4-adjacent)

**File:** `test/core/widgets/neumorphic_test.dart` — VelvetLogo group, test 2

**Finding:** The `compact: true` assertion locates pillow Containers by filtering for square aspect ratio and height > 40 px, then compares sorted heights. This is correct but fragile if any other square Container enters the widget tree (e.g., a prefix icon or future pillow variant). A `Key` added to the pillow Container in the source (`Key('velvet_logo_pillow')`) would make the assertion direct.

**Fix (next iteration):** Add `key: const Key('velvet_logo_pillow')` to the pillow `Container` in `VelvetLogo.build`. Update the test to `tester.getSize(find.byKey(Key('velvet_logo_pillow')))` and compare directly.

**Pattern:** M4-adjacent (indirect assertion on a render-budget dimension).

**Added:** 2026-05-23 | **Audit:** Phase 1.6 neumorphic widget library QA audit

---

## LOW — NeumorphicTextField missing enableInteractiveSelection: false when obscured (mobile-security)

**File:** `lib/core/widgets/neumorphic.dart` — `_NeumorphicTextFieldState` (inner TextField)

**Finding:** When `obscureToggle: true` and `_obscured == true`, the inner `TextField` does not set `enableInteractiveSelection: false`. On some Android OEM keyboards the long-press context menu on an obscured field offers "Select All" and may reveal content via the clipboard path. Defense-in-depth only — no direct exploit path today.

**Fix (next iteration):** Pass `enableInteractiveSelection: !_obscured` to the inner `TextField`. Restore to `true` when `_obscured == false` so revealed-password fields remain normally selectable.

**Pattern:** MS-adjacent (MASVS-PLATFORM, context menu hardening on password fields).

**Added:** 2026-05-23 | **Audit:** Phase 1.6 neumorphic widget library security audit

---

## LOW — NeumorphicTextField autofillHints passthrough lacks obscureToggle pairing assert (mobile-security)

**File:** `lib/core/widgets/neumorphic.dart` — `NeumorphicTextField` constructor

**Finding:** `autofillHints` is an unguarded passthrough. A caller could pass `AutofillHints.password` on a field without `obscureToggle: true`, silently exposing password content in the OS suggestion strip above the keyboard. No current call site does this (zero call sites outside the definition file as of Phase 1.6).

**Fix (next iteration):** Add a debug `assert` before any call site wires this widget to live auth screens:
```dart
assert(
  autofillHints == null ||
  obscureToggle ||
  !autofillHints!.any((h) => h == AutofillHints.password || h == AutofillHints.newPassword),
  'Use obscureToggle: true when passing password autofillHints',
);
```

**Pattern:** MS-adjacent (MASVS-PLATFORM, autofill contract).

**Added:** 2026-05-23 | **Audit:** Phase 1.6 neumorphic widget library security audit

---

## LOW — _InsetShadowPainter.paint() allocates Paint + RRect objects per repaint (mobile-perf)

**File:** `lib/core/widgets/neumorphic.dart` — `_InsetShadowPainter.paint()` (~line 50–74)

**Finding:** Three `Paint` objects and one `RRect` are allocated on-stack on every `paint()` call. `shouldRepaint` correctly returns `false` when `radius` is unchanged (auth screens — never changes at runtime), so the painter does not repaint at steady state. GC churn is effectively zero in practice. No action required unless profiling shows allocation pressure on a screen with many inset fields.

**Fix (next iteration):** Hoist the three `Paint` instances to `final` fields on the painter class, initialized once in the constructor. The `RRect` can remain local (it depends on `size` which varies).

**Pattern:** MP-adjacent (GC allocation, zero steady-state impact).

**Added:** 2026-05-23 | **Audit:** Phase 1.6 neumorphic widget library perf audit

---

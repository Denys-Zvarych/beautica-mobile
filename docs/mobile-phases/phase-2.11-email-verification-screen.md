# Phase 2.11 — Email Verification Screen ✅ COMPLETE

> ⚠️ **VelvetTouch redesign (2026-05-22) — Status reset to PENDING.**
> The previous implementation shipped the functional OTP screen with glassmorphism styling + 4-pill progress indicator. All visual structure is replaced by the VelvetTouch neumorphic design. Auth behavior (OTP submit, resend, 429 throttle, error handling) is unchanged.

## Status
- `VerificationScreen` ✅ implemented (`lib/features/auth/presentation/verification_screen.dart`)
- `VerificationScreenTest` ✅ implemented (16 tests — all passing)
- QA score: 83/100 | Completed: 2026-05-23

## Goal
Redesign the `VerificationScreen` to the VelvetTouch visual language. Port structure verbatim from `docs/signup-designs/VelvetTouchDesign/lib/screens/verify_email_screen.dart`.

**Design source of truth:** `docs/signup-designs/VelvetTouchDesign/lib/screens/verify_email_screen.dart` — transcribe literally.

**Key VelvetTouch elements:**
- `AuthScaffold(showBack: true)` wrapping the screen
- `VelvetHeader()` at top
- `NeumorphicCard` containing the 6-digit OTP entry row (6 × `NeumorphicInset` cells)
- Resend code countdown + link (`VelvetText.link()`)
- `NeumorphicButton(label: 'Підтвердити')` CTA
- Error / success inline feedback via `AuthBanner` or inline text

## Prerequisites
- Phase 1.6 (Neumorphic widget library).
- Phase 2.4 (AuthNotifier — `verifyEmail` + `resendCode` methods).
- Phase 2.5 (Login screen redesigned — `AuthScaffold` pattern established).

## Implementation Steps

### Step 1 — Replace visual shell
**File:** `lib/features/auth/presentation/verification_screen.dart`
**Action:** Modify
**Details:** Replace the existing scaffold (glassmorphism card, `BackdropFilter`, 4-pill progress row) with `AuthScaffold`. Transcribe the VelvetTouch OTP entry layout verbatim — 6 `NeumorphicInset` cells in a Row, keyboard `TextInputType.number`.

### Step 2 — Wire existing notifier methods
**Details:** `AuthNotifier.verifyEmail()` and `AuthNotifier.resendCode()` calls remain unchanged. Only the visual layer changes. The `email` parameter is passed down from the navigation argument exactly as before.

### Step 3 — Update tests
**File:** `test/features/auth/presentation/verification_screen_test.dart`
**Action:** Modify
**Details:** Update widget keys to match VelvetTouch source keys. Retain all behavioral tests (submit on 6-digit entry, resend shows countdown, 429 throttle feedback, error feedback). Regenerate goldens after ground-truth render diff.

## Files to create / modify
- `lib/features/auth/presentation/verification_screen.dart` (modify)
- `test/features/auth/presentation/verification_screen_test.dart` (modify)

## Test Cases

### Unit
_(none — all logic exercised through widget tests; `_errorMessage` dispatch covered by tests 5, 5b, 5c)_

### Widget
- `1.` filling 6 digits enables the verify NeumorphicButton (onPressed non-null)
- `2.` fewer than 6 digits keeps verify NeumorphicButton disabled (onPressed null)
- `3.` resend link hidden while countdown active, visible when timer = 0
- `3b.` tapping verify_resend clears OTP input and restarts the countdown
- `3b-ext.` tapping verify_resend passes the screen email to resendVerificationCode (strict arg match)
- `3c.` resend 429 (ResendThrottledFailure) adopts server retryAfterSeconds
- `4.` verify success navigates away from verification screen
- `4b.` verify success persists refresh token and arrives at home
- `5.` verify failure (VerificationFailure.invalidCode) shows inline verificationErrInvalidCode copy
- `5b.` AuthBanner appears after a verify failure sets _inlineError
- `5c.` VerificationFailure.alreadyVerified shows verificationErrAlreadyVerified inline copy (not invalidCode)
- `6.` back link navigates to /register/step-3
- `7.` no BackdropFilter widgets on screen (VelvetTouch has no glassmorphism)
- `7b.` hidden OTP TextField (verify_code_input) has correct settings
- `8.` NeumorphicButton verify_submit is disabled while authProvider is AsyncLoading
- `9.` Verification copy renders as a progress-active-label

### Golden
_(deferred — visual regression on OTP cells and NeumorphicButton states tracked in backlog)_

### Integration
_(deferred — verify end-to-end OTP flow in master_flow_test.dart)_

## Acceptance Criteria
- [x] Screen uses `AuthScaffold(showBack: true)` — no raw `Scaffold` with dark background
- [x] 6 `NeumorphicInset` cells for OTP entry — no old `TextFormField` row
- [x] `NeumorphicButton` CTA — no old gradient `DecoratedBox` CTA
- [x] No `BackdropFilter` / glassmorphism in this file
- [x] Resend countdown logic unchanged; existing `AuthNotifier.resendCode()` wired
- [x] `flutter analyze --no-fatal-infos` → 0 errors, 0 warnings
- [x] `flutter test test/features/auth/presentation/verification_screen_test.dart` → all green
- [ ] `mobile-perf` score ≥ 70
- [ ] `mobile-security` score ≥ 70
- [x] `mobile-qa` score ≥ 70 with no CRITICAL/HIGH/MEDIUM findings

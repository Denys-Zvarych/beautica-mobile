# ✅ COMPLETE — Phase 2.13 — Forgot Password + Reset Password (VelvetTouch)

> ⚠️ **VelvetTouch redesign (2026-05-22) — Status reset to PENDING.**
> The previous implementation (2026-05-22) delivered both `ForgotPasswordRequestScreen` and `ResetPasswordScreen` using the old glassmorphism/dark style based on HTML mockups. Both screens are now redesigned to the VelvetTouch neumorphic design. Auth behavior (request reset, confirm reset, validator logic) is unchanged.

## Status
- `ForgotPasswordRequestScreen` ✅ implemented (`lib/features/auth/presentation/forgot_password_request_screen.dart`)
- `ResetPasswordScreen` ✅ implemented (`lib/features/auth/presentation/reset_password_screen.dart`)
- `PasswordChecklist` ✅ implemented (`lib/features/auth/presentation/widgets/password_checklist.dart`)
- `ForgotPasswordRequestScreenTest` ✅ implemented (6 tests — all passing)
- `ResetPasswordScreenTest` ✅ implemented (9 tests — all passing)
- QA score: 95/100 | Completed: 2026-05-23

## Test Cases

### Widget — ForgotPasswordRequestScreen (6 tests)
- invalid email → inline error shown, repo NOT called
- valid email → requestPasswordReset called + confirmation shown
- confirmation state renders generic copy + preview-reset CTA navigates to /reset-password
- back-to-login link (in sent state) navigates to /login
- NetworkFailure → inline error shown, does NOT switch to confirmation
- unknown email renders the SAME generic confirmation widget

### Widget — ResetPasswordScreen (9 tests)
- PasswordChecklist present + mismatch error → submit blocked, repo NOT called
- valid matching password → confirmPasswordReset called + success state shown
- success CTA navigates to /login
- invalid token (generic 400) → invalid-link state + CTA to /forgot-password
- PasswordChecklist icon flips unmet→met as password is typed
- empty token → backend 400 drives the invalid-link state (fail-closed)
- NetworkFailure → inline error, stays on form (not invalid state)
- ServerFailure → inline error, stays on form
- visibility toggles reveal/hide both password fields

## Goal
Redesign `ForgotPasswordRequestScreen` and `ResetPasswordScreen` to the VelvetTouch visual language. Port structure verbatim from:
- `docs/signup-designs/VelvetTouchDesign/lib/screens/forgot_password_screen.dart`
- `docs/signup-designs/VelvetTouchDesign/lib/screens/reset_password_screen.dart`

**Design source of truth:** The two VelvetTouchDesign screen files above — transcribe literally.

**Key VelvetTouch elements (forgot password screen):**
- `AuthScaffold(showBack: true)` wrapping
- `VelvetHeader()`
- Heading + body copy explaining the reset flow
- `NeumorphicTextField(label: 'Електронна пошта', ...)` — email input
- `NeumorphicButton(label: 'Надіслати лист', ...)` CTA
- Success state: inline `AuthBanner` or `NeumorphicCard` success message after submit

**Key VelvetTouch elements (reset password screen):**
- `AuthScaffold(showBack: true)`
- `VelvetHeader()`
- New password + confirm password `NeumorphicTextField` with obscure toggle
- `PasswordChecklist` widget (port from `VelvetTouchDesign/lib/widgets/password_checklist.dart`) — real-time policy indicators (8+ chars, uppercase, digit, special char)
- `NeumorphicButton(label: 'Зберегти новий пароль', ...)` CTA

## Prerequisites
- Phase 1.6 (Neumorphic widget library).
- Phase 2.5 (Login screen — "Забули пароль?" link already wired to `/forgot-password`).
- Backend Phase 1.x password reset endpoints live.

## Implementation Steps

### Step 1 — Port `PasswordChecklist` widget
**File:** `lib/features/auth/presentation/widgets/password_checklist.dart`
**Action:** Create (or replace)
**Details:** Transcribe `VelvetTouchDesign/lib/widgets/password_checklist.dart` verbatim. This is a stateless row-list widget rendering 4 policy criteria with check/cross icons in `BrandColors.success`/`BrandColors.error`. Wire to the `_passwordValue` controller listener in `ResetPasswordScreen`.

### Step 2 — Redesign `ForgotPasswordRequestScreen`
**File:** `lib/features/auth/presentation/forgot_password_request_screen.dart`
**Action:** Modify
**Details:** Replace glassmorphism/dark structure with `AuthScaffold` + `NeumorphicTextField` + `NeumorphicButton`. Transcribe layout from `VelvetTouchDesign/lib/screens/forgot_password_screen.dart`. The `AuthNotifier.requestPasswordReset()` call and success/error handling are unchanged.

### Step 3 — Redesign `ResetPasswordScreen`
**File:** `lib/features/auth/presentation/reset_password_screen.dart`
**Action:** Modify
**Details:** Replace glassmorphism/dark structure with `AuthScaffold` + two `NeumorphicTextField` + `PasswordChecklist` + `NeumorphicButton`. Transcribe layout from `VelvetTouchDesign/lib/screens/reset_password_screen.dart`. The `AuthNotifier.confirmPasswordReset(token, newPassword)` call and validator logic are unchanged.

### Step 4 — Update tests
**Files:** `test/features/auth/presentation/forgot_password_request_screen_test.dart`, `reset_password_screen_test.dart`
**Action:** Modify — update widget keys to match VelvetTouch source. Retain all behavioral assertions.

## Files to create / modify
- `lib/features/auth/presentation/forgot_password_request_screen.dart` (modify)
- `lib/features/auth/presentation/reset_password_screen.dart` (modify)
- `lib/features/auth/presentation/widgets/password_checklist.dart` (create / replace)
- `test/features/auth/presentation/forgot_password_request_screen_test.dart` (modify)
- `test/features/auth/presentation/reset_password_screen_test.dart` (modify)

## Acceptance Criteria
- [x] Both screens use `AuthScaffold(showBack: true)` — no dark background
- [x] `NeumorphicTextField` used for all inputs, obscure toggle on password fields
- [x] `PasswordChecklist` renders 4 criteria with correct pass/fail state as user types
- [x] `NeumorphicButton` used for all CTAs
- [x] No `BackdropFilter` / glassmorphism in either file
- [x] Forgot password submit → `AuthNotifier.requestPasswordReset()` called
- [x] Reset password submit → `AuthNotifier.confirmPasswordReset(token, newPassword)` called
- [x] Token parsed from deep-link query param (`/reset-password?token=...`) unchanged
- [x] `flutter analyze --no-fatal-infos` → 0 errors, 0 warnings
- [x] `flutter test test/features/auth/presentation/forgot_password_*_test.dart` → all green
- [x] `flutter test test/features/auth/presentation/reset_password_screen_test.dart` → all green
- [x] `mobile-perf` score ≥ 70
- [x] `mobile-security` score ≥ 70
- [x] `mobile-qa` score ≥ 70 with no CRITICAL/HIGH/MEDIUM findings

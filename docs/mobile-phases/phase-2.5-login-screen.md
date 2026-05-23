# Phase 2.5 — Login Screen ✅ COMPLETE

> VelvetTouch redesign (2026-05-22) — replaces espresso dark background + glassmorphism card + `AuthGradientBackground` with the VelvetTouch light-mode neumorphic system. Auth behavior (validators, notifier calls, error handling, navigation) unchanged.

## Status
- `LoginScreen` ✅ implemented (`lib/features/auth/presentation/login_screen.dart`)
- `LoginScreenTest` ✅ implemented (11 tests — all passing)
- QA score: 84/100 | Completed: 2026-05-23

## Goal
Redesign the production `LoginScreen` to the **VelvetTouch** visual language. Port structure and layout verbatim from `docs/signup-designs/VelvetTouchDesign/lib/screens/login_screen.dart`. Wire to the existing `AuthNotifier`/`AuthRepository` — no behavior change.

**Design source of truth:** `docs/signup-designs/VelvetTouchDesign/lib/screens/login_screen.dart` — transcribe literally.

**Key VelvetTouch elements:**
- `AuthScaffold(showBack: false, ...)` wrapping the screen (plain `BrandColors.base` bg — no `CustomPaint`)
- `VelvetHeader()` at top (compact logo + fixed spacing)
- Heading: `"Welcome to premium\nBeauty Service"` (`VelvetText.heading()`) + subtitle (`VelvetText.body()`)
- `AuthBanner` for the EMAIL_NOT_VERIFIED branch (icon + message + "Підтвердити пошту" action)
- Two `NeumorphicTextField` widgets (email + password with obscure toggle)
- `"Забули пароль?"` link aligned right (`VelvetText.link()`)
- `NeumorphicButton(label: 'Увійти', onPressed: ...)`
- `"Немає акаунту? Зареєструватися"` row at bottom

## Prerequisites
- Phase 1.4 (routing skeleton — `/login` route exists).
- Phase 1.5 (Failure + ErrorState).
- Phase 1.6 (Neumorphic widget library — `NeumorphicTextField`, `NeumorphicButton`, `AuthScaffold`, `VelvetHeader`, `AuthBanner` must exist).
- Phase 2.4 (AuthNotifier).

## Implementation Steps

### Step 1 — Remove glassmorphism shell
**File:** `lib/features/auth/presentation/login_screen.dart`
**Action:** Modify
**Details:** Remove any `CustomPaint(painter: AuthGradientBackground(), ...)` wrapper (should already be gone after Phase 1.6), any `BackdropFilter`, any `glassmorphism card` `Container` with `Colors.white.withOpacity(0.065)`. Replace the scaffold structure with `AuthScaffold(showBack: false, child: Column(...))`.

### Step 2 — Replace widgets with neumorphic equivalents
**File:** `lib/features/auth/presentation/login_screen.dart`
**Action:** Modify
**Details:** Transcribe the widget tree from `VelvetTouchDesign/lib/screens/login_screen.dart` exactly:
- All spacing via `VelvetSpacing` constants (NOT raw numbers).
- All colors via `BrandColors` (NOT hardcoded hex).
- All text via `VelvetText` helpers.
- Email-not-verified branch uses `AuthBanner` widget (imported from `lib/features/auth/presentation/widgets/auth_scaffold.dart`).
- Keep existing controller disposal, validator logic, `onPressed` wiring to `AuthNotifier`.

### Step 3 — Verify auth behavior unchanged
**Details:** The `AuthNotifier.login()` call, error display (SnackBar or inline banner), EMAIL_NOT_VERIFIED routing to `/verification`, and success routing must behave identically to the pre-redesign screen. No behavioral changes in this phase.

### Step 4 — Update tests
**File:** `test/features/auth/presentation/login_screen_test.dart`
**Action:** Modify
**Details:** Update widget finder keys to match the VelvetTouch source (`key: const ValueKey<String>('login_email')`, `'login_password'`, `'login_submit'`, `'login_forgot'`, `'login_signup'`). Repoint finders; behavioral assertions (form validation, submit, navigation) remain unchanged. Regenerate goldens only after ground-truth render diff against the preview app — not blindly.

## Files to create / modify
- `lib/features/auth/presentation/login_screen.dart` (modify)
- `test/features/auth/presentation/login_screen_test.dart` (modify — update keys, regen goldens)

## Test Cases

### Widget (11 tests — `test/features/auth/presentation/login_screen_test.dart`)
- Test 1: valid email + password → login(email, password) called
- Test 2: invalid email → inline errorText shown on field, login not called
- Test 3: while AsyncLoading → NeumorphicButton shows CircularProgressIndicator and label text is not visible
- Test 4: shows SnackBar with error message on failed login
- Test 5: login_signup key is present in the widget tree
- Test 6: tapping login_signup navigates to /register/role placeholder
- Test 7: login_forgot navigates to /forgot-password
- Test 8: EMAIL_NOT_VERIFIED error → AuthBanner shown instead of SnackBar
- Test 9: successful login → navigates to home screen
- Test 10: empty password → errPasswordRequired shown on field, login not called
- Test 11: tapping AuthBanner action after EMAIL_NOT_VERIFIED navigates to /verification

## Acceptance Criteria
- [x] Screen uses `AuthScaffold(showBack: false)` — no raw `Scaffold` with dark background
- [x] Email field key `ValueKey('login_email')`, password `'login_password'`, submit `'login_submit'`
- [x] `NeumorphicTextField` used for both fields — no `TextFormField` with old glass style
- [x] `NeumorphicButton` used for the CTA — no `ElevatedButton`/`DecoratedBox` CTA pattern
- [x] No `BackdropFilter` / `AuthGradientBackground` in this file (grep gate)
- [x] All spacing via `VelvetSpacing` — no raw numeric padding
- [x] EMAIL_NOT_VERIFIED branch renders `AuthBanner` with action link
- [x] Existing auth behavior (login success, error SnackBar, forgot-password nav) unchanged
- [x] `flutter analyze --no-fatal-infos` → 0 errors, 0 warnings
- [x] `flutter test test/features/auth/presentation/login_screen_test.dart` → all green
- [ ] `mobile-perf` score ≥ 70
- [ ] `mobile-security` score ≥ 70
- [x] `mobile-qa` score ≥ 70 with no CRITICAL/HIGH/MEDIUM findings

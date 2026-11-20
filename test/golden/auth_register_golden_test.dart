// Phase 17.4 / M515 — Visual regression goldens for the phone-first
// registration wizard (role → phone → SMS code → password → profile).
//
// Screens goldened (wizard step in brackets):
//   • RegisterStep1Screen    [1/4] — phone + terms           — 6 PNGs
//   • RegisterCodeScreen     [2/4] — SMS code, draft phone   — 6 PNGs
//     + filled (6 digits) and error (400 INVALID_CODE banner) at
//       360 dp × 1.0                                          — 2 PNGs
//   • RegisterPasswordScreen [3/4] — password + confirm      — 6 PNGs
//   • RegisterStep2Screen    [4/4] — profile, INDEPENDENT_MASTER — 6 PNGs
//   • RegisterStep2Screen    [4/4] — profile, SALON_OWNER (adds salon-name
//                                    field)                  — 6 PNGs
// Matrix: {320, 360, 414} dp × {textScale 1.0, 1.3} = 30 golden PNGs, plus
// the 2 register_code state PNGs (phone-first hardening).
//
// Clock: register screens render no date-bearing UI — no clock override needed.
//
// Strategy:
//   • Every step screen is rendered standalone (outside the ShellRoute /
//     RegisterFlowShell they use in production) — the goldens cover each
//     step's own form fields and CTA.
//   • [registerDraftProvider] is seeded per-role (and with a phone for the
//     code step, which shows the formatted number) so role-conditional fields
//     render correctly.
//   • authRepositoryProvider + secureStorageProvider are faked to prevent
//     network calls.
//   • No router override needed: the initial render of these screens does not
//     call context.go() — navigation fires only on CTA / back tap (not
//     captured by goldens).

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/register_code_screen.dart';
import 'package:beautica_mobile/features/auth/presentation/register_password_screen.dart';
import 'package:beautica_mobile/features/auth/presentation/register_step_1_screen.dart';
import 'package:beautica_mobile/features/auth/presentation/register_step_2_screen.dart';
import 'package:beautica_mobile/features/auth/state/register_draft.dart';
import 'package:beautica_mobile/features/auth/state/register_draft_notifier.dart';
import 'package:flutter/widgets.dart' show ValueKey;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes/fake_auth_repository.dart';
import '../helpers/fakes/fake_secure_storage.dart';
import 'helpers/golden_pump.dart';

// ---------------------------------------------------------------------------
// Override factories
// ---------------------------------------------------------------------------

/// Overrides for a given role — the role drives which conditional fields the
/// Step 2 screen renders (SALON_OWNER adds the salon-name field).
List<Object> _overridesFor(
  UserRole role, {
  String phone = '',
  Object verifyRegistrationCodeResult = 'ticket-1',
}) => <Object>[
  authRepositoryProvider.overrideWithValue(
    FakeAuthRepository()
      ..verifyRegistrationCodeResult = verifyRegistrationCodeResult,
  ),
  secureStorageProvider.overrideWithValue(FakeSecureStorage()),
  // Seed a draft so role-conditional fields in Step 2 render correctly.
  registerDraftProvider.overrideWith(() => _SeededDraftNotifier(role, phone)),
];

/// Base overrides (INDEPENDENT_MASTER draft) shared by Step 1, the password
/// step and the master variant of Step 2.
List<Object> _baseOverrides() => _overridesFor(UserRole.independentMaster);

// ---------------------------------------------------------------------------
// Stub notifier — pre-seeds the draft without requiring the role-selection
// navigation step.
// ---------------------------------------------------------------------------

class _SeededDraftNotifier extends RegisterDraftNotifier {
  _SeededDraftNotifier(this._role, this._phone);
  final UserRole _role;
  final String _phone;

  @override
  RegisterDraft? build() => RegisterDraft(role: _role, phone: _phone); // pre-seeded for golden
}

// ---------------------------------------------------------------------------
// Goldens
// ---------------------------------------------------------------------------

void main() {
  // ── RegisterStep1Screen ──────────────────────────────────────────────────

  for (final width in kGoldenWidths) {
    for (final scale in kGoldenTextScales) {
      final suffix = widthScaleSuffix(width, scale);

      goldenTest(
        'register_step1 ${width.toInt()}dp text-${scale}x',
        fileName: 'register_step1_$suffix',
        constraints: BoxConstraints.tight(Size(width, kGoldenHeight)),
        textScaleFactor: scale,
        pumpWidget: goldenPumpWidget(overrides: _baseOverrides(), width: width),
        builder: () => const RegisterStep1Screen(),
      );
    }
  }

  // ── RegisterCodeScreen (wizard 2/4) ─────────────────────────────────────
  // Seeded with a phone so the formatted number renders in the headline copy.

  for (final width in kGoldenWidths) {
    for (final scale in kGoldenTextScales) {
      final suffix = widthScaleSuffix(width, scale);

      goldenTest(
        'register_code ${width.toInt()}dp text-${scale}x',
        fileName: 'register_code_$suffix',
        constraints: BoxConstraints.tight(Size(width, kGoldenHeight)),
        textScaleFactor: scale,
        pumpWidget: goldenPumpWidget(
          overrides: _overridesFor(
            UserRole.independentMaster,
            phone: '+380671234567',
          ),
          width: width,
        ),
        builder: () => const RegisterCodeScreen(),
      );
    }
  }

  // ── RegisterCodeScreen — filled / error states (360 dp × 1.0) ───────────

  Future<void> enterCode(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const ValueKey<String>('phone_code_input')),
      '123456',
    );
    await tester.pumpAndSettle();
  }

  goldenTest(
    'register_code filled 360dp',
    fileName: 'register_code_filled_360',
    constraints: BoxConstraints.tight(const Size(360, kGoldenHeight)),
    textScaleFactor: 1.0,
    whilePerforming: (WidgetTester tester) async {
      await enterCode(tester);
      return null;
    },
    pumpWidget: goldenPumpWidget(
      overrides: _overridesFor(
        UserRole.independentMaster,
        phone: '+380671234567',
      ),
      width: 360,
    ),
    builder: () => const RegisterCodeScreen(),
  );

  goldenTest(
    'register_code error 360dp',
    fileName: 'register_code_error_360',
    constraints: BoxConstraints.tight(const Size(360, kGoldenHeight)),
    textScaleFactor: 1.0,
    whilePerforming: (WidgetTester tester) async {
      await enterCode(tester);
      await tester.tap(find.byKey(const ValueKey<String>('phone_code_submit')));
      await tester.pumpAndSettle();
      return null;
    },
    pumpWidget: goldenPumpWidget(
      overrides: _overridesFor(
        UserRole.independentMaster,
        phone: '+380671234567',
        verifyRegistrationCodeResult: const PhoneIdentityFailure(
          code: PhoneIdentityErrorCode.invalidCode,
        ),
      ),
      width: 360,
    ),
    builder: () => const RegisterCodeScreen(),
  );

  // ── RegisterPasswordScreen (wizard 3/4) ─────────────────────────────────

  for (final width in kGoldenWidths) {
    for (final scale in kGoldenTextScales) {
      final suffix = widthScaleSuffix(width, scale);

      goldenTest(
        'register_password ${width.toInt()}dp text-${scale}x',
        fileName: 'register_password_$suffix',
        constraints: BoxConstraints.tight(Size(width, kGoldenHeight)),
        textScaleFactor: scale,
        pumpWidget: goldenPumpWidget(overrides: _baseOverrides(), width: width),
        builder: () => const RegisterPasswordScreen(),
      );
    }
  }

  // ── RegisterStep2Screen (wizard 4/4 — profile) ───────────────────────────

  for (final width in kGoldenWidths) {
    for (final scale in kGoldenTextScales) {
      final suffix = widthScaleSuffix(width, scale);

      // INDEPENDENT_MASTER variant — name + phone, no salon-name field.
      goldenTest(
        'register_step2 ${width.toInt()}dp text-${scale}x',
        fileName: 'register_step2_$suffix',
        constraints: BoxConstraints.tight(Size(width, kGoldenHeight)),
        textScaleFactor: scale,
        pumpWidget: goldenPumpWidget(overrides: _baseOverrides(), width: width),
        builder: () => const RegisterStep2Screen(),
      );
    }
  }

  // ── RegisterStep2Screen — SALON_OWNER variant ────────────────────────────
  // SALON_OWNER Step 2 has a different field set (adds the salon-name field),
  // so it needs its own golden coverage.

  for (final width in kGoldenWidths) {
    for (final scale in kGoldenTextScales) {
      final suffix = widthScaleSuffix(width, scale);

      goldenTest(
        'register_step2 SALON_OWNER ${width.toInt()}dp text-${scale}x',
        fileName: 'register_step2_owner_$suffix',
        constraints: BoxConstraints.tight(Size(width, kGoldenHeight)),
        textScaleFactor: scale,
        pumpWidget: goldenPumpWidget(
          overrides: _overridesFor(UserRole.salonOwner),
          width: width,
        ),
        builder: () => const RegisterStep2Screen(),
      );
    }
  }
}

// Phase 17.4 — Visual regression goldens for registration step screens.
//
// Screens goldened: RegisterStep1Screen, RegisterStep2Screen.
// Matrix: {320, 360, 414} dp × {textScale 1.0, 1.3}.
//   • RegisterStep1Screen                      — 6 PNGs
//   • RegisterStep2Screen (INDEPENDENT_MASTER) — 6 PNGs
//   • RegisterStep2Screen (SALON_OWNER)        — 6 PNGs (adds salon-name field)
// = 18 golden PNGs.
//
// Clock: register screens render no date-bearing UI — no clock override needed.
//
// Strategy:
//   • RegisterStep1Screen + RegisterStep2Screen are rendered standalone
//     (outside the ShellRoute / RegisterFlowShell they use in production).
//     The shell chrome (logo, role chip, headline, progress dots) lives in
//     RegisterFlowShell; the step screens render their OWN content. This
//     matches what the visual design tests for — the form fields and CTA.
//   • [registerDraftProvider] is seeded per-role so the role-conditional field
//     matrix in Step 2 renders correctly: INDEPENDENT_MASTER (Ім'я / Прізвище /
//     Телефон, no salon-name field) and SALON_OWNER (adds the salon-name field).
//   • authRepositoryProvider + secureStorageProvider are faked to prevent
//     network calls.
//   • No router override needed: the initial render of both screens does not
//     call context.go() — navigation fires only on CTA tap (not captured by
//     goldens).

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/register_step_1_screen.dart';
import 'package:beautica_mobile/features/auth/presentation/register_step_2_screen.dart';
import 'package:beautica_mobile/features/auth/state/register_draft.dart';
import 'package:beautica_mobile/features/auth/state/register_draft_notifier.dart';

import '../helpers/fakes/fake_auth_repository.dart';
import '../helpers/fakes/fake_secure_storage.dart';
import 'helpers/golden_pump.dart';

// ---------------------------------------------------------------------------
// Override factories
// ---------------------------------------------------------------------------

/// Overrides for a given role — the role drives which conditional fields the
/// Step 2 screen renders (SALON_OWNER adds the salon-name field).
List<Object> _overridesFor(UserRole role) => <Object>[
  authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
  secureStorageProvider.overrideWithValue(FakeSecureStorage()),
  // Seed a draft so role-conditional fields in Step 2 render correctly.
  registerDraftProvider.overrideWith(() => _SeededDraftNotifier(role)),
];

/// Base overrides (INDEPENDENT_MASTER draft) shared by Step 1 + the master
/// variant of Step 2.
List<Object> _baseOverrides() => _overridesFor(UserRole.independentMaster);

// ---------------------------------------------------------------------------
// Stub notifier — pre-seeds the draft without requiring the role-selection
// navigation step.
// ---------------------------------------------------------------------------

class _SeededDraftNotifier extends RegisterDraftNotifier {
  _SeededDraftNotifier(this._role);
  final UserRole _role;

  @override
  RegisterDraft? build() => RegisterDraft(role: _role); // pre-seeded for golden
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

  // ── RegisterStep2Screen ──────────────────────────────────────────────────

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

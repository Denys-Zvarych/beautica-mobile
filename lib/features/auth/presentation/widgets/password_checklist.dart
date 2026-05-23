// Phase 2.13 — Live password-requirement checklist (VelvetTouch).
//
// Ported verbatim from
// `docs/signup-designs/VelvetTouchDesign/lib/widgets/password_checklist.dart`.
// The only changes from the design source are:
//   - `velvet_tokens.dart` import replaced with the real project imports below.
//   - `VelvetColors.*` references replaced with `BrandColors.*`.
//   - `VelvetSpacing.*` / `VelvetText.*` unchanged (same token names in project).
//
// The `passwordRules` factory and `PasswordRule` class live here so that both
// the reset-password screen and any future register/invite screens can share the
// identical rule-set without re-importing the old `PasswordCriteriaRow` widget
// (which belongs to the retired glassmorphism layer and must not be imported
// from this file or any VelvetTouch screen).

import 'package:flutter/material.dart';

import '../../../../core/theme/brand_colors.dart';
import '../../../../core/theme/velvet_geometry.dart';
import '../../../../core/theme/velvet_text.dart';

/// A single password-policy rule plus a live predicate to evaluate it.
class PasswordRule {
  const PasswordRule(this.label, this.test);

  final String label;
  final bool Function(String value) test;
}

/// Register / reset password policy surfaced live: 8–128 chars, >=1 digit,
/// >=1 uppercase. ([minLength] is overridable for the invite path, which
/// requires 12–128.)
///
/// The backend `@StrongPassword` policy ALSO rejects common passwords, but a
/// phone cannot check that list live without a network round-trip — so the
/// former "Не зі списку поширених паролів" live ✓/✗ row was removed
/// (2026-05-22). Common-password rejection is enforced by the backend on
/// submit; showing a fake live check for it would mislead the user.
List<PasswordRule> passwordRules({int minLength = 8}) => <PasswordRule>[
  PasswordRule(
    'Від $minLength до 128 символів',
    (String v) => v.length >= minLength && v.length <= 128,
  ),
  const PasswordRule('Хоча б одна цифра', _hasDigit),
  const PasswordRule('Хоча б одна велика літера', _hasUppercase),
];

// Module-level compiled patterns — constructed once, not on every keystroke.
final RegExp _digitPattern = RegExp(r'\d');
final RegExp _uppercasePattern = RegExp(r'[A-ZА-ЯІЇЄ]');

bool _hasDigit(String v) => v.contains(_digitPattern);
bool _hasUppercase(String v) => v.contains(_uppercasePattern);

/// Live requirement checklist. Each rule shows a check (met) or cross (unmet)
/// icon alongside its label, so the state is conveyed by icon + text, not by
/// color alone.
class PasswordChecklist extends StatelessWidget {
  const PasswordChecklist({
    super.key,
    required this.value,
    required this.rules,
  });

  final String value;
  final List<PasswordRule> rules;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Вимоги до пароля',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final PasswordRule rule in rules)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: _RuleRow(met: rule.test(value), label: rule.label),
            ),
        ],
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.met, required this.label});

  final bool met;
  final String label;

  @override
  Widget build(BuildContext context) {
    final Color color = met ? BrandColors.success : BrandColors.muted;
    return Semantics(
      label: '$label: ${met ? 'виконано' : 'не виконано'}',
      excludeSemantics: true,
      child: Row(
        children: <Widget>[
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Icon(
              met ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
              key: ValueKey<bool>(met),
              size: 17,
              color: color,
            ),
          ),
          const SizedBox(width: VelvetSpacing.sm),
          Text(
            label,
            style: VelvetText.feedback(
              color,
            ).copyWith(fontWeight: met ? FontWeight.w700 : FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

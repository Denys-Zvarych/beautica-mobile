// Shared password strength indicator widget.
//
// A compact (≤ 40 px tall) three-segment bar that evaluates the given
// [password] string synchronously and renders a colour-coded indicator.
//
// Strength levels and colours:
//   Weak   (1 segment lit) — BrandColors.error  (#B0452F)
//   Medium (2 segments lit) — BrandColors.accent (#B89A7A)
//   Strong (3 segments lit) — green (#2E9E5B)
//
// Rules:
//   Weak:   < 8 chars OR only one character class.
//   Medium: ≥ 8 chars AND ≥ 2 character classes.
//   Strong: ≥ 8 chars AND ≥ 3 character classes AND ≥ 1 special character.
//
// The indicator is invisible when [password] is empty so it does not take
// vertical space before the user has started typing. Uses AnimatedContainer
// for a smooth colour transition between levels.
//
// Usage:
//   PasswordStrengthIndicator(password: _passwordController.text)
//
// Drive updates by attaching a listener on the TextEditingController and
// calling setState in the parent to pass the latest text value.

import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/brand_colors.dart';
import '../../l10n/app_localizations.dart';

// ---------------------------------------------------------------------------
// Strength enum
// ---------------------------------------------------------------------------

/// The three strength levels this widget can represent.
enum PasswordStrength { weak, medium, strong }

// ---------------------------------------------------------------------------
// Strength evaluation
// ---------------------------------------------------------------------------

// Module-level static RegExps — allocated once, never recreated per build.
// ignore: avoid-non-ascii-identifiers (regex char class, not user-visible text)
final RegExp _reUpper = RegExp(r'[A-Z]');
final RegExp _reLower = RegExp(r'[a-z]');
final RegExp _reDigit = RegExp(r'\d');
final RegExp _reSpecial = RegExp(r'[^A-Za-z\d]');

/// Returns the [PasswordStrength] for [password].
///
/// Exported as a top-level function so unit tests can cover it without
/// constructing a widget tree.
PasswordStrength evaluatePasswordStrength(String password) {
  if (password.isEmpty) return PasswordStrength.weak;

  final hasSpecial = _reSpecial.hasMatch(password);
  int classes = 0;
  if (_reUpper.hasMatch(password)) classes++;
  if (_reLower.hasMatch(password)) classes++;
  if (_reDigit.hasMatch(password)) classes++;
  if (hasSpecial) classes++;

  if (password.length >= 8 && classes >= 3 && hasSpecial) {
    return PasswordStrength.strong;
  }
  if (password.length >= 8 && classes >= 2) {
    return PasswordStrength.medium;
  }
  return PasswordStrength.weak;
}

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

/// Compact password strength bar with a Ukrainian label.
///
/// Pass [password] as a reactive value from the parent's `setState`-driven
/// listener on a [TextEditingController]. The widget is a pure [StatelessWidget]
/// — it has no internal state and re-renders only when [password] changes.
class PasswordStrengthIndicator extends StatelessWidget {
  const PasswordStrengthIndicator({super.key, required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    // Nothing rendered until the user has started typing.
    if (password.isEmpty) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final strength = evaluatePasswordStrength(password);
    final filledCount = switch (strength) {
      PasswordStrength.weak => 1,
      PasswordStrength.medium => 2,
      PasswordStrength.strong => 3,
    };
    final activeColor = switch (strength) {
      PasswordStrength.weak => BrandColors.error,
      PasswordStrength.medium => BrandColors.accent,
      PasswordStrength.strong => const Color(0xFF2E9E5B),
    };
    final label = switch (strength) {
      PasswordStrength.weak => l10n.passwordStrengthWeak,
      PasswordStrength.medium => l10n.passwordStrengthMedium,
      PasswordStrength.strong => l10n.passwordStrengthStrong,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: AppSpacing.xs),
        // Three-segment bar.
        Row(
          children: List.generate(3, (i) {
            final isActive = i < filledCount;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: i == 0 ? 0 : AppSpacing.xxs),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isActive
                        ? activeColor
                        : Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: AppSpacing.xxs),
        // Strength label — right-aligned to avoid overlapping field hint text.
        Align(
          alignment: Alignment.centerRight,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              label,
              key: ValueKey(strength),
              style: TextStyle(
                fontSize: 11,
                color: activeColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

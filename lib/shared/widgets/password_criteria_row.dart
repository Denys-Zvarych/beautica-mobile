// Shared password-criteria helper row for the registration details screen.
//
// Exact transcription of the `.helper-row` block in sign-up-page.html
// (lines 381–387). Replaces the previous Слабкий/Середній/Сильний strength
// bar — the approved design shows a 3-criteria live-validating dot row
// instead:
//
//   .helper-row  { display:flex; align-items:center; gap:5px; margin-top:8px;
//                  flex-wrap:wrap }
//   .helper-dot  { width:6px; height:6px; border-radius:50% }
//   .helper-dot.ok { background:#10b981 }
//   .helper-dot.no { background:rgba(255,255,255,0.18) }
//   .helper-text { font-size:10.5px; color:rgba(255,255,255,0.28) }
//   .helper-spacer { width:8px }   (between criteria groups)
//
// Three criteria, matching the design copy verbatim:
//   • "8+ симв."      — password length ≥ 8
//   • "Цифра"         — contains at least one digit
//   • "Велика літера" — contains at least one uppercase letter
//
// Colour is NOT the only signal — each dot is paired with its own text
// label, so the row remains meaningful without colour perception
// (ux color-not-only). The whole row is wrapped in a single merged
// [Semantics] node so a screen reader announces it as one helper string
// rather than reading six disjoint fragments.

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

// Module-level RegExps — allocated once, never recreated per build.
final RegExp _reDigit = RegExp(r'\d');
final RegExp _reUpper = RegExp(r'[A-Z]');

/// The three live password criteria from sign-up-page.html `.helper-row`.
///
/// Pass [password] as a reactive value from the parent's controller listener.
/// Pure [StatelessWidget] — re-renders only when [password] changes.
class PasswordCriteriaRow extends StatelessWidget {
  const PasswordCriteriaRow({super.key, required this.password});

  final String password;

  // sign-up-page.html: ok #10b981, no rgba(255,255,255,0.18).
  static const Color _kOk = Color(0xFF10B981);
  static const Color _kNo = Color(0x2EFFFFFF); // white 18%

  // .helper-text { font-size: 10.5px; color: rgba(255,255,255,0.28) }.
  static const TextStyle _kTextStyle = TextStyle(
    fontSize: 10.5,
    color: Color(0x47FFFFFF), // white 28%
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final lengthOk = password.length >= 8;
    final digitOk = _reDigit.hasMatch(password);
    final upperOk = _reUpper.hasMatch(password);

    return Semantics(
      container: true,
      // Screen-reader summary of the live criteria state.
      label:
          '${l10n.registerPasswordCriteriaLength}: '
          '${lengthOk ? '✓' : '✗'}, '
          '${l10n.registerPasswordCriteriaDigit}: '
          '${digitOk ? '✓' : '✗'}, '
          '${l10n.registerPasswordCriteriaUppercase}: '
          '${upperOk ? '✓' : '✗'}',
      excludeSemantics: true,
      // .helper-row { margin-top: 8px } → SizedBox above the wrap.
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        // flex-wrap: wrap + align-items: center; gap: 5px.
        child: Wrap(
          spacing: 5,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _Criterion(
              ok: lengthOk,
              label: l10n.registerPasswordCriteriaLength,
            ),
            // .helper-spacer { width: 8px } — but the Wrap already adds the
            // 5px gap on each side, so an extra 3px reaches the design's 8px
            // logical separation between criteria groups.
            const SizedBox(width: 3),
            _Criterion(ok: digitOk, label: l10n.registerPasswordCriteriaDigit),
            const SizedBox(width: 3),
            _Criterion(
              ok: upperOk,
              label: l10n.registerPasswordCriteriaUppercase,
            ),
          ],
        ),
      ),
    );
  }
}

/// A single 6px dot + its text label, matching `.helper-dot` + `.helper-text`.
class _Criterion extends StatelessWidget {
  const _Criterion({required this.ok, required this.label});

  final bool ok;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // .helper-dot { width: 6px; height: 6px; border-radius: 50% }.
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: ok ? PasswordCriteriaRow._kOk : PasswordCriteriaRow._kNo,
            shape: BoxShape.circle,
          ),
        ),
        // .helper-row gap: 5px between the dot and its text.
        const SizedBox(width: 5),
        Text(label, style: PasswordCriteriaRow._kTextStyle),
      ],
    );
  }
}

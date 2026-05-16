// Shared uppercase field label for the auth screens — Phase 2.x (Defect 1).
//
// The approved Warm Mocha mockups (login-page.html / sign-up-page.html) place
// a static uppercase `<label>` ABOVE every input, in addition to the
// placeholder text inside the field:
//
//   label {
//     font-size: 10.5px; font-weight: 500;
//     color: rgba(255,255,255,0.42);
//     letter-spacing: 0.07em;
//     text-transform: uppercase;
//     margin-bottom: 6px;
//   }
//
// The implemented screens only used `hintText`, so the static label was
// missing entirely. This widget restores it identically on both screens.
//
// Font size increased to 13 for on-device readability (+2 px pass; was 12).
// 0.07em at 13px = 0.91 logical px of letter spacing.

import 'package:flutter/material.dart';

/// Static uppercase label rendered above an auth input field, matching the
/// HTML mockup `label` rule. Includes the 6 px gap to the field below it.
///
/// The [text] is uppercased here so callers pass the normal localized string
/// (no separate uppercase l10n key required — pure presentation transform).
class AuthFieldLabel extends StatelessWidget {
  const AuthFieldLabel(this.text, {super.key});

  final String text;

  /// fontSize 13, w500, letterSpacing 0.07 * 13 = 0.91, white 42%.
  /// Increased from 10.5 to 12, then to 13 for on-device readability (+2 px pass).
  /// Hoisted to a static const per the perf convention (heavy-ish TextStyle
  /// reused on every field on every auth screen).
  static const TextStyle _kLabelStyle = TextStyle(
    color: Color(0x6BFFFFFF), // white ~42%
    fontSize: 13, // increased from 12
    fontWeight: FontWeight.w500,
    letterSpacing: 0.91, // 0.07em × 13 = 0.91 (was 0.84 at 12)
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text.toUpperCase(), style: _kLabelStyle),
        const SizedBox(height: 6),
      ],
    );
  }
}

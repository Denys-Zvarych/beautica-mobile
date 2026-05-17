// Warm Mocha auth background — Phase 2.x visual redesign (LinearGradient).
//
// Design history: four prior attempts reproduced the HTML design's two
// RadialGradient "blob" pseudo-elements. On real devices those ALWAYS rendered
// as a visible ring/disc no matter how the geometry was tuned. The radial
// approach is abandoned entirely. There is now ZERO RadialGradient, zero
// Rect.fromCircle, zero positioned circle, zero BackdropFilter — a ring is
// physically impossible to render here.
//
// The background is a single full-bleed [LinearGradient] sweeping a gentle
// top-left → bottom-right diagonal. ui-ux-pro-max ("Modern Dark / Cinema
// Mobile" style) prescribes a premium dark surface as a smooth two-to-four
// stop LinearGradient between a slightly-elevated deep tone and the deepest
// base tone — never pure black, no localized light. Translated to Warm Mocha:
// a restrained mocha-brown warm corner (behind the brand mark at the top)
// settling into the espresso base in the opposite corner. The diagonal reads
// best on a portrait phone auth screen — the warm lift frames the logo while
// the form sinks into calm darkness. It is a directional ambient wash, not a
// glow: monotonic end-to-end, no interior peak, no possibility of a disc.

import 'package:flutter/material.dart';

/// Full-screen Warm Mocha background — a single smooth [LinearGradient].
///
/// Renders a [DecoratedBox] sized to fill its parent (via [SizedBox.expand])
/// whose [BoxDecoration.gradient] is one [LinearGradient] running from
/// [Alignment.topLeft] to [Alignment.bottomRight]:
///
///   * `#3A2615` restrained mocha — the warm corner (top-left)
///   * `#2A1A0E` deep warm brown
///   * `#1C1109` darker warm brown
///   * `#0D0906` espresso — the base (bottom-right)
///
/// Dark-first, subtle, premium: an ambient warm wash, never a bright field
/// and never a ring. This widget is always [const]; it carries no state.
class AuthGradientBackground extends StatelessWidget {
  const AuthGradientBackground({super.key});

  // HTML: --phone-bg: #0d0906 — espresso, the gradient's darkest base stop.
  static const Color _kEspresso = Color(0xFF0D0906);

  // Warm Mocha gradient stops (no light/cream tones — stays DARK throughout).
  static const Color _kMochaWarm = Color(0xFF3A2615); // restrained mocha lift
  static const Color _kBrownDeep = Color(0xFF2A1A0E); // deep warm brown
  static const Color _kBrownDark = Color(0xFF1C1109); // darker warm brown

  /// The single linear gradient. Exposed so tests can assert the exact spec.
  static const LinearGradient gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [_kMochaWarm, _kBrownDeep, _kBrownDark, _kEspresso],
    stops: [0.0, 0.35, 0.65, 1.0],
  );

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(gradient: gradient),
    child: SizedBox.expand(),
  );
}

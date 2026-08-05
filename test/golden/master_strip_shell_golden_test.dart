// Chrome golden — [MasterStripShell], the identity card nine booking screens
// share (`lib/features/booking/presentation/widgets/master_strip_shell.dart`).
//
// WHY THIS FILE EXISTS
// --------------------
// Phase 240 gave the shell a SECOND shape: an optional `onTap` that nests a
// transparency `Material` + a radius-24 `InkWell` INSIDE the card's
// `DecoratedBox`. `grep -rn MasterStrip test/golden/` returned nothing before
// this file — the most-shared card in the booking flow had no pixel baseline
// at all, and the new branch shipped with none either. Both the build verifier
// and mobile-perf flagged the gap.
//
// Three cells, pinning two failure modes that no structural test can see:
//
//  1. REST-STATE PARITY (cells 1 + 2). The affordance is deliberately
//     press-only — no chevron, no glyph, no tint at rest — so a tappable strip
//     and an inert one are pixel-identical until touched. Half of the nine
//     screens must stay inert; a rest-state marker would either shift all of
//     them or make one object look like two. The two rest baselines are
//     additionally asserted BYTE-IDENTICAL by the parity test at the bottom of
//     this file, which is the mechanical form of that policy: a marker gated
//     on `onTap != null` changes cell 2 and not cell 1, so parity goes red.
//
//  2. SPLASH CLIP (cell 3). A press paints camel ink that MUST be clipped to
//     the card's own 24dp corners. An `InkWell` that loses its `borderRadius`
//     paints a square wash over the rounded card; one reparented ABOVE the
//     `DecoratedBox` paints under the opaque `_stripSurface` fill and vanishes
//     entirely. Both are pixel diffs here and invisible everywhere else.
//
// A NOTE ON WHAT THESE BASELINES ARE NOT
// --------------------------------------
// A golden regenerated from the code under test is self-referential. The
// CORRECTNESS of the tappable branch's structure — InkWell inside the
// DecoratedBox, own Material, radius-24 clip, inert branch untouched — is
// established independently and structurally in
// `test/features/booking/presentation/widgets/master_strip_shell_test.dart`.
// These PNGs' job from here is unintended pixel DRIFT, nothing more.
//
// Matrix kept tight (this is chrome, not a screen): {360} dp × {1.0} scale —
// the convention `client_top_bar_golden_test.dart` established for shared
// chrome. Suite config renders CI-mode goldens (`obscureText: true`,
// `renderShadows: false`), so text is coloured blocks and the card's halo is
// suppressed; the splash wash is neither, and renders normally.
//
// CLOCK: the shell renders no date — no clock override needed.

import 'dart:io';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_strip_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/golden_pump.dart';

const String _kInertFile = 'master_strip_shell_inert_360_1x';
const String _kTappableRestFile = 'master_strip_shell_tappable_rest_360_1x';
const String _kTappablePressedFile =
    'master_strip_shell_tappable_pressed_360_1x';

/// Hosts [child] on the brand base color with the booking screens' real
/// horizontal page padding, so the card's border renders against its
/// production backdrop rather than a bare white canvas.
Widget _host(double width, Widget child) => ColoredBox(
  color: BrandColors.base,
  child: SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: child,
    ),
  ),
);

/// The card content is IDENTICAL across all three cells — only `onTap` and the
/// press state vary. That is the whole point: any pixel difference between the
/// inert and tappable REST baselines is a rest-state marker leaking in.
///
/// i18n-finder-ok / raw strings: this is a golden fixture feeding a layout
/// primitive's opaque slots, not production UI copy governed by l10n.
MasterStripShell _card({VoidCallback? onTap}) => MasterStripShell(
  semanticsLabel: 'Софія Бондар, майстриня манікюру, 4.9, 24 відгуки',
  name: 'Софія Бондар',
  topLabel: 'Запис до майстра',
  middleLine: const Text(
    'Майстриня манікюру',
    style: TextStyle(fontSize: 12, color: BrandColors.muted),
  ),
  trailing: const Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Icon(Icons.star_rounded, size: 16, color: BrandColors.accent),
      SizedBox(width: 2),
      Text('4.9', style: TextStyle(fontSize: 14)),
      SizedBox(width: 3),
      Text('(24)', style: TextStyle(fontSize: 11.5)),
    ],
  ),
  onTap: onTap,
);

void main() {
  const double width = 360;
  // 170, not 120: the cell is a TIGHT constraint, so it also caps the card. At
  // 120 the 16dp host padding plus the card's own padding left the name column
  // 64dp, and the topLabel + name + role stack overflowed it — the suite-wide
  // overflow guard failed the cell rather than quietly clipping it, which is
  // the guard working. 170 gives the card its natural height with slack.
  const Size cell = Size(width, 170);

  // Cell 1 — INERT branch (onTap: null). The unchanged widget tree the three
  // in-flight wizard steps mount: DecoratedBox → Padding → Row, no nested
  // Material, no InkWell.
  goldenTest(
    'master_strip_shell inert (onTap: null)',
    fileName: _kInertFile,
    constraints: BoxConstraints.tight(cell),
    textScaleFactor: 1.0,
    pumpWidget: goldenPumpWidget(width: width),
    builder: () => _host(width, _card()),
  );

  // Cell 2 — TAPPABLE branch at REST. Must be pixel-identical to cell 1.
  goldenTest(
    'master_strip_shell tappable at rest (nested Material + InkWell paint '
    'nothing until touched)',
    fileName: _kTappableRestFile,
    constraints: BoxConstraints.tight(cell),
    textScaleFactor: 1.0,
    pumpWidget: goldenPumpWidget(width: width),
    builder: () => _host(width, _card(onTap: () {})),
  );

  // Cell 3 — TAPPABLE branch MID-PRESS, captured through alchemist's built-in
  // `press` interaction so the hold duration (and therefore the splash radius)
  // is fixed rather than wall-clock dependent. 150 ms is well inside the ink's
  // grow, so the wash is partial and its CLIP against the 24dp corners is what
  // the image records.
  goldenTest(
    'master_strip_shell tappable mid-press (camel wash clipped to the card\'s '
    '24dp corners)',
    fileName: _kTappablePressedFile,
    constraints: BoxConstraints.tight(cell),
    textScaleFactor: 1.0,
    pumpWidget: goldenPumpWidget(width: width),
    whilePerforming: press(
      find.byType(MasterStripShell),
      holdFor: const Duration(milliseconds: 150),
    ),
    builder: () => _host(width, _card(onTap: () {})),
  );

  // ── The rest-state parity policy, mechanically ───────────────────────────
  //
  // Not a golden itself: a direct byte comparison of the two REST baselines.
  // This is what makes cell 2 load-bearing. Without it, cell 2 is just "some
  // picture of a tappable card" and a rest-state marker would sail through by
  // being dutifully baked into its own baseline on the next
  // `--update-goldens`. Because the marker would be gated on `onTap != null`,
  // it changes cell 2 and NOT cell 1 — so comparing the two catches exactly
  // the regression the policy forbids, and catches it even after a
  // regeneration.
  //
  // Also proves cell 3 is not a silent duplicate: a press interaction that
  // stops working (or an InkWell that paints nothing) would make the pressed
  // baseline equal to the rest one, and this test says so.
  group('rest-state parity (the press-only affordance policy)', () {
    File goldenFile(String name) => File('test/golden/goldens/$name.png');

    test('the inert and tappable-at-rest baselines are byte-identical — a '
        'tappable strip must be indistinguishable from an inert one until '
        'touched', () {
      final File inert = goldenFile(_kInertFile);
      final File tappable = goldenFile(_kTappableRestFile);
      expect(
        inert.existsSync() && tappable.existsSync(),
        isTrue,
        reason:
            'both rest baselines must be committed; run '
            '`flutter test test/golden/ --update-goldens` if this is a first '
            'generation.',
      );

      expect(
        tappable.readAsBytesSync(),
        orderedEquals(inert.readAsBytesSync()),
        reason:
            'the affordance is press-only BY POLICY: no chevron, no glyph, no '
            'tint at rest. A rest-state marker gated on `onTap != null` shows '
            'up here as a byte difference — and would silently shift, or '
            'visually fork, the nine screens that share this card.',
      );
    });

    test('the pressed baseline DIFFERS from the rest baseline — otherwise the '
        'splash cell is a duplicate that could never fail', () {
      final File rest = goldenFile(_kTappableRestFile);
      final File pressed = goldenFile(_kTappablePressedFile);
      expect(rest.existsSync() && pressed.existsSync(), isTrue);

      expect(
        pressed.readAsBytesSync(),
        isNot(orderedEquals(rest.readAsBytesSync())),
        reason:
            'the mid-press cell must actually capture ink. If these match, '
            'either the press interaction stopped landing or the InkWell '
            'paints nothing — and the splash/clip golden is proving nothing.',
      );
    });
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-level regression guard for the Impeller-GLES avatar-rendering bug
/// (salon booking flow, Phase 14.13 / 14.16).
///
/// THE BUG
/// -------
/// Under Impeller's OpenGLES backend
/// (`android/app/src/main/AndroidManifest.xml` → `ImpellerBackend=opengles`),
/// a blurred `BoxShadow` (a `MaskFilter.blur`) painted on a
/// `BoxDecoration(shape: BoxShape.circle, boxShadow: ...)` rasterizes as a
/// hard white SQUARE (the shadow's bounding box), not a soft circle. The user
/// saw the selected master's avatar / select-token turn into a white square
/// with corner rectangles. Impeller's RRect blur path is correct, so the fix
/// converted the four shadow-bearing circle avatars/tokens from
/// `shape: BoxShape.circle` to `borderRadius: BorderRadius.circular(halfSide)`
/// (a visually identical circle routed through the correct blur path):
///   • `_SelectToken` (selected)         — salon_master_selection_screen.dart
///   • `_MasterPickRow` avatar (52dp)    — salon_master_selection_screen.dart
///   • `_GroupRow` avatar (40dp)         — salon_master_selection_screen.dart
///   • `SalonMasterStrip` avatar (48dp)  — salon_master_strip.dart (deleted)
///
/// WIDGET-CONSOLIDATION REFACTOR (2026-07): every master avatar in both booking
/// flows now renders through the shared `widgets/master_avatar_badge.dart`
/// (`MasterAvatarBadge`) — the identity card was unified onto the single
/// `MasterStrip` and `salon_master_strip.dart` is gone, as is `_MasterPickRow`'s
/// hand-rolled 52 dp avatar (the row renders the shared card instead). The
/// shadow-bearing `BoxDecoration` that carries the RRect workaround therefore
/// lives at ONE source, `master_avatar_badge.dart`, which is guarded below —
/// otherwise a future edit reintroducing `shape: BoxShape.circle` at the
/// avatar's new home would sail past this guard.
/// `salon_master_selection_screen.dart` stays guarded for its remaining
/// selection-screen circles (`_SelectToken`, `_GroupRow`).
///
/// WHY THIS IS A STRUCTURAL TEST, NOT A GOLDEN
/// -------------------------------------------
/// Golden tests render on **Skia** in the test harness, which draws
/// circle+shadow CORRECTLY — so a golden cannot reproduce the Impeller-GLES
/// artifact and cannot guard this bug. The only reliable guard is structural:
/// forbid the exact `BoxShape.circle` + non-null `boxShadow` combination in
/// the widgets that were fixed, so a future edit can't silently reintroduce
/// it. Mirrors the `test/android/manifest_deeplink_contract_test.dart`
/// precedent (a fast, host-independent contract test that reads raw source
/// and fails in the normal `flutter test` CI job).
///
/// SCOPE
/// -----
/// Deliberately limited to the two files this fix touched. The same latent
/// `BoxShape.circle` + `boxShadow` pattern still exists in ~30 other spots
/// across `lib/` (e.g. `core/widgets/neumorphic.dart`, several `schedule/`
/// editors, the shared `booking/.../master_strip.dart`), none of which were
/// part of this fix and several of which have never visibly broken. Widening
/// this guard to all of `lib/` would make it RED today — the app-wide audit is
/// a separate task (see `docs/mobile-phases/mobile-backlog.md`). This file
/// guards precisely what was fixed.
///
/// NOTE — this guard does NOT ban `BoxShape.circle` outright. A circle with no
/// shadow renders fine under Impeller-GLES (e.g. this screen's 3dp role-dot
/// separator and the 22dp candidate-chip avatar keep `shape: BoxShape.circle`
/// legitimately). Only the circle **+ shadow** combination is forbidden.
void main() {
  // Package-root-relative (`flutter test`'s working directory is
  // beautica-mobile/), matching the manifest contract test's convention.
  const List<String> guardedFiles = <String>[
    'lib/features/booking/presentation/salon_master_selection_screen.dart',
    // Single-source home of the shared master avatar's shadow-bearing
    // decoration (widget-consolidation refactor) — the RRect workaround now
    // lives here for EVERY booking-flow avatar, so it must be guarded here.
    'lib/features/booking/presentation/widgets/master_avatar_badge.dart',
  ];

  // The SECOND Impeller-GLES artifact, same backend, different trigger: a
  // shadow-only rounded `BoxDecoration` (a non-null `boxShadow` but NO top-level
  // `color:` fill) rasterizes its pale blurred shadow (VelvetShadows'
  // near-white light pair) as an OPAQUE SQUARE in the corners. A `ClipRRect`
  // around the child can't clip the PARENT's shadow, so the earlier
  // "shadow box -> ClipRRect -> fill" split never worked. The fix collapses
  // each surface back to ONE `BoxDecoration` that carries `color` AND
  // `boxShadow` together (the NeumorphicCard idiom). These two surfaces were
  // the offenders; guard them so a future edit can't re-split them.
  const List<String> shadowFillFiles = <String>[
    'lib/features/booking/presentation/widgets/calendar_button.dart',
    'lib/features/booking/presentation/widgets/master_strip_shell.dart',
  ];

  group('Impeller-GLES circle+shadow guard', () {
    test('salon-booking avatars never combine BoxShape.circle with a boxShadow', () {
      final List<String> offenders = <String>[];
      for (final String path in guardedFiles) {
        final File file = File(path);
        expect(
          file.existsSync(),
          isTrue,
          reason:
              'Guarded source "$path" not found (relative to beautica-mobile/). '
              'If the file moved, update this guard\'s `guardedFiles` list.',
        );
        final String code = _stripCommentsAndStrings(file.readAsStringSync());
        for (final String args in _boxDecorationArgs(code)) {
          if (_hasCircleShape(args) && _hasNonNullBoxShadow(args)) {
            offenders.add(path);
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'A BoxDecoration in these salon-booking widgets combines '
            '`shape: BoxShape.circle` with a non-null `boxShadow` — the exact '
            'pattern Impeller-GLES rasterizes as a hard white square. Draw the '
            'circle as an RRect instead: replace `shape: BoxShape.circle` with '
            '`borderRadius: BorderRadius.circular(<half the side length>)`. '
            'Offending file(s): ${offenders.toSet().join(', ')}.',
      );
    });

    test(
      'shadowed booking surfaces carry a fill color on the SAME BoxDecoration',
      () {
        final List<String> offenders = <String>[];
        for (final String path in shadowFillFiles) {
          final File file = File(path);
          expect(
            file.existsSync(),
            isTrue,
            reason:
                'Guarded source "$path" not found (relative to beautica-mobile/). '
                'If the file moved, update this guard\'s `shadowFillFiles` list.',
          );
          final String code = _stripCommentsAndStrings(file.readAsStringSync());
          for (final String args in _boxDecorationArgs(code)) {
            if (_hasNonNullBoxShadow(args) && !_hasTopLevelColor(args)) {
              offenders.add(path);
            }
          }
        }
        expect(
          offenders,
          isEmpty,
          reason:
              'A BoxDecoration in these booking surfaces declares a non-null '
              '`boxShadow` but no top-level `color:` fill — the shadow-only '
              'pattern Impeller-GLES rasterizes as opaque near-white corner '
              'squares. Put the `color:` on the SAME BoxDecoration as the '
              '`boxShadow` (do NOT split the shadow onto an outer box behind a '
              'ClipRRect — a ClipRRect cannot clip the parent shadow). '
              'Offending file(s): ${offenders.toSet().join(', ')}.',
        );
      },
    );

    test('each shadow-fill surface actually declares a shadowed BoxDecoration '
        '(the fill-color guard is never vacuous)', () {
      // The "carries a fill color" test above only proves an ABSENCE (no
      // shadow-only decoration). If a future refactor moved the shadowed card
      // out of these files entirely, that test would pass with nothing left to
      // guard — silent rot. This positive assertion forces the shadowFillFiles
      // list to stay pointed at a real shadowed surface.
      for (final String path in shadowFillFiles) {
        final File file = File(path);
        expect(
          file.existsSync(),
          isTrue,
          reason: 'Guarded source "$path" not found.',
        );
        final String code = _stripCommentsAndStrings(file.readAsStringSync());
        final bool hasShadowed = _boxDecorationArgs(
          code,
        ).any(_hasNonNullBoxShadow);
        expect(
          hasShadowed,
          isTrue,
          reason:
              '"$path" no longer declares any shadow-bearing BoxDecoration, so '
              'the "carries a fill color on the SAME BoxDecoration" guard now '
              'passes vacuously. If the shadowed surface moved, repoint '
              '`shadowFillFiles` at its new home; if the shadow was removed on '
              'purpose, drop this file from the list.',
        );
      }
    });

    // --- Meta-tests: prove the detector actually detects. ------------------
    // A structural guard that can never fail is worthless, so these assert the
    // detector fires on the known-bad shape and stays quiet on the two legit
    // shapes present in the guarded files (circle-only, shadow-only).

    test('detector flags a circle decoration that carries a boxShadow', () {
      const String bad = '''
        BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(colors: <Color>[a, b]),
          boxShadow: <BoxShadow>[BoxShadow(blurRadius: 5, offset: Offset(2, 2))],
        )
      ''';
      final List<String> args = _boxDecorationArgs(
        _stripCommentsAndStrings(bad),
      );
      expect(args, hasLength(1));
      expect(_hasCircleShape(args.single), isTrue);
      expect(_hasNonNullBoxShadow(args.single), isTrue);
    });

    test('detector ignores a circle decoration with no shadow', () {
      const String ok = '''
        BoxDecoration(shape: BoxShape.circle, color: BrandColors.faint)
      ''';
      final String args = _boxDecorationArgs(
        _stripCommentsAndStrings(ok),
      ).single;
      expect(_hasCircleShape(args), isTrue);
      expect(_hasNonNullBoxShadow(args), isFalse);
    });

    test(
      'detector ignores an RRect (borderRadius) decoration with a shadow',
      () {
        const String ok = '''
        BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: VelvetShadows.extrudedSmall,
        )
      ''';
        final String args = _boxDecorationArgs(
          _stripCommentsAndStrings(ok),
        ).single;
        expect(_hasCircleShape(args), isFalse);
        expect(_hasNonNullBoxShadow(args), isTrue);
      },
    );

    test('detector treats an explicit `boxShadow: null` as safe', () {
      const String ok = '''
        BoxDecoration(shape: BoxShape.circle, boxShadow: null)
      ''';
      final String args = _boxDecorationArgs(
        _stripCommentsAndStrings(ok),
      ).single;
      expect(_hasNonNullBoxShadow(args), isFalse);
    });

    test('color detector flags a shadow-only decoration (no fill)', () {
      const String bad = '''
        BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: VelvetShadows.extrudedCard,
        )
      ''';
      final String args = _boxDecorationArgs(
        _stripCommentsAndStrings(bad),
      ).single;
      expect(_hasNonNullBoxShadow(args), isTrue);
      expect(_hasTopLevelColor(args), isFalse);
    });

    test('color detector accepts a decoration with fill + shadow together', () {
      const String ok = '''
        BoxDecoration(
          color: BrandColors.base,
          borderRadius: BorderRadius.circular(24),
          boxShadow: cond ? null : VelvetShadows.extrudedButton,
        )
      ''';
      final String args = _boxDecorationArgs(
        _stripCommentsAndStrings(ok),
      ).single;
      expect(_hasNonNullBoxShadow(args), isTrue);
      expect(_hasTopLevelColor(args), isTrue);
    });

    test('color detector treats an explicit `color: null` as no fill', () {
      // Symmetric with the `boxShadow: null` case: a decoration that sets
      // `color: null` while carrying a real boxShadow renders the shadow-only
      // square at runtime, so it MUST still be flagged as an offender.
      const String bad = '''
        BoxDecoration(
          color: null,
          borderRadius: BorderRadius.circular(24),
          boxShadow: VelvetShadows.extrudedCard,
        )
      ''';
      final String args = _boxDecorationArgs(
        _stripCommentsAndStrings(bad),
      ).single;
      expect(_hasNonNullBoxShadow(args), isTrue);
      expect(_hasTopLevelColor(args), isFalse);
    });

    test('color detector ignores a nested Border.all(color:) as a fill', () {
      // A `border: Border.all(color: X)` must NOT count as the surface fill —
      // the fill `color:` lives at the top level of the BoxDecoration args.
      const String borderOnly = '''
        BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: BrandColors.accent),
          boxShadow: VelvetShadows.extrudedButton,
        )
      ''';
      final String args = _boxDecorationArgs(
        _stripCommentsAndStrings(borderOnly),
      ).single;
      expect(_hasTopLevelColor(args), isFalse);
    });

    test('comment/string stripping keeps parentheses balanced', () {
      // The fixed files contain comments that mention "BoxShape.circle" and
      // parentheses, e.g. "(a blurred BoxShadow on BoxShape.circle ...)". The
      // stripper must remove those before paren-matching or the guard breaks.
      const String tricky = '''
        // note: a blurred BoxShadow on BoxShape.circle (bounding box) breaks
        BoxDecoration(
          borderRadius: BorderRadius.circular(15), // was shape: BoxShape.circle
          boxShadow: <BoxShadow>[BoxShadow()],
        )
      ''';
      final List<String> args = _boxDecorationArgs(
        _stripCommentsAndStrings(tricky),
      );
      expect(args, hasLength(1));
      // The only real `shape: BoxShape.circle` lived in comments → not matched.
      expect(_hasCircleShape(args.single), isFalse);
    });
  });
}

// ---------------------------------------------------------------------------
// Detection helpers
// ---------------------------------------------------------------------------

/// Removes `//` line comments, `/* */` block comments and string literals so
/// paren-matching and token detection only ever see real Dart code. Comments
/// in the guarded files literally contain "BoxShape.circle" and unbalanced-
/// looking parentheses, so this pre-pass is required for correctness.
String _stripCommentsAndStrings(String src) {
  final StringBuffer buf = StringBuffer();
  int i = 0;
  final int n = src.length;
  while (i < n) {
    final String c = src[i];
    final String next = i + 1 < n ? src[i + 1] : '';
    if (c == '/' && next == '/') {
      while (i < n && src[i] != '\n') {
        i++;
      }
      continue;
    }
    if (c == '/' && next == '*') {
      i += 2;
      while (i < n && !(src[i] == '*' && i + 1 < n && src[i + 1] == '/')) {
        i++;
      }
      i += 2;
      buf.write(' ');
      continue;
    }
    if (c == "'" || c == '"') {
      final bool triple = i + 2 < n && src[i + 1] == c && src[i + 2] == c;
      final int delimLen = triple ? 3 : 1;
      i += delimLen;
      while (i < n) {
        if (src[i] == r'\') {
          i += 2;
          continue;
        }
        if (triple) {
          if (i + 2 < n && src[i] == c && src[i + 1] == c && src[i + 2] == c) {
            i += 3;
            break;
          }
          i++;
        } else {
          if (src[i] == c) {
            i++;
            break;
          }
          if (src[i] == '\n') break; // unterminated single-line string safety
          i++;
        }
      }
      buf.write('""'); // inert placeholder — no parens, no keywords
      continue;
    }
    buf.write(c);
    i++;
  }
  return buf.toString();
}

/// Returns the balanced-parenthesis argument substring of every
/// `BoxDecoration(...)` constructor call in [code] (comments/strings already
/// stripped). Nested parens — `LinearGradient(...)`, `Border.all(...)`,
/// `Offset(x, y)` — are handled by depth counting.
List<String> _boxDecorationArgs(String code) {
  final List<String> out = <String>[];
  final RegExp ctor = RegExp(r'BoxDecoration\s*\(');
  for (final RegExpMatch m in ctor.allMatches(code)) {
    int depth = 1;
    int j = m.end;
    final int start = j;
    while (j < code.length && depth > 0) {
      final String ch = code[j];
      if (ch == '(') {
        depth++;
      } else if (ch == ')') {
        depth--;
      }
      j++;
    }
    out.add(code.substring(start, j - 1));
  }
  return out;
}

bool _hasCircleShape(String args) =>
    RegExp(r'shape\s*:\s*BoxShape\.circle').hasMatch(args);

/// True when the block declares a `boxShadow:` whose value is not the literal
/// `null`. A conditional such as `boxShadow: cond ? null : X` is still flagged
/// because the non-null branch paints the broken square.
bool _hasNonNullBoxShadow(String args) {
  final RegExpMatch? m = RegExp(r'boxShadow\s*:\s*').firstMatch(args);
  if (m == null) return false;
  final String rest = args.substring(m.end).trimLeft();
  if (rest.startsWith('null')) return false;
  return true;
}

/// Removes the contents of every nested parenthesised group, leaving only the
/// BoxDecoration's TOP-LEVEL argument tokens. Needed so a nested
/// `Border.all(color: …)` / `LinearGradient(colors: …)` is not mistaken for the
/// surface's own `color:` fill.
String _stripNestedParens(String s) {
  final StringBuffer buf = StringBuffer();
  int depth = 0;
  for (int i = 0; i < s.length; i++) {
    final String c = s[i];
    if (c == '(') {
      depth++;
      continue;
    }
    if (c == ')') {
      if (depth > 0) depth--;
      continue;
    }
    if (depth == 0) buf.write(c);
  }
  return buf.toString();
}

/// True when the BoxDecoration declares a NON-NULL top-level `color:` fill
/// (ignoring any `color:` that lives inside a nested `Border.all(...)` /
/// gradient call). An explicit `color: null` is treated as NO fill — symmetric
/// with [_hasNonNullBoxShadow] — so `color: null` + a real `boxShadow` is still
/// flagged as the shadow-only pattern it renders as at runtime.
bool _hasTopLevelColor(String args) {
  final String top = _stripNestedParens(args);
  final RegExpMatch? m = RegExp(r'\bcolor\s*:\s*').firstMatch(top);
  if (m == null) return false;
  final String rest = top.substring(m.end).trimLeft();
  if (rest.startsWith('null')) return false;
  return true;
}

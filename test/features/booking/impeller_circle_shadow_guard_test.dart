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
///   • `SalonMasterStrip` avatar (48dp)  — salon_master_strip.dart
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
    'lib/features/booking/presentation/widgets/salon_master_strip.dart',
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

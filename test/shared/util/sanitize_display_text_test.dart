// Phase 221 re-audit fix (mobile-security LOW) — unit tests for
// `sanitizeDisplayText`'s bidi/zero-width control-character coverage.
//
// Phase 223 (a) — moved from `test/features/master/presentation/widgets/
// master_text_sanitizer_test.dart` alongside the function's promotion to
// `lib/shared/util/sanitize_display_text.dart`. The function itself and its
// name are unchanged, so only the import below moved.
//
// WHY THIS FILE EXISTS
// --------------------
// The original Phase 221 regex only covered the bidi OVERRIDE/ISOLATE
// controls (U+202A-U+202E, U+2066-U+2069) and the ZERO-WIDTH range
// (U+200B-U+200D, U+FEFF) — but the file's own doc comment claimed to strip
// the broader Cf "bidi format control" class, which also includes the
// IMPLICIT directional marks: U+061C (Arabic Letter Mark), U+200E (Left-to-
// Right Mark), U+200F (Right-to-Left Mark). Those three were silently
// passing through un-stripped. Exploit value on their own is low (they only
// bias the direction of adjacent NEUTRAL characters — digits, punctuation —
// they cannot reverse a whole run the way LRO/RLO can), but the regex was
// incomplete relative to the file's stated intent.
//
// Every case below is built via `String.fromCharCode` (never a literal
// control character pasted into this source file) and asserts BOTH halves
// that matter equally:
//   - the target control character IS stripped
//   - the adjacent Cyrillic address text survives INTACT (no over-stripping)

import 'package:beautica_mobile/shared/util/sanitize_display_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sanitizeDisplayText — implicit directional marks (re-audit gap)', () {
    test('strips U+061C (Arabic Letter Mark) without corrupting adjacent '
        'Cyrillic text', () {
      final String alm = String.fromCharCode(0x061C);
      final String raw = 'вул. Хрещатик$alm, 22';

      expect(sanitizeDisplayText(raw), 'вул. Хрещатик, 22');
    });

    test('strips U+200E (Left-to-Right Mark) without corrupting adjacent '
        'Cyrillic text', () {
      final String lrm = String.fromCharCode(0x200E);
      final String raw = 'кв. 3$lrm, 2 поверх';

      expect(sanitizeDisplayText(raw), 'кв. 3, 2 поверх');
    });

    test('strips U+200F (Right-to-Left Mark) without corrupting adjacent '
        'Cyrillic text', () {
      final String rlm = String.fromCharCode(0x200F);
      final String raw = 'Вхід у двір$rlm з боку вулиці Хрещатик';

      expect(sanitizeDisplayText(raw), 'Вхід у двір з боку вулиці Хрещатик');
    });
  });

  group('sanitizeDisplayText — pre-existing coverage stays intact', () {
    test('still strips RLO (U+202E) — the original Phase 221 case', () {
      final String rlo = String.fromCharCode(0x202E);
      final String raw = 'кв. 3$rlo, 2 поверх';

      expect(sanitizeDisplayText(raw), 'кв. 3, 2 поверх');
    });

    test('still strips zero-width joiner (U+200D) and BOM (U+FEFF)', () {
      final String zwj = String.fromCharCode(0x200D);
      final String bom = String.fromCharCode(0xFEFF);
      final String raw = '$bomВхід у двір$zwj, кв. 3';

      expect(sanitizeDisplayText(raw), 'Вхід у двір, кв. 3');
    });

    test('leaves plain Cyrillic address text completely unchanged', () {
      const String note =
          "Вхід у двір з боку вулиці Хрещатик, повз кав'ярню на розі.";

      expect(sanitizeDisplayText(note), note);
    });
  });
}

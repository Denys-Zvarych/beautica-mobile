// Unit tests for [serverFieldMessageOr] — the one rule deciding whether an
// untrusted, server-supplied `fieldErrors` value may be rendered as a UI label.
//
// The function is a KEEP-OR-REPLACE gate, not a sanitizer that repairs input:
// every rejection must yield the caller's localized fallback verbatim. So the
// interesting axis is which inputs get rejected, and the trap is a gate that
// passes by rejecting EVERYTHING — hence the accept-side control group below,
// which must stay green for the reject-side assertions to mean anything.
//
// Two deliberate choices run through the whole file:
//
//  • Every hostile character is written as a `\uXXXX` ESCAPE, never as a
//    literal. A literal NUL / NEL / RLO in a test file is invisible to review,
//    reorders the surrounding source in an editor, and is at the mercy of any
//    tool that rewrites whitespace. The escape says exactly which code point is
//    under test.
//  • Every probe places that character in the INTERIOR of the string.
//    `String.trim()` already strips the whitespace members (LF, CR, TAB, LS,
//    PS, NEL) from the EDGES, so an edge-placed probe would be rejected by the
//    pre-existing blank/trim path and would prove nothing about the character
//    class under test.

import 'package:beautica_mobile/shared/formatters/server_field_message.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for the localized copy each call site passes.
const String _fallback = 'FALLBACK';

void main() {
  // ── Accept side (control) ────────────────────────────────────────────────
  //
  // Without these, every reject-side expectation below is satisfiable by
  // `String serverFieldMessageOr(_, f) => f;`.

  group('CONTROL — fit messages still pass through unchanged', () {
    test('an ordinary short ASCII message is returned verbatim', () {
      expect(
        serverFieldMessageOr('Price must be at least 50', _fallback),
        'Price must be at least 50',
        reason:
            'a short, single-line server message is the whole point of this '
            'helper — it is more specific than any localized fallback',
      );
    });

    test('a Cyrillic message is returned verbatim (no ASCII-only bias)', () {
      const String msg = 'Ціна має бути більшою за 50';
      expect(
        serverFieldMessageOr(msg, _fallback),
        msg,
        reason:
            'the rejection class must target control/bidi code points, not '
            'simply everything outside Latin-1',
      );
    });

    test('interior spaces and punctuation are not treated as controls', () {
      const String msg = 'Duration: 30-180 min (step 15).';
      expect(serverFieldMessageOr(msg, _fallback), msg);
    });

    test('a message exactly at the cap is kept', () {
      final String msg = 'x' * kMaxServerFieldMessageChars;
      expect(
        serverFieldMessageOr(msg, _fallback),
        msg,
        reason: 'the cap is inclusive — only LONGER than the cap is rejected',
      );
    });

    test('edge whitespace is trimmed, not rejected', () {
      expect(serverFieldMessageOr('  Too low  ', _fallback), 'Too low');
    });
  });

  // ── Pre-existing rejections (regression guard) ───────────────────────────

  group('rejects unfit values it already rejected', () {
    test(
      'null',
      () => expect(serverFieldMessageOr(null, _fallback), _fallback),
    );

    test('empty', () => expect(serverFieldMessageOr('', _fallback), _fallback));

    test('whitespace-only', () {
      expect(serverFieldMessageOr('   \t  ', _fallback), _fallback);
    });

    test('longer than the cap', () {
      final String msg = 'x' * (kMaxServerFieldMessageChars + 1);
      expect(serverFieldMessageOr(msg, _fallback), _fallback);
    });

    test('interior LF', () {
      expect(serverFieldMessageOr('line one\nline two', _fallback), _fallback);
    });

    test('interior CR', () {
      expect(serverFieldMessageOr('line one\rline two', _fallback), _fallback);
    });
  });

  // ── Mandatory line breaks beyond \n and \r ───────────────────────────────
  //
  // Flutter's text layout (UAX#14) breaks unconditionally on every one of
  // these. A short string carrying several of them occupies as many lines and
  // pushes a dialog's submit button off-screen — the exact defect the length
  // cap exists to prevent, reached WITHOUT exceeding the cap. Each probe is
  // deliberately far shorter than [kMaxServerFieldMessageChars] so a rejection
  // can only come from the character class, never from the length check.

  group('rejects mandatory line breaks that defeat the length cap', () {
    const Map<String, String> breaks = <String, String>{
      'U+2028 LINE SEPARATOR': '\u2028',
      'U+2029 PARAGRAPH SEPARATOR': '\u2029',
      'U+0085 NEL': '\u0085',
      'U+000B VERTICAL TAB': '\u000B',
      'U+000C FORM FEED': '\u000C',
    };

    breaks.forEach((String label, String ch) {
      test('interior $label falls back', () {
        final String msg = 'ab${ch}cd';
        expect(
          msg.length < kMaxServerFieldMessageChars,
          isTrue,
          reason:
              'precondition: this probe is well under the cap, so rejecting it '
              'proves the character class fired and not the length check',
        );
        expect(
          serverFieldMessageOr(msg, _fallback),
          _fallback,
          reason:
              '$label is a UAX#14 mandatory break: it wraps the slot '
              'regardless of width, so it can blow the layout inside the cap',
        );
      });
    });
  });

  // ── Bidi format controls ─────────────────────────────────────────────────
  //
  // An RLO or an unterminated isolate reorders the glyphs around it, so an
  // untrusted server string can render reversed or visually splice itself into
  // adjacent UI text.

  group('rejects bidi format controls', () {
    const Map<String, String> bidi = <String, String>{
      'U+202E RIGHT-TO-LEFT OVERRIDE': '\u202E',
      'U+202B RIGHT-TO-LEFT EMBEDDING': '\u202B',
      'U+200F RIGHT-TO-LEFT MARK': '\u200F',
      'U+200E LEFT-TO-RIGHT MARK': '\u200E',
      'U+2066 LEFT-TO-RIGHT ISOLATE': '\u2066',
      'U+2069 POP DIRECTIONAL ISOLATE': '\u2069',
      'U+061C ARABIC LETTER MARK': '\u061C',
    };

    bidi.forEach((String label, String ch) {
      test('interior $label falls back', () {
        expect(
          serverFieldMessageOr('ab${ch}cd', _fallback),
          _fallback,
          reason:
              '$label is a Bidi_Control code point — it can render the label '
              'reversed or splice it into adjacent UI text',
        );
      });
    });
  });

  // ── Remaining C0 / C1 controls ───────────────────────────────────────────

  group('rejects other control characters', () {
    test('interior TAB', () {
      expect(
        serverFieldMessageOr('ab\tcd', _fallback),
        _fallback,
        reason:
            'trim() only strips a tab at the EDGES; an interior one expands '
            'unpredictably in a Text widget',
      );
    });

    test('interior NUL', () {
      expect(serverFieldMessageOr('ab\u0000cd', _fallback), _fallback);
    });

    test('interior U+007F DELETE', () {
      expect(serverFieldMessageOr('ab\u007Fcd', _fallback), _fallback);
    });

    test('interior U+0007 BELL', () {
      expect(serverFieldMessageOr('ab\u0007cd', _fallback), _fallback);
    });

    test('interior U+009B (C1 control)', () {
      expect(serverFieldMessageOr('ab\u009Bcd', _fallback), _fallback);
    });
  });
}

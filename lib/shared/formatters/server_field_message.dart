// One rule for "may this server-supplied field message be rendered as a UI
// label?", shared by every surface that shows a backend `fieldErrors` value.
//
// THE GAP THIS FILLS
// ------------------
// `ErrorMapperInterceptor._extractFieldErrors` caps each value at 200
// characters. That is a TRANSPORT guard — it stops an unbounded body from being
// carried around — and it was doing double duty as the only guard before a
// value reached a `Text` widget. 200 characters is far too long for an inline
// field hint: it wraps to five or six lines, pushes a neumorphic card's geometry
// apart, and in a dialog can shove the submit button off-screen. The strings are
// also untranslated internal English, so a long one is both ugly and unreadable
// to the Ukrainian-only audience.
//
// The three call sites that render one (the service-setup row's price slot and
// the two suggestion dialogs' name slots) all now go through
// [serverFieldMessageOr], which keeps a short, plausible server message —
// genuinely the most specific thing anyone can say about a constraint the client
// does not model — and falls back to localized copy for anything blank,
// oversized, or otherwise unfit to display.

/// The longest server-supplied string that still reads as a field hint rather
/// than as a paragraph.
///
/// Chosen against the narrowest slot that renders one: an inline error under a
/// price/name field inside a dialog constrained to 420 dp, at Nunito 12/13.
/// Roughly two full lines there. Deliberately much tighter than
/// `ErrorMapperInterceptor`'s 200-character transport cap, which exists for a
/// different reason.
const int kMaxServerFieldMessageChars = 90;

/// Characters that disqualify a server string from being rendered as a label.
///
/// Two families, both of which defeat the length cap rather than exceed it:
///
///  1. MANDATORY LINE BREAKS (UAX#14 class BK/CR/LF/NL). Flutter's text layout
///     breaks unconditionally on every one of these, so a 20-character string
///     can still occupy six lines and shove a dialog's submit button
///     off-screen — the exact defect [kMaxServerFieldMessageChars] exists to
///     prevent. `\n` and `\r` are only the two best-known members: the C0
///     range also carries VT and FF, and U+0085 NEL, U+2028 LINE SEPARATOR and
///     U+2029 PARAGRAPH SEPARATOR break just as hard.
///  2. BIDI FORMAT CONTROLS (the complete `Bidi_Control` property set: U+061C,
///     U+200E/U+200F, U+202A–U+202E, U+2066–U+2069). An RLO or an unterminated
///     isolate reorders the glyphs around it, letting a server-supplied label
///     render reversed or splice itself into adjacent UI text.
///
/// The remaining C0 controls and U+007F are swept up with the first range:
/// none of them has a legitimate reading inside a field hint, and `\t` in
/// particular expands unpredictably.
///
/// Deliberately matched against the TRIMMED value: `String.trim()` removes
/// these only at the edges (and only the whitespace ones), so an interior
/// occurrence — the one that actually breaks layout — survives it untouched.
/// Written with regex-level `\uXXXX` escapes inside a RAW string on purpose:
/// the alternative embeds literal NUL / NEL / RLO bytes in this source file,
/// where they are invisible to review and survive no tool that normalizes
/// whitespace.
final RegExp _kUnrenderableChars = RegExp(
  r'[\u0000-\u001F\u007F-\u009F\u061C\u200E\u200F'
  r'\u2028\u2029\u202A-\u202E\u2066-\u2069]',
);

/// Returns [raw] when it is fit to render as an inline field error, otherwise
/// [fallback].
///
/// Rejects blank / whitespace-only values, anything longer than
/// [kMaxServerFieldMessageChars], and anything carrying a control, line-break
/// or bidi-override character (see [_kUnrenderableChars] — a multi-line server
/// message is a stack trace or a joined violation list, never a field hint).
///
/// Note this NEVER truncates: a half-sentence ending mid-word reads as a
/// rendering bug and is less useful than the localized sentence. It is a
/// keep-or-replace decision, not a trim.
String serverFieldMessageOr(String? raw, String fallback) {
  if (raw == null) return fallback;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return fallback;
  if (trimmed.length > kMaxServerFieldMessageChars) return fallback;
  if (_kUnrenderableChars.hasMatch(trimmed)) return fallback;
  return trimmed;
}

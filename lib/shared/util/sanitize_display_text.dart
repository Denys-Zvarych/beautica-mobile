// Phase 221 audit fix (mobile-security MEDIUM) - provider-authored free text
// (`Master.locationNote`, `street`, `buildingNo`, `city`) has no
// character-class validation at the backend - only a length cap
// (`@Size(max = ...)`; confirmed absent from `IndependentMasterController` /
// `UserService`). Before this phase, `locationNote`'s single-line
// `overflow: ellipsis` (with no `maxLines`) accidentally bounded the blast
// radius of a hostile Unicode payload to whatever fit on one clipped line.
// The Phase 219-221 fix (explicit `maxLines`, a locality/street split, and a
// tap-to-expand note) removed that accidental mitigation, so a malicious
// master's note can now surface far more of a bidi-override or zero-width
// payload to every client viewing the public profile.
//
// Strips (does not escape - a plain `Text` widget has no markup to
// re-interpret, so removal alone is sufficient and keeps the string
// readable). Expressed as \uXXXX escapes (never literal characters) so this
// file does not itself embed the very control characters it strips:
//   - Bidi format/override controls: U+202A-U+202E (LRE/RLE/PDF/LRO/RLO),
//     U+2066-U+2069 (LRI/RLI/FSI/PDI)
//   - Implicit directional marks: U+061C (ALM), U+200E (LRM), U+200F (RLM) -
//     same Cf "bidi format control" class as the override/isolate controls
//     above; on their own they only bias the direction of adjacent NEUTRAL
//     characters (digits, punctuation) rather than reversing a whole run the
//     way LRO/RLO can, but they belong to the class this file strips.
//   - Zero-width characters: U+200B-U+200D (ZWSP/ZWNJ/ZWJ), U+FEFF
//     (BOM / ZWNBSP)
//
// Pure Dart - no Flutter import.
//
// Phase 223 (a) - promoted from `features/master/presentation/widgets/
// master_text_sanitizer.dart` to `shared/util/` now that the salon feature's
// public profile needs the same sanitization for its own `locationNote`
// field - a second consumer outside `master/` meets the DRY "extract to
// `shared/`" bar this file's original comment was waiting on. The function
// itself is unchanged.
//
// `review/presentation/widgets/review_card.dart` has the same defect class
// but is explicitly out of scope for this fix (already resolved-by-decision,
// backlog rows 65/66); do not fold it in here.
final RegExp _bidiAndZeroWidthPattern = RegExp(
  '[\u061C\u200B-\u200F\u202A-\u202E\u2066-\u2069\uFEFF]',
);

/// Strips Unicode bidi override/format controls and zero-width characters
/// from provider-authored free text before it reaches a client-facing
/// `Text` widget.
String sanitizeDisplayText(String input) =>
    input.replaceAll(_bidiAndZeroWidthPattern, '');

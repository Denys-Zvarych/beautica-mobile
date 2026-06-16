// Service-category request feature — category code (slug) derivation + validation.
//
// The "suggest a category" dialog asks the master only for a Ukrainian display
// name. The uppercase latin wire slug is an internal value the user never sees:
// it is auto-derived from the display name at submit time. The backend enforces
// `^[A-Z][A-Z0-9_]*$` (≤50 chars), so the derived slug is validated before
// submitting.
//
// Pure Dart — no Flutter imports — so it is trivially unit-testable.

/// The backend slug contract: starts with an uppercase letter, then any run of
/// uppercase letters, digits, or underscores. Mirrors the `@Pattern` on
/// `CreateCategoryRequestRequest.name` and the V64 DB CHECK constraint.
final RegExp kCategorySlugPattern = RegExp(r'^[A-Z][A-Z0-9_]*$');

/// Maximum slug length accepted by the backend (`@Size(max = 50)`).
const int kCategorySlugMaxLength = 50;

/// Maximum display-name length accepted by the backend
/// (`CreateCategoryRequestRequest.displayName` `@Size(max = 100)`).
const int kCategoryDisplayNameMaxLength = 100;

/// Stray leading/trailing underscores left by edge separators.
/// Hoisted to file scope so it compiles once instead of per `deriveCategorySlug`
/// call (which runs per keystroke in the suggest-category dialog).
final RegExp _edgeUnderscoresRe = RegExp(r'^_+|_+$');

/// True when the slug starts with a digit (needs a `C_` prefix to satisfy the
/// "must start with a letter" rule). Hoisted — compiled once.
final RegExp _leadingDigitRe = RegExp(r'^[0-9]');

/// Trailing underscores left after length truncation. Hoisted — compiled once.
final RegExp _trailingUnderscoresRe = RegExp(r'_+$');

/// Cyrillic → latin transliteration table (Ukrainian-leaning).
///
/// Lower-case keys only; callers upper-case the input first so a single map
/// covers both cases. Multi-character outputs (e.g. `щ → SHCH`) are handled
/// by emitting the whole run. Anything not in the map and not `[A-Za-z0-9]`
/// becomes a separator (collapsed to a single `_`).
const Map<String, String> _translit = <String, String>{
  'а': 'A',
  'б': 'B',
  'в': 'V',
  'г': 'H',
  'ґ': 'G',
  'д': 'D',
  'е': 'E',
  'є': 'IE',
  'ж': 'ZH',
  'з': 'Z',
  'и': 'Y',
  'і': 'I',
  'ї': 'I',
  'й': 'I',
  'к': 'K',
  'л': 'L',
  'м': 'M',
  'н': 'N',
  'о': 'O',
  'п': 'P',
  'р': 'R',
  'с': 'S',
  'т': 'T',
  'у': 'U',
  'ф': 'F',
  'х': 'KH',
  'ц': 'TS',
  'ч': 'CH',
  'ш': 'SH',
  'щ': 'SHCH',
  'ь': '',
  'ю': 'IU',
  'я': 'IA',
  "'": '',
  '’': '',
  'ʼ': '',
};

/// Derives an uppercase latin slug candidate from arbitrary [input].
///
/// Behaviour:
///   - transliterates Cyrillic to latin (Ukrainian table above);
///   - keeps ASCII letters/digits, upper-cased;
///   - collapses every other run of characters (spaces, punctuation,
///     unmapped glyphs) into a single underscore separator;
///   - trims leading/trailing underscores;
///   - if the result starts with a digit, prefixes `C_` so it satisfies the
///     "must start with a letter" rule;
///   - truncates to [kCategorySlugMaxLength];
///   - returns an empty string when [input] yields no usable characters.
///
/// The output is NOT guaranteed non-empty for all inputs (e.g. "123" alone →
/// "C_123", but "!!!" → ""), so callers still validate with
/// [isValidCategorySlug] before submitting.
String deriveCategorySlug(String input) {
  final buffer = StringBuffer();
  var pendingSeparator = false;

  void appendChunk(String chunk) {
    if (chunk.isEmpty) return;
    if (pendingSeparator && buffer.isNotEmpty) buffer.write('_');
    pendingSeparator = false;
    buffer.write(chunk);
  }

  for (final rune in input.runes) {
    final ch = String.fromCharCode(rune);
    final lower = ch.toLowerCase();

    if (_translit.containsKey(lower)) {
      appendChunk(_translit[lower]!);
      continue;
    }

    final code = ch.codeUnitAt(0);
    final isAsciiLetter =
        (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A);
    final isDigit = code >= 0x30 && code <= 0x39;

    if (isAsciiLetter) {
      appendChunk(ch.toUpperCase());
    } else if (isDigit) {
      appendChunk(ch);
    } else {
      // Any other glyph (space, punctuation, unmapped) is a separator.
      pendingSeparator = true;
    }
  }

  var slug = buffer.toString();
  // Strip any stray leading/trailing underscores produced by edge separators.
  slug = slug.replaceAll(_edgeUnderscoresRe, '');
  if (slug.isEmpty) return '';

  // Must start with a letter; prefix when the first char is a digit.
  if (_leadingDigitRe.hasMatch(slug)) {
    slug = 'C_$slug';
  }

  if (slug.length > kCategorySlugMaxLength) {
    slug = slug.substring(0, kCategorySlugMaxLength);
    // Truncation may leave a trailing underscore — trim it.
    slug = slug.replaceAll(_trailingUnderscoresRe, '');
  }
  return slug;
}

/// Returns `true` when [slug] satisfies the backend slug contract:
/// matches `^[A-Z][A-Z0-9_]*$` and is within [kCategorySlugMaxLength].
bool isValidCategorySlug(String slug) =>
    slug.length <= kCategorySlugMaxLength &&
    kCategorySlugPattern.hasMatch(slug);

/// Case/whitespace-insensitive equality for category wire slugs.
///
/// Defends against drift between a persisted selection and the approved-list
/// entries (e.g. `'brows '` vs `'BROWS'`). Returns `false` when [a] is null.
bool categorySlugMatches(String? a, String b) {
  if (a == null) return false;
  return a.trim().toUpperCase() == b.trim().toUpperCase();
}

/// Graceful degradation for a wire slug with no known Ukrainian label:
/// `NAIL_ART` → `Nail Art`, `BROWS` → `Brows`. Pure transform of the slug;
/// not user-authored copy, so no l10n key is required.
///
/// Used as the fallback label when a service's category slug is absent from the
/// approved-category list (deactivated/retired category, or the provider is
/// still loading / errored) — never leak a raw ALL-CAPS wire value to the user.
String humanizeCategorySlug(String slug) {
  final String trimmed = slug.trim();
  if (trimmed.isEmpty) return trimmed;
  return trimmed
      .split(RegExp(r'[_\s]+'))
      .where((String word) => word.isNotEmpty)
      .map((String word) {
        final String lower = word.toLowerCase();
        return lower[0].toUpperCase() + lower.substring(1);
      })
      .join(' ');
}

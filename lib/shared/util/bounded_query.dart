// Phase 346 (perf L2 / security #2 + #3) — the ONE spelling of "bound a
// search term to a server length limit".
//
// Used by BOTH ends of the settlement autocomplete: the search sheet, which
// commits the bounded term as the provider family key, and the repository,
// which sends it. Because the function is idempotent, the repository's call is
// a no-op on anything the sheet already bounded — so the cached key, the
// searchability check and the wire text are the SAME string, never three
// near-copies that differ past the limit.
//
// Pure Dart: no Flutter imports.

/// Trims [raw], cuts it to at most [maxUtf16Units] UTF-16 code units, and
/// trims again.
///
/// The limit is counted in UTF-16 units because that is what the server's
/// `@Size(max = …)` counts (`String.length()` in Java), so a bounded term can
/// never earn a 400. The cut walks RUNES, so it never splits a surrogate pair:
/// a supplementary-plane character that would straddle the limit is dropped
/// whole rather than leaving a lone high surrogate on the wire.
///
/// The trailing trim keeps the result idempotent — a cut that lands just after
/// a space would otherwise leave a trailing space that the next call strips.
String boundSearchQuery(String raw, int maxUtf16Units) {
  assert(maxUtf16Units >= 0, 'maxUtf16Units must be non-negative');
  final String trimmed = raw.trim();
  if (trimmed.length <= maxUtf16Units) return trimmed;
  final StringBuffer out = StringBuffer();
  int units = 0;
  for (final int rune in trimmed.runes) {
    final int width = rune > 0xFFFF ? 2 : 1;
    if (units + width > maxUtf16Units) break;
    out.writeCharCode(rune);
    units += width;
  }
  return out.toString().trim();
}

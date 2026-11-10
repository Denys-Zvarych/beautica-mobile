// Duplicate-service name key — the client mirror of backend phase 464's
// `ServiceCatalogService.canonicalName` + the V233 index's `lower(...)`.
//
// Pure Dart — no Flutter imports.

/// Runs of two or more U+0020 — backend `SPACE_RUN` (`" {2,}"`).
final RegExp _spaceRun = RegExp(' {2,}');

/// The key two service names are compared by when deciding whether a copy of
/// a service type duplicates another (same type + duration + this key):
/// compatibility-folded, internal space runs collapsed to one, trimmed and
/// lower-cased — so `"Манікюр  класичний"` and `" манікюр КЛАСИЧНИЙ "` match.
///
/// Backend applies full Unicode NFKC (keeping `№`). Dart has no stdlib NFKC
/// and the project carries no normalisation package, so only the
/// compatibility cases a typed or pasted name realistically contains are
/// folded here (see [_foldCompatibility]); any other NFKC-only difference
/// (ligatures, superscripts, half-width katakana, ...) is left to the server
/// 409, which stays the backstop.
String serviceNameKey(String name) => serviceNameCanonical(name).toLowerCase();

/// [name] as the backend stores it — `ServiceCatalogService.canonicalName`:
/// compatibility-folded, internal space runs collapsed, trimmed, case KEPT.
/// Two names with equal canonical forms save to the same stored name, so
/// a typed name that only differs from the saved one by this normalisation
/// is not a rename; a case-only change still is.
String serviceNameCanonical(String name) =>
    _foldCompatibility(name).replaceAll(_spaceRun, ' ').trim();

/// The subset of NFKC relevant to service names: full-width ASCII
/// (U+FF01–U+FF5E) to ASCII, and the Unicode spaces NFKC folds to U+0020
/// (U+00A0, U+2000–U+200A, U+202F, U+205F, U+3000). `№` (U+2116) is left as
/// is, matching the backend's `nfkcKeepingNumeroSign`.
String _foldCompatibility(String value) {
  StringBuffer? out;
  for (var i = 0; i < value.length; i++) {
    final int unit = value.codeUnitAt(i);
    final int folded = _foldUnit(unit);
    if (folded != unit) {
      out ??= StringBuffer(value.substring(0, i));
      out.writeCharCode(folded);
    } else {
      out?.writeCharCode(unit);
    }
  }
  return out?.toString() ?? value;
}

int _foldUnit(int unit) {
  if (unit >= 0xFF01 && unit <= 0xFF5E) return unit - 0xFEE0;
  if (unit == 0x00A0 ||
      (unit >= 0x2000 && unit <= 0x200A) ||
      unit == 0x202F ||
      unit == 0x205F ||
      unit == 0x3000) {
    return 0x20;
  }
  return unit;
}

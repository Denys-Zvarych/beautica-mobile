// Phase 238 — the presentation-side labels a wish-list entry renders.
//
// The domain deliberately stores none of these: `wishlist_service.dart`'s
// header states that `masterInitials` and a duration label are FORMATTING
// concerns, not domain state, and storing them would freeze one locale's
// formatting into the model. The approved preview's fixture carries them
// pre-baked only because a mockup has no formatter to call.
//
// Both wish-list surfaces (the passport page's compact card and the full-list
// page's row) derive them HERE, once, so the two cannot drift — which is the
// whole reason this is a file rather than two private helpers.

// For `String.characters` (grapheme clusters). Imported from Flutter rather
// than `package:characters` directly: the latter is a transitive dependency, so
// naming it here would trip `depend_on_referenced_packages`. This is a
// presentation-layer file and already Flutter-bound through l10n.
import 'package:flutter/widgets.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/formatters/duration_minutes.dart';
import '../../domain/wishlist_service.dart';

/// The labels one wish-list entry renders, derived from its domain model.
extension WishlistEntryLabels on WishlistService {
  /// The master's name, or the localised fallback when the wire carried
  /// neither name part.
  ///
  /// The mapper leaves [masterName] EMPTY rather than inventing a placeholder
  /// (its own header says the render site owns that copy, because it is a copy
  /// decision and not a data one). This is that render site.
  String displayMasterName(AppLocalizations l10n) =>
      masterName.isEmpty ? l10n.wishlistMasterFallbackName : masterName;

  /// Up to two initials for the avatar disc, taken from the FIRST character of
  /// each of the first two whitespace-separated name parts.
  ///
  /// Uses `characters` (grapheme clusters), not `[0]`: Dart indexes a String by
  /// UTF-16 code unit, so a name whose first letter is outside the BMP would
  /// yield half a surrogate pair and render as «□». Ukrainian names are all BMP
  /// today, but a display name is free-text a user typed.
  ///
  /// Falls back to the localised master fallback's own initial rather than to
  /// an empty disc: a blank avatar reads as a failed image load, which this is
  /// not.
  String masterInitials(AppLocalizations l10n) {
    final String name = displayMasterName(l10n);
    final List<String> parts = name
        .split(RegExp(r'\s+'))
        .where((String p) => p.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) return '';
    final StringBuffer out = StringBuffer();
    for (final String part in parts.take(2)) {
      out.write(part.characters.first.toUpperCase());
    }
    return out.toString();
  }

  /// «60 хв», «2 год 30 хв» — the shipped duration formatter, shared with every
  /// other surface that states a service length.
  ///
  /// Returns null when the duration is not known. The mapper maps an absent
  /// wire value to 0 precisely so it is displayable as "no duration known"
  /// rather than fabricated, and «0 хв» would be a fabrication: a service that
  /// takes no time is not a thing. Both render sites drop the label entirely.
  String? durationLabel() =>
      durationMinutes > 0 ? DurationMinutes.format(durationMinutes) : null;

  /// Whether there is a price to draw at all.
  ///
  /// [WishlistService.priceLabel] resolves to an empty string for a legacy
  /// definition that carries no price. An empty pill is a recessed well
  /// announcing a figure that is not there, so both surfaces omit it.
  bool get showsPrice => priceLabel.isNotEmpty;
}

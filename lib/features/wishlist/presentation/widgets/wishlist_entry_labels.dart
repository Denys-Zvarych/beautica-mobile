// Phase 238 — the presentation-side labels a wish-list entry renders.
// Phase F adds the SALON-arm equivalents ([displayTitle], [attributionIcon],
// [avatarImageUrl], [avatarFallbackIcon], [avatarInitials]) so both wish-list
// surfaces can render either arm without branching on [WishlistSourceType]
// themselves.
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
//
// [masterInitials] / [displayMasterName] are MASTER-ARM ONLY and `assert`
// against being called on a SALON row — a SALON row has no master to name.
// Call sites that must render correctly on BOTH arms use [displayTitle] /
// [avatarInitials] instead, which branch internally and never reach the
// asserting getters on a SALON row.

// Material rather than the bare `widgets.dart` this file used pre-Phase F:
// `attributionIcon` needs `Icons`/`IconData`, which only `material.dart`
// exports. `material.dart` re-exports `widgets.dart` in full, so
// `String.characters` (see [masterInitials]) is still available through it.
import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/formatters/duration_minutes.dart';
import '../../domain/wishlist_service.dart';

/// The labels one wish-list entry renders, derived from its domain model.
extension WishlistEntryLabels on WishlistService {
  /// The master's name, or the localised fallback when the wire carried
  /// neither name part.
  ///
  /// MASTER-ARM ONLY — asserts against a SALON row, which has no master to
  /// name. Use [displayTitle] at any call site that must render both arms.
  ///
  /// The mapper leaves [WishlistService.masterName] EMPTY rather than
  /// inventing a placeholder (its own header says the render site owns that
  /// copy, because it is a copy decision and not a data one). This is that
  /// render site.
  String displayMasterName(AppLocalizations l10n) {
    assert(
      sourceType == WishlistSourceType.master,
      'displayMasterName must not be called on a SALON row — use displayTitle',
    );
    final String name = masterName ?? '';
    return name.isEmpty ? l10n.wishlistMasterFallbackName : name;
  }

  /// The salon's name, or the localised fallback when the wire carried none.
  ///
  /// SALON-ARM ONLY — mirrors [displayMasterName]'s policy for the other arm.
  /// Private: [displayTitle] is the arm-agnostic call site everything else
  /// should use.
  String _displaySalonName(AppLocalizations l10n) {
    assert(
      sourceType == WishlistSourceType.salon,
      '_displaySalonName must not be called on a MASTER row',
    );
    final String name = (salonName ?? '').trim();
    return name.isEmpty ? l10n.wishlistSalonFallbackName : name;
  }

  /// The attribution line's TEXT — the master's display name for a MASTER
  /// row, the salon's name for a SALON row. The one call site both wish-list
  /// surfaces should use; never branch on [sourceType] at the call site
  /// instead.
  String displayTitle(AppLocalizations l10n) => switch (sourceType) {
    WishlistSourceType.master => displayMasterName(l10n),
    WishlistSourceType.salon => _displaySalonName(l10n),
  };

  /// The attribution line's GLYPH — a person for a MASTER row, a storefront
  /// for a SALON row. The system's established salon glyph
  /// (`result_thumbnail.dart`, `booking_card.dart`, `salon_cover_widgets.dart`).
  IconData get attributionIcon => switch (sourceType) {
    WishlistSourceType.master => Icons.person_outline_rounded,
    WishlistSourceType.salon => Icons.storefront_rounded,
  };

  /// [HubAvatar.imageUrl] for this entry — the salon's avatar for a SALON
  /// row, or null for a MASTER row.
  ///
  /// MASTER rows deliberately do NOT plumb [WishlistService.masterAvatarUrl]
  /// through here: neither wish-list surface has ever rendered a master
  /// photo (both show initials only), and starting to now would be an
  /// unrelated visual change riding on Phase F's salon-rendering work —
  /// exactly the kind of master-row regression that phase was told to avoid.
  String? get avatarImageUrl =>
      sourceType == WishlistSourceType.salon ? salonAvatarUrl : null;

  /// [HubAvatar.fallbackIcon] for this entry — [attributionIcon] for a SALON
  /// row (a brand name's initials read poorly; the glyph is the signal), or
  /// null for a MASTER row (which keeps its initials disc).
  IconData? get avatarFallbackIcon =>
      sourceType == WishlistSourceType.salon ? attributionIcon : null;

  /// [HubAvatar.initials] for this entry — [masterInitials] for a MASTER row,
  /// or '' for a SALON row (whose disc renders [avatarFallbackIcon] instead
  /// and never falls through to text).
  String avatarInitials(AppLocalizations l10n) =>
      sourceType == WishlistSourceType.salon ? '' : masterInitials(l10n);

  /// The filled CTA's label — «Записатись» for a MASTER row (it books a
  /// specific master straight away), «Обрати майстра» for a SALON row (Phase
  /// G: tapping it does not book anything by itself, it opens that salon's
  /// masters tab filtered to the performing masters, so the client still has
  /// to pick one — see `wishlist_rebook.dart`'s Phase G section). Both wish-
  /// list surfaces (compact card + full row) call THIS rather than branching
  /// on [sourceType] themselves, mirroring [displayTitle]'s policy.
  String bookCtaLabel(AppLocalizations l10n) => switch (sourceType) {
    WishlistSourceType.master => l10n.wishlistBookCta,
    WishlistSourceType.salon => l10n.wishlistChooseMasterCta,
  };

  /// Up to two initials for the avatar disc, taken from the FIRST character of
  /// each of the first two whitespace-separated name parts.
  ///
  /// MASTER-ARM ONLY — asserts against a SALON row; see [avatarInitials] for
  /// the arm-agnostic call site.
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
    assert(
      sourceType == WishlistSourceType.master,
      'masterInitials must not be called on a SALON row — use avatarInitials',
    );
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

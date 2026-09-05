// Phase 21.16 — the salon-affiliation card.
//
// «Салон» — the ONE salon a staff member belongs to, rendered on their own
// first-person profile as a compact context link: logo mark, salon name, and
// the resolved locality line. Ported from the approved preview's
// `_SalonAffiliationCard` (`docs/signup-designs/SalonManagementDesign/lib/
// screens/admin_own_profile_screen.dart:215-258`).
//
// ── WHY NOT [SalonHubCard] ────────────────────────────────────────────────
// The obvious-looking reuse is the «Мої салони» hub card, which also draws a
// salon as logo + name + locality — but the approved preview draws a
// deliberately QUIETER object, and the two diverge on six independent axes:
// a 44 dp logo vs 58, `VelvetSpacing.md` padding vs `md + 2`, a card-title
// name vs `displayName21`, a single plain locality line vs a pin-glyph
// two-line address block, no «Основний» badge, no chevron, and no press
// depression (the hub card is a required-`onTap` navigation row; this one is
// optionally tappable and reads as context, not as a list item). Six optional
// parameters to make one widget paint both would be a fork wearing a
// parameter list. What IS reused is every leaf and every rule below it:
// [NeumorphicCard], [SalonLogo], the same [resolvedLocalityProvider] +
// [buildFullAddressLine] locality chain [SalonHubCard] and
// `_ManagementHeroCard` share, and the same monogram derivation.
//
// ── NO LOGO IMAGE ─────────────────────────────────────────────────────────
// The phase doc asks for `logoUrl`. `Salon.avatarUrl` exists on the domain
// model but is rendered by NOTHING in the shipped app — every salon mark in
// Beautica today is [SalonLogo]'s monogram-on-gradient (the hub card, the
// management hero, the rotate-destination picker). This card follows that
// convention rather than introducing a second, inconsistent salon mark; when
// [SalonLogo] learns to paint a real logo, this call site inherits it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/location/domain/resolved_locality.dart';
import 'package:beautica_mobile/features/location/state/resolved_locality_provider.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/address_lines.dart';

import '../../domain/salon.dart';
import 'salon_cover_widgets.dart';

/// A raised card naming the salon its viewer belongs to: logo, name, locality.
///
/// Read-only by default. [onTap] is optional and, when null, the card renders
/// with no gesture affordance at all — which is what the stand-alone route
/// wants (there is no shell tab to send the viewer back to) and exactly what
/// the approved preview draws.
class SalonAffiliationCard extends ConsumerWidget {
  const SalonAffiliationCard({super.key, required this.salon, this.onTap});

  final Salon salon;

  /// Optional "take me to this salon" handler. Null → inert card.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    // The SAME locality chain `SalonHubCard` and `_ManagementHeroCard` use —
    // `salon.city` is legacy free-text frozen since Phase 10.6 (see
    // [Salon.city]), so the taxonomy ids are resolved through the shared,
    // keepAlive-backed [resolvedLocalityProvider] and the legacy string is
    // only consulted when the salon carries no [Salon.cityId] at all. While a
    // real `cityId` is still resolving the line stays BLANK rather than
    // showing a possibly-wrong legacy city first.
    final ResolvedLocality? resolved = ref
        .watch(
          resolvedLocalityProvider(
            oblastId: salon.oblastId,
            cityId: salon.cityId,
            districtId: salon.districtId,
          ),
        )
        .value;
    final bool hasTaxonomyCity = salon.cityId.trim().isNotEmpty;
    final String? cityName =
        resolved?.city?.name ?? (hasTaxonomyCity ? null : salon.city);
    final String? locality = buildFullAddressLine(
      cityName: cityName,
      districtName: resolved?.district?.name,
    );
    final String name = salon.name.trim();
    final String? monogram = name.isEmpty ? null : name[0].toUpperCase();

    final Widget card = NeumorphicCard(
      padding: const EdgeInsets.all(VelvetSpacing.md),
      child: Row(
        children: <Widget>[
          SalonLogo(diameter: VelvetSizes.affiliationLogo, monogram: monogram),
          const SizedBox(width: VelvetSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  name,
                  key: const Key('salon-affiliation-card-name'),
                  style: VelvetText.cardTitle(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                // Omitted entirely, not rendered blank, while the locality is
                // unresolved or absent — an empty line would leave the card
                // visibly lopsided against the 44 dp logo.
                if (locality != null) ...<Widget>[
                  const SizedBox(height: VelvetSpacing.xs - 1),
                  Text(
                    locality,
                    key: const Key('salon-affiliation-card-locality'),
                    style: VelvetText.salonHubAddressLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    final VoidCallback? onTap = this.onTap;
    if (onTap == null) {
      // Inert: no Semantics button node, no gesture detector — the card is
      // orientation, not an action.
      return card;
    }
    return Semantics(
      button: true,
      label: l10n.salonAffiliationCardSemanticLabel(name),
      child: GestureDetector(onTap: onTap, child: card),
    );
  }
}

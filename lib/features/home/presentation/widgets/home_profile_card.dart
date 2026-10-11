// Phase 13.7 — Home hub: profile block (Step 2).
//
// Ported verbatim from the preview's `_ProfileBlock` inner class.
// No card surface — sits directly on the background like the mockup.
// Shows: circular avatar with camera badge, name, city (tappable), phone.
// Phase 367 — the avatar is the shared live `SelfAvatarEditor`.
//
// 2026-09-26 (user-reported) — the private `_MetaLine` here was a
// byte-for-byte fork of `PassportScreen._ProfileBlock._line`. Both are now
// the promoted `ProfileMetaLine` (see
// `lib/shared/widgets/profile_meta_line.dart`); the locality row opts into
// `maxLines: 2` so a long composed saved-settlement label wraps instead of
// being silently collapsed to one ellipsised line.

import 'package:flutter/material.dart';

import '../../../../core/media/upload/avatar_editor_binding.dart';

import '../../../../core/icons/app_icon.dart';
import '../../../../core/icons/beautica_asset_icons.dart';
import '../../../../core/theme/brand_colors.dart';
import '../../../../core/theme/velvet_geometry.dart';
import '../../../../core/theme/velvet_text.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/profile_meta_line.dart';
import '../../domain/home_hub_models.dart';
import '../../../location/presentation/saved_settlement_label.dart';

/// The profile block at the top of the Home Hub.
///
/// The avatar is the shared [SelfAvatarEditor] (Phase 367 — live own-avatar
/// upload). [onLocation] opens the locality picker.
class HomeProfileCard extends StatelessWidget {
  const HomeProfileCard({
    super.key,
    required this.profile,
    required this.onLocation,
  });

  final ClientProfileSummary profile;
  final VoidCallback onLocation;

  // Pre-composed text style to avoid per-build TextStyle allocation.
  static final TextStyle _nameStyle = VelvetText.displayName21;

  // Shared location-pin SVG sized/tinted to match the Material glyph it replaced
  // (16 px, [BrandColors.accent] — same as [ProfileMetaLine]'s Material fallback).
  static const Widget _locationIcon = AppIcon(
    BeauticaAssetIcons.locationMarker,
    size: 16,
    color: BrandColors.accent,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // «м. Львів, Львівська обл.», composed exactly as the picker composes it;
    // the bare [ClientProfileSummary.city] when there is nothing to compose.
    final String locality = profile.localityLabel(
      savedSettlementLabel(l10n, profile.settlement),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Phase 367 — the OWN photo (or monogram) with the live camera
        // badge: the SAME shared own-avatar editor every role's own profile
        // uses (it replaced a dead white badge that did nothing on tap).
        SelfAvatarEditor(
          key: const Key('home_hub_change_photo_button'),
          initials: profile.initials,
          editorKey: const Key('home-hub-avatar-editor'),
        ),
        // No spacer: the editor carries its own badge→text gutter
        // ([SelfAvatarEditor.textGap]).
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SizedBox(height: 4),
              Text(
                profile.fullName,
                key: const Key('home_profile_name'),
                style: _nameStyle,
                maxLines: 2,
                softWrap: true,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: VelvetSpacing.sm + 2),
              // Location row — tappable. maxLines: 2 — a long composed
              // saved-settlement label (village + hromada + oblast) must
              // wrap, not silently collapse to one ellipsised line.
              if (locality.isNotEmpty)
                ProfileMetaLine(
                  icon: Icons.location_on_rounded,
                  iconWidget: _locationIcon,
                  text: locality,
                  onTap: onLocation,
                  textKey: const Key('home_profile_city'),
                  maxLines: 2,
                )
              else
                ProfileMetaLine(
                  icon: Icons.location_on_rounded,
                  iconWidget: _locationIcon,
                  text: l10n.homeHubLocationPlaceholder,
                  onTap: onLocation,
                  maxLines: 2,
                ),
              const SizedBox(height: VelvetSpacing.sm),
              // Phone row
              if (profile.phone.isNotEmpty)
                ProfileMetaLine(
                  icon: Icons.call_rounded,
                  text: profile.phone,
                  textKey: const Key('home_profile_phone'),
                )
              else
                ProfileMetaLine(
                  icon: Icons.call_rounded,
                  text: l10n.homeHubPhonePlaceholder,
                  textKey: const Key('home_profile_phone'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

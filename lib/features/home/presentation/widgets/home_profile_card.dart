// Phase 13.7 — Home hub: profile block (Step 2).
//
// Ported verbatim from the preview's `_ProfileBlock` inner class.
// No card surface — sits directly on the background like the mockup.
// Shows: circular avatar with camera badge, name, city (tappable), phone.

import 'package:flutter/material.dart';

import '../../../../core/icons/app_icon.dart';
import '../../../../core/icons/beautica_asset_icons.dart';
import '../../../../core/theme/brand_colors.dart';
import '../../../../core/theme/velvet_geometry.dart';
import '../../../../core/theme/velvet_text.dart';
import '../../../../l10n/app_localizations.dart';
import '../widgets/hub_widgets.dart';
import '../../domain/home_hub_models.dart';

/// The profile block at the top of the Home Hub.
///
/// [onCamera] opens the photo-picker (placeholder until Phase 13.7.1 wires
/// image upload). [onLocation] opens the locality picker.
class HomeProfileCard extends StatelessWidget {
  const HomeProfileCard({
    super.key,
    required this.profile,
    required this.onCamera,
    required this.onLocation,
  });

  final ClientProfileSummary profile;
  final VoidCallback onCamera;
  final VoidCallback onLocation;

  // Pre-composed text style to avoid per-build TextStyle allocation.
  static final TextStyle _nameStyle = VelvetText.displayName().copyWith(
    fontSize: 21,
  );

  // Shared location-pin SVG sized/tinted to match the Material glyph it replaced
  // (16 px, [BrandColors.accent] — same as [_MetaLine]'s Material fallback).
  static const Widget _locationIcon = AppIcon(
    BeauticaAssetIcons.locationMarker,
    size: 16,
    color: BrandColors.accent,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Avatar with camera badge bottom-right.
        SizedBox(
          height: 100,
          width: 100,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              HubAvatar(initials: profile.initials, size: 96, fontSize: 30),
              Positioned(
                right: 0,
                bottom: 0,
                child: Semantics(
                  button: true,
                  label: l10n.homeHubChangePhotoLabel,
                  child: GestureDetector(
                    key: const Key('home_hub_change_photo_button'),
                    onTap: onCamera,
                    child: Container(
                      height: 30,
                      width: 30,
                      decoration: BoxDecoration(
                        color: BrandColors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: BrandColors.base, width: 2),
                      ),
                      child: const Icon(
                        Icons.photo_camera_rounded,
                        size: 15,
                        color: BrandColors.accentDeep,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: VelvetSpacing.md),
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
              // Location row — tappable
              if (profile.city.isNotEmpty)
                _MetaLine(
                  icon: Icons.location_on_rounded,
                  iconWidget: _locationIcon,
                  text: profile.city,
                  onTap: onLocation,
                  textKey: const Key('home_profile_city'),
                )
              else
                _MetaLine(
                  icon: Icons.location_on_rounded,
                  iconWidget: _locationIcon,
                  text: l10n.homeHubLocationPlaceholder,
                  onTap: onLocation,
                ),
              const SizedBox(height: VelvetSpacing.sm),
              // Phone row
              if (profile.phone.isNotEmpty)
                _MetaLine(
                  icon: Icons.call_rounded,
                  text: profile.phone,
                  textKey: const Key('home_profile_phone'),
                )
              else
                _MetaLine(
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

class _MetaLine extends StatelessWidget {
  const _MetaLine({
    required this.icon,
    required this.text,
    this.iconWidget,
    this.onTap,
    this.textKey,
  });

  final IconData icon;

  /// Optional pre-built icon widget (e.g. an [AppIcon] SVG). When non-null it
  /// replaces the Material [Icon] built from [icon]; callers must size/tint it
  /// to match (16 px, [BrandColors.accent]).
  final Widget? iconWidget;
  final String text;
  final VoidCallback? onTap;

  /// Optional key applied to the inner [Text] so finders can target a specific
  /// meta line (e.g. the city) by key rather than matching its literal string.
  final Key? textKey;

  static final TextStyle _style = VelvetText.body().copyWith(
    fontSize: 14,
    color: BrandColors.text,
  );

  @override
  Widget build(BuildContext context) {
    final Widget row = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        iconWidget ?? Icon(icon, size: 16, color: BrandColors.accent),
        const SizedBox(width: VelvetSpacing.sm),
        Flexible(
          child: Text(
            text,
            key: textKey,
            style: _style,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
    if (onTap == null) return row;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: row,
    );
  }
}

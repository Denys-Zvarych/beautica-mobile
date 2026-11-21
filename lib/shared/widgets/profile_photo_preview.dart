// 2026-11-21 — tap a profile photo → the full-screen photo viewer.
//
// The ONE tap wrapper every opted-in avatar (ClientAvatar, ProfileAvatar,
// MasterAvatarBadge, SalonLogo) goes through, so the entry affordance, its
// semantics and the viewer it opens live in one place. It paints nothing:
// a wrapped avatar is pixel-identical at rest. No photo (monogram / icon
// well) → the child is returned untouched, not tappable.
//
// The viewer is the shared `PortfolioPhotoViewer` (via
// [showProfilePhotoViewer]) — never a second viewer.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/portfolio_photo_viewer.dart';

class ProfilePhotoPreviewTap extends StatelessWidget {
  const ProfilePhotoPreviewTap({
    super.key,
    required this.imageUrl,
    required this.child,
    this.fullImageUrl,
  });

  /// The avatar's (display) photo; `null` → no preview.
  final String? imageUrl;

  /// The full-size photo, when the model has one; else [imageUrl] is shown.
  final String? fullImageUrl;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final String? url = fullImageUrl ?? imageUrl;
    if (imageUrl == null || url == null) return child;
    void open() => showProfilePhotoViewer(context, url);
    return Semantics(
      button: true,
      label: AppLocalizations.of(context).profilePhotoViewAction,
      onTap: open,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: open,
        child: child,
      ),
    );
  }
}

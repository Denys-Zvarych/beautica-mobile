// Phase 071 — «Фото» source sheet: gallery / camera / (optional) remove.
//
// Built entirely from the shared VelvetTouch sheet pieces promoted out of the
// sort sheet (`VelvetSheetChrome`, `VelvetSheetOptionRow`, `showVelvetSheet`).

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/velvet_sheet.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

enum ImageSourceChoice { gallery, camera, remove }

/// Shows the sheet; resolves with the choice, or `null` when dismissed.
Future<ImageSourceChoice?> showImageSourceSheet(
  BuildContext context, {
  bool canRemove = false,
}) {
  return showVelvetSheet<ImageSourceChoice>(
    context,
    builder: (BuildContext ctx) => ImageSourceSheet(canRemove: canRemove),
  );
}

class ImageSourceSheet extends StatelessWidget {
  const ImageSourceSheet({super.key, this.canRemove = false});

  final bool canRemove;

  static const double _iconSize = 22;

  void _pop(BuildContext context, ImageSourceChoice choice) =>
      ModalRoute.of(context)?.navigator?.pop(choice);

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return VelvetSheetChrome(
      title: l10n.imageSourceTitle,
      children: <Widget>[
        VelvetSheetOptionRow(
          tapKey: const Key('image-source-gallery'),
          label: l10n.imageSourceGallery,
          leading: const Icon(
            Symbols.photo_library,
            color: BrandColors.textSecondary,
            size: _iconSize,
          ),
          onTap: () => _pop(context, ImageSourceChoice.gallery),
        ),
        VelvetSheetOptionRow(
          tapKey: const Key('image-source-camera'),
          label: l10n.imageSourceCamera,
          leading: const Icon(
            Symbols.photo_camera,
            color: BrandColors.textSecondary,
            size: _iconSize,
          ),
          onTap: () => _pop(context, ImageSourceChoice.camera),
        ),
        if (canRemove)
          VelvetSheetOptionRow(
            tapKey: const Key('image-source-remove'),
            label: l10n.imageSourceRemove,
            labelStyle: VelvetText.discSortOption.copyWith(
              color: BrandColors.error,
            ),
            leading: const Icon(
              Symbols.delete,
              color: BrandColors.error,
              size: _iconSize,
            ),
            onTap: () => _pop(context, ImageSourceChoice.remove),
          ),
      ],
    );
  }
}

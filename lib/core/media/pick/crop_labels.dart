// Phase 071 — localised strings for the NATIVE crop screen.
//
// The gateway has no BuildContext, so the caller (which has one) resolves the
// ARB strings and passes them in. Null labels → the platform defaults.
//
// Phase 369 — [CropLabels.forKind] gives each [MediaKind] its own crop title
// (the salon logo / cover say WHAT is being cropped); [CropLabels.of] is
// unchanged and stays the avatar / service-photo default.

import 'package:beautica_mobile/core/media/pick/media_kind.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

final class CropLabels {
  const CropLabels({
    required this.title,
    required this.doneButton,
    required this.cancelButton,
  });

  factory CropLabels.of(AppLocalizations l10n) => CropLabels(
    title: l10n.cropTitle,
    doneButton: l10n.cropDone,
    cancelButton: l10n.cropCancel,
  );

  /// The per-kind labels: the crop title names the salon logo / cover; every
  /// other kind gets [CropLabels.of].
  factory CropLabels.forKind(AppLocalizations l10n, MediaKind kind) {
    final String title = switch (kind) {
      MediaKind.avatar || MediaKind.servicePhoto => l10n.cropTitle,
      MediaKind.salonLogo => l10n.cropTitleSalonLogo,
      MediaKind.salonCover => l10n.cropTitleSalonCover,
    };
    return CropLabels(
      title: title,
      doneButton: l10n.cropDone,
      cancelButton: l10n.cropCancel,
    );
  }

  final String title;
  final String doneButton;
  final String cancelButton;
}

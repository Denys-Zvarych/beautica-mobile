// Phase 071 — localised strings for the NATIVE crop screen.
//
// The gateway has no BuildContext, so the caller (which has one) resolves the
// ARB strings and passes them in. Null labels → the platform defaults.

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

  final String title;
  final String doneButton;
  final String cancelButton;
}

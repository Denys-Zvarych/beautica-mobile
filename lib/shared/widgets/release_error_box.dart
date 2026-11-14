import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/theme/brand_colors.dart';
import '../../core/theme/velvet_geometry.dart';
import '../../core/theme/velvet_text.dart';
import '../../l10n/app_localizations.dart';

/// The release-build replacement for Flutter's default [ErrorWidget] — a
/// flat grey box that takes every pixel its parent allows, so a throw inside
/// an unbounded column (e.g. the week header) could blank the whole body.
///
/// This box is compact and sizes to its content: under loose or unbounded
/// constraints it is one line tall; under tight constraints the extra space
/// stays transparent instead of turning grey. Debug/profile keep the red
/// screen — [installReleaseErrorWidget] is a no-op there.
class ReleaseErrorBox extends StatelessWidget {
  const ReleaseErrorBox({super.key});

  static const Key boxKey = Key('release_error_box');

  @override
  Widget build(BuildContext context) {
    // The error may sit above `MaterialApp` — no localizations, possibly no
    // `Directionality`: fall back to the icon alone.
    final AppLocalizations? l10n = Localizations.of<AppLocalizations>(
      context,
      AppLocalizations,
    );
    final bool hasText =
        l10n != null && Directionality.maybeOf(context) != null;
    return Align(
      alignment: Alignment.topCenter,
      widthFactor: 1,
      heightFactor: 1,
      child: Padding(
        padding: const EdgeInsets.all(VelvetSpacing.sm),
        child: DecoratedBox(
          key: boxKey,
          decoration: BoxDecoration(
            color: BrandColors.baseEmphasis,
            borderRadius: BorderRadius.circular(VelvetRadii.field),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: VelvetSpacing.md,
              vertical: VelvetSpacing.sm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              textDirection: TextDirection.ltr,
              children: <Widget>[
                const Icon(
                  Icons.error_outline_rounded,
                  size: VelvetSpacing.md,
                  color: BrandColors.error,
                  textDirection: TextDirection.ltr,
                ),
                if (hasText) ...<Widget>[
                  const SizedBox(width: VelvetSpacing.sm),
                  Flexible(
                    child: Text(
                      l10n.errUnknown,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: VelvetText.body().copyWith(
                        color: BrandColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Installs [ReleaseErrorBox] as the global [ErrorWidget.builder] in release
/// builds only. Reporting is untouched: `FlutterError.onError` (Sentry chain
/// in `crash_reporting.dart`) still receives every error — this changes only
/// what is painted in place of the failed subtree.
void installReleaseErrorWidget({bool releaseMode = kReleaseMode}) {
  if (!releaseMode) return;
  ErrorWidget.builder = (FlutterErrorDetails details) =>
      const ReleaseErrorBox();
}

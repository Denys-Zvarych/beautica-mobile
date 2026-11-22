// The list-tail notice + explicit retry shown after a "load next page" request
// failed (nothing re-fires by itself).
//
// PROMOTED from the failure branch of `NotificationsLoadMoreFooter` so every
// paged list shares ONE retry footer: a centred [VelvetText.body] message and a
// `VelvetText.link` «Спробувати знову» action sitting on a
// [NeumorphicIconButton.extent]-high hit target. Geometry is byte-for-byte what
// the notifications footer shipped.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

class LoadMoreRetryFooter extends StatelessWidget {
  const LoadMoreRetryFooter({
    super.key,
    required this.message,
    required this.onRetry,
    required this.retryKey,
  });

  /// Localised «Couldn't load …» notice.
  final String message;
  final VoidCallback onRetry;

  /// Key of the tappable retry action (hosts keep their own, for tests).
  final Key retryKey;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: VelvetSpacing.sm),
      child: Column(
        children: <Widget>[
          Text(message, textAlign: TextAlign.center, style: VelvetText.body()),
          InkWell(
            key: retryKey,
            onTap: onRetry,
            borderRadius: BorderRadius.circular(VelvetRadii.field),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: NeumorphicIconButton.extent,
                minWidth: NeumorphicIconButton.extent,
              ),
              child: Center(
                widthFactor: 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: VelvetSpacing.md,
                  ),
                  child: Text(l10n.retryLabel, style: VelvetText.link()),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

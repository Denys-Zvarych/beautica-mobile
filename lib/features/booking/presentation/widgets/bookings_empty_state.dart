// Phase 14.3 — «МОЇ ЗАПИСИ» empty state, shown per-tab when a status
// partition has no bookings. Icon + text + a neumorphic CTA to `/search`.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

class BookingsEmptyState extends StatelessWidget {
  const BookingsEmptyState({super.key, required this.onFindMaster});

  /// Invoked by «Знайти майстра» — navigates to `/search`.
  final VoidCallback onFindMaster;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      key: const Key('my-bookings-empty'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.all(VelvetSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.event_note_outlined,
                size: 48,
                color: BrandColors.accent,
              ),
              const SizedBox(height: VelvetSpacing.md),
              Text(
                l10n.myBookingsEmptyTitle,
                textAlign: TextAlign.center,
                style: VelvetText.subheading(),
              ),
              const SizedBox(height: VelvetSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: NeumorphicButton(
                  key: const Key('my-bookings-empty-find-master'),
                  label: l10n.myBookingsEmptyCta,
                  icon: Icons.search_rounded,
                  onPressed: onFindMaster,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

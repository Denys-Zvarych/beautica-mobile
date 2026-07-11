// Phase 14.16 — SalonMasterStrip: the "who you're booking with" context card
// for the salon booking flow's step-3 "Час" screen.
//
// NOT a fork of `widgets/master_strip.dart`'s existing `MasterStrip` — that
// widget is a SHARED, already-in-production part of the independent-master
// flow (`SlotDateScreen`/`ServiceSelectorSheet`, Phase 14.1), constructed
// from a bare [Master] with no services/duration display. The approved
// `docs/signup-designs/SalonBookingTime/lib/widgets/master_strip.dart`
// preview widget is a DIFFERENT shape (it also renders the services THIS
// master performs + their summed duration, since the salon flow's whole
// point is "N appointments, one per master"), so porting it under the same
// `MasterStrip` name/file would either silently change `SlotDateScreen`'s
// unrelated strip or require a second, conflicting `MasterStrip` class in
// the same library. This file is the SAME visual treatment (the camel-wash
// `#EDE4D5` card + raised avatar) transcribed under a distinct name instead.
// [MonthCalendar]/[SlotChip] remain the only widgets this port shares
// verbatim with the independent-master flow — see the phase docs'
// "Architecture decision" section for why those two (and only those two)
// are locked as shared.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/duration_minutes.dart';

import '../../domain/salon_master_schedule.dart';
import 'master_strip.dart' show masterRoleLabel;

/// A compact "whose appointment you're picking" strip pinned to the top of
/// each per-master slide — a camel-wash card with a small raised avatar, the
/// master's name/role, the services THIS master performs, and their summed
/// appointment length.
class SalonMasterStrip extends StatelessWidget {
  const SalonMasterStrip({
    super.key,
    required this.schedule,
    required this.avatarGradient,
  });

  final SalonMasterSchedule schedule;

  /// Avatar gradient — the `SalonMasterCard` treatment, stable across this
  /// screen's slides.
  final List<Color> avatarGradient;

  static const Color _stripSurface = Color(0xFFEDE4D5);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String name = '${schedule.firstName} ${schedule.lastName}'.trim();
    final String role = masterRoleLabel(schedule.type, l10n);
    final String servicesLabel = schedule.services
        .map((service) => service.name)
        .join(' · ');
    final String durationLabel = DurationMinutes.format(
      schedule.summedDurationMinutes,
    );

    return Semantics(
      label: l10n.salonScheduleMasterStripSemantics(
        name,
        servicesLabel,
        durationLabel,
      ),
      child: NeumorphicCard(
        color: _stripSurface,
        padding: const EdgeInsets.all(VelvetSpacing.sm + 4),
        child: Row(
          children: <Widget>[
            Container(
              height: 48,
              width: 48,
              decoration: BoxDecoration(
                // RRect (radius = half the 48dp side) reads as a circle but
                // avoids Impeller-GLES's broken circle box-shadow blur path
                // (a blurred BoxShadow on BoxShape.circle rasterizes as a hard
                // white square under the opengles backend).
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: avatarGradient,
                ),
                boxShadow: VelvetShadows.extrudedSmall,
                border: Border.all(
                  color: BrandColors.white.withValues(alpha: 0.35),
                  width: 2,
                ),
              ),
              child: Center(
                child: Icon(
                  Icons.person_rounded,
                  color: BrandColors.white.withValues(alpha: 0.82),
                  size: 24,
                ),
              ),
            ),
            const SizedBox(width: VelvetSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    l10n.bookingMasterStripLabel,
                    style: VelvetText.masterStripLabel,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    name,
                    style: VelvetText.masterStripName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Icon(
                        Icons.check_circle_outline_rounded,
                        size: 13,
                        color: BrandColors.accent,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          servicesLabel.isEmpty ? role : servicesLabel,
                          style: VelvetText.masterStripServiceLabel,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: VelvetSpacing.sm),
            _DurationPill(label: durationLabel),
          ],
        ),
      ),
    );
  }
}

/// A small raised camel-wash pill carrying the master's summed appointment
/// length.
class _DurationPill extends StatelessWidget {
  const _DurationPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.sm + 2,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: BrandColors.base,
        borderRadius: BorderRadius.circular(999),
        boxShadow: VelvetShadows.extrudedSmall,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.schedule_rounded,
            size: 14,
            color: BrandColors.accentDeep,
          ),
          const SizedBox(width: 4),
          Text(label, style: VelvetText.masterStripDurationLabel),
        ],
      ),
    );
  }
}

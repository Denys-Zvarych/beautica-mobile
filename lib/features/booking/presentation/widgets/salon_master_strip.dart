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
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/duration_minutes.dart';

import '../../domain/salon_master_schedule.dart';
import 'master_strip.dart' show masterRoleLabel;
import 'master_strip_shell.dart';

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

    return MasterStripShell(
      semanticsLabel: l10n.salonScheduleMasterStripSemantics(
        name,
        servicesLabel,
        durationLabel,
      ),
      name: name,
      topLabel: l10n.bookingMasterStripLabel,
      avatarGradient: avatarGradient,
      avatarBordered: true,
      middleGap: 4,
      middleLine: Row(
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
      trailing: _DurationPill(label: durationLabel),
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

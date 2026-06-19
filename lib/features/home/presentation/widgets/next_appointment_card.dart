// Phase 13.7 — Next appointment card (Step 5).
//
// Shows the soonest upcoming booking (PENDING / CONFIRMED). When null, renders
// the "Немає майбутніх записів" empty state.
//
// Ported verbatim from `_NextAppointmentSection` in the approved preview.
// Backend 19.3 is not yet ready — the caller passes null and the empty state
// displays. When 19.3 ships, the caller passes the real NextAppointment.
//
// Uses IntrinsicHeight on the main content Row (avatar + details + actions)
// so the three columns stay top-aligned without needing CrossAxisAlignment.stretch
// against an unbounded cross axis.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/brand_colors.dart';
import '../../../../core/theme/velvet_geometry.dart';
import '../../../../core/theme/velvet_text.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../routing/route_names.dart';
import '../../domain/home_hub_models.dart';
import '../widgets/hub_widgets.dart';

/// Next appointment section. [appointment] is null when there is no upcoming
/// booking.
class NextAppointmentCard extends StatelessWidget {
  const NextAppointmentCard({
    super.key,
    required this.appointment,
    required this.onReschedule,
    required this.onCancel,
    required this.onAddToGoogleCalendar,
    required this.onAddToAppleCalendar,
  });

  final NextAppointment? appointment;
  final VoidCallback onReschedule;
  final VoidCallback onCancel;
  final VoidCallback onAddToGoogleCalendar;
  final VoidCallback onAddToAppleCalendar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final appt = appointment;

    if (appt == null) {
      return Column(
        key: const Key('next_appointment_empty'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          HubSectionTitle(title: l10n.homeHubNextAppointmentTitle),
          const SizedBox(height: VelvetSpacing.md),
          HubFlatCard(
            padding: const EdgeInsets.symmetric(
              horizontal: VelvetSpacing.md,
              vertical: VelvetSpacing.lg,
            ),
            child: HubEmptyState(
              icon: Icons.event_busy_rounded,
              message: l10n.homeHubNoUpcomingAppointments,
              ctaLabel: l10n.homeHubFindMaster,
              onCta: () => context.push(RouteNames.clientSearch),
            ),
          ),
        ],
      );
    }

    return Column(
      key: const Key('next_appointment_populated'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        HubSectionTitle(
          title: l10n.homeHubNextAppointmentTitle,
          trailing: CountdownChip(target: appt.startsAt),
        ),
        const SizedBox(height: VelvetSpacing.md),
        HubFlatCard(
          padding: const EdgeInsets.all(VelvetSpacing.md),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                HubPhoto(initials: appt.masterInitials, size: 96, radius: 16),
                const SizedBox(width: VelvetSpacing.md - 2),
                // Middle: date / time / service / master / location.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(appt.dateLabel, style: _dateLabelStyle),
                      const SizedBox(height: 2),
                      Text(appt.timeLabel, style: _timeLabelStyle),
                      const SizedBox(height: 2),
                      Text(appt.service, style: _serviceStyle),
                      const SizedBox(height: VelvetSpacing.xs + 2),
                      _MetaRow(
                        icon: Icons.person_outline_rounded,
                        text: appt.masterName,
                      ),
                      const SizedBox(height: 2),
                      _MetaRow(
                        icon: Icons.location_on_rounded,
                        text: appt.location,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: VelvetSpacing.sm),
                // Right: action stack.
                // Overflow-hardening: 96dp is the natural width, but on sub-360dp
                // devices photo (96) + details + this column overflows the Row.
                // Flexible + a 96dp max lets the column shrink instead of
                // overflowing; the button labels FittedBox-scale within it.
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 96),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        HubFilledButton(
                          key: const Key('next_appt_reschedule_button'),
                          label: l10n.homeHubRescheduleAppointment,
                          onTap: onReschedule,
                        ),
                        const SizedBox(height: VelvetSpacing.sm),
                        HubOutlineButton(
                          key: const Key('next_appt_cancel_button'),
                          label: l10n.homeHubCancelAppointment,
                          danger: true,
                          onTap: onCancel,
                        ),
                        const SizedBox(height: VelvetSpacing.sm),
                        // Overflow-hardening: the two fixed-size calendar
                        // buttons + gap exceed the action column's width on
                        // sub-360dp devices at large text scale (the column is
                        // squeezed to ~61dp, the Row's natural width is ~84dp).
                        // Each button is Flexible so the Row shrinks the buttons
                        // to fit instead of overflowing; FittedBox keeps the
                        // glyphs visible within the smaller box.
                        Row(
                          children: <Widget>[
                            Flexible(
                              child: HubSquareIconButton(
                                key: const Key('next_appt_google_cal_button'),
                                semanticLabel: l10n.homeHubAddToGoogleCalendar,
                                onTap: onAddToGoogleCalendar,
                                builder: (_) => const FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: GoogleCalendarGlyph(),
                                ),
                              ),
                            ),
                            const SizedBox(width: VelvetSpacing.sm),
                            Flexible(
                              child: HubSquareIconButton(
                                key: const Key('next_appt_apple_cal_button'),
                                semanticLabel: l10n.homeHubAddToAppleCalendar,
                                onTap: onAddToAppleCalendar,
                                builder: (_) => const FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Icon(
                                    Icons.apple,
                                    size: 22,
                                    color: BrandColors.text,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// Pre-composed text styles — hoisted to module-level statics so build() never
// allocates a new TextStyle object on each call.
final TextStyle _metaStyle = VelvetText.body().copyWith(
  fontSize: 12.5,
  color: BrandColors.text,
);

final TextStyle _dateLabelStyle = VelvetText.body().copyWith(fontSize: 12.5);
final TextStyle _timeLabelStyle = VelvetText.heading().copyWith(fontSize: 26);
final TextStyle _serviceStyle = VelvetText.bodyStrong().copyWith(
  fontSize: 13.5,
);

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 14, color: BrandColors.accent),
        const SizedBox(width: VelvetSpacing.xs + 1),
        Flexible(
          child: Text(text, style: _metaStyle, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

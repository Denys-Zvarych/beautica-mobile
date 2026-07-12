// ClientBookingConflictDialog — the client-side "you already have a booking
// then" modal (backend commit f95d8fd, CLIENT_BOOKING_CONFLICT 409).
//
// Distinct from the generic slot-taken 409 (`ConflictFailure`, still shown
// via a plain transient SnackBar on the confirm screens): this failure is
// dense enough — clashing service name, master name, AND a time window — that
// a transient one-line SnackBar would either truncate or vanish before the
// client finishes reading it. A small modal gives it room, and a structured
// two-row recap (mirroring `LabelledRow`, the SAME atom
// `BookingSummaryCards` / `SalonAppointmentCard` already use for exactly this
// "label above value" shape) reads faster than one run-on sentence.
//
// Tone: calm and informational, NOT alarming — this is a routine scheduling
// clash the client can resolve in one tap, not a system failure. No red
// error icon/circle (that vocabulary is reserved for genuine failures, e.g.
// `NeumorphicTextField`'s inline field errors) — a soft camel-tinted circle
// with a calendar glyph, matching the CTA gradient family, signals "you have
// a conflicting appointment" without reading as a warning.
//
// Chrome is 1:1 with `CategoryRequestDialog`
// (`services/presentation/widgets/category_request_dialog.dart`): the same
// transparent `Dialog` shell, `insetPadding`, `maxWidth: 420` constraint, and
// single `NeumorphicCard` surface — no new modal chrome invented for this one
// dialog.
//
// NAVIGATION SPLIT (why this dialog never calls `context.pop()` itself): a
// `showDialog` overlay route has no `InheritedGoRouter` ancestor in its own
// `BuildContext`, so a go_router screen-navigation call from inside the
// dialog would throw (see `core/navigation/overlay_navigation.dart`'s file
// header). This dialog only ever dismisses ITS OWN overlay route via
// `dismissOverlay`, resolving the awaited `Future<bool?>` with whether the
// client chose "Обрати інший час" — the CALLER (a real screen context, e.g.
// `BookingConfirmScreen`) decides whether to pop back to the slot picker.
// Mirrors `CategoryRequestDialog`'s own caller-decides contract.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/navigation/overlay_navigation.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';

import 'labelled_row.dart';
import 'section_rule.dart';

/// Opens the client-booking-conflict dialog for [failure].
///
/// Resolves to `true` when the client tapped "Обрати інший час" (the caller
/// should then navigate back to slot selection — typically `context.pop()`
/// back to the slot-time screen), or `false`/`null` when they dismissed the
/// dialog (tapped "Залишитись тут", the scrim, or the OS back gesture) —
/// the caller should do nothing further, leaving the confirm screen and its
/// in-progress selection exactly as they were.
Future<bool?> showClientBookingConflictDialog(
  BuildContext context,
  ClientBookingConflictFailure failure,
) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => ClientBookingConflictDialog(failure: failure),
  );
}

/// The "you already have a booking then" modal (VelvetTouch neumorphic).
///
/// See the file header for why this exists as a dedicated modal rather than
/// reusing the plain SnackBar the generic [ConflictFailure] shows.
class ClientBookingConflictDialog extends StatelessWidget {
  const ClientBookingConflictDialog({super.key, required this.failure});

  final ClientBookingConflictFailure failure;

  // PERF: hoisted to avoid a .copyWith() allocation per build — same pattern
  // as _NeumorphicTextFieldState in core/widgets/neumorphic.dart.
  static final TextStyle _subtitleStyle = VelvetText.body().copyWith(
    color: BrandColors.textSecondary,
  );
  static final TextStyle _secondaryCtaStyle = VelvetText.body().copyWith(
    color: BrandColors.muted,
    fontWeight: FontWeight.w700,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String windowLabel = formatBookingWindow(
      failure.startsAt,
      failure.endsAt,
    );

    // Mirrors CategoryRequestDialog's exact Dialog shell — see that file's
    // build() comment for why insetPadding (not a manual keyboard-inset
    // calculation) is the correct approach here too.
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.lg,
        vertical: VelvetSpacing.xl,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: NeumorphicCard(
          key: const Key('client-booking-conflict-dialog'),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Center(child: _ConflictBadge()),
                const SizedBox(height: VelvetSpacing.lg),
                Text(
                  l10n.bookingConflictClientTitle,
                  textAlign: TextAlign.center,
                  style: VelvetText.subheading(),
                ),
                const SizedBox(height: VelvetSpacing.sm),
                Text(
                  l10n.bookingConflictClientSubtitle,
                  textAlign: TextAlign.center,
                  style: _subtitleStyle,
                ),
                const SizedBox(height: VelvetSpacing.xl),

                // The clashing booking's structured recap — the SAME
                // LabelledRow/SectionRule atoms `BookingSummaryCards` /
                // `SalonAppointmentCard` use, so a client who has already
                // seen a booking-details card recognizes the shape instantly.
                LabelledRow(
                  label: l10n.bookingServiceLabel,
                  value: failure.serviceName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SectionRule(),
                LabelledRow(
                  label: l10n.bookingMasterLabel,
                  value: failure.masterName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SectionRule(),
                LabelledRow(label: l10n.bookingTimeLabel, value: windowLabel),
                const SizedBox(height: VelvetSpacing.xl),

                NeumorphicButton(
                  key: const Key('client-booking-conflict-pick-another-time'),
                  label: l10n.bookingConflictClientPrimaryCta,
                  icon: Icons.edit_calendar_outlined,
                  onPressed: () => dismissOverlay(context, true),
                ),
                const SizedBox(height: VelvetSpacing.sm),
                Center(
                  child: TextButton(
                    key: const Key('client-booking-conflict-stay'),
                    onPressed: () => dismissOverlay(context, false),
                    child: Text(
                      l10n.bookingConflictClientSecondaryCta,
                      style: _secondaryCtaStyle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The calm, non-alarming icon badge — a soft camel-tinted circle (NOT the
/// red error-circle vocabulary reserved for genuine failures) around a
/// calendar glyph. See the file header's Tone note.
class _ConflictBadge extends StatelessWidget {
  const _ConflictBadge();

  static const double _diameter = 56;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _diameter,
      width: _diameter,
      decoration: BoxDecoration(
        color: BrandColors.accent.withValues(alpha: 0.16),
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.event_repeat_rounded,
        color: BrandColors.accentDeep,
        size: 28,
      ),
    );
  }
}

/// Phase 14.3 — «Скасувати запис?» — the destructive confirmation, which
/// also collects the client's cancellation note.
///
/// Ported from `docs/signup-designs/MyBookings/lib/widgets/cancel_booking_dialog.dart`.
///
/// ## ⚠⚠ PORTER, READ THIS FIRST — DO NOT BUILD A PICKER OUT OF THE ENUM
///
/// `PATCH /bookings/{id}/cancel` takes TWO things: `cancellationReason` — an
/// enum, `@NotNull`/required (`CLIENT_NO_SHOW` / `CLIENT_CANCELLED` /
/// `PROVIDER_UNAVAILABLE` / `DUPLICATE` / `OTHER`) — and `comment`, OPTIONAL
/// free text. This dialog collects ONLY the free text. The client-facing
/// dialog always sends `CLIENT_CANCELLED`, implicitly and invisibly (see
/// `BookingRepository.cancelBooking`) — the client picks nothing. Showing a
/// reason picker built from that enum would put a machine-facing taxonomy
/// code («DUPLICATE») in front of a client cancelling a haircut.
///
/// ## Chrome — mirrored from the shipped app, not invented
///
/// The shell is 1:1 with `ClientBookingConflictDialog`, itself 1:1 with
/// `CategoryRequestDialog`: a transparent [Dialog], `insetPadding` (h: lg,
/// v: xl), a `maxWidth: 420` [ConstrainedBox], one [NeumorphicCard] surface —
/// then a centred badge circle, a `subheading()` title, a muted `body()`
/// subline, a [LabelledRow]/[SectionRule] recap, a primary pill and a centred
/// [TextButton] secondary. The confirm button is filled `error` (the ONE
/// saturated red surface in the feature — see [_DestructiveButton]'s doc);
/// the back-out is the plain text button, mirroring `DeleteServiceDialog`
/// (the app's only other destructive confirmation).
///
/// ## Backing out is the safe path
///
/// `barrierDismissible: true`, the OS back gesture, and an explicit «Не
/// скасовувати» all resolve to `null` — nothing is cancelled unless the
/// client deliberately taps the red button. The destructive action is the
/// only one that requires intent; every reflex is safe.
library;

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/navigation/overlay_navigation.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';

import '../../domain/booking.dart';
import 'labelled_row.dart';
import 'section_rule.dart';

/// Opens the cancellation confirmation for [booking].
///
/// Resolves to the client's note (possibly an EMPTY string — they confirmed
/// but wrote nothing) when the cancellation is confirmed, and to `null` when
/// they backed out by any means. `null` means *do nothing*.
Future<String?> showCancelBookingDialog(BuildContext context, Booking booking) {
  return showDialog<String>(
    context: context,
    barrierDismissible: true,
    builder: (_) => CancelBookingDialog(booking: booking),
  );
}

class CancelBookingDialog extends StatefulWidget {
  const CancelBookingDialog({super.key, required this.booking});

  final Booking booking;

  @override
  State<CancelBookingDialog> createState() => _CancelBookingDialogState();
}

class _CancelBookingDialogState extends State<CancelBookingDialog> {
  final TextEditingController _note = TextEditingController();

  /// The backend caps `client_cancellation_note` at 1000; `BookingCommentField`
  /// (the booking flow's own note composer) uses 500 and this matches it — the
  /// client is writing a sentence to a person, not an essay.
  static const int _maxLength = 500;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final Booking b = widget.booking;

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
          key: const Key('cancel-booking-dialog'),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Center(child: _DestructiveBadge()),
                const SizedBox(height: VelvetSpacing.md),

                Text(
                  l10n.cancelBookingDialogTitle,
                  textAlign: TextAlign.center,
                  style: VelvetText.subheading(),
                ),
                const SizedBox(height: VelvetSpacing.xs),
                Text(
                  l10n.cancelBookingDialogSubtitle,
                  textAlign: TextAlign.center,
                  style: VelvetText.bookSuccessSubline,
                ),
                const SizedBox(height: VelvetSpacing.md),

                // ── WHAT is about to be destroyed — an irreversible action
                //    must show you the thing it is about to take away.
                LabelledRow(
                  label: l10n.bookingServiceLabel,
                  value: b.serviceName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  compactText: true,
                ),
                const SectionRule(dense: true),
                LabelledRow(
                  label: l10n.bookingMasterLabel,
                  value: '${b.masterFirstName} ${b.masterLastName}'.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  compactText: true,
                ),
                const SectionRule(dense: true),
                LabelledRow(
                  label: l10n.bookingWhenLabel,
                  value: formatFullDate(b.startAt),
                  detail: formatTimeRange(b.startAt, b.durationMinutes),
                  compactText: true,
                ),
                const SizedBox(height: VelvetSpacing.md),

                // ── The note. Optional, and the client is told plainly that
                //    a real person will read it.
                _NoteField(controller: _note, maxLength: _maxLength),
                const SizedBox(height: VelvetSpacing.md),

                // ── The destructive action — the ONLY way anything is
                //    cancelled.
                _DestructiveButton(
                  label: l10n.cancelBookingConfirmCta,
                  icon: Icons.close_rounded,
                  onPressed: () => dismissOverlay(context, _note.text.trim()),
                ),
                const SizedBox(height: VelvetSpacing.xs),

                // ── The safe way out. Also the scrim, also the back gesture.
                Center(
                  child: TextButton(
                    key: const Key('cancel-booking-keep'),
                    onPressed: () => dismissOverlay(context),
                    child: Text(
                      l10n.cancelBookingKeepCta,
                      style: VelvetText.feedbackMutedSm,
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

/// The badge circle. `ClientBookingConflictDialog` deliberately uses a
/// *camel* circle (a routine scheduling clash, not a failure); this dialog
/// IS a destructive state, so it takes the red — the exact line that other
/// dialog draws.
class _DestructiveBadge extends StatelessWidget {
  const _DestructiveBadge();

  static const double _diameter = 56;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _diameter,
      width: _diameter,
      decoration: BoxDecoration(
        color: BrandColors.error.withValues(alpha: 0.16),
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.event_busy_rounded,
        color: BrandColors.error,
        size: 28,
      ),
    );
  }
}

/// The cancellation note — mirrors `BookingCommentField`'s shape (a muted
/// `label()` caption, a [NeumorphicInset] well, a multiline field, a live
/// `x / max` counter isolated via [ValueListenableBuilder]) with this
/// dialog's own copy, which `BookingCommentField` does not expose overrides
/// for.
class _NoteField extends StatelessWidget {
  const _NoteField({required this.controller, required this.maxLength});

  final TextEditingController controller;
  final int maxLength;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(l10n.cancelBookingNoteLabel, style: VelvetText.label()),
        const SizedBox(height: VelvetSpacing.xs - 2),
        // The provider's own note composer tells THEM the client will read
        // their words; this is the same courtesy in reverse.
        Text(l10n.cancelBookingNotePromise, style: VelvetText.feedbackMutedSm),
        const SizedBox(height: VelvetSpacing.xs),
        NeumorphicInset(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: VelvetSpacing.sm,
              vertical: VelvetSpacing.xs,
            ),
            child: TextField(
              key: const Key('cancel-booking-note-field'),
              controller: controller,
              maxLines: 3,
              minLines: 3,
              maxLength: maxLength,
              cursorColor: BrandColors.accentDeep,
              style: VelvetText.body(),
              buildCounter:
                  (
                    BuildContext context, {
                    required int currentLength,
                    required int? maxLength,
                    required bool isFocused,
                  }) => null,
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintText: l10n.cancelBookingNoteHint,
                hintStyle: VelvetText.body().copyWith(
                  color: BrandColors.placeholder,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: VelvetSpacing.xs - 2),
        Align(
          alignment: Alignment.centerRight,
          // Only the counter Text listens to the controller — the dialog
          // never rebuilds while typing.
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (BuildContext context, TextEditingValue v, Widget? _) {
              return Text(
                l10n.cancelBookingNoteCounter(
                  v.text.characters.length,
                  maxLength,
                ),
                style: VelvetText.feedbackMutedXs,
              );
            },
          ),
        ),
      ],
    );
  }
}

/// The destructive pill — the ONLY saturated red surface in the feature.
/// Filled `error` with cream text (4.83:1, clears AA) — `DeleteServiceDialog`'s
/// exact treatment for a destructive confirm. Filled here and nowhere else:
/// on «Деталі запису» the «Скасувати запис» button is a quiet base-tone pill
/// with a red edge and glyph — findable and unmistakably destructive, but not
/// a red slab. Once the client has said "yes, I want to cancel this", the
/// confirm button is allowed to be as loud as the act.
class _DestructiveButton extends StatefulWidget {
  const _DestructiveButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  State<_DestructiveButton> createState() => _DestructiveButtonState();
}

class _DestructiveButtonState extends State<_DestructiveButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        key: const Key('cancel-booking-confirm'),
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onPressed();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: VelvetSizes.cta,
          decoration: BoxDecoration(
            color: BrandColors.error,
            borderRadius: BorderRadius.circular(VelvetRadii.button),
            boxShadow: _pressed
                ? null
                : <BoxShadow>[
                    BoxShadow(
                      color: BrandColors.error.withValues(alpha: 0.32),
                      offset: const Offset(0, 5),
                      blurRadius: 12,
                    ),
                  ],
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(widget.icon, size: 18, color: BrandColors.white),
              const SizedBox(width: VelvetSpacing.xs),
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VelvetText.cta(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

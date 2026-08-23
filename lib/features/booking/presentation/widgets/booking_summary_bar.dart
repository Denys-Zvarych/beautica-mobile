// Phase 14.1 — BookingSummaryBar: the pinned "Послуги та ціни" shelf.
//
// Unifies the approved preview's TWO nearly-identical widgets —
// `BookingServiceSelection/lib/widgets/booking_summary.dart` (`BookingSummaryBar`,
// step 1) and `BookingSlotPicker/lib/widgets/booking_summary.dart`
// (`BookingConfirmBar`, steps 2a/2b) — into one reusable widget, exactly the
// way the SECOND preview already unified them (`showChosenWindow` /
// `chosenWindowLabel` flags). Reused verbatim across all three screens of this
// phase (`ServiceSelectorSheet`, `SlotDateScreen`, `SlotTimeScreen`).
//
// Unlike the preview (which formats price/duration by re-parsing display
// STRINGS with regex — see the preview's `_parsePrice`/`_parseDuration`), this
// port sums the already-typed [MasterService.priceMin]/[priceMax]/
// [durationMinutes] fields directly and renders via the existing
// `ServicePriceDisplay` / `DurationMinutes` shared formatters — no string
// parsing, no generated-DTO leakage, and it can never desync from a
// display-string format change.
//
// The itemized expand/collapse list itself now lives in
// `SelectedServicesShelf` (extracted so `SalonMasterSelectionScreen`'s
// `_AssignConfirmBar` and `SalonTimeScreen`'s `ScheduleConfirmBar` can pin
// the exact same selected-services shelf above their own progress-counter +
// CTA content) — this widget composes that shared widget rather than
// building the toggle/list itself, so there is exactly one implementation of
// the expand/collapse interaction.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/booking_price_labels.dart';

import 'schedule_progress_hint.dart';
import 'selected_services_shelf.dart';

/// The pinned booking-summary shelf shared by every screen of the booking
/// flow. Carries the "Послуги та ціни" list + "Разом" total + primary CTA, and
/// (when [showChosenWindow] is true) a chosen-appointment-window block.
///
/// The itemized selected-service list ([SelectedServicesShelf]) is collapsed
/// by default behind a tap-to-expand toggle on the label row — with several
/// services selected it used to always reserve up to
/// [SelectedServicesShelf.listMaxHeight] of vertical space, crowding the
/// screen. The "Разом" total and primary CTA always stay visible regardless
/// of the toggle state; only the itemized list is gated.
class BookingSummaryBar extends StatelessWidget {
  const BookingSummaryBar({
    super.key,
    required this.services,
    required this.ctaLabel,
    required this.ctaIcon,
    required this.enabled,
    required this.onAction,
    this.chosenWindowLabel,
    this.showChosenWindow = false,
    this.onRemove,
    this.progressScheduled,
    this.progressTotal,
  });

  /// The client's selected service(s) (0..n). Empty renders the muted
  /// empty-state prompt + disabled CTA.
  final List<MasterService> services;

  /// CTA caption — "Далі" (selector / date screen) or "Підтвердити" (time
  /// screen).
  final String ctaLabel;
  final IconData ctaIcon;

  /// Whether the CTA is tappable. The bar itself also disables the CTA
  /// whenever [services] is empty, regardless of this flag.
  final bool enabled;

  /// Fires when the (enabled) CTA is tapped.
  final VoidCallback onAction;

  /// Fires when the client removes a service from the itemized list via its
  /// per-item "×" affordance — a SECOND way to deselect a service, alongside
  /// unchecking it in the catalogue above. Callers wire this to the exact
  /// same toggle used by the catalogue tile (e.g. `_toggleService(id)`), so
  /// both removal paths converge on identical end-state.
  ///
  /// `null` (the default) renders no remove affordance at all — this keeps
  /// [SlotDateScreen]/[SlotTimeScreen] (which carry an immutable, already-past
  /// selection step) visually unchanged, since there is nothing to wire a
  /// removal to at that point in the flow.
  final void Function(MasterService service)? onRemove;

  /// The chosen booked window, e.g. "вт, 14 лип · 14:00–18:30", or `null`
  /// when no slot is chosen yet. Only consulted when [showChosenWindow].
  final String? chosenWindowLabel;

  /// Whether to render the chosen-window block above the CTA (the time
  /// screen only).
  final bool showChosenWindow;

  /// Phase 275 — additive progress-well slot for the salon schedule hub's
  /// footer: how many of [progressTotal] rows are scheduled so far. `null`
  /// (the default, alongside [progressTotal]) renders nothing extra at all —
  /// every existing call site (service selector, independent date/time
  /// screens) is unaffected. Both must be non-null together to render the
  /// shared [ScheduleProgressHint] well (the same widget
  /// `ScheduleConfirmBar` renders on the salon per-master "Час" screen —
  /// promoted out of that file's former private `_ProgressHint`, see
  /// `schedule_progress_hint.dart`, rather than a second near-duplicate
  /// progress readout).
  final int? progressScheduled;

  /// See [progressScheduled].
  final int? progressTotal;

  static const Color _shelfSurface = Color(0xFFEDE4D5);

  // No local State: the itemized list's own expand/collapse toggle is now
  // fully self-contained inside `SelectedServicesShelf` (its own
  // StatefulWidget), so this widget no longer owns any mutable state itself
  // — a plain StatelessWidget composing `SelectedServicesShelf` alongside
  // `_TotalRow`/`_ChosenWindow`/the CTA.

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bool hasSelection = services.isNotEmpty;
    return Container(
      decoration: const BoxDecoration(
        color: _shelfSurface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(VelvetRadii.card),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: BrandColors.shadowDarkCard,
            offset: Offset(0, -9),
            blurRadius: 24,
          ),
          BoxShadow(
            color: BrandColors.shadowLightStrong,
            offset: Offset(0, -1),
            blurRadius: 3,
            spreadRadius: -1,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            VelvetSpacing.lg,
            VelvetSpacing.lg,
            VelvetSpacing.lg,
            VelvetSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: hasSelection
                ? _populatedChildren(l10n)
                : _emptyChildren(l10n),
          ),
        ),
      ),
    );
  }

  List<Widget> _emptyChildren(AppLocalizations l10n) {
    return <Widget>[
      Padding(
        padding: const EdgeInsets.symmetric(vertical: VelvetSpacing.xs),
        child: Text(
          l10n.bookingEmptySelectionPrompt,
          textAlign: TextAlign.center,
          style: VelvetText.bookSummaryMuted14,
        ),
      ),
      const SizedBox(height: VelvetSpacing.md),
      NeumorphicButton(
        key: const Key('booking-summary-cta'),
        label: ctaLabel,
        icon: ctaIcon,
        onPressed: null,
      ),
    ];
  }

  List<Widget> _populatedChildren(AppLocalizations l10n) {
    // Map the typed price/duration fields onto `BookingTotalTerm` (never a
    // re-parsed display string) and let the shared formatter do the summing.
    // Handing over TERMS rather than pre-summed figures is deliberate: `+` is
    // not protective, so two out-of-range terms that cancel
    // (`1e30 + -1e30 == 0.0`) would clear a sum-level check and state a
    // confident, fictional «0 ₴» on the very screen where the client agrees to
    // a price. Same mapping as `IndependentScheduleConfirmBar._totals`.
    final ({String priceLabel, String? durationLabel}) totals =
        formatBookingTotalsFromTerms(
          services.map(
            (MasterService s) => (
              min: s.priceMin,
              max: s.priceType == ServicePriceType.range
                  ? (s.priceMax ?? s.priceMin)
                  : s.priceMin,
              minutes: s.durationMinutes,
            ),
          ),
        );
    return <Widget>[
      // The extracted, self-contained expand/collapse itemized list — its
      // own internal `ValueListenableBuilder` means an expand/collapse tap
      // never rebuilds this StatelessWidget nor `_TotalRow`/`_ChosenWindow`/
      // the CTA below.
      SelectedServicesShelf(services: services, onRemove: onRemove),
      const SizedBox(height: VelvetSpacing.md),
      Container(height: 1, color: BrandColors.faint.withValues(alpha: 0.5)),
      const SizedBox(height: VelvetSpacing.sm + 2),
      _TotalRow(
        l10n: l10n,
        price: totals.priceLabel,
        duration: totals.durationLabel,
      ),
      const SizedBox(height: VelvetSpacing.md),
      if (showChosenWindow) _ChosenWindow(l10n: l10n, label: chosenWindowLabel),
      if (showChosenWindow && chosenWindowLabel != null)
        const SizedBox(height: VelvetSpacing.md),
      if (progressScheduled case final int scheduled)
        if (progressTotal case final int total) ...<Widget>[
          ScheduleProgressHint(scheduled: scheduled, total: total),
          const SizedBox(height: VelvetSpacing.md),
        ],
      NeumorphicButton(
        key: const Key('booking-summary-cta'),
        label: ctaLabel,
        icon: ctaIcon,
        onPressed: enabled ? onAction : null,
      ),
    ];
  }
}

/// The chosen-appointment-window block on the time screen. Renders nothing
/// before a slot is chosen; a camel-accented "Запис:" well once one is.
class _ChosenWindow extends StatelessWidget {
  const _ChosenWindow({required this.l10n, required this.label});

  final AppLocalizations l10n;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final bool chosen = label != null;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      switchInCurve: Curves.easeOutCubic,
      child: chosen
          ? Semantics(
              key: const ValueKey<bool>(true),
              label: l10n.bookingChosenWindowSemantics(label!),
              child: NeumorphicInset(
                radius: VelvetRadii.field,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: VelvetSpacing.md,
                    vertical: VelvetSpacing.sm + 4,
                  ),
                  child: Row(
                    children: <Widget>[
                      const Icon(
                        Icons.event_available_rounded,
                        size: 18,
                        color: BrandColors.accentDeep,
                      ),
                      const SizedBox(width: VelvetSpacing.sm),
                      Text(
                        l10n.bookingChosenWindowLabel,
                        style: VelvetText.bookFeedbackSec13,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          label!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: VelvetText.bookAccentValue14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(key: ValueKey<bool>(false)),
    );
  }
}

/// The pinned "Разом" total line.
class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.l10n, required this.price, this.duration});

  final AppLocalizations l10n;
  final String price;
  final String? duration;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${l10n.bookingTotalLabel} ${duration ?? ''} $price',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          Text(l10n.bookingTotalLabel, style: VelvetText.bodyStrong()),
          if (duration != null) ...<Widget>[
            const SizedBox(width: VelvetSpacing.sm),
            Text(duration!, style: VelvetText.feedbackMutedSm),
          ],
          const Spacer(),
          Text(price, style: VelvetText.bookPriceMd),
        ],
      ),
    );
  }
}

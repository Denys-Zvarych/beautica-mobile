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

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/duration_minutes.dart';
import 'package:beautica_mobile/shared/formatters/service_count_label.dart';
import 'package:beautica_mobile/shared/formatters/service_price_display.dart';

/// The pinned booking-summary shelf shared by every screen of the booking
/// flow. Carries the "Послуги та ціни" list + "Разом" total + primary CTA, and
/// (when [showChosenWindow] is true) a chosen-appointment-window block.
///
/// The itemized selected-service list is collapsed by default behind a
/// tap-to-expand toggle on the label row — with several services selected it
/// used to always reserve up to [_listMaxHeight] of vertical space, crowding
/// the screen. The "Разом" total and primary CTA always stay visible
/// regardless of the toggle state; only the itemized list is gated.
class BookingSummaryBar extends StatefulWidget {
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

  static const double _listMaxHeight = 188;
  static const Color _shelfSurface = Color(0xFFEDE4D5);

  @override
  State<BookingSummaryBar> createState() => _BookingSummaryBarState();
}

class _BookingSummaryBarState extends State<BookingSummaryBar> {
  /// Ephemeral UI-only state — purely a display toggle for the itemized
  /// list, so it does not need a Riverpod provider. Always collapsed on
  /// first build, regardless of selection size (uniform, predictable
  /// behaviour across all three host screens).
  ///
  /// Held in a [ValueNotifier] + narrow [ValueListenableBuilder] (mobile-perf
  /// finding) rather than a plain `bool` `State` field driving `setState`:
  /// an expand/collapse tap used to re-run the ENTIRE `_populatedChildren()`
  /// method, rebuilding `_TotalRow`/`_ChosenWindow`/the CTA button even
  /// though none of their inputs changed. Now only the toggle row + itemized
  /// list rebuild per tap; the rest of `_populatedChildren()` is built once
  /// per actual widget-config change. Mirrors the same idiom already used in
  /// `service_selector_sheet.dart` (`_selectedIdsNotifier` /
  /// `ValueListenableBuilder<Set<String>>`) for its own bottom-shelf rebuild.
  final ValueNotifier<bool> _expandedNotifier = ValueNotifier<bool>(false);

  void _toggleExpanded() => _expandedNotifier.value = !_expandedNotifier.value;

  @override
  void dispose() {
    _expandedNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bool hasSelection = widget.services.isNotEmpty;
    return Container(
      decoration: const BoxDecoration(
        color: BookingSummaryBar._shelfSurface,
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
                ? _populatedChildren(context, l10n)
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
        label: widget.ctaLabel,
        icon: widget.ctaIcon,
        onPressed: null,
      ),
    ];
  }

  List<Widget> _populatedChildren(BuildContext context, AppLocalizations l10n) {
    final _BookingTotals totals = _BookingTotals.from(widget.services);
    return <Widget>[
      // Narrow ValueListenable watch (mobile-perf finding): only this toggle
      // row + the itemized list rebuild on an expand/collapse tap. The
      // `_TotalRow`/`_ChosenWindow`/CTA button below stay out of this
      // builder, so they are built once per actual widget-config change
      // rather than on every tap.
      ValueListenableBuilder<bool>(
        valueListenable: _expandedNotifier,
        builder: (BuildContext context, bool expanded, _) {
          final String toggleSemantics = expanded
              ? l10n.bookingSummaryCollapseLabel
              : l10n.bookingSummaryExpandLabel;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Semantics(
                button: true,
                expanded: expanded,
                label: toggleSemantics,
                child: GestureDetector(
                  key: const Key('booking-summary-expand-toggle'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleExpanded,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: VelvetSpacing.sm),
                    child: Row(
                      children: <Widget>[
                        Text(
                          l10n.publicMasterBookingSectionLabel,
                          style: VelvetText.sectionLabel(),
                        ),
                        const Spacer(),
                        Text(
                          formatServiceCountUk(widget.services.length),
                          style: VelvetText.feedbackMutedSm,
                        ),
                        const SizedBox(width: VelvetSpacing.xs),
                        AnimatedRotation(
                          turns: expanded ? 0.5 : 0.0,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          child: const Icon(
                            Icons.expand_more_rounded,
                            size: 20,
                            color: BrandColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                // The itemized list is only built while expanded — collapsed,
                // it no longer reserves the up-to-`_listMaxHeight` shelf
                // space that used to crowd the screen once several services
                // were selected.
                child: expanded
                    ? ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxHeight: BookingSummaryBar._listMaxHeight,
                        ),
                        child: SingleChildScrollView(
                          padding: EdgeInsets.zero,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              for (
                                int i = 0;
                                i < widget.services.length;
                                i++
                              ) ...<Widget>[
                                _SelectionEntry(
                                  service: widget.services[i],
                                  onRemove: widget.onRemove == null
                                      ? null
                                      : () => widget.onRemove!(
                                          widget.services[i],
                                        ),
                                ),
                                if (i < widget.services.length - 1)
                                  const SizedBox(height: VelvetSpacing.md - 4),
                              ],
                            ],
                          ),
                        ),
                      )
                    : const SizedBox(width: double.infinity, height: 0),
              ),
            ],
          );
        },
      ),
      const SizedBox(height: VelvetSpacing.md),
      Container(height: 1, color: BrandColors.faint.withValues(alpha: 0.5)),
      const SizedBox(height: VelvetSpacing.sm + 2),
      _TotalRow(
        l10n: l10n,
        price: totals.priceLabel,
        duration: totals.durationLabel,
      ),
      const SizedBox(height: VelvetSpacing.md),
      if (widget.showChosenWindow)
        _ChosenWindow(l10n: l10n, label: widget.chosenWindowLabel),
      if (widget.showChosenWindow && widget.chosenWindowLabel != null)
        const SizedBox(height: VelvetSpacing.md),
      NeumorphicButton(
        key: const Key('booking-summary-cta'),
        label: widget.ctaLabel,
        icon: widget.ctaIcon,
        onPressed: widget.enabled ? widget.onAction : null,
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

/// One 2-line selected-service entry: name + price (+ optional remove
/// affordance) on line one, duration on line two.
class _SelectionEntry extends StatelessWidget {
  const _SelectionEntry({required this.service, this.onRemove});

  final MasterService service;

  /// Fires when the per-item "×" is tapped — `null` renders no remove
  /// affordance at all, leaving this entry's layout identical to before the
  /// removal feature existed (see [BookingSummaryBar.onRemove]).
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String name = _serviceLabel(service);
    final String duration = DurationMinutes.format(service.durationMinutes);
    final String price = ServicePriceDisplay.format(service);
    return Semantics(
      label: l10n.bookingServiceTileSemantics(name, duration, price),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            // `center` rather than `baseline`: [name] and [price] share the
            // exact same `bodyStrong()` font metrics, so this is a no-op for
            // them (center-aligning same-size text is pixel-identical to
            // baseline-aligning it), but it also lets the optional
            // [_RemoveButton] — a non-text child with no baseline of its own —
            // lay out safely without relying on baseline-alignment's
            // top-align-and-hope-it-fits fallback for non-text children.
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VelvetText.bodyStrong(),
                ),
              ),
              const SizedBox(width: VelvetSpacing.md),
              Text(
                price,
                style: VelvetText.bodyStrong().copyWith(
                  color: BrandColors.accentDeep,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (onRemove != null) ...<Widget>[
                const SizedBox(width: VelvetSpacing.xs),
                _RemoveButton(service: service, onRemove: onRemove!),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.schedule_outlined,
                size: 12,
                color: BrandColors.muted,
              ),
              const SizedBox(width: 3),
              Text(duration, style: VelvetText.feedbackMutedSm),
            ],
          ),
        ],
      ),
    );
  }
}

/// The per-item "×" remove affordance on an expanded [_SelectionEntry] — a
/// second way to deselect a service, alongside unchecking it in the catalogue
/// above. Mirrors the small icon-only tappable convention already used for
/// `attachment_tray.dart`'s per-attachment remove control (`Semantics(button:
/// true) → GestureDetector(key, opaque hit-test) → icon`), sized down to sit
/// inline in this narrower row: a plain (undecorated) glyph tinted
/// [BrandColors.muted] — matching this entry's other secondary element, the
/// duration icon/text below — rather than that control's raised well, which
/// would look out of place floating mid-row instead of on its own card face.
///
/// Tap target: a fixed 32×32dp `SizedBox` around the 16px glyph (mobile-qa
/// audit finding) — NOT the 6dp `EdgeInsets.all` padding (~28×28dp) this
/// originally shipped with. 32×32 matches `attachment_tray.dart`'s per-row remove
/// control, the established floor this codebase already uses for an inline
/// per-row remove/close affordance (`interval_editor.dart`/
/// `day_hours_sheet.dart` go up to 38×38, but those sit in a much roomier
/// row). Still short of Material's 48dp *recommendation*, but this is a
/// SECONDARY deselection path — the catalogue checkbox above remains the
/// primary, larger-target way to deselect — and the entry `Row` auto-sizes
/// to its tallest child, so bumping this does not encroach on the fixed gap
/// to neighbouring entries.
class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.service, required this.onRemove});

  final MasterService service;
  final VoidCallback onRemove;

  static const double _tapTarget = 32;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String name = _serviceLabel(service);
    return Semantics(
      // `container: true` (mobile-qa audit finding): without it, this
      // explicit `button`/`label` config merges UPWARD into the ancestor
      // `_SelectionEntry` Semantics node instead of forming its own — a
      // screen-reader user would get ONE unreadable node concatenating the
      // entry's name/duration/price AND "Прибрати «…» зі списку" together,
      // with the entry's own tap action shadowed by this button's `onTap`.
      // `container: true` forces this button to stay a distinct, separately
      // reachable semantics node.
      container: true,
      button: true,
      label: l10n.bookingRemoveServiceSemantics(name),
      child: GestureDetector(
        key: Key('booking-summary-remove-${service.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: onRemove,
        child: const SizedBox(
          height: _tapTarget,
          width: _tapTarget,
          child: Center(
            child: Icon(
              Icons.close_rounded,
              size: 16,
              color: BrandColors.muted,
            ),
          ),
        ),
      ),
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

/// Aggregated totals derived from typed [MasterService] fields — a (low, high)
/// price band (collapsing to a single value when the band is degenerate) plus
/// the summed duration.
class _BookingTotals {
  const _BookingTotals({required this.priceLabel, this.durationLabel});

  final String priceLabel;
  final String? durationLabel;

  factory _BookingTotals.from(List<MasterService> services) {
    double minSum = 0;
    double maxSum = 0;
    int minutes = 0;
    for (final MasterService s in services) {
      minSum += s.priceMin;
      maxSum += s.priceType == ServicePriceType.range
          ? (s.priceMax ?? s.priceMin)
          : s.priceMin;
      minutes += s.durationMinutes;
    }
    final String priceLabel = minSum == maxSum
        ? '${_amount(minSum)} грн'
        : '${_amount(minSum)}–${_amount(maxSum)} грн';
    return _BookingTotals(
      priceLabel: priceLabel,
      durationLabel: minutes > 0 ? DurationMinutes.format(minutes) : null,
    );
  }

  static String _amount(double value) => value.toStringAsFixed(0);
}

/// Card label rule mirrored from `services_list_screen.dart`'s `_ServiceCard`:
/// the master's optional custom [MasterService.name] replaces the platform
/// service-type name; the two are never shown together.
String _serviceLabel(MasterService s) {
  final String typeName = (s.serviceTypeNameUk ?? '').trim();
  final String customName = s.name.trim();
  return customName.isNotEmpty ? customName : typeName;
}

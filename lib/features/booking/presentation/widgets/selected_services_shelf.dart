// SelectedServicesShelf — the expandable itemized "Послуги та ціни" list,
// extracted out of `BookingSummaryBar` (Phase 14.1) so the salon
// master-assignment ("Майстри") and time ("Час") steps can pin the exact
// same expand/collapse selected-services list above their own
// progress-counter + CTA content, without duplicating the toggle/list
// implementation a second (and third) time.
//
// `BookingSummaryBar` itself now composes THIS widget for its own itemized
// list (see that file), so there is exactly one implementation of the
// expand/collapse interaction across all three salon-booking bars —
// `BookingSummaryBar` (services step), `_AssignConfirmBar` (masters step),
// and `ScheduleConfirmBar` (time step).
//
// Deliberately does NOT own the outer shelf chrome (surface color, rounded
// top, shadow, SafeArea, CTA) — callers compose this widget as the first
// child inside their own `bottomNavigationBar` Column, directly above
// whatever "Разом"/progress/CTA content they already render. This is what
// lets `_AssignConfirmBar`/`ScheduleConfirmBar` keep their own progress
// semantics (`N з M призначено` / `N з M заплановано`) untouched while still
// gaining the shelf.
//
// Height-bounding: the itemized list is capped at [listMaxHeight] via a
// `ConstrainedBox` (same value `BookingSummaryBar` always used) — collapsed,
// it renders nothing at all. Combined with each caller's own bounded
// progress row + fixed-height CTA, an expanded shelf can never push a
// `bottomNavigationBar` bar into unbounded growth.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/duration_minutes.dart';
import 'package:beautica_mobile/shared/formatters/service_count_label.dart';
import 'package:beautica_mobile/shared/formatters/service_price_display.dart';

import '../../../salon/domain/salon_service_catalog.dart';

/// The expand/collapse itemized selected-service list shared by every salon
/// booking bar. Collapsed by default; tapping the header row toggles it.
class SelectedServicesShelf extends StatefulWidget {
  const SelectedServicesShelf({
    super.key,
    required this.services,
    this.onRemove,
    this.chosenLabelFor,
  });

  /// The client's selected service(s) (0..n) to itemize when expanded.
  final List<MasterService> services;

  /// Fires when the client removes a service via its per-item "×"
  /// affordance. `null` (the default) renders no remove affordance at all —
  /// the right choice for a flow step downstream of selection (masters/time
  /// screens), where deselecting a service after masters/times have already
  /// been assigned to it would invalidate that assignment.
  final void Function(MasterService service)? onRemove;

  /// Optional per-service chosen appointment-window label (e.g.
  /// "вт, 14 лип · 14:00–15:00"), rendered as a third accent line inside the
  /// service's expanded row once the client has picked its date+time.
  ///
  /// Returning `null` for a service (or leaving this callback `null`, the
  /// default) renders NO third line at all — the salon bars
  /// (`BookingSummaryBar` / `ScheduleConfirmBar` / `_AssignConfirmBar`) omit it
  /// and stay pixel-identical. Only the independent-master
  /// `IndependentScheduleConfirmBar` wires it, since that flow schedules a
  /// SEPARATE date/time per SERVICE (the salon flow schedules one window per
  /// master-slide, shown in the pager, not per service in the shelf).
  final String? Function(MasterService service)? chosenLabelFor;

  /// Maximum height the expanded itemized list may occupy — bounds every
  /// host bar's worst-case height inside a `bottomNavigationBar`.
  static const double listMaxHeight = 188;

  @override
  State<SelectedServicesShelf> createState() => _SelectedServicesShelfState();
}

class _SelectedServicesShelfState extends State<SelectedServicesShelf> {
  /// Ephemeral UI-only state — purely a display toggle for the itemized
  /// list, so it does not need a Riverpod provider. Always collapsed on
  /// first build. Held in a [ValueNotifier] + narrow [ValueListenableBuilder]
  /// (mobile-perf pattern carried over from `BookingSummaryBar`) so an
  /// expand/collapse tap only rebuilds the toggle row + itemized list, never
  /// whatever total/progress/CTA content the host bar renders below this
  /// widget.
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
    // Hoisted out of the ValueListenableBuilder's `builder` below (mobile-perf
    // nit fixed while extracting this widget out of `BookingSummaryBar`):
    // neither the section label nor the selected-count text depends on
    // `expanded`, so passing this in via the builder's `child` means it is
    // built once per services-list change instead of rebuilt on every
    // expand/collapse tap.
    final Widget labelRow = Row(
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
      ],
    );

    return ValueListenableBuilder<bool>(
      valueListenable: _expandedNotifier,
      builder: (BuildContext context, bool expanded, Widget? child) {
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
                      Expanded(child: child!),
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
              // it reserves no shelf space at all.
              child: expanded
                  ? ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxHeight: SelectedServicesShelf.listMaxHeight,
                      ),
                      // `ListView.separated` (not the previous plain
                      // non-lazy `Column` inside a `SingleChildScrollView`)
                      // so only the visible entries are built even when many
                      // services are selected (mobile-perf backlog nit fixed
                      // while extracting this widget).
                      child: ListView.separated(
                        key: const Key('booking-summary-expanded-list'),
                        // `shrinkWrap: true` so the list sizes to its actual
                        // row count instead of greedily filling the whole
                        // [listMaxHeight] the enclosing `ConstrainedBox` allows
                        // — a non-shrink-wrapped `ListView` in a bounded
                        // viewport always expands to the max extent, which left
                        // a large blank gap under the last service whenever the
                        // rows totalled less than 188dp (visible in every flow
                        // with only 1–2 selected services, salon and
                        // independent alike). Shrink-wrapping makes the panel
                        // fit its content; the `ConstrainedBox` above still
                        // caps it at [listMaxHeight], and once the rows exceed
                        // that cap the list is clamped and scrolls as before.
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: widget.services.length,
                        separatorBuilder: (BuildContext context, int i) =>
                            const SizedBox(height: VelvetSpacing.md - 4),
                        itemBuilder: (BuildContext context, int i) {
                          final MasterService service = widget.services[i];
                          return _SelectionEntry(
                            // Keyed by service id (mobile-perf backlog nit
                            // fixed while extracting this widget) so Flutter
                            // can correctly diff/reuse entries instead of
                            // matching purely by list position.
                            key: ValueKey<String>(service.id),
                            service: service,
                            chosenLabel: widget.chosenLabelFor?.call(service),
                            onRemove: widget.onRemove == null
                                ? null
                                : () => widget.onRemove!(service),
                          );
                        },
                      ),
                    )
                  : const SizedBox(width: double.infinity, height: 0),
            ),
          ],
        );
      },
      child: labelRow,
    );
  }
}

/// One selected-service entry: name + price (+ optional remove affordance) on
/// line one, duration on line two, and — only in the independent flow, once a
/// slot is picked — the chosen appointment window as a third accent line.
class _SelectionEntry extends StatelessWidget {
  const _SelectionEntry({
    super.key,
    required this.service,
    this.onRemove,
    this.chosenLabel,
  });

  final MasterService service;

  /// Fires when the per-item "×" is tapped — `null` renders no remove
  /// affordance at all (see [SelectedServicesShelf.onRemove]).
  final VoidCallback? onRemove;

  /// This service's chosen appointment-window label, or `null` when it has no
  /// pick yet (or this host bar never supplies one). See
  /// [SelectedServicesShelf.chosenLabelFor].
  final String? chosenLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String name = _serviceLabel(service);
    final String duration = DurationMinutes.format(service.durationMinutes);
    final String price = ServicePriceDisplay.format(service);
    final String? chosen = chosenLabel;
    // Fold the chosen window into the entry's own semantics node (reusing the
    // existing "Запис:" key) so a screen-reader user hears the picked time as
    // part of the service, not as a separate unlabelled node.
    final String semanticsLabel = chosen == null
        ? l10n.bookingServiceTileSemantics(name, duration, price)
        : '${l10n.bookingServiceTileSemantics(name, duration, price)}, '
              '${l10n.bookingChosenWindowLabel} $chosen';
    return Semantics(
      label: semanticsLabel,
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
          // Third line — the chosen appointment window, in the camel accent so
          // it reads as the "resolved" beat above the muted duration line
          // (hierarchy by colour, not size). Absent (SizedBox.shrink) until the
          // client picks a slot; fades + grows in when it lands.
          _ChosenLine(label: chosen),
        ],
      ),
    );
  }
}

/// The per-service chosen-window line inside an expanded [_SelectionEntry].
/// Renders nothing until [label] is non-null, then reveals with a gentle
/// fade + size beat (matching the shelf's own 220 ms expand animation).
class _ChosenLine extends StatelessWidget {
  const _ChosenLine({required this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final String? chosen = label;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      transitionBuilder: (Widget child, Animation<double> anim) =>
          FadeTransition(
            opacity: anim,
            child: SizeTransition(
              sizeFactor: anim,
              axisAlignment: -1,
              child: child,
            ),
          ),
      child: chosen == null
          ? const SizedBox(key: ValueKey<bool>(false), width: double.infinity)
          : Padding(
              key: const ValueKey<bool>(true),
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.event_available_rounded,
                    size: 12,
                    color: BrandColors.accentDeep,
                  ),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(
                      chosen,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: VelvetText.bookAccentValue14,
                    ),
                  ),
                ],
              ),
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

/// Card label rule mirrored from `services_list_screen.dart`'s `_ServiceCard`:
/// the master's optional custom [MasterService.name] replaces the platform
/// service-type name; the two are never shown together.
String _serviceLabel(MasterService s) {
  final String typeName = (s.serviceTypeNameUk ?? '').trim();
  final String customName = s.name.trim();
  return customName.isNotEmpty ? customName : typeName;
}

/// Pure display adapter — [SalonCatalogService] → [MasterService] — letting
/// every salon-booking bar reuse [SelectedServicesShelf] /
/// [BookingSummaryBar] verbatim instead of re-deriving a near-identical
/// itemized entry per screen. Shared by `SalonServiceSelectionScreen`,
/// `SalonMasterSelectionScreen`'s `_AssignConfirmBar`, and
/// `SalonTimeScreen`'s `ScheduleConfirmBar` — a single implementation so the
/// three bars cannot drift apart.
///
/// Display-only: [priceDisplay]/duration pass straight through so the
/// rendered totals never diverge from what the catalogue tile above shows.
/// NEVER used for the actual booking write path — that stays
/// [SalonCatalogService] / raw service ids all the way through
/// `SalonBookingMasterSelectionArgs`/`SalonBookingTimeArgs`.
MasterService salonServiceForShelf(SalonCatalogService s) => MasterService(
  id: s.id,
  serviceDefId: s.id,
  name: s.name,
  category: s.category,
  durationMinutes: s.durationMinutes ?? 0,
  priceType: s.priceType ?? ServicePriceType.fixed,
  priceMin: s.priceMin ?? 0,
  priceMax: s.priceMax,
  priceDisplay: s.priceDisplay,
);

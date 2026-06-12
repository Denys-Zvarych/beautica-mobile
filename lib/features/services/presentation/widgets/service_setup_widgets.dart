// First-time service-setup widgets.
//
// Ported 1:1 from the approved preview
// `docs/signup-designs/ServiceSetup/lib/widgets/service_setup_widgets.dart`
// (+ `pricing_field.dart`). The preview's standalone VelvetColors / VelvetText /
// VelvetShadows tokens are swapped for the production BrandColors / VelvetText /
// VelvetShadows + the shared NeumorphicInset; the layout, motion, and geometry
// are unchanged.
//
// VelvetTouch craft (within the locked palette): unselected chip = a recessed
// inset pill; selected chip = a raised camel→mocha gradient pillow with a leading
// icon + cream label + optional cream count badge. Each service-type row is a
// raised card that expands (AnimatedSize + cross-fade) to reveal the pricing
// control while its include toggle is ON, and dims to a single muted line while
// OFF.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/core/widgets/velvet_field.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/pricing_field.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

/// Why a save-time validation flag fired on a row, so its card can show a
/// precise message (and the right inline field hints) instead of one generic
/// "missing duration and price" string. [none] means the row is valid / not
/// flagged.
enum RowFlagReason {
  /// Row is valid or has not been flagged.
  none,

  /// Included row whose duration is empty / not a positive integer.
  missingDuration,

  /// Included fixed-price row whose price is empty / unparseable.
  missingPrice,

  /// Included row missing BOTH a valid duration and a valid price.
  missingBoth,

  /// Included range-priced row whose price range is missing or invalid
  /// (max must exceed min). The precise range message is surfaced inline by
  /// [PricingField] beneath the price fields, so the flag stays terse.
  invalidRange,
}

/// Maps a platform-category wire slug to a leading glyph for the chip / group
/// header. Categories are dynamic (sourced from the backend), so this is a
/// best-effort visual hint with a calm spa fallback for unknown slugs — it never
/// affects data, only the icon shown.
IconData serviceCategoryIcon(String slug) {
  switch (slug.trim().toUpperCase()) {
    case 'MANICURE':
      return Icons.brush_rounded;
    case 'PEDICURE':
      return Icons.spa_rounded;
    case 'HAIR':
    case 'HAIRCUT':
      return Icons.content_cut_rounded;
    case 'BROWS_LASHES':
    case 'BROWS':
    case 'EYELASH':
    case 'LASHES':
      return Icons.remove_red_eye_rounded;
    case 'FACE':
      return Icons.face_rounded;
    case 'BODY':
      return Icons.self_improvement_rounded;
    case 'MAKEUP':
      return Icons.palette_rounded;
    default:
      return Icons.spa_rounded;
  }
}

/// A multi-selectable category chip — the entry point that, when selected,
/// expands inline to reveal every service-type under the category.
///
/// Unselected = a recessed inset well; selected = a raised camel→mocha gradient
/// pillow with a leading icon + cream label, cross-faded by a 150 ms
/// [AnimatedContainer]. Once the master has included rows inside it the selected
/// chip carries a cream count badge so the chip telegraphs progress.
class CategoryChip extends StatelessWidget {
  const CategoryChip({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.includedCount,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;

  /// How many service-types under this category are currently toggled ON.
  final int includedCount;
  final VoidCallback onTap;

  static const BorderRadius _pillRadius = BorderRadius.all(
    Radius.circular(VelvetRadii.pill),
  );

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          decoration: selected
              ? const BoxDecoration(
                  borderRadius: _pillRadius,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      BrandColors.accentLatte,
                      BrandColors.accentDeep,
                    ],
                  ),
                  boxShadow: VelvetShadows.extrudedButtonAccent,
                )
              : null,
          child: selected ? _selectedContent() : _unselectedContent(),
        ),
      ),
    );
  }

  Widget _selectedContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.md,
        vertical: VelvetSpacing.sm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: BrandColors.white),
          const SizedBox(width: VelvetSpacing.sm - 2),
          Text(
            label,
            style: VelvetText.pill().copyWith(color: BrandColors.white),
          ),
          if (includedCount > 0) ...<Widget>[
            const SizedBox(width: VelvetSpacing.sm - 2),
            _CountBadge(count: includedCount, onAccent: true),
          ],
        ],
      ),
    );
  }

  Widget _unselectedContent() {
    return NeumorphicInset(
      radius: VelvetRadii.pill,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: VelvetSpacing.md,
          vertical: VelvetSpacing.sm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 16, color: BrandColors.accent),
            const SizedBox(width: VelvetSpacing.sm - 2),
            Text(label, style: VelvetText.pill()),
          ],
        ),
      ),
    );
  }
}

/// A small pill-shaped count badge. On the camel chip it is a cream disc with
/// mocha digits; on the base surface it is a soft camel disc with cream digits.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, this.onAccent = false});

  final int count;
  final bool onAccent;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: onAccent ? BrandColors.white : BrandColors.accent,
        borderRadius: BorderRadius.circular(VelvetRadii.pill),
      ),
      child: Text(
        '$count',
        style: VelvetText.pill().copyWith(
          fontSize: 12,
          color: onAccent ? BrandColors.accentDeep : BrandColors.white,
        ),
      ),
    );
  }
}

/// The header that introduces an expanded category's row list — its icon, the
/// Ukrainian name, and a live "n з m" count of included service-types.
class CategoryGroupHeader extends StatelessWidget {
  const CategoryGroupHeader({
    super.key,
    required this.icon,
    required this.label,
    required this.includedCount,
    required this.total,
  });

  final IconData icon;
  final String label;
  final int includedCount;
  final int total;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final TextStyle style = VelvetText.body().copyWith(
      fontSize: 12,
      height: 1.4,
      fontWeight: FontWeight.w800,
      color: BrandColors.accentDeep,
    );
    return Padding(
      padding: const EdgeInsets.only(
        left: VelvetSpacing.xs,
        top: VelvetSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 14, color: BrandColors.accentDeep),
          const SizedBox(width: VelvetSpacing.xs + 2),
          Flexible(
            child: Text(
              label,
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: VelvetSpacing.xs + 2),
          Text(l10n.serviceSetupGroupCount(includedCount, total), style: style),
        ],
      ),
    );
  }
}

/// Mutable per-row UI state for one service-type while the master configures the
/// one-pass menu. Holds everything the bottom save serialises into the per-row
/// bulk payload `{ serviceTypeId, durationMinutes, priceType, price |
/// priceMin/priceMax }`. The service name + category are derived server-side from
/// the service-type, so there is deliberately no name field here.
///
/// A [ChangeNotifier] so the row's own card — and the derived footer count /
/// chip badges — can rebuild *locally* when `included` / `pricingMode` /
/// `flagged` change, instead of forcing a full-tree `setState` on the screen.
/// It also owns the four field controllers so the card is the single source of
/// truth for its own rebuild (range-error recomputation included).
class ServiceRowState extends ChangeNotifier {
  ServiceRowState({required this.serviceTypeId, required this.nameUk});

  /// The platform service-type id submitted in the bulk payload.
  final String serviceTypeId;

  /// Ukrainian display name shown on the row card.
  final String nameUk;

  /// Field controllers, owned by the row so its card can recompute the
  /// cross-field range error from the min/max text without a screen rebuild.
  final TextEditingController duration = TextEditingController();
  final TextEditingController fixed = TextEditingController();
  final TextEditingController min = TextEditingController();
  final TextEditingController max = TextEditingController();

  bool _included = false;

  /// Include toggle — defaults OFF (opt-in model). Expanding a category just
  /// reveals its service-types; the master toggles ON only the ones they offer.
  /// Only included rows are submitted and require a duration + price; the
  /// untouched (off) rows are skipped by the save, so browsing a category never
  /// makes its rows required.
  bool get included => _included;
  set included(bool value) {
    if (_included == value) return;
    _included = value;
    notifyListeners();
  }

  ServicePriceType _pricingMode = ServicePriceType.fixed;
  ServicePriceType get pricingMode => _pricingMode;
  set pricingMode(ServicePriceType value) {
    if (_pricingMode == value) return;
    _pricingMode = value;
    notifyListeners();
  }

  RowFlagReason _flagReason = RowFlagReason.none;

  /// The precise reason this row is flagged (or [RowFlagReason.none] when
  /// valid). Drives the card's flag message + the inline per-field hints.
  RowFlagReason get flagReason => _flagReason;
  set flagReason(RowFlagReason value) {
    if (_flagReason == value) return;
    _flagReason = value;
    notifyListeners();
  }

  /// True when the row is included but missing a required value, so its card
  /// shows the validation flag + tinted rim. Derived from [flagReason].
  bool get flagged => _flagReason != RowFlagReason.none;

  /// Clears any active validation flag (e.g. when the row is toggled or the
  /// pricing mode changes, giving the master a clean slate before re-saving).
  void clearFlag() => flagReason = RowFlagReason.none;

  @override
  void dispose() {
    duration.dispose();
    fixed.dispose();
    min.dispose();
    max.dispose();
    super.dispose();
  }
}

/// One configurable service-type row inside an expanded category.
///
/// A raised neumorphic card. The header row carries the service name, an
/// optional "потрібна ціна" validation flag, and the include toggle on the
/// trailing edge. While included the card expands ([AnimatedSize] + cross-fade)
/// to reveal the duration field and the fixed/range price control; while excluded
/// it collapses to a single muted header line and the card face dims, so an "off"
/// row reads as physically receded without leaving the menu.
/// Resolves the cross-field "max > min" range error for a row from its current
/// min/max text + pricing mode. Returns null when valid / not in range mode.
typedef RangeErrorResolver = String? Function(ServiceRowState row);

class ServiceTypeRowCard extends StatefulWidget {
  const ServiceTypeRowCard({
    super.key,
    required this.row,
    required this.resolveRangeError,
    this.onChanged,
  });

  final ServiceRowState row;

  /// Computes the cross-field "max > min" message for this row from its current
  /// field text — re-run locally on min/max keystrokes (null when valid / N/A).
  final RangeErrorResolver resolveRangeError;

  /// Notifies the screen that this row's `included` / `pricingMode` changed, so
  /// any derived aggregate (footer count, chip badges) can re-derive. The row's
  /// own card already rebuilds itself via its [ServiceRowState] notifier.
  final VoidCallback? onChanged;

  @override
  State<ServiceTypeRowCard> createState() => _ServiceTypeRowCardState();
}

class _ServiceTypeRowCardState extends State<ServiceTypeRowCard> {
  static final List<TextInputFormatter> _durationFormatters =
      <TextInputFormatter>[
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(3),
      ];

  @override
  void initState() {
    super.initState();
    widget.row.addListener(_onRowChanged);
    // Recompute the range error locally as the user edits min/max — no screen
    // rebuild, just this one card.
    widget.row.min.addListener(_onFieldChanged);
    widget.row.max.addListener(_onFieldChanged);
  }

  @override
  void didUpdateWidget(ServiceTypeRowCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.row, widget.row)) {
      oldWidget.row.removeListener(_onRowChanged);
      oldWidget.row.min.removeListener(_onFieldChanged);
      oldWidget.row.max.removeListener(_onFieldChanged);
      widget.row.addListener(_onRowChanged);
      widget.row.min.addListener(_onFieldChanged);
      widget.row.max.addListener(_onFieldChanged);
    }
  }

  @override
  void dispose() {
    widget.row.removeListener(_onRowChanged);
    widget.row.min.removeListener(_onFieldChanged);
    widget.row.max.removeListener(_onFieldChanged);
    super.dispose();
  }

  void _onRowChanged() {
    if (mounted) setState(() {});
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  void _setIncluded(bool v) {
    widget.row.included = v;
    // Toggling clears any stale flag — an excluded row is never required, and a
    // freshly-included one starts clean (its inline hints fire only on save).
    widget.row.clearFlag();
    widget.onChanged?.call();
  }

  void _setMode(ServicePriceType m) {
    widget.row.pricingMode = m;
    widget.row.clearFlag();
    widget.onChanged?.call();
  }

  /// The terse header flag message for the row's current [RowFlagReason]. The
  /// precise range message is surfaced inline by [PricingField], so the
  /// [RowFlagReason.invalidRange] header copy stays generic to avoid
  /// double-reporting it.
  String _flagMessage(AppLocalizations l10n, RowFlagReason reason) {
    switch (reason) {
      case RowFlagReason.missingDuration:
        return l10n.serviceSetupRowMissingDuration;
      case RowFlagReason.missingPrice:
        return l10n.serviceSetupRowMissingPriceOnly;
      case RowFlagReason.invalidRange:
        return l10n.serviceSetupRowFixRange;
      case RowFlagReason.missingBoth:
      case RowFlagReason.none:
        return l10n.serviceSetupRowMissingPrice;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ServiceRowState row = widget.row;
    final bool on = row.included;
    final RowFlagReason reason = row.flagReason;
    final bool flagged = row.flagged;
    final String? rangeError = widget.resolveRangeError(row);

    // Inline per-field hints derived from the save-time flag reason, so a
    // flagged row points the master at the exact empty field rather than
    // relying on the header line alone. The range case is left to
    // PricingField's own inline cross-field hint.
    final bool durationFlagged =
        reason == RowFlagReason.missingDuration ||
        reason == RowFlagReason.missingBoth;
    final bool fixedPriceFlagged =
        reason == RowFlagReason.missingPrice ||
        reason == RowFlagReason.missingBoth;
    final String? durationError = durationFlagged
        ? l10n.serviceSetupDurationRequired
        : null;
    final String? fixedPriceError =
        fixedPriceFlagged && row.pricingMode == ServicePriceType.fixed
        ? l10n.serviceSetupPriceRequired
        : null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: BrandColors.base,
        borderRadius: BorderRadius.circular(VelvetRadii.card),
        border: Border.all(
          color: flagged ? BrandColors.error : Colors.transparent,
          width: flagged ? 1.4 : 0,
        ),
        boxShadow: on
            ? VelvetShadows.extrudedCard
            : VelvetShadows.extrudedSmall,
      ),
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.md + 2,
        VelvetSpacing.md,
        VelvetSpacing.md,
        VelvetSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Header: name + (flag / excluded sub-label) + include switch.
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: VelvetText.subheading().copyWith(
                        fontSize: 16,
                        color: on ? BrandColors.text : BrandColors.muted,
                      ),
                      child: Text(row.nameUk),
                    ),
                    if (flagged) ...<Widget>[
                      const SizedBox(height: 4),
                      Row(
                        children: <Widget>[
                          const Icon(
                            Icons.error_outline_rounded,
                            size: 14,
                            color: BrandColors.error,
                          ),
                          const SizedBox(width: VelvetSpacing.xs + 1),
                          Flexible(
                            child: Text(
                              _flagMessage(l10n, reason),
                              style: VelvetText.feedback(BrandColors.error),
                            ),
                          ),
                        ],
                      ),
                    ] else if (!on) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        l10n.serviceSetupRowExcluded,
                        style: VelvetText.body().copyWith(
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: VelvetSpacing.sm),
              _IncludeSwitch(
                value: on,
                onChanged: _setIncluded,
                semanticLabel: row.nameUk,
              ),
            ],
          ),

          // Configured fields — present only while included.
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (Widget child, Animation<double> anim) {
                return FadeTransition(
                  opacity: anim,
                  child: SizeTransition(
                    sizeFactor: anim,
                    axisAlignment: -1,
                    child: child,
                  ),
                );
              },
              child: on
                  ? KeyedSubtree(
                      key: const ValueKey<String>('row-fields'),
                      child: Padding(
                        padding: const EdgeInsets.only(top: VelvetSpacing.md),
                        // Compact one-line layout: the duration field is handed
                        // to PricingField as its leading slot, so duration and
                        // price share a single Row beneath the mode toggle.
                        child: PricingField(
                          mode: row.pricingMode,
                          onModeChanged: _setMode,
                          fixedController: row.fixed,
                          minController: row.min,
                          maxController: row.max,
                          rangeError: rangeError,
                          fixedError: fixedPriceError,
                          leading: VelvetField(
                            label: l10n.serviceSetupDurationLabel,
                            controller: row.duration,
                            hint: '60',
                            keyboardType: TextInputType.number,
                            inputFormatters: _durationFormatters,
                            errorText: durationError,
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(
                      key: ValueKey<String>('row-collapsed'),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The per-row include toggle — a soft-UI switch. A recessed inset track holds a
/// raised pebble that slides on toggle; ON fills the track with the camel
/// gradient + a cream check, OFF is a plain inset well. Mirrors the tactile
/// language of the pricing-mode toggle so the two read as one family.
class _IncludeSwitch extends StatelessWidget {
  const _IncludeSwitch({
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String semanticLabel;

  static const double _w = 54;
  static const double _h = 30;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          width: _w,
          height: _h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(VelvetRadii.pill),
            gradient: value
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      BrandColors.accentLatte,
                      BrandColors.accentDeep,
                    ],
                  )
                : null,
            color: value ? null : BrandColors.base,
            boxShadow: value ? VelvetShadows.extrudedSmall : null,
          ),
          child: value
              ? _knob(alignment: Alignment.centerRight, showCheck: true)
              : NeumorphicInset(
                  radius: VelvetRadii.pill,
                  child: _knob(
                    alignment: Alignment.centerLeft,
                    showCheck: false,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _knob({required Alignment alignment, required bool showCheck}) {
    return Padding(
      padding: const EdgeInsets.all(VelvetSpacing.xs),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        alignment: alignment,
        child: Container(
          width: _h - 8,
          height: _h - 8,
          decoration: const BoxDecoration(
            color: BrandColors.white,
            shape: BoxShape.circle,
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: showCheck
              ? const Icon(
                  Icons.check_rounded,
                  size: 14,
                  color: BrandColors.accentDeep,
                )
              : null,
        ),
      ),
    );
  }
}

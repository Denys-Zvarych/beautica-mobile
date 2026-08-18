// Phase 14.1 — SlotChip: the time-picker pill.
//
// Transcribed verbatim (tokens, layout, shadows) from
// `docs/signup-designs/BookingSlotPicker/lib/widgets/slot_chip.dart`.
// Selection is encoded through DEPTH, not a flat fill:
//   • available  → a RAISED soft pillow, espresso label, inviting a tap;
//   • selected   → a recessed INSET well wearing a camel accent ring +
//                  camel/bold label;
//   • unavailable→ a GREYED-OUT inset well, faint label, NOT tappable.
//
// [BookingSlot.available] is always `true` under the CURRENT backend contract
// (the slots endpoint only ever returns bookable slots — see the file header
// of `features/booking/domain/booking_slot.dart`), so no slot fetched today
// renders the unavailable face in production. The prop is still honoured
// end-to-end (never hardcoded to `true` here) so the widget is correct for
// the day the backend starts returning held/taken slots, and so it is
// independently testable with a hand-built unavailable [BookingSlot] fixture.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

/// A neumorphic time-slot pill. Displays [time] as "HH:mm".
class SlotChip extends StatefulWidget {
  const SlotChip({
    super.key,
    required this.time,
    required this.selected,
    required this.available,
    required this.onTap,
  });

  /// Start time as "HH:mm" — pre-formatted by the caller (see
  /// `shared/formatters/booking_date_labels.dart`'s `formatSlotTime`).
  final String time;
  final bool selected;
  final bool available;

  /// Called when an available, unselected chip is tapped. Never invoked when
  /// [available] is false (the [GestureDetector] handlers are `null`).
  final VoidCallback onTap;

  @override
  State<SlotChip> createState() => _SlotChipState();
}

class _SlotChipState extends State<SlotChip> {
  bool _pressed = false;

  static const double _height = 40;
  static const double _radius = VelvetRadii.pill;

  bool get _enabled => widget.available && !widget.selected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String state = !widget.available
        ? l10n.bookingSlotUnavailableState
        : widget.selected
        ? l10n.bookingSelectedState
        : l10n.bookingSlotAvailableState;
    return Semantics(
      button: widget.available,
      enabled: widget.available,
      selected: widget.selected,
      label: '${widget.time}, $state',
      child: GestureDetector(
        onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
        onTapUp: _enabled
            ? (_) {
                setState(() => _pressed = false);
                widget.onTap();
              }
            : null,
        child: AnimatedScale(
          scale: _pressed ? 0.96 : 1,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          child: _buildFace(),
        ),
      ),
    );
  }

  Widget _buildFace() {
    if (widget.selected) {
      return Container(
        height: _height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_radius),
          border: Border.all(color: BrandColors.accent, width: 2),
        ),
        child: NeumorphicInset(
          radius: _radius,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: VelvetSpacing.sm + 2,
              ),
              child: Text(widget.time, style: _label(BrandColors.accentDeep)),
            ),
          ),
        ),
      );
    }

    if (!widget.available) {
      return Opacity(
        opacity: 0.7,
        child: SizedBox(
          height: _height,
          child: NeumorphicInset(
            radius: _radius,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: VelvetSpacing.sm + 2,
                ),
                child: Text(widget.time, style: _label(BrandColors.faint)),
              ),
            ),
          ),
        ),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: _height,
      decoration: BoxDecoration(
        color: BrandColors.base,
        borderRadius: BorderRadius.circular(_radius),
        boxShadow: _pressed ? null : VelvetShadows.extrudedSmall,
      ),
      child: Center(
        // Same horizontal inset as the selected and unavailable faces above
        // (`sm + 2`): the three faces are the same pill in three depths and
        // must agree. At `md` (16) the available face left only ~42px of the
        // caller's fixed 74px box for an 11sp w800 "13:30" — which fits, but
        // has nothing to spare at the app-wide `textScaler` clamp of 1.3
        // (`main.dart`), and made the label visibly jump inward the moment a
        // chip was selected.
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.sm + 2),
          child: Text(widget.time, style: _label(BrandColors.text)),
        ),
      ),
    );
  }

  TextStyle _label(Color color) =>
      VelvetText.bookSlotChip.copyWith(color: color);
}

/// One time-of-day group (Ранок / День / Вечір): a muted sub-label + a
/// [Wrap] of [SlotChip]s.
class SlotGroup extends StatelessWidget {
  const SlotGroup({super.key, required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: VelvetSpacing.sm),
          child: Row(
            children: <Widget>[
              Text(label, style: VelvetText.bookSlotGroupLabel),
              const SizedBox(width: VelvetSpacing.sm),
              Expanded(
                child: Container(
                  height: 1,
                  color: BrandColors.faint.withValues(alpha: 0.45),
                ),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: VelvetSpacing.sm,
          runSpacing: VelvetSpacing.sm,
          children: children,
        ),
      ],
    );
  }
}

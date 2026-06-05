// VelvetTouch wheel time picker.
//
// Ported verbatim from the approved preview app at
// `docs/signup-designs/MasterSchedule/lib/widgets/interval_editor.dart`
// (`showVelvetTimePicker` + `_WheelTimePicker` + `_wheel`).  The preview's
// standalone tokens (VelvetColors, VelvetText, VelvetRadii, VelvetSpacing,
// VelvetShadows, NeumorphicInset, NeumorphicButton) map 1:1 onto the
// production equivalents in `lib/core/theme/` and `lib/core/widgets/`.
//
// This deliberately REPLACES Flutter's Material `showTimePicker` clock dial,
// which clashed with the soft-UI surface.  In its place a neumorphic bottom
// sheet with two scroll wheels — hours (00–23) and minutes in 15-minute steps
// (00/15/30/45) — under a fixed centred selection band.  Snapping to 15 minutes
// keeps salon scheduling tidy and makes the wheels short enough to spin to any
// value in one flick.
//
// Lives under the `schedule` feature so BOTH the working-hours screen
// (Phase 6.2) and the future schedule editors (Phase 15.3 / 15.4) reuse one
// identical time-selection surface.  All user-facing copy is passed in by the
// caller (already resolved through AppLocalizations) so this widget stays free
// of any localization import.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';

/// Minute steps the wheel snaps to.
const List<int> _minuteSteps = <int>[0, 15, 30, 45];

/// Round an arbitrary minute to the nearest 15-minute step (for seeding the
/// wheel from a [TimeOfDay] that wasn't picked here).
int _snapMinute(int minute) {
  int best = _minuteSteps.first;
  int bestDelta = (minute - best).abs();
  for (final int step in _minuteSteps) {
    final int delta = (minute - step).abs();
    if (delta < bestDelta) {
      best = step;
      bestDelta = delta;
    }
  }
  return best;
}

/// Presents the VelvetTouch wheel time picker and resolves to the chosen time
/// (or `null` if dismissed). Shared by every time field across the working-hours
/// screen and the schedule editors so all time selection reads identically.
///
/// Copy ([title], [confirmLabel], [hoursSemanticLabel], [minutesSemanticLabel])
/// must already be resolved through `AppLocalizations` by the caller — this
/// surface deliberately does not import localization itself.
///
/// Uses [showModalBottomSheet] (a transient overlay, not route navigation), so
/// it is exempt from the go_router-only rule.
Future<TimeOfDay?> showVelvetTimePicker(
  BuildContext context,
  TimeOfDay initial, {
  required String title,
  required String confirmLabel,
  required String hoursSemanticLabel,
  required String minutesSemanticLabel,
}) {
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: BrandColors.text.withValues(alpha: 0.35),
    builder: (BuildContext context) => _WheelTimePicker(
      initial: initial,
      title: title,
      confirmLabel: confirmLabel,
      hoursSemanticLabel: hoursSemanticLabel,
      minutesSemanticLabel: minutesSemanticLabel,
    ),
  );
}

/// The wheel picker sheet body: two snapping scroll wheels behind a single
/// inset selection band, a title, and a camel confirm CTA.
class _WheelTimePicker extends StatefulWidget {
  const _WheelTimePicker({
    required this.initial,
    required this.title,
    required this.confirmLabel,
    required this.hoursSemanticLabel,
    required this.minutesSemanticLabel,
  });

  final TimeOfDay initial;
  final String title;
  final String confirmLabel;
  final String hoursSemanticLabel;
  final String minutesSemanticLabel;

  @override
  State<_WheelTimePicker> createState() => _WheelTimePickerState();
}

class _WheelTimePickerState extends State<_WheelTimePicker> {
  static const double _itemExtent = 46;
  static const double _wheelHeight =
      46 * 3; // selection band + 1 row each side.

  /// Per-row digit style, hoisted so the wheel builder doesn't allocate a fresh
  /// [TextStyle] (via `copyWith`) per row per raster while spinning.
  static final TextStyle _wheelDigitStyle = VelvetText.heading().copyWith(
    fontSize: 24,
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  );

  /// The fixed `:` separator style, hoisted to match house style.
  static final TextStyle _separatorStyle = VelvetText.heading().copyWith(
    fontSize: 26,
  );

  late final FixedExtentScrollController _hourController;
  late final FixedExtentScrollController _minuteController;

  late int _hour;
  late int _minuteIndex; // index into _minuteSteps

  @override
  void initState() {
    super.initState();
    _hour = widget.initial.hour;
    final int snapped = _snapMinute(widget.initial.minute);
    _minuteIndex = _minuteSteps.indexOf(snapped);
    _hourController = FixedExtentScrollController(initialItem: _hour);
    _minuteController = FixedExtentScrollController(initialItem: _minuteIndex);
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  void _confirm() {
    Navigator.of(
      context,
    ).pop(TimeOfDay(hour: _hour, minute: _minuteSteps[_minuteIndex]));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: BrandColors.base,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(VelvetRadii.card),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            VelvetSpacing.lg,
            VelvetSpacing.md,
            VelvetSpacing.lg,
            VelvetSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                height: 5,
                width: 44,
                decoration: BoxDecoration(
                  color: BrandColors.faint,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: VelvetSpacing.md),
              Row(
                children: <Widget>[
                  const Icon(
                    Icons.schedule_rounded,
                    size: 20,
                    color: BrandColors.accentDeep,
                  ),
                  const SizedBox(width: VelvetSpacing.sm),
                  Expanded(
                    child: Text(widget.title, style: VelvetText.subheading()),
                  ),
                ],
              ),
              const SizedBox(height: VelvetSpacing.lg),
              SizedBox(
                height: _wheelHeight,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    // Centred inset selection band behind both wheels.
                    const Center(
                      child: SizedBox(
                        height: _itemExtent,
                        child: NeumorphicInset(
                          radius: VelvetRadii.field,
                          child: SizedBox.expand(),
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        _wheel(
                          controller: _hourController,
                          count: 24,
                          builder: (int i) => i.toString().padLeft(2, '0'),
                          onSelected: (int i) => _hour = i,
                          semanticLabel: widget.hoursSemanticLabel,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: VelvetSpacing.sm,
                          ),
                          child: Text(':', style: _separatorStyle),
                        ),
                        _wheel(
                          controller: _minuteController,
                          count: _minuteSteps.length,
                          builder: (int i) =>
                              _minuteSteps[i].toString().padLeft(2, '0'),
                          onSelected: (int i) => _minuteIndex = i,
                          semanticLabel: widget.minutesSemanticLabel,
                        ),
                      ],
                    ),
                    // Soft fade veils top and bottom so off-band rows recede.
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: <Color>[
                                BrandColors.base,
                                BrandColors.base.withValues(alpha: 0.0),
                                BrandColors.base.withValues(alpha: 0.0),
                                BrandColors.base,
                              ],
                              stops: const <double>[0.0, 0.28, 0.72, 1.0],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: VelvetSpacing.lg),
              NeumorphicButton(
                key: const Key('btn-velvet-time-picker-confirm'),
                label: widget.confirmLabel,
                icon: Icons.check_rounded,
                onPressed: _confirm,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _wheel({
    required FixedExtentScrollController controller,
    required int count,
    required String Function(int) builder,
    required ValueChanged<int> onSelected,
    required String semanticLabel,
  }) {
    return Semantics(
      label: semanticLabel,
      child: SizedBox(
        width: 78,
        child: ListWheelScrollView.useDelegate(
          controller: controller,
          itemExtent: _itemExtent,
          perspective: 0.004,
          diameterRatio: 1.5,
          physics: const FixedExtentScrollPhysics(),
          overAndUnderCenterOpacity: 0.32,
          onSelectedItemChanged: onSelected,
          childDelegate: ListWheelChildBuilderDelegate(
            childCount: count,
            builder: (BuildContext context, int index) {
              return Center(
                child: Text(builder(index), style: _wheelDigitStyle),
              );
            },
          ),
        ),
      ),
    );
  }
}

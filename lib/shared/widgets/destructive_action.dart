// The destructive confirm pill + its quiet back-out — the app-wide
// confirmation-dialog action pair.
//
// PROMOTED (REUSE-FIRST, Phase 21.6) out of
// `features/schedule/presentation/widgets/day_off_conflict_dialog.dart`,
// where both classes were already PUBLIC but reachable only by importing
// another feature's `presentation/` tree (which the architecture's
// cross-feature import rule forbids). Phase 21.6's «Видалити адміністратора»
// confirmation needs the identical pair, and the alternative — a second red
// pill written inside the salon feature — is exactly the fork this rule
// exists to prevent. The code below is the ORIGINAL, moved verbatim: no
// parameter added, no default changed, no render altered. (Later additive
// param: `onPressedAsync`, default null — every existing caller unchanged.)
//
// `DayOffConflictDialog` (and its own widget/golden tests) now import this
// file; nothing about how it renders changed.

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';

/// The destructive confirm pill — **the only saturated `error` surface a
/// confirmation dialog is allowed to carry.**
///
/// [BrandColors.error] (`#B0452F`) is a warm brick that shares the palette's
/// red-dominant, low-chroma warmth rather than a bolted-on Material red, so
/// it sits inside the Warm Mocha family rather than shouting over it. Colour
/// is never the only signal: the pill also carries an `event_busy` glyph and
/// a label that names the object («Так, скасувати записи»).
///
/// The lift ([VelvetShadows.destructiveLift]) is non-offset and
/// alpha-attenuated — see that constant's doc for the Impeller-GLES
/// corner-sliver rationale. Motion mirrors [NeumorphicButton]:
/// `AnimatedScale(0.97)` on press.
class DestructiveButton extends StatefulWidget {
  const DestructiveButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.event_busy_rounded,
    this.loading = false,
    this.onPressedAsync,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData icon;
  final bool loading;

  /// SINGLE-FLIGHT async action — same contract as
  /// [NeumorphicButton.onPressedAsync]: a busy flag set synchronously on the
  /// tap, the [loading] visual while pending, taps ignored until the future
  /// completes. Takes precedence over [onPressed]; null keeps the button
  /// exactly as before.
  final Future<void> Function()? onPressedAsync;

  @override
  State<DestructiveButton> createState() => _DestructiveButtonState();
}

class _DestructiveButtonState extends State<DestructiveButton> {
  bool _pressed = false;

  /// Single-flight busy flag for [DestructiveButton.onPressedAsync].
  bool _busy = false;

  bool get _loading => widget.loading || _busy;

  bool get _enabled =>
      (widget.onPressed != null || widget.onPressedAsync != null) && !_loading;

  // ASYNC path only — a plain [onPressed] is invoked synchronously from the
  // gesture callback (see `_handleTapUp`), so a sync throw still reaches the
  // gesture recognizer's own `FlutterError.reportError`, exactly as before
  // `onPressedAsync` existed. This future is not awaited by the gesture: an
  // error the async action throws (sync or async) is caught here and
  // reported through [FlutterError.reportError] explicitly — otherwise it
  // would surface as an unhandled zone error — and the button re-enables.
  Future<void> _fire(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e, st) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: e,
          stack: st,
          library: 'DestructiveButton',
          context: ErrorDescription('while running onPressedAsync'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _handleTapUp(TapUpDetails _) {
    setState(() => _pressed = false);
    final Future<void> Function()? action = widget.onPressedAsync;
    if (action == null) {
      // Synchronous, un-wrapped — identical to the pre-`onPressedAsync` path.
      widget.onPressed?.call();
      return;
    }
    unawaited(_fire(action));
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.label,
      child: GestureDetector(
        onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
        onTapUp: _enabled ? _handleTapUp : null,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: VelvetSizes.cta,
            decoration: BoxDecoration(
              color: BrandColors.error,
              borderRadius: BorderRadius.circular(VelvetRadii.button),
              boxShadow: _pressed || !_enabled
                  ? null
                  : VelvetShadows.destructiveLift,
            ),
            alignment: Alignment.center,
            child: _loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: BrandColors.white,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(widget.icon, size: 18, color: BrandColors.white),
                      const SizedBox(width: VelvetSpacing.sm),
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
      ),
    );
  }
}

/// The safe way out — a quiet, full-width text action with a real 48 dp
/// target.
///
/// `DayOffConflictDialog` is the one screen in the app where «Скасувати» is
/// genuinely ambiguous: it means both *cancel the bookings* and *cancel this
/// action*, and a master reading fast would have to guess which. So there the
/// destructive button names its object («…скасувати записи») and the back-out
/// never uses the verb at all — «Залишити як є» says plainly that nothing
/// moves. Every caller passes its own [label]; this widget only supplies the
/// quiet treatment and the 48 dp target.
class QuietAction extends StatelessWidget {
  const QuietAction({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: SizedBox(
        height: 48,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: BrandColors.accentDeep,
            overlayColor: BrandColors.accent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(VelvetRadii.button),
            ),
          ),
          child: Text(
            label,
            style: VelvetText.feedback(BrandColors.textSecondary),
          ),
        ),
      ),
    );
  }
}

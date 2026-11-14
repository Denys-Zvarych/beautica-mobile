// Forwards a horizontal drag from a widget that is NOT itself a scrollable
// (the week grid's pinned header row, the week strip) onto a scrollable's
// position as a real [Drag] — `ScrollPosition.drag` — so the target's own
// physics owns the gesture: no snap or spring-back while the finger is down,
// and the release velocity becomes that physics' fling + settle.

import 'package:flutter/gestures.dart' show Drag;
import 'package:flutter/widgets.dart';

/// One forwarded drag at a time onto a [ScrollController]'s single position.
///
/// [scale] on [update] / [end] maps source travel to target pixels: `1` is a
/// 1:1 forward (finger right → content right, i.e. pixels decrease); a
/// negative factor inverts the direction (the strip: finger right → the
/// window, i.e. the pixels, move right).
final class ForwardedScrollDrag {
  Drag? _drag;

  /// Whether a forwarded drag is in flight.
  bool get isActive => _drag != null;

  /// Starts a drag on [controller]'s position; a no-op unless it has exactly
  /// one. Any drag already in flight is cancelled first.
  void start(ScrollController controller, DragStartDetails details) {
    // Defensive: `ScrollPosition.drag` already disposes the previous drag
    // when it begins a new activity, but cancelling here keeps this class
    // correct on its own and clears `_drag` if the start below is a no-op.
    cancel();
    if (controller.positions.length != 1) return;
    Drag? created;
    created = controller.position.drag(details, () {
      // Clear only if this drag is still the current one — a late dispose of
      // an older drag must not orphan a newer drag in flight.
      if (identical(_drag, created)) _drag = null;
    });
    _drag = created;
  }

  void update(DragUpdateDetails details, {double scale = 1}) {
    final Drag? drag = _drag;
    if (drag == null) return;
    if (scale == 1) {
      drag.update(details);
      return;
    }
    final double dx = details.delta.dx * scale;
    drag.update(
      DragUpdateDetails(
        globalPosition: details.globalPosition,
        localPosition: details.localPosition,
        sourceTimeStamp: details.sourceTimeStamp,
        delta: Offset(dx, 0),
        primaryDelta: dx,
        kind: details.kind,
      ),
    );
  }

  void end(DragEndDetails details, {double scale = 1}) {
    final Drag? drag = _drag;
    _drag = null;
    if (drag == null) return;
    if (scale == 1) {
      drag.end(details);
      return;
    }
    final double vx = details.velocity.pixelsPerSecond.dx * scale;
    drag.end(
      DragEndDetails(
        globalPosition: details.globalPosition,
        localPosition: details.localPosition,
        velocity: Velocity(pixelsPerSecond: Offset(vx, 0)),
        primaryVelocity: vx,
      ),
    );
  }

  /// Cancels the drag in flight, if any (dispose, controller swap, gesture
  /// cancel). The target's physics then settles from where it is.
  void cancel() {
    final Drag? drag = _drag;
    _drag = null;
    drag?.cancel();
  }
}

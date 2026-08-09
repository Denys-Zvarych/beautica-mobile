// VelvetSnack host — the `Overlay`-driven mechanism that animates, positions
// and auto-dismisses a bare `VelvetSnack`, with single-slot pre-emption.
// Transcribed verbatim (motion spec, positioning, pre-emption) from the
// approved preview app at
// `docs/signup-designs/VelvetSnack/lib/widgets/velvet_snack_host.dart`.
//
// This file is the MECHANISM layer. `show_velvet_snack.dart` is the thin,
// call-site-facing API every screen actually uses — split into its own file
// so the migration wave (63 legacy `ScaffoldMessenger` sites) can be briefed
// against a small, stable public surface without also reading the overlay
// bookkeeping below.
//
// ## Why an `Overlay` and not `ScaffoldMessenger`
//
// `ScaffoldMessenger` owns its own entrance animation, its own `SnackBar`
// layout and its own **FIFO queue**. The queue is the real problem: a user
// who taps «Зберегти» three times gets three snacks played back-to-back for
// twelve seconds. VelvetSnack is single-slot — a new snack pre-empts the
// current one with a fast 120ms exit, then plays its own entrance. Driving
// that through `ScaffoldMessenger` means fighting it; an `OverlayEntry`
// gives it for free and also frees the motion spec from Material's curves.
//
// ## Why the snack survives a route pop fired right after it
//
// [Overlay.of] is called here with `rootOverlay: true`, which walks PAST any
// nested `Navigator`'s own `Overlay` (a `ShellRoute` / `StatefulShellRoute`
// branch, a `showDialog`/`showModalBottomSheet` route) to the single
// outermost `Overlay` — the one owned by the app's ROOT `Navigator`, created
// once by `MaterialApp.router` and never rebuilt for the lifetime of the
// app. The inserted `OverlayEntry` therefore is NOT a descendant of the
// calling route's subtree: it is a sibling of the root `Navigator`'s whole
// page stack. A save-then-pop flow that calls `showVelvetSnack(context, ...)`
// immediately before `context.pop()` is safe because popping the calling
// route only removes THAT route's subtree from the root Navigator's page
// stack — it does not touch the root Overlay the snack's entry lives in. No
// widget-level "host" needs to be mounted anywhere for this to work: every
// `BuildContext` under `MaterialApp.router` already has this root Overlay as
// an ancestor from the very first frame, across every shell tab, dialog and
// bottom sheet.
//
// ## The known `ScaffoldMessenger` bug this design avoids
//
// `ScaffoldMessengerState.hideCurrentSnackBar` early-returns when the bar was
// already dismissed (e.g. by a timeout that raced a manual dismiss),
// silently leaving any `Future` that awaited the close unresolved — see
// `service_setup_screen.dart`'s `_showSnack`/`_retrySnack` handling for a
// documented instance. [_VelvetSnackScopeState.retire] avoids the whole
// class of bug structurally: it memoises the in-flight retirement `Future`
// (`_retirement ??= _retire(duration)`) so repeat calls return the SAME
// future rather than racing a second teardown, and every path through
// `_retire`/`_dismissImmediately` unconditionally reaches `widget.onRetired()`
// (or, on the "already disposed" branch, the entry has already been removed
// by an earlier call — the future for THAT call already completed). The
// future returned by [VelvetSnackHandle.dismiss] therefore always completes.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';

import 'velvet_snack.dart';

/// Handle on a live snack, so a caller can dismiss it early — e.g. a long
/// "завантаження" info snack replaced by the success one when a request
/// lands.
class VelvetSnackHandle {
  VelvetSnackHandle._(this._occupant);

  final _VelvetSnackOccupant _occupant;

  /// Plays the exit animation and tears the entry down. Always completes —
  /// see the class-level doc above.
  ///
  /// Goes through [_VelvetSnackOccupant.retireAndClear] rather than reading
  /// `key.currentState` directly, so a caller that dismisses a snack that is
  /// still QUEUED (pre-empting an earlier occupant, `initState` not yet run)
  /// actually cancels it instead of no-op'ing — `retireAndClear` already
  /// handles both the mounted and not-yet-mounted cases correctly, and is
  /// safe to call more than once (`remove()` is guarded by its own `removed`
  /// flag; the mounted branch's `retire()` memoises its future).
  Future<void> dismiss() => _occupant.retireAndClear(VelvetSnackMotion.exit);
}

/// Shows a [VelvetSnack] floating above everything, bottom-anchored, on the
/// app's ROOT `Overlay`. This is the mechanism `show_velvet_snack.dart`'s
/// `showVelvetSnack` wraps; screens should call that, not this, directly.
VelvetSnackHandle showOnVelvetSnackHost({
  required BuildContext context,
  required VelvetSnackVariant variant,
  required String message,
  String? actionLabel,
  VoidCallback? onAction,
  bool showClose = false,
  int maxLines = 2,
  Duration? dwell,
  double bottomInset = 0,
}) {
  return _VelvetSnackOverlay.instance.show(
    context: context,
    variant: variant,
    message: message,
    actionLabel: actionLabel,
    onAction: onAction,
    showClose: showClose,
    maxLines: maxLines,
    dwell: dwell,
    bottomInset: bottomInset,
  );
}

/// The overlay's current occupant, tracked independently of whether its
/// widget has actually mounted yet.
///
/// [_VelvetSnackOverlay.show] used to defer "who holds the slot" to
/// `_VelvetSnackScopeState.initState`'s `_register` call — but `initState`
/// only runs a frame after `OverlayState.insert` schedules its rebuild, so
/// two `show()` calls issued in the same synchronous tick both observed no
/// occupant and both inserted, mounting two overlapping snacks. This class
/// is claimed SYNCHRONOUSLY inside `show()`, before the entry is even
/// inserted, so a second same-tick call always sees a real occupant.
class _VelvetSnackOccupant {
  _VelvetSnackOccupant({required this.key, required this.remove});

  final GlobalKey<_VelvetSnackScopeState> key;
  final VoidCallback remove;

  /// Set by [_VelvetSnackOverlay.show] to the exact deferred-insert future it
  /// builds when THIS occupant itself had to wait behind an earlier one —
  /// left null when this occupant inserted immediately, since then there is
  /// nothing upstream to wait on.
  ///
  /// Exists so a pre-emption chains through the WHOLE lineage instead of
  /// stopping at its immediate predecessor. Without it: a still-queued
  /// occupant — never mounted, itself still waiting on ITS OWN predecessor's
  /// real exit — reads as "already gone" the instant a third `show()` call
  /// inspects it, because `key.currentState == null` looks identical whether
  /// nothing was ever here or something upstream is still mid-exit.
  /// Chaining onto `pendingInsert` distinguishes the two: it only resolves
  /// once every predecessor has genuinely retired AND this occupant's own
  /// insert-or-skip decision has already run.
  Future<void>? pendingInsert;

  /// Retires this occupant and guarantees it is gone by the time this
  /// completes.
  ///
  /// If its widget already mounted, that means playing the real exit
  /// animation via [_VelvetSnackScopeState.retire]. Otherwise this occupant
  /// never mounted — either it was pre-empted before `initState` ever ran,
  /// or it is itself still queued behind an earlier occupant.
  /// [remove] is called first either way, which is what marks it cancelled
  /// so its OWN deferred-insert callback (built in `show()`) skips inserting
  /// it once `pendingInsert` resolves — `remove` is idempotent, so calling
  /// it here even when it will also fire later (or already did) is safe.
  /// Returning `pendingInsert` (or an already-resolved future when there was
  /// nothing to wait on) then makes the CALLER wait for the entire upstream
  /// lineage to actually clear before treating the slot as free — never just
  /// this one occupant's absence.
  Future<void> retireAndClear(Duration duration) {
    final _VelvetSnackScopeState? state = key.currentState;
    if (state != null) {
      return state.retire(duration);
    }
    remove();
    return pendingInsert ?? Future<void>.value();
  }
}

/// Single-slot overlay manager.
///
/// Each entry owns its own removal closure — the manager never removes an
/// entry it does not currently hold, so a pre-empted snack tearing itself
/// down can never take its successor with it.
///
/// The slot (`_current`) is freed — via `onSlotFreed` — ONLY once an
/// occupant's own teardown has actually finished: see
/// `_VelvetSnackScopeState._retire`'s ordering and `_dismissImmediately`,
/// which both pair `onSlotFreed` with `onRetired` back-to-back with no async
/// gap between them. "The slot reads as free" and "the previous entry is
/// actually gone from the Overlay" must be the same moment — freeing the
/// slot any earlier reopens the exact single-slot guarantee this class
/// exists to provide, by letting an unrelated `show()` land in that gap,
/// read `_current == null`, and insert immediately instead of pre-empting
/// through `retireAndClear`.
class _VelvetSnackOverlay {
  _VelvetSnackOverlay._();

  static final _VelvetSnackOverlay instance = _VelvetSnackOverlay._();

  _VelvetSnackOccupant? _current;

  VelvetSnackHandle show({
    required BuildContext context,
    required VelvetSnackVariant variant,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
    required bool showClose,
    required int maxLines,
    Duration? dwell,
    required double bottomInset,
  }) {
    final OverlayState overlay = Overlay.of(context, rootOverlay: true);

    final GlobalKey<_VelvetSnackScopeState> key =
        GlobalKey<_VelvetSnackScopeState>();

    final Duration resolvedDwell =
        dwell ??
        (actionLabel != null
            ? VelvetSnackMotion.dwellWithAction
            : VelvetSnackMotion.dwell);

    late final OverlayEntry entry;
    bool removed = false;
    // Guards `entry.remove()` against ever firing before `entry` was
    // actually inserted — reachable when a THIRD same-tick `show()` call
    // pre-empts a second one whose own insertion is still a pending
    // microtask (see `retireAndClear`'s pre-mount branch below). Calling
    // `OverlayEntry.remove()` on an entry that was never inserted trips its
    // internal `_overlay != null` assertion.
    bool inserted = false;
    void remove() {
      if (removed) return;
      removed = true;
      if (inserted) entry.remove();
    }

    void insert() {
      inserted = true;
      overlay.insert(entry);
    }

    // Declared before `entry` is assigned (Dart forbids a closure — even one
    // that runs later — from referencing a local `final` before its
    // declaration point, unlike `entry` above, which sidesteps that via
    // `late`). `occupant` only needs `key` and `remove`, both already in
    // scope, so it can be built first and captured by `entry`'s builder.
    final _VelvetSnackOccupant occupant = _VelvetSnackOccupant(
      key: key,
      remove: remove,
    );

    entry = OverlayEntry(
      builder: (BuildContext ctx) => _VelvetSnackScope(
        key: key,
        variant: variant,
        message: message,
        actionLabel: actionLabel,
        onAction: onAction,
        showClose: showClose,
        maxLines: maxLines,
        dwell: resolvedDwell,
        bottomInset: bottomInset,
        onRetired: remove,
        onSlotFreed: () => _clearIfCurrent(occupant),
      ),
    );

    // Pre-empt whatever is on screen — no queue, ever. The incoming snack
    // waits for the outgoing one to clear so the two never overlap in the
    // same slot. Claiming the slot happens right here, synchronously, so a
    // second `show()` call in this same tick always observes `previous`
    // non-null and takes the pre-empt branch below instead of also
    // inserting directly — see `_VelvetSnackOccupant`'s doc comment.
    final _VelvetSnackOccupant? previous = _current;
    _current = occupant;
    if (previous == null) {
      insert();
    } else {
      final Future<void> deferredInsert = previous
          .retireAndClear(VelvetSnackMotion.replace)
          .then((_) {
            if (overlay.mounted && !removed) insert();
          });
      // Recorded so a LATER `show()` call that pre-empts THIS occupant
      // before it ever mounts can chain onto the same future instead of
      // reading "not mounted yet" as "already gone" — see
      // `_VelvetSnackOccupant.pendingInsert`.
      occupant.pendingInsert = deferredInsert;
      unawaited(deferredInsert);
    }

    return VelvetSnackHandle._(occupant);
  }

  void _clearIfCurrent(_VelvetSnackOccupant occupant) {
    if (identical(_current, occupant)) _current = null;
  }
}

/// The animated, positioned, dismissible wrapper around a bare [VelvetSnack].
class _VelvetSnackScope extends StatefulWidget {
  const _VelvetSnackScope({
    super.key,
    required this.variant,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    required this.showClose,
    required this.maxLines,
    required this.dwell,
    required this.bottomInset,
    required this.onRetired,
    required this.onSlotFreed,
  });

  final VelvetSnackVariant variant;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool showClose;
  final int maxLines;
  final Duration dwell;
  final double bottomInset;
  final VoidCallback onRetired;

  /// Tells the manager this occupant is retiring — clears `_current` if this
  /// is still the current occupant, so the next `show()` call sees the slot
  /// as free instead of stuck behind a stale reference. Distinct from
  /// [onRetired], which only tears down THIS entry's `OverlayEntry`.
  final VoidCallback onSlotFreed;

  @override
  State<_VelvetSnackScope> createState() => _VelvetSnackScopeState();
}

class _VelvetSnackScopeState extends State<_VelvetSnackScope>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: VelvetSnackMotion.enter,
    reverseDuration: VelvetSnackMotion.exit,
  );

  /// Drives slide + scale: `easeOutCubic` in, `easeInCubic` out.
  late final CurvedAnimation _travel = CurvedAnimation(
    parent: _controller,
    curve: VelvetSnackMotion.enterCurve,
    reverseCurve: VelvetSnackMotion.exitCurve,
  );

  /// Drives opacity. In: front-loaded (`Interval(0, .6)`) so the text is
  /// readable before the slide settles. Out: linear-ish `easeIn` across the
  /// whole exit, so the snack fades as it drops rather than snapping away.
  late final CurvedAnimation _fade = CurvedAnimation(
    parent: _controller,
    curve: VelvetSnackMotion.fadeIn,
    reverseCurve: Curves.easeIn,
  );

  Timer? _dwellTimer;
  Future<void>? _retirement;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _dwellTimer = Timer(
      VelvetSnackMotion.enter + widget.dwell,
      () => retire(VelvetSnackMotion.exit),
    );
    // Production-only delta from the preview (web has no haptics) — README
    // "Deviations / notes for the port": a light buzz on `error` only, since
    // success/info/warning are not worth one.
    if (widget.variant == VelvetSnackVariant.error) {
      unawaited(HapticFeedback.lightImpact());
    }
  }

  /// Plays the exit and tears the entry down. Idempotent — repeat calls
  /// return the in-flight retirement rather than starting a second one, so
  /// the returned future always completes exactly once, on every call path.
  Future<void> retire(Duration duration) {
    return _retirement ??= _retire(duration);
  }

  Future<void> _retire(Duration duration) async {
    _dwellTimer?.cancel();
    _controller.reverseDuration = duration;
    try {
      await _controller.reverse();
    } on TickerCanceled {
      // Disposed mid-exit; the entry is already going away.
    }
    if (!mounted) return;
    // Free the slot and tear the entry down together, back-to-back with no
    // async gap — matching `_dismissImmediately` — and only once the exit
    // animation has actually finished. Freeing the slot any earlier (this
    // used to run before `_controller.reverse()`) let an independent
    // `show()` land in the window while this snack was still visibly
    // exiting, read `_current == null`, and insert immediately instead of
    // pre-empting through `retireAndClear` — briefly mounting two snacks at
    // once. See `_VelvetSnackOverlay`'s class doc.
    widget.onSlotFreed();
    widget.onRetired();
  }

  /// Immediate teardown with no exit animation — the swipe already moved the
  /// snack off, so replaying a slide-down would double the motion.
  void _dismissImmediately() {
    _retirement ??= Future<void>.value();
    _dwellTimer?.cancel();
    widget.onSlotFreed();
    widget.onRetired();
  }

  @override
  void dispose() {
    _dwellTimer?.cancel();
    widget.onSlotFreed();
    _travel.dispose();
    _fade.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final MediaQueryData mq = MediaQuery.of(context);

    // Sit above the keyboard when one is open, above the safe area
    // otherwise, and above any caller-declared chrome (bottom nav) on top of
    // that.
    final double bottom =
        VelvetSpacing.md +
        widget.bottomInset +
        (mq.viewInsets.bottom > 0
            ? mq.viewInsets.bottom
            : mq.viewPadding.bottom);

    return Positioned(
      left: VelvetSpacing.md,
      right: VelvetSpacing.md,
      bottom: bottom,
      child: Material(
        type: MaterialType.transparency,
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: VelvetSnackMotion.slideFrom,
              end: Offset.zero,
            ).animate(_travel),
            child: ScaleTransition(
              scale: Tween<double>(
                begin: VelvetSnackMotion.scaleFrom,
                end: 1,
              ).animate(_travel),
              // Anchored to the bottom edge so the inflate reads as the
              // surface pushing up out of the page, not as a centred zoom.
              alignment: Alignment.bottomCenter,
              // `RenderTransform` — the render object behind `ScaleTransition`
              // — only composites a CACHED layer for its child when that
              // child `isRepaintBoundary`; otherwise it repaints the whole
              // subtree every animation tick, including `VelvetSnack`'s 16px
              // blurred `VelvetShadows.snackLift` shadow. Placed here,
              // directly under `ScaleTransition` (the innermost of the three
              // transitions this snack runs), so entrance (~19 frames),
              // exit (~12) and replace (~7) all animate one cached raster
              // instead of re-blurring on every frame.
              child: RepaintBoundary(
                child: Dismissible(
                  key: const ValueKey<String>('velvet_snack_dismissible'),
                  direction: DismissDirection.down,
                  // No resize phase — the snack is in an Overlay with
                  // unbounded height, and there is nothing below it to
                  // collapse into.
                  resizeDuration: null,
                  onDismissed: (_) => _dismissImmediately(),
                  child: VelvetSnack(
                    variant: widget.variant,
                    message: widget.message,
                    actionLabel: widget.actionLabel,
                    maxLines: widget.maxLines,
                    onAction: widget.onAction == null
                        ? null
                        : () {
                            widget.onAction!.call();
                            unawaited(retire(VelvetSnackMotion.replace));
                          },
                    onDismiss: widget.showClose
                        ? () => unawaited(retire(VelvetSnackMotion.exit))
                        : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// A 1 Hz countdown that rebuilds ONLY itself — the shared mechanism behind
// every "you must wait N seconds" affordance outside the OTP journey.
//
// ## Why this exists as its own widget
//
// Two surfaces needed the same behaviour in the same audit pass (2026-09-20):
//
//   * `MyBookingsErrorState` — a salon-board read came back
//     [SalonBoardRateLimitedFailure], and its retry button must stay DISABLED,
//     naming the wait, until the limiter's own `Retry-After` window closes.
//     Before this, the retry was a bare `ref.invalidate(...)` that re-fired
//     instantly straight back into the live limiter.
//   * `master_archive_screen.dart`'s list footer — a failed `loadMore` now
//     parks behind a cooldown (`MasterArchiveState.retryNotBefore`) instead of
//     re-arming itself on every scroll notification, and the footer has to say
//     so rather than swallowing the failure.
//
// ## Relationship to `OtpResendRow`
//
// `auth/presentation/widgets/otp_resend_row.dart` owns the ORIGINAL version of
// this mechanism (a `Timer.periodic`, a `setState` confined to a small
// subtree, and the [kMaxUxCooldownSeconds] ceiling above which no periodic
// timer is started at all). This widget is that mechanism and nothing else;
// the copy semantics, the tap→server→new-cooldown round trip and the
// `GlobalKey`-driven `resetCooldown()` that `VerificationScreen` depends on
// stay where they are.
//
// `OtpResendRow` is DELIBERATELY not rewired onto this primitive in the same
// change. It lives in `features/auth/presentation/`, so neither booking call
// site could import it anyway (cross-feature imports go through `domain/` or
// `shared/` only — `ARCHITECTURE-mobile.md`'s layer table), and its public
// `OtpResendRowState.resetCooldown()` is reached by `GlobalKey` from two auth
// screens, which a child-delegate rewrite would have to re-plumb through a
// second key. That is an auth-journey change with no benefit to either caller
// here. If it is ever done, this file is the target — do not fork a third
// timer.
//
// ## The ceiling
//
// Above [kMaxUxCooldownSeconds] (10 min) NO periodic timer is started: there
// is no number worth refreshing once a second for an hour. One single-shot
// timer fires at the end of the window instead, so the affordance still
// recovers on its own — 1 tick instead of ~3600. Same reasoning, and the same
// constant, as `OtpResendRow._isUnavailableWindow`.

import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:beautica_mobile/core/errors/failures.dart'
    show kMaxUxCooldownSeconds;

/// Builds the countdown's UI for the seconds still remaining.
///
/// [secondsRemaining] is `0` once the window has elapsed (and on the very
/// first build when [CooldownTicker.seconds] was already `<= 0`), which is the
/// signal to render the enabled affordance. Above [kMaxUxCooldownSeconds] it
/// is the un-ticking initial value, so a builder that wants a non-numeric
/// "unavailable" label can branch on `secondsRemaining > kMaxUxCooldownSeconds`.
typedef CooldownBuilder =
    Widget Function(BuildContext context, int secondsRemaining, Widget? child);

/// Counts [seconds] down to zero, rebuilding only this subtree once a second.
///
/// Restarting is keyed on [seconds] changing ([didUpdateWidget]): handing the
/// same value again does NOT restart the window, so a parent that rebuilds for
/// an unrelated reason cannot reset a running cooldown. A caller that must
/// restart an identical window changes the widget's [Key].
class CooldownTicker extends StatefulWidget {
  const CooldownTicker({
    required this.seconds,
    required this.builder,
    this.child,
    this.onElapsed,
    super.key,
  });

  /// The window to count down, in seconds. `<= 0` means "no cooldown" — the
  /// builder is called once with `0` and no timer is ever started.
  final int seconds;

  final CooldownBuilder builder;

  /// Hoisted out of the per-tick rebuild and handed back to [builder]
  /// unchanged, exactly as `AnimatedBuilder.child` does — anything in the
  /// countdown's subtree that does not depend on the remaining seconds belongs
  /// here.
  final Widget? child;

  /// Called ONCE, from the timer callback, the moment the window closes —
  /// never from [builder], so a host is free to `setState` in it.
  ///
  /// Exists for a host whose own build has to re-evaluate when the cooldown
  /// ends rather than merely re-rendering this subtree: `master_archive_
  /// screen.dart`'s auto-continue branch decides whether to schedule the next
  /// `loadMore` inside `build`, so without this hook a lapsed cooldown would
  /// leave it parked until some unrelated rebuild happened along.
  ///
  /// NOT called when [seconds] was already `<= 0` (there was no window to
  /// end) and not called on dispose.
  final VoidCallback? onElapsed;

  @override
  State<CooldownTicker> createState() => _CooldownTickerState();
}

class _CooldownTickerState extends State<CooldownTicker> {
  int _remaining = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _start(widget.seconds);
  }

  @override
  void didUpdateWidget(CooldownTicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seconds != widget.seconds) {
      _start(widget.seconds);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start(int seconds) {
    _timer?.cancel();
    _remaining = seconds > 0 ? seconds : 0;
    if (_remaining == 0) return;
    if (_remaining > kMaxUxCooldownSeconds) {
      // No periodic tick — see the file header. One single-shot timer so the
      // window still genuinely elapses instead of freezing forever.
      _timer = Timer(Duration(seconds: _remaining), () {
        if (!mounted) return;
        setState(() => _remaining = 0);
        widget.onElapsed?.call();
      });
      return;
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_remaining <= 1) {
        // Cancelled BEFORE the setState so no further tick can fire.
        t.cancel();
        setState(() => _remaining = 0);
        widget.onElapsed?.call();
      } else {
        setState(() => _remaining--);
      }
    });
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _remaining, widget.child);
}

// Shared "resend OTP" row — extracted from `verification_screen.dart`
// (Phase 2.11 VelvetTouch redesign, Fix B / MEDIUM-2) so the password-reset
// OTP flow can reuse the exact same visual treatment (Beautica OTP task,
// "Phase B1").
//
// Owns the cooldown [Timer] so that every tick calls setState only on this
// small subtree, not on a parent screen's entire State.
//
// Zero behavioural change from the original private `_ResendRow` /
// `_ResendRowState`: all copy ("Не отримали код?", "Надіслати знову", the
// countdown label) is now supplied by the caller via constructor parameters
// instead of being hardcoded to the email-verification l10n keys, so a second
// screen (password-reset OTP) can reuse the exact same widget with its own
// copy. [OtpResendRowState] stays public (renamed from `_ResendRowState`) so
// callers can hold a `GlobalKey<OtpResendRowState>` and call
// [OtpResendRowState.resetCooldown] exactly like `VerificationScreen` did.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:beautica_mobile/core/errors/failures.dart'
    show kMaxUxCooldownSeconds;
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';

/// Default cooldown (seconds) assumed immediately on a resend tap, before the
/// server confirms — matches the backend's default resend-cooldown window.
const int kDefaultOtpResendCooldownSeconds = 30;

/// Resend-code row: the [promptText] followed by either [resendLabel] or the
/// live countdown built by [resendTimerLabel].
///
/// [onResend] is called when the user taps the resend link. It must return
/// the cooldown (seconds) the row should display afterwards — the server's
/// authoritative value on throttle, [assumedCooldownSeconds] on success, or
/// `null` on a generic error (no cooldown — allow immediate retry).
class OtpResendRow extends StatefulWidget {
  const OtpResendRow({
    super.key,
    required this.onResend,
    required this.promptText,
    required this.resendLabel,
    required this.resendTimerLabel,
    required this.resendKey,
    this.initialCooldown = 0,
    this.assumedCooldownSeconds = kDefaultOtpResendCooldownSeconds,
    this.resendUnavailableLabel,
  });

  /// Called when the user taps the resend link. Returns the cooldown seconds
  /// to display (the server value for a throttle, [assumedCooldownSeconds]
  /// for success, or `null` for a generic error / no cooldown).
  final Future<int?> Function() onResend;

  /// Leading prompt text shown before the resend link (e.g. "Не отримали код?").
  final String promptText;

  /// Link label shown when the cooldown has reached zero (e.g. "Надіслати знову").
  final String resendLabel;

  /// Builds the label shown WHILE the cooldown is active, given the remaining
  /// seconds (e.g. `(s) => l10n.verificationResendTimer('$s с')`).
  final String Function(int secondsRemaining) resendTimerLabel;

  /// Key applied to the tappable resend [GestureDetector] — widget tests find
  /// + tap the row via this key.
  final Key resendKey;

  /// Cooldown (in seconds) to start immediately on mount. Pass a non-zero
  /// value when the screen loads right after the OTP was already sent by the
  /// backend, so the button stays disabled for the same window as the
  /// server-side cooldown.
  final int initialCooldown;

  /// Cooldown assumed optimistically the instant the user taps resend, before
  /// the network call resolves. Also used to detect whether the server
  /// returned a DIFFERENT cooldown that must replace the optimistic one.
  final int assumedCooldownSeconds;

  /// Optional non-numeric label for a cooldown longer than
  /// [kMaxUxCooldownSeconds] (10 min) — e.g. «Недоступно».
  ///
  /// OPT-IN, and deliberately so. Leave it `null` (the default) and this
  /// widget behaves exactly as it always has for every cooldown value: the
  /// numeric [resendTimerLabel] plus a 1 Hz timer. Supply it and a cooldown
  /// above the ceiling renders THIS label instead and starts **no periodic**
  /// timer — there is no number left to refresh once per second, and ticking
  /// for an hour to rebuild an unchanging string is pure waste. A single
  /// one-shot timer fires at the end of the window and re-enables the link,
  /// so the row still recovers on its own: 1 tick instead of ~3600.
  ///
  /// Added 2026-09-15 for the password-reset journey, whose per-IP 429 carries
  /// `Retry-After: 3600` and rendered «Надіслати знову (3600 с)» — not a human
  /// unit. The link stays DISABLED either way; only the label and the tick
  /// change. Re-enabling it is the original bug (it burns the user's next
  /// attempt against a bucket that is still closed) and must not regress.
  ///
  /// Below the ceiling this parameter changes nothing, whatever it is set to.
  final String? resendUnavailableLabel;

  @override
  State<OtpResendRow> createState() => OtpResendRowState();
}

class OtpResendRowState extends State<OtpResendRow> {
  int _cooldown = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.initialCooldown > 0) {
      _startCooldown(widget.initialCooldown);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Whether [seconds] is long enough that this row shows
  /// [OtpResendRow.resendUnavailableLabel] instead of a live countdown.
  ///
  /// False whenever the caller did not opt in, which is what keeps every
  /// pre-existing caller byte-identical.
  bool _isUnavailableWindow(int seconds) =>
      widget.resendUnavailableLabel != null && seconds > kMaxUxCooldownSeconds;

  void _startCooldown(int seconds) {
    _timer?.cancel();
    setState(() => _cooldown = seconds);
    if (_isUnavailableWindow(seconds)) {
      // No PERIODIC timer: the label for this window carries no number, so a
      // 1 Hz rebuild would recompute an identical string ~3600 times.
      //
      // One SINGLE-SHOT timer instead — 1 tick rather than `seconds` ticks,
      // which is the whole performance win, while still letting the window
      // actually elapse. Freezing `_cooldown` with no timer at all (the
      // 2026-09-15 first cut) left a row that is mounted past the window
      // showing a stale «Недоступно» forever: nothing else on this screen
      // clears it, since `resetCooldown()` is never called here.
      _timer = Timer(Duration(seconds: seconds), () {
        if (!mounted) return;
        setState(() => _cooldown = 0);
      });
      return;
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_cooldown <= 1) {
        // Cancel before the setState to ensure no further ticks can fire.
        t.cancel();
        setState(() => _cooldown = 0);
      } else {
        setState(() => _cooldown--);
      }
    });
  }

  /// Immediately cancels the running cooldown and resets the counter to zero.
  ///
  /// Called by a parent screen via [GlobalKey] when a post-OTP step fails
  /// after the OTP was already consumed: the user must be able to request a
  /// new code without waiting out the cooldown window.
  void resetCooldown() {
    _timer?.cancel();
    if (!mounted) return;
    setState(() => _cooldown = 0);
  }

  Future<void> _handleTap() async {
    // Fire-and-forget haptic so the tap always gives tactile feedback.
    // unawaited() because we don't gate any logic on completion and awaiting
    // a platform channel in widget tests blocks the async chain permanently.
    unawaited(HapticFeedback.lightImpact());

    if (_cooldown > 0) return;
    // Optimistic update — start the countdown immediately so the button
    // disables and the user gets instant visual feedback rather than seeing
    // "0 с" (no countdown) while the network request is in-flight.
    _startCooldown(widget.assumedCooldownSeconds);
    final int? serverSeconds = await widget.onResend();
    if (!mounted) return;
    if (serverSeconds == null) {
      // null = generic error OR server cooldown exceeded the UX ceiling.
      // Either way: cancel the optimistic countdown and let the user retry
      // immediately. The inline error banner already carries the appropriate
      // message.
      _timer?.cancel();
      setState(() => _cooldown = 0);
    } else if (serverSeconds != widget.assumedCooldownSeconds) {
      // Server returned a different cooldown (e.g. throttle retry-after).
      _startCooldown(serverSeconds);
    }
    // serverSeconds == assumedCooldownSeconds: timer already running — no change.
  }

  /// The label for the current cooldown: the resend link at zero, the
  /// non-numeric "unavailable" copy above the ceiling (opt-in only), and the
  /// live countdown otherwise.
  String _label() {
    if (_cooldown <= 0) return widget.resendLabel;
    final String? unavailable = widget.resendUnavailableLabel;
    if (unavailable != null && _isUnavailableWindow(_cooldown)) {
      return unavailable;
    }
    return widget.resendTimerLabel(_cooldown);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Text(widget.promptText, style: VelvetText.body()),
        const SizedBox(width: VelvetSpacing.xs),
        GestureDetector(
          key: widget.resendKey,
          onTap: _cooldown > 0 ? null : _handleTap,
          child: Text(
            _label(),
            // Batch-2 A3: use pre-cached styles — no per-tick copyWith allocation.
            // Active branch reuses the base _linkStyle (already accentDeep).
            style: _cooldown > 0
                ? VelvetText.resendCooldown
                : VelvetText.link(),
          ),
        ),
      ],
    );
  }
}

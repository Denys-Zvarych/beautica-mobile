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

  void _startCooldown(int seconds) {
    _timer?.cancel();
    setState(() => _cooldown = seconds);
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
            _cooldown > 0
                ? widget.resendTimerLabel(_cooldown)
                : widget.resendLabel,
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

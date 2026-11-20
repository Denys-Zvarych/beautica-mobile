// The ONE failure → resend-cooldown mapping of the SMS / email code steps
// ([PhoneCodeStep.onResend] contract: seconds to wait, or `null` = the link is
// usable again at once).
//
// PROMOTED (REUSE-FIRST, phone-first hardening M1, AUTH-D27 a) from
// `ContactVerifyScreen._resend`. `RegisterCodeScreen` had its own copy that
// returned `null` on EVERY failure, so a 429 re-enabled «Надіслати знову»
// immediately and the user could hammer a throttled send; both screens now
// call this helper.

import '../../../core/errors/failures.dart';
import 'widgets/phone_code_step.dart';

/// Cooldown that makes [PhoneCodeStep]'s resend row show its «unavailable»
/// label instead of a countdown (the row's `resendUnavailableLabel` window is
/// anything above [kMaxUxCooldownSeconds]).
const int kResendUnavailableCooldownSeconds = kMaxUxCooldownSeconds + 1;

/// Seconds the resend link stays disabled after a failed resend [f], or `null`
/// when an immediate retry is allowed (network error, App Check, …).
///
///  * [ResendThrottledFailure] → its positive `retryAfterSeconds`; `null`
///    (the server value was over the UX ceiling) →
///    [kResendUnavailableCooldownSeconds]; 0 / absent →
///    [kPhoneCodeResendCooldownSeconds];
///  * [PhoneIdentityFailure] `rateLimited` (429 on a phone OTP send, e.g. the
///    60 s per-phone cooldown) → its positive `Retry-After` (an over-ceiling
///    value arrives as [kResendUnavailableCooldownSeconds]), else
///    [kPhoneCodeResendCooldownSeconds];
///  * anything else → `null`.
///
/// A 0 / negative / missing `Retry-After` NEVER unlocks the link at once.
int? resendCooldownFor(Failure f) => switch (f) {
  ResendThrottledFailure(:final int? retryAfterSeconds) =>
    retryAfterSeconds == null
        ? kResendUnavailableCooldownSeconds
        : _positiveOrDefault(retryAfterSeconds),
  PhoneIdentityFailure(
    code: PhoneIdentityErrorCode.rateLimited,
    :final int? retryAfterSeconds,
  ) =>
    _positiveOrDefault(retryAfterSeconds),
  _ => null,
};

int _positiveOrDefault(int? seconds) => (seconds != null && seconds > 0)
    ? seconds
    : kPhoneCodeResendCooldownSeconds;

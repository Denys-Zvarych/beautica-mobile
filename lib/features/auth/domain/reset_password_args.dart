// Beautica OTP password-reset task (Phase B) — navigation payload for
// `RouteNames.resetPassword`.
//
// Replaces the old `?token=` deep-link query parameter: the single-use reset
// ticket now arrives via in-app navigation (`context.go(..., extra: ...)`)
// from `ResetOtpVerificationScreen`, never a deep link — see
// `app_router.dart`'s route registration comment for the full rationale.
//
// [fromChangePassword] distinguishes the two flows that both land on
// `ResetPasswordScreen`:
//   - `false` — the forgot-password flow (user is NOT logged in). On success
//     the screen shows its normal in-screen success state + "Увійти" CTA.
//   - `true`  — the settings "change password" flow (user IS logged in). On
//     success the screen proactively logs the user out (the backend revokes
//     the caller's own refresh token on any password reset) and routes
//     straight to /login with a "please sign in again" message, instead of
//     showing the normal success state.
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'reset_password_args.freezed.dart';

/// Navigation extra for `RouteNames.resetPassword`.
@freezed
abstract class ResetPasswordArgs with _$ResetPasswordArgs {
  const factory ResetPasswordArgs({
    required String resetTicket,
    @Default(false) bool fromChangePassword,
  }) = _ResetPasswordArgs;
}

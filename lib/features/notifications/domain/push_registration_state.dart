import 'package:freezed_annotation/freezed_annotation.dart';

part 'push_registration_state.freezed.dart';

/// Phase 067 — where the device's FCM registration stands for the signed-in
/// user. Pure Dart. Deliberately carries NO token: the generated toString /
/// equality would expose it (the notifier keeps it private).
@freezed
sealed class PushRegistrationState with _$PushRegistrationState {
  /// Nothing to do yet (signed out, or registration still in flight).
  const factory PushRegistrationState.idle() = PushIdle;

  /// The token is registered with the backend and notifications are allowed.
  const factory PushRegistrationState.registered() = PushRegistered;

  /// The user declined the system prompt. The token is still registered
  /// (harmless; a later grant in system settings just works); no re-prompt.
  const factory PushRegistrationState.permissionDenied() = PushPermissionDenied;

  /// Firebase is not usable (non-Android, or no `google-services.json`).
  const factory PushRegistrationState.unavailable() = PushUnavailable;
}

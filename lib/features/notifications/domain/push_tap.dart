import 'package:freezed_annotation/freezed_annotation.dart';

import 'app_notification.dart';

part 'push_tap.freezed.dart';

/// Phase 068 — an FCM `data` payload (backend 339) decoded into domain types.
/// Pure Dart; built by `NotificationMapper.pushTapFromData`. Carries only ids
/// and enums — never title / body text.
@freezed
abstract class PushTap with _$PushTap {
  const factory PushTap({
    required String notificationId,
    required AppNotificationType type,
    required NotificationTarget target,
  }) = _PushTap;
}

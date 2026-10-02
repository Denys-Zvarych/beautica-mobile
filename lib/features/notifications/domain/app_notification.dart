// Phase 359 — in-app notification feed domain model.
//
// Pure Dart. Hydrated by `NotificationMapper.fromDto` off
// `GET /api/v1/notifications` (backend 334). The generated DTOs never escape
// the data layer.
//
// FORWARD COMPATIBILITY: an unrecognised `type` decodes to
// [AppNotificationType.unknown] and its target to [NoTarget] — a backend that
// ships an eleventh type must not blank the list.
//
// SCOPE: the feed is per USER, global across every salon an owner owns. Rows
// carry `params.salonName` so the UI can label which salon an item is about;
// nothing here is keyed by an "active salon".

import 'package:freezed_annotation/freezed_annotation.dart';

part 'app_notification.freezed.dart';

/// Backend notification types (mirror of `NotificationResponse.type`).
enum AppNotificationType {
  bookingCreated,
  bookingCancelledByClient,
  bookingDeclined,
  bookingNotCompleted,
  bookingRescheduled,
  reviewRequested,
  bookingCancelledSalonClosed,
  bookingCancelledMasterRemoved,
  reviewReceived,
  inviteAccepted,

  /// A wire value this build predates. Rendered as a generic row; never throws.
  unknown,
}

/// Where tapping a notification leads.
@freezed
sealed class NotificationTarget with _$NotificationTarget {
  /// Open the booking / visit detail.
  const factory NotificationTarget.booking({
    required String bookingId,
    String? appointmentId,
    String? salonId,
  }) = BookingTarget;

  /// Open the booking detail's review affordance.
  const factory NotificationTarget.bookingReview({required String bookingId}) =
      BookingReviewTarget;

  /// Open the salon's «Команда» tab.
  const factory NotificationTarget.salonTeam({required String salonId}) =
      SalonTeamTarget;

  /// Mark-read only.
  const factory NotificationTarget.none() = NoTarget;
}

/// Display parameters. Every field is nullable: the backend nulls them when the
/// recipient lost access to the subject (e.g. removed from the salon), and the
/// UI must render a params-less row instead of crashing.
@freezed
abstract class NotificationParams with _$NotificationParams {
  const factory NotificationParams({
    String? counterpartName,
    String? serviceName,

    /// Number of services in the visit; `null` when absent.
    int? serviceCount,

    /// Booking start as an absolute instant (UTC). Kyiv-day display is the
    /// caller's job (`lib/shared/time/kyiv_day.dart`).
    DateTime? startsAt,

    /// Salon the item is about — the owner-multi-salon label.
    String? salonName,
    String? subjectName,

    /// Wire role name of the subject (`CLIENT`, `SALON_MASTER`, …); `null`
    /// when absent or unrecognised.
    String? subjectRole,
  }) = _NotificationParams;

  const NotificationParams._();

  /// All-null params (lost access / absent payload).
  static const NotificationParams empty = NotificationParams();
}

/// One row of the feed.
@freezed
abstract class AppNotification with _$AppNotification {
  const factory AppNotification({
    required String id,
    required AppNotificationType type,
    required DateTime createdAt,
    required bool read,
    required NotificationTarget target,
    @Default(NotificationParams.empty) NotificationParams params,
  }) = _AppNotification;
}

/// One page of the feed, newest first.
@freezed
abstract class NotificationPage with _$NotificationPage {
  const factory NotificationPage({
    required List<AppNotification> items,
    required int page,
    required int size,
    required int totalElements,
    required int totalPages,
  }) = _NotificationPage;

  const NotificationPage._();

  /// Whether another page exists after this one.
  bool get hasNext => page + 1 < totalPages;
}

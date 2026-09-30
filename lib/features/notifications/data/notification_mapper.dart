// Phase 359 — notification feed mapper (generated DTO → domain).
//
// NULLABILITY POLICY — every generated field is nullable (SpringDoc emits no
// `required` list), so this is the one place the domain's shape is decided:
//   • a row with no `id` or no `createdAt` is DROPPED (returns null): without
//     an id it cannot be marked read, without a timestamp it cannot be sorted
//     or grouped. Dropping one row beats failing the page.
//   • unknown / absent `type`  → [AppNotificationType.unknown] + [NoTarget].
//   • unknown / absent `kind`, or a kind whose required id is missing
//                              → [NoTarget].
//   • absent `params`          → [NotificationParams.empty].
//   • absent `read`            → `false` (the safe side: it stays visible).

import 'dart:developer';

import 'package:beautica_api/beautica_api.dart' as api;
import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart'
    show EqualUnmodifiableListView;

import '../../../core/network/api_enum_names.dart';
import '../domain/app_notification.dart';

abstract final class NotificationMapper {
  static AppNotificationType typeFromDto(
    api.NotificationResponseTypeEnum? dto,
  ) {
    if (dto == null || isOpenApiUnknownDefault(dto)) {
      return AppNotificationType.unknown;
    }
    if (dto == api.NotificationResponseTypeEnum.BOOKING_CREATED) {
      return AppNotificationType.bookingCreated;
    }
    if (dto == api.NotificationResponseTypeEnum.BOOKING_CANCELLED_BY_CLIENT) {
      return AppNotificationType.bookingCancelledByClient;
    }
    if (dto == api.NotificationResponseTypeEnum.BOOKING_DECLINED) {
      return AppNotificationType.bookingDeclined;
    }
    if (dto == api.NotificationResponseTypeEnum.BOOKING_NOT_COMPLETED) {
      return AppNotificationType.bookingNotCompleted;
    }
    if (dto == api.NotificationResponseTypeEnum.BOOKING_RESCHEDULED) {
      return AppNotificationType.bookingRescheduled;
    }
    if (dto == api.NotificationResponseTypeEnum.REVIEW_REQUESTED) {
      return AppNotificationType.reviewRequested;
    }
    if (dto ==
        api.NotificationResponseTypeEnum.BOOKING_CANCELLED_SALON_CLOSED) {
      return AppNotificationType.bookingCancelledSalonClosed;
    }
    if (dto ==
        api.NotificationResponseTypeEnum.BOOKING_CANCELLED_MASTER_REMOVED) {
      return AppNotificationType.bookingCancelledMasterRemoved;
    }
    if (dto == api.NotificationResponseTypeEnum.REVIEW_RECEIVED) {
      return AppNotificationType.reviewReceived;
    }
    if (dto == api.NotificationResponseTypeEnum.INVITE_ACCEPTED) {
      return AppNotificationType.inviteAccepted;
    }
    return AppNotificationType.unknown;
  }

  static NotificationTarget targetFromDto(api.NotificationTarget? dto) {
    final kind = dto?.kind;
    if (dto == null || kind == null || isOpenApiUnknownDefault(kind)) {
      return const NotificationTarget.none();
    }
    final String? bookingId = _nonBlank(dto.bookingId);
    final String? salonId = _nonBlank(dto.salonId);
    if (kind == api.NotificationTargetKindEnum.BOOKING && bookingId != null) {
      return NotificationTarget.booking(
        bookingId: bookingId,
        appointmentId: _nonBlank(dto.appointmentId),
        salonId: salonId,
      );
    }
    if (kind == api.NotificationTargetKindEnum.BOOKING_REVIEW &&
        bookingId != null) {
      return NotificationTarget.bookingReview(bookingId: bookingId);
    }
    if (kind == api.NotificationTargetKindEnum.SALON_TEAM && salonId != null) {
      return NotificationTarget.salonTeam(salonId: salonId);
    }
    return const NotificationTarget.none();
  }

  static NotificationParams paramsFromDto(api.NotificationParams? dto) {
    if (dto == null) return NotificationParams.empty;
    return NotificationParams(
      counterpartName: _nonBlank(dto.counterpartName),
      serviceName: _nonBlank(dto.serviceName),
      serviceCount: dto.serviceCount,
      startsAt: dto.startsAt?.toUtc(),
      salonName: _nonBlank(dto.salonName),
      subjectName: _nonBlank(dto.subjectName),
      subjectRole: knownEnumName(dto.subjectRole),
    );
  }

  /// `null` when the row is unusable (no id / no createdAt).
  static AppNotification? fromDto(api.NotificationResponse dto) {
    final String? id = _nonBlank(dto.id);
    final DateTime? createdAt = dto.createdAt;
    if (id == null || createdAt == null) {
      if (kDebugMode) {
        log(
          'dropping notification row without id/createdAt',
          name: 'feature.notifications.mapper',
          level: 900,
        );
      }
      return null;
    }
    final AppNotificationType type = typeFromDto(dto.type);
    return AppNotification(
      id: id,
      type: type,
      createdAt: createdAt.toUtc(),
      read: dto.read ?? false,
      // An unknown type has no known destination even if `kind` is known.
      target: type == AppNotificationType.unknown
          ? const NotificationTarget.none()
          : targetFromDto(dto.target),
      params: paramsFromDto(dto.params),
    );
  }

  static NotificationPage pageFromDto(
    api.PageResponseNotificationResponse dto,
  ) {
    // Built ONCE and stored as an [EqualUnmodifiableListView]: freezed's
    // getter returns it as-is, so `identical(page.items, page.items)` holds
    // (a bare `List.unmodifiable` would be re-wrapped on every access).
    final List<AppNotification> items = EqualUnmodifiableListView(
      (dto.data ?? const <api.NotificationResponse>[])
          .map(fromDto)
          .nonNulls
          .toList(growable: false),
    );
    return NotificationPage(
      items: items,
      page: dto.page ?? 0,
      size: dto.size ?? items.length,
      totalElements: dto.totalElements ?? items.length,
      totalPages: dto.totalPages ?? 1,
    );
  }

  static String? _nonBlank(String? v) {
    final t = v?.trim();
    return t == null || t.isEmpty ? null : t;
  }
}

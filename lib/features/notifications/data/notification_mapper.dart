// Phase 359 — notification feed mapper (generated DTO → domain).
//
// NULLABILITY POLICY — every generated field is nullable (SpringDoc emits no
// `required` list), so this is the one place the domain's shape is decided:
//   • a row with no `id` or no `createdAt` is DROPPED (returns null): without
//     an id it cannot be marked read, without a timestamp it cannot be sorted
//     or grouped. Dropping one row beats failing the page. So is a row whose
//     `id` is not a UUID (it is interpolated into a URL path).
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
import '../domain/push_tap.dart';

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
    // Both ids are interpolated into route paths: a non-UUID value downgrades
    // the whole target to [NoTarget]. Only the REASON is logged, never the value.
    final String? bookingId = _nonBlank(dto.bookingId);
    final String? salonId = _nonBlank(dto.salonId);
    if ((bookingId != null && !_uuid.hasMatch(bookingId)) ||
        (salonId != null && !_uuid.hasMatch(salonId))) {
      if (kDebugMode) {
        log(
          'dropping notification target with a non-UUID id',
          name: 'feature.notifications.mapper',
          level: 900,
        );
      }
      return const NotificationTarget.none();
    }
    if (kind == api.NotificationTargetKindEnum.BOOKING && bookingId != null) {
      // `appointmentId` is optional and reaches routing too (untrusted FCM
      // data): a non-UUID value is dropped, the booking target itself stays.
      final String? rawAppointmentId = _nonBlank(dto.appointmentId);
      final String? appointmentId =
          rawAppointmentId != null && _uuid.hasMatch(rawAppointmentId)
          ? rawAppointmentId
          : null;
      if (rawAppointmentId != null && appointmentId == null && kDebugMode) {
        log(
          'dropping non-UUID appointmentId from notification target',
          name: 'feature.notifications.mapper',
          level: 900,
        );
      }
      return NotificationTarget.booking(
        bookingId: bookingId,
        appointmentId: appointmentId,
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

  /// Phase 068 — builds the target from an FCM `data` map (backend 339) and
  /// DELEGATES to [targetFromDto], so feed and push share one validation path
  /// (UUID checks, [NoTarget] fallback). Non-string / absent / unknown
  /// `targetKind` → [NoTarget]. Never throws.
  static NotificationTarget targetFromPushData(Map<String, dynamic> d) {
    final String? kindName = _pushString(d['targetKind']);
    if (kindName == null) return const NotificationTarget.none();
    // Wire name → generated member by lookup (never `valueOf`, whose
    // fallback member would masquerade as data). Unknown → [NoTarget].
    final api.NotificationTargetKindEnum? kind = api
        .NotificationTargetKindEnum
        .values
        .where((e) => knownEnumName(e) == kindName)
        .firstOrNull;
    if (kind == null) return const NotificationTarget.none();
    final api.NotificationTarget dto = api.NotificationTarget(
      (b) => b
        ..kind = kind
        ..bookingId = _pushString(d['bookingId'])
        ..appointmentId = _pushString(d['appointmentId'])
        ..salonId = _pushString(d['salonId']),
    );
    return targetFromDto(dto);
  }

  /// Phase 068 — decodes an FCM `data` map. `null` (ignore the message) when
  /// `notificationId` is absent / not a UUID. `v` is not gated: known keys are
  /// always parsed, an unknown `type` / `targetKind` degrades to
  /// [AppNotificationType.unknown] / [NoTarget] (same rule as [fromDto]).
  static PushTap? pushTapFromData(Map<String, dynamic> d) {
    final String? id = _pushString(d['notificationId']);
    if (id == null || !_uuid.hasMatch(id)) return null;
    final String? typeName = _pushString(d['type']);
    final AppNotificationType type = typeFromDto(
      api.NotificationResponseTypeEnum.values
          .where((e) => knownEnumName(e) == typeName)
          .firstOrNull,
    );
    return PushTap(
      notificationId: id,
      type: type,
      target: type == AppNotificationType.unknown
          ? const NotificationTarget.none()
          : targetFromPushData(d),
    );
  }

  static String? _pushString(Object? v) => v is String ? _nonBlank(v) : null;

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
      masterName: _nonBlank(dto.masterName),
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
    // The id is interpolated into `PATCH /notifications/{id}/read`: anything
    // that is not a UUID is dropped here rather than ever reaching a path.
    // Only the REASON is logged, never the value.
    if (!_uuid.hasMatch(id)) {
      if (kDebugMode) {
        log(
          'dropping notification row with a non-UUID id',
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

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static String? _nonBlank(String? v) {
    final t = v?.trim();
    return t == null || t.isEmpty ? null : t;
  }
}

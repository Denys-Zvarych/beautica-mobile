// Phase 359 — in-app notification feed repository.
//
// Wraps the four `/api/v1/notifications` routes (backend 334) behind the
// generated [NotificationsApi]. Every method resolves or throws a typed
// [Failure]; raw [DioException]s never escape. The 429 mapping
// ([NotificationsRateLimitedFailure]) is done by `ErrorMapperInterceptor` and
// arrives here as `e.error`.
//
// `markRead` surfaces a 404 (missing OR someone else's item) as
// [NotFoundFailure]; the feed notifier (phase 363) treats that as "done".

import 'dart:developer';

import 'package:beautica_api/beautica_api.dart' as api;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/errors/failures.dart';
import '../../../core/network/api_client_provider.dart';
import '../../../core/network/error_mapper_interceptor.dart';
import '../domain/app_notification.dart';
import 'notification_mapper.dart';

part 'notification_repository.g.dart';

abstract interface class NotificationRepository {
  /// Newest-first page. Backend bounds: `size` 1–50, `page` ≤ 10000.
  Future<NotificationPage> fetchPage({required int page, required int size});

  /// Unread count, capped at 99 by the backend.
  Future<int> unreadCount();

  /// Idempotent; throws [NotFoundFailure] for a missing / foreign id.
  Future<void> markRead(String id);

  /// Marks everything created at or before [upTo] (default: now) read.
  /// Returns the number of rows updated.
  Future<int> markAllRead({DateTime? upTo});
}

final class HttpNotificationRepository implements NotificationRepository {
  HttpNotificationRepository(this._api);

  final api.NotificationsApi _api;

  @override
  Future<NotificationPage> fetchPage({required int page, required int size}) =>
      _guard('fetchPage', () async {
        final res = await _api.listFeed(page: page, size: size);
        final dto = res.data;
        if (dto == null) throw const ServerFailure(statusCode: null);
        return NotificationMapper.pageFromDto(dto);
      });

  @override
  Future<int> unreadCount() => _guard('unreadCount', () async {
    final int? count = (await _api.unreadCount()).data?.data?.count;
    if (count == null) throw const ServerFailure(statusCode: null);
    return count < 0 ? 0 : count;
  });

  @override
  Future<void> markRead(String id) => _guard('markRead', () async {
    await _api.markRead(id: id);
  });

  @override
  Future<int> markAllRead({DateTime? upTo}) => _guard('markAllRead', () async {
    final res = await _api.markAllRead(
      markAllReadRequest: api.MarkAllReadRequest(
        (b) => b..upTo = upTo?.toUtc(),
      ),
    );
    final int? updated = res.data?.data?.updated;
    if (updated == null) throw const ServerFailure(statusCode: null);
    return updated;
  });

  Future<T> _guard<T>(String op, Future<T> Function() body) async {
    try {
      return await body();
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          '$op failed: ${e.type} ${e.response?.statusCode}',
          name: 'feature.notifications.repository',
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  Failure _mapDioException(DioException e) {
    if (e.error is Failure) return e.error as Failure;
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return NetworkFailure(cause: e);
      case DioExceptionType.badCertificate:
        return CertificateFailure(cause: e);
      case DioExceptionType.badResponse:
        final int? status = e.response?.statusCode;
        if (status == 404) return NotFoundFailure(cause: e);
        if (status == 429) {
          return NotificationsRateLimitedFailure(
            retryAfterSeconds:
                ErrorMapperInterceptor.notificationsRetryAfterSeconds(e),
            cause: e,
          );
        }
        return ServerFailure(statusCode: status, cause: e);
      case DioExceptionType.cancel:
      case DioExceptionType.unknown:
        return ServerFailure(statusCode: e.response?.statusCode, cause: e);
    }
  }
}

@Riverpod(keepAlive: true)
NotificationRepository notificationRepository(Ref ref) =>
    HttpNotificationRepository(ref.watch(notificationsApiProvider));

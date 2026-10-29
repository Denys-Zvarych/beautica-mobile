// Phase 424 — ContentReportRepository: the one seam for backend 395
// `POST /api/v1/reports`.
//
// Implemented over the generated `beautica_api` [ReportControllerApi]. DTOs are
// never hand-written: [HttpContentReportRepository] maps the generated
// [CreateReportRequest] / [ReportResponse] to [ContentReportRequest] /
// [ContentReport]. The request carries the reporter's free-text comment, so it
// is never logged (only transport metadata is), and `/api/v1/reports` is a
// redacted path in `LoggingInterceptor` (`kPiiPathPrefixes`).

import 'dart:developer';

import 'package:beautica_api/beautica_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/api_enum_names.dart';
import 'package:beautica_mobile/core/network/dio_provider.dart';
import 'package:beautica_mobile/features/moderation/domain/content_report.dart';

part 'content_report_repository.g.dart';

const String _tag = 'feature.moderation.repository';

/// Contract for reporting user-generated content.
///
/// Every method either resolves or throws a [Failure]; raw Dio types never
/// cross this boundary.
abstract interface class ContentReportRepository {
  /// `POST /api/v1/reports`. Resolves with the created report (201) or the
  /// caller's existing open report for the same target (200, idempotent).
  ///
  /// Throws:
  ///   - [ValidationFailure] on **400** (bad body / self-report).
  ///   - [NotFoundFailure] on **404** (target not visible to the caller).
  ///   - [ServerFailure] with `statusCode: 429` on the rate limit.
  ///   - [ResponseUnusableFailure] on a 2xx whose envelope lacks the report
  ///     (safe to retry — the endpoint is idempotent per target).
  ///   - [NetworkFailure] / [ServerFailure] / [UnknownFailure] otherwise.
  Future<ContentReport> create(ContentReportRequest request);

  /// Phase 428 add-on — every target the signed-in user has reported
  /// (backend 415 `GET /reports/mine`). Unknown target types are dropped.
  Future<Set<ReportedTarget>> mine();
}

/// HTTP implementation of [ContentReportRepository].
///
/// Inject via [contentReportRepositoryProvider] — never construct directly
/// outside tests.
final class HttpContentReportRepository implements ContentReportRepository {
  HttpContentReportRepository(this._api);

  final ReportControllerApi _api;

  @override
  Future<ContentReport> create(ContentReportRequest request) async {
    final String? trimmed = request.comment?.trim();
    final String? comment = (trimmed == null || trimmed.isEmpty)
        ? null
        : trimmed;
    final Response<ApiResponseReportResponse> response;
    try {
      response = await _api.createReport(
        createReportRequest: CreateReportRequest(
          (b) => b
            ..targetType = _targetTypeDto(request.targetType)
            ..targetId = request.targetId
            ..reason = _reasonDto(request.reason)
            ..comment = comment,
        ),
      );
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        // Transport metadata only — never the body (free-text comment).
        log(
          'create failed: ${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw mapContentReportDioException(e);
    }

    final ReportResponse? dto = response.data?.data;
    final String? id = dto?.id;
    final String? status = knownEnumName(dto?.status);
    final DateTime? createdAt = dto?.createdAt;
    if (id == null || status == null || createdAt == null) {
      throw const ResponseUnusableFailure();
    }
    return ContentReport(id: id, status: status, createdAt: createdAt);
  }

  @override
  Future<Set<ReportedTarget>> mine() async {
    final Response<ApiResponseListReportedTargetResponse> response;
    try {
      response = await _api.myReports();
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'mine failed: ${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw mapContentReportDioException(e);
    }
    final Set<ReportedTarget> out = <ReportedTarget>{};
    for (final ReportedTargetResponse row
        in response.data?.data ?? const <ReportedTargetResponse>[]) {
      final String? wire = knownEnumName(row.targetType);
      final String? id = row.targetId;
      if (wire == null || id == null || id.isEmpty) continue;
      for (final ReportTargetType t in ReportTargetType.values) {
        if (t.wireName == wire) out.add((type: t, id: id));
      }
    }
    return out;
  }

  static CreateReportRequestTargetTypeEnum _targetTypeDto(
    ReportTargetType type,
  ) => switch (type) {
    ReportTargetType.review => CreateReportRequestTargetTypeEnum.REVIEW,
    ReportTargetType.clientReview =>
      CreateReportRequestTargetTypeEnum.CLIENT_REVIEW,
    ReportTargetType.portfolioPhoto =>
      CreateReportRequestTargetTypeEnum.PORTFOLIO_PHOTO,
    ReportTargetType.masterProfile =>
      CreateReportRequestTargetTypeEnum.MASTER_PROFILE,
    ReportTargetType.salonProfile =>
      CreateReportRequestTargetTypeEnum.SALON_PROFILE,
    ReportTargetType.clientProfile =>
      CreateReportRequestTargetTypeEnum.CLIENT_PROFILE,
  };

  static CreateReportRequestReasonEnum _reasonDto(ReportReason reason) =>
      switch (reason) {
        ReportReason.spam => CreateReportRequestReasonEnum.SPAM,
        ReportReason.offensive => CreateReportRequestReasonEnum.OFFENSIVE,
        ReportReason.harassment => CreateReportRequestReasonEnum.HARASSMENT,
        ReportReason.falseInfo => CreateReportRequestReasonEnum.FALSE_INFO,
        ReportReason.sexualContent =>
          CreateReportRequestReasonEnum.SEXUAL_CONTENT,
        ReportReason.other => CreateReportRequestReasonEnum.OTHER,
      };
}

/// Maps a `POST /reports` [DioException] to a typed [Failure] (phase 424 D4).
///
/// The status arms run BEFORE the interceptor-attached failure: the shared
/// [ErrorMapperInterceptor] has no generic 429 arm (it yields an
/// [UnknownFailure]), and the sheet keys its «Забагато скарг» copy on
/// `ServerFailure(statusCode: 429)`.
@visibleForTesting
Failure mapContentReportDioException(DioException e) {
  final int? statusCode = e.response?.statusCode;
  if (statusCode == 429) return ServerFailure(statusCode: 429, cause: e);
  if (statusCode == 404) return NotFoundFailure(cause: e);
  final Object? attached = e.error;
  if (attached is Failure) return attached;
  if (statusCode == 400 || statusCode == 422) {
    return ValidationFailure(fieldErrors: const {}, cause: e);
  }
  switch (e.type) {
    case DioExceptionType.connectionError:
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return NetworkFailure(cause: e);
    case DioExceptionType.badResponse:
      if (statusCode == 401) return UnauthorizedFailure(cause: e);
      return ServerFailure(statusCode: statusCode, cause: e);
    case DioExceptionType.cancel:
    case DioExceptionType.badCertificate:
    case DioExceptionType.unknown:
      return UnknownFailure(cause: e);
  }
}

/// The generated [ReportControllerApi] on the authenticated Dio (full
/// interceptor chain). Feature-local, mirroring `clientReviewApiProvider`.
@Riverpod(keepAlive: true)
ReportControllerApi reportApi(Ref ref) =>
    ReportControllerApi(ref.watch(dioProvider), standardSerializers);

/// The app-wide [ContentReportRepository].
@Riverpod(keepAlive: true)
ContentReportRepository contentReportRepository(Ref ref) =>
    HttpContentReportRepository(ref.watch(reportApiProvider));

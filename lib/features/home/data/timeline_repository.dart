// Phase 110 (13.9) — BEAUTY TIMELINE repository.
//
// Fetches the CLIENT's completed-procedure timeline from
// `GET /api/v1/clients/me/timeline` (backend 19.5) through the generated
// [ClientControllerApi] and maps it via [TimelineMapper.fromDtoList].
//
// Error policy mirrors [HttpPassportRepository] (`../../passport/data/
// passport_repository.dart`) exactly: every method either resolves
// successfully or throws a [Failure] subclass from `core/errors/
// failures.dart`. Raw [DioException]s are caught here and never escape, so
// the screen only ever sees a typed failure. There is no retry loop — this
// is a plain idempotent GET and the screen (`_CardErrorState` in
// `home_hub_screen.dart`) owns the retry affordance via
// `ref.invalidate(beautyTimelineProvider)`.
//
// The API client comes from the shared, keep-alive [clientApiProvider]
// (`core/network/api_client_provider.dart`), which is built on the singleton
// [dioProvider] carrying the full interceptor chain (auth → log → retry →
// error map → refresh). Never construct a bare `Dio()` here.

import 'dart:developer';

import 'package:beautica_api/beautica_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/errors/failures.dart';
import '../domain/home_hub_models.dart';
import 'timeline_mapper.dart';

/// Reads the CLIENT's BEAUTY TIMELINE (completed-procedure history).
abstract interface class TimelineRepository {
  /// Returns the signed-in client's beauty timeline, most-recent-first.
  ///
  /// Throws a typed [Failure] on any transport or server error; raw
  /// [DioException]s never escape the implementation.
  Future<List<TimelineEntry>> getMyTimeline();
}

/// HTTP implementation of [TimelineRepository] backed by the generated
/// [ClientControllerApi].
///
/// Inject via `timelineRepositoryProvider` (`application/
/// home_hub_notifier.dart`) — never construct directly outside that
/// provider.
final class HttpTimelineRepository implements TimelineRepository {
  HttpTimelineRepository(this._clientApi);

  final ClientControllerApi _clientApi;

  static const _tag = 'feature.home.timeline_repository';

  /// The single page fetched. `BeautyTimelineSection` is a horizontal rail
  /// with no page footer or infinite-scroll affordance in the approved
  /// design, so — matching `HttpFavoriteRepository.pageSize`'s policy —
  /// this states the requested size explicitly rather than relying on the
  /// endpoint's own `@PageableDefault`, so a future backend-side default
  /// change cannot silently resize the rail. A client with more than 20
  /// completed procedures sees only the 20 most recent.
  static const int _pageSize = 20;

  static final Pageable _firstPage = Pageable(
    (PageableBuilder b) => b
      ..page = 0
      ..size = _pageSize,
  );

  @override
  Future<List<TimelineEntry>> getMyTimeline() async {
    try {
      final Response<ApiResponsePageResponseTimelineItemResponse> res =
          await _clientApi.getTimeline(pageable: _firstPage);
      final PageResponseTimelineItemResponse? page = res.data?.data;
      if (page == null) {
        if (kDebugMode) {
          log(
            'getMyTimeline: response envelope .data is null',
            name: _tag,
            level: 1000,
          );
        }
        throw const ServerFailure(statusCode: null);
      }
      // An ABSENT rows list is an EMPTY timeline, not an error: the envelope
      // itself arrived, so the server answered. Only a missing envelope
      // (above) is a broken payload.
      final rows = page.data;
      if (rows == null) return const <TimelineEntry>[];
      return TimelineMapper.fromDtoList(rows);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'getMyTimeline failed: ${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  /// Maps a [DioException] to a typed [Failure]. If `ErrorMapperInterceptor`
  /// already attached a [Failure] as `e.error`, that value is re-thrown
  /// directly; otherwise the Dio type is inspected. Identical policy to
  /// [HttpPassportRepository._mapDioException] (deliberately mirrored, per
  /// this phase's brief, rather than picking up `HttpFavoriteRepository`'s
  /// separately-scoped `badCertificate`/404 refinement).
  Failure _mapDioException(DioException e) {
    if (e.error is Failure) return e.error as Failure;
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return NetworkFailure(cause: e);
      case DioExceptionType.badResponse:
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return ServerFailure(statusCode: e.response?.statusCode, cause: e);
    }
  }
}

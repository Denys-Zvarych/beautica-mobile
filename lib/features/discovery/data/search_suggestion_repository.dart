// Phase 352 — SearchSuggestionRepository: interface + HTTP implementation.
//
// Wraps `GET /api/v1/search/suggestions` (backend Phase 331). Issues the GET
// directly through the shared authenticated [Dio] with a FLAT dot-notation
// query map — the SAME wire-format fix `search_repository.dart` applies to
// `/search/masters` / `/search/salons`: the generated
// `SearchSuggestionControllerApi.suggest` serialises its whole `request`
// object as a single object query param, which Dio bracket-nests
// (`request[0]=type&request[1]=CATEGORY&…`) rather than the flat
// `location.cityId=…` shape `@ModelAttribute SearchSuggestionRequest` binds.
// So this repository is hand-built against the raw Dio client, exactly like
// `HttpSearchRepository`, and reuses its exact `location.*` mapping via
// [addSearchLocationQuery] (Phase 352 D2 — "don't re-type it").
//
// The response envelope is still deserialized through the generated
// `standardSerializers`, so DTO parsing is unchanged; `standardSerializers`
// (not `beauticaSerializers`) suffices because `enumUnknownDefaultCase=true`
// already gives `SearchSuggestionResponseTypeEnum` an `unknownDefaultOpenApi`
// fallback member — an unrecognised `type` decodes to that member rather than
// throwing (`core/network/api_enum_names.dart`), and [_fromDto] reads it via
// [knownEnumName] and drops the row (never crashes, never logs the user out —
// `forbid_api_enum_fallback.sh`).
//
// All DioExceptions are mapped to typed [Failure] subclasses, mirroring
// `HttpSearchRepository._mapDioException`. No generated DTO type escapes this
// file — the UI never sees `SearchSuggestionResponse`.

import 'dart:developer';

import 'package:beautica_api/beautica_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/serializer.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/api_enum_names.dart';
import 'package:beautica_mobile/core/network/dio_provider.dart';

import '../domain/search_suggestion.dart';
import '../domain/search_suggestions.dart' show kSearchSuggestionMax;
import 'search_location_query.dart';

part 'search_suggestion_repository.g.dart';

/// Contract for the «Пошук» suggestion endpoint.
///
/// Resolves with an ordered (server-ranked) list of suggestions, or throws a
/// [Failure] subclass. Never returns more than [limit] rows; the backend's own
/// cap is 8, this app always sends 6 (Phase 352 D4).
abstract interface class SearchSuggestionRepository {
  /// [cancelToken], when passed, lets the caller cancel a superseded fetch
  /// (mobile-perf LOW cycle-1 fix — `search_suggestions_provider.dart`'s
  /// `_scheduleFetch`). A cancellation surfaces as a [DioException] with
  /// `CancelToken.isCancel(e)` true — NOT wrapped into a [Failure] — so the
  /// caller can drop it silently instead of treating it as a real error.
  Future<List<SearchSuggestion>> fetch({
    required String term,
    String? cityId,
    String? districtId,
    int limit = kSearchSuggestionMax,
    CancelToken? cancelToken,
  });
}

/// HTTP implementation of [SearchSuggestionRepository].
///
/// Inject via `searchSuggestionRepositoryProvider` — never construct
/// directly.
final class HttpSearchSuggestionRepository
    implements SearchSuggestionRepository {
  HttpSearchSuggestionRepository(this._dio, this._serializers);

  final Dio _dio;
  final Serializers _serializers;

  static const _tag = 'feature.discovery.suggestions';
  static const _path = '/api/v1/search/suggestions';

  @override
  Future<List<SearchSuggestion>> fetch({
    required String term,
    String? cityId,
    String? districtId,
    int limit = kSearchSuggestionMax,
    CancelToken? cancelToken,
  }) async {
    try {
      final Map<String, dynamic> q = <String, dynamic>{
        'q': term,
        'limit': limit,
      };
      addSearchLocationQuery(q, cityId: cityId, districtId: districtId);

      final Response<Object> res = await _dio.get<Object>(
        _path,
        queryParameters: q,
        cancelToken: cancelToken,
      );
      final ApiResponseListSearchSuggestionResponse? envelope =
          _deserialize<ApiResponseListSearchSuggestionResponse>(
            res.data,
            const FullType(ApiResponseListSearchSuggestionResponse),
            res,
          );
      final BuiltList<SearchSuggestionResponse>? data = envelope?.data;
      if (data == null) return const <SearchSuggestion>[];

      final List<SearchSuggestion> rows = <SearchSuggestion>[];
      for (final SearchSuggestionResponse dto in data) {
        final SearchSuggestion? mapped = _fromDto(dto);
        if (mapped != null) rows.add(mapped);
      }
      return rows;
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      // Supersede (mobile-perf LOW cycle-1 fix) — a cancellation is not a
      // real failure: rethrow the raw DioException so the provider can
      // recognise `CancelToken.isCancel(e)` and drop it silently, instead of
      // mapping it into a Failure the place-chosen fallback would treat as a
      // genuine error and clear the list for.
      if (CancelToken.isCancel(e)) rethrow;
      if (kDebugMode) {
        log(
          'suggestions fetch failed: ${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  /// Maps one [SearchSuggestionResponse] DTO to the domain [SearchSuggestion],
  /// or `null` for a malformed/unusable row (never thrown — one bad row must
  /// not fail the whole list).
  ///
  /// Dropped when: `label`/`categoryKey` absent or blank (nothing to show/
  /// apply); `type` is absent or the generated fallback (a future wire value
  /// this build predates — `knownEnumName` returns `null` for both, per
  /// `forbid_api_enum_fallback.sh`); SERVICE with no `serviceTypeSlug` (D5
  /// needs it to filter).
  static SearchSuggestion? _fromDto(SearchSuggestionResponse dto) {
    final String? label = dto.label;
    final String? categoryKey = dto.categoryKey;
    if (label == null || label.isEmpty) return null;
    if (categoryKey == null || categoryKey.isEmpty) return null;

    switch (knownEnumName(dto.type)) {
      case 'CATEGORY':
        return SearchSuggestion(
          type: SearchSuggestionType.category,
          label: label,
          categoryKey: categoryKey,
        );
      case 'SERVICE':
        final String? slug = dto.serviceTypeSlug;
        if (slug == null || slug.isEmpty) return null;
        return SearchSuggestion(
          type: SearchSuggestionType.service,
          label: label,
          categoryKey: categoryKey,
          serviceTypeSlug: slug,
        );
      default:
        return null;
    }
  }

  /// Deserializes a Dio response body into the generated envelope [T] using
  /// the same `standardSerializers` the generated client uses. Mirrors
  /// `HttpSearchRepository._deserialize`.
  T? _deserialize<T>(Object? raw, FullType type, Response<Object> res) {
    if (raw == null) return null;
    try {
      return _serializers.deserialize(raw, specifiedType: type) as T;
    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: res.requestOptions,
        response: res,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Maps a [DioException] to a typed [Failure]. Mirrors
  /// `HttpSearchRepository._mapDioException`.
  Failure _mapDioException(DioException e) {
    if (e.error is Failure) return e.error as Failure;
    final int? statusCode = e.response?.statusCode;
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return NetworkFailure(cause: e);
      case DioExceptionType.badResponse:
        if (statusCode == 400 || statusCode == 422) {
          return ValidationFailure(fieldErrors: const {}, cause: e);
        }
        if (statusCode == 404) return NotFoundFailure(cause: e);
        return ServerFailure(statusCode: statusCode, cause: e);
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return ServerFailure(statusCode: statusCode, cause: e);
    }
  }
}

/// Provides the [SearchSuggestionRepository] singleton.
///
/// Built from the shared authenticated [dioProvider] (so the interceptor
/// chain — auth, logging, error-mapping, refresh — applies, mirroring
/// `searchRepositoryProvider`) and the generated `standardSerializers`. Kept
/// alive so the suggestions provider shares one repository instance across the
/// session. `/search/suggestions` is public/unauthenticated on the backend, so
/// there is no readiness guard here.
@Riverpod(keepAlive: true)
SearchSuggestionRepository searchSuggestionRepository(Ref ref) =>
    HttpSearchSuggestionRepository(ref.watch(dioProvider), standardSerializers);

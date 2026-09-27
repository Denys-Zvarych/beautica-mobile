// TODO(phase-3.2): replace hand-written DTOs with generated LocationApi.
//
// Phase 2.18 — LocationRepository (hand-written Dio).
//
// The OpenAPI codegen for `lib/api/` is deferred to Phase 3.1/3.2, so there is
// no generated `LocationApi` yet. This repository talks to the backend's
// public `/locations/*` read endpoints directly through the singleton
// [dioProvider] Dio — mirroring [HttpAuthRepository]'s envelope handling.
//
// The `/locations/*` endpoints are PUBLIC reads (no auth required), but we
// reuse [dioProvider] anyway for the shared base URL and the
// ErrorMapper interceptor that converts DioException → typed [Failure]. The
// AuthInterceptor harmlessly skips attaching a token when none is stored.
//
// Backend response envelope for all endpoints:
//   { "success": bool, "data": T, "message": String }
// This class extracts the payload from `response.data['data']`, then maps each
// element through the domain `fromResponse` mapper at the repository boundary.
//
// Live backend contract (verified):
//   GET /locations/oblasts                       -> List<OblastResponse>
//   GET /locations/oblasts/{oblastId}/cities     -> List<CityResponse>   (UUID)
//   GET /locations/cities/{cityId}/districts     -> List<CityDistrictResponse> (UUID)

import 'dart:developer';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/dio_provider.dart';
import 'package:beautica_mobile/core/network/path_segment.dart';
import 'package:beautica_mobile/features/discovery/domain/search_filters.dart'
    show kSearchMinQueryLength;
import 'package:beautica_mobile/shared/util/bounded_query.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/city.dart';
import '../domain/city_district.dart';
import '../domain/oblast.dart';
import '../domain/settlement.dart';

part 'location_repository.g.dart';

/// Contract for the locality reference-data layer.
///
/// Every method either resolves with the requested list or throws a [Failure]
/// subclass from `core/errors/failures.dart`. Raw [DioException]s are caught
/// inside the implementation and never escape.
abstract interface class LocationRepository {
  /// Fetches all Ukrainian oblasts (first cascade level).
  Future<List<Oblast>> fetchOblasts();

  /// Fetches the cities of the oblast identified by [oblastId] (a UUID).
  Future<List<City>> fetchCities(String oblastId);

  /// Fetches the urban districts of the city identified by [cityId] (a UUID).
  ///
  /// Only called when `City.hasDistricts == true`; for cities without
  /// districts the cascade shows a disabled helper row and never reaches here.
  Future<List<CityDistrict>> fetchDistricts(String cityId);

  /// Phase 346 — ranked settlement matches for one autocomplete keystroke.
  ///
  /// Backs the single «Населений пункт» field that REPLACES the three-level
  /// cascade above. Unlike the other three reads this endpoint is
  /// parameterised by caller input, so it is the one locality read the backend
  /// rate-limits per IP.
  ///
  /// Contract (`GET /api/v1/settlements?query=…`, phase-326):
  ///   - [query] blank -> the ~50 `is_major` settlements, so the sheet is never
  ///     empty before the user types (phase-346 D6);
  ///   - [query] without a 3-character alphanumeric RUN -> HTTP 200 with an
  ///     EMPTY list and a hint message. The caller must not issue this: see
  ///     [settlementQueryIsSearchable], which mirrors the server predicate so
  ///     a 1-2 character keystroke costs no request at all;
  ///   - otherwise -> at most 20 matches, prefix-first then by similarity.
  ///
  /// A [query] longer than 50 characters is a hard 400 on the server and is
  /// truncated here rather than sent, because an autocomplete would otherwise
  /// re-issue the identical doomed request on every subsequent keystroke. The
  /// cut is [boundSearchQuery] — rune-safe, and the SAME function the search
  /// sheet applies before it commits a family key, so the key and the wire
  /// text are identical.
  ///
  /// [cancelToken] aborts the GET when the caller no longer wants the answer
  /// (`settlementSearchProvider` cancels it from `ref.onDispose`, i.e. when a
  /// newer query supersedes this one). The resulting cancellation error lands
  /// on a disposed provider, which Riverpod drops — it never reaches the UI.
  Future<List<Settlement>> searchSettlements(
    String query, {
    CancelToken? cancelToken,
  });
}

/// Longest `query` the settlements endpoint accepts.
///
/// Mirrors `SettlementSearchController.MAX_QUERY_LENGTH` — a longer term is a
/// 400, not a wider search.
const int kSettlementQueryMaxLength = 50;

/// Whether [query] is a term the settlements index can actually serve.
///
/// Mirrors the server's `NormalizedSearchQuery.hasIndexServableRun` verbatim:
/// the term must contain an UNINTERRUPTED alphanumeric run of at least
/// [kSearchMinQueryLength] characters. A whole-term length floor is NOT the
/// same predicate and is not sufficient — «•»x50 satisfies a length floor, is
/// tokenised by `pg_trgm` into the empty key set, and degrades into a
/// sequential scan of 25 698 rows on an unauthenticated endpoint. Repeating a
/// sub-trigram fragment («•к»x25) adds no distinct key either, which is why the
/// RUN is the only form padding cannot defeat.
///
/// A BLANK term is searchable in the sense that matters here — it is the
/// pre-typing major-settlement list, not a below-minimum error — so it returns
/// `true` and the caller sends no `query` parameter at all.
bool settlementQueryIsSearchable(String query) {
  final String trimmed = query.trim();
  if (trimmed.isEmpty) return true;
  return _alphanumericRun.hasMatch(trimmed);
}

/// An uninterrupted run of [kSearchMinQueryLength] Unicode letters/digits.
///
/// ONE regex pass over the term (perf N5) instead of a `String` allocation and
/// a regex match per rune. Exactly the old per-rune loop's predicate: in
/// `unicode: true` mode a character class matches whole code points (a
/// surrogate pair is one character), and `{n}` of the class is precisely "n
/// consecutive letter/digit code points". A per-rune RANGE check is NOT
/// equivalent — `\p{L}` / `\p{N}` span hundreds of ranges — so the Unicode
/// property classes stay.
final RegExp _alphanumericRun = RegExp(
  '[\\p{L}\\p{N}]{$kSearchMinQueryLength}',
  unicode: true,
);

/// HTTP implementation of [LocationRepository].
///
/// Inject via [locationRepositoryProvider] — never construct directly.
final class HttpLocationRepository implements LocationRepository {
  HttpLocationRepository(this._dio);

  final Dio _dio;

  @override
  Future<List<Oblast>> fetchOblasts() => _fetchList(
    path: '/api/v1/locations/oblasts',
    mapper: Oblast.fromResponse,
    operation: 'fetchOblasts',
  );

  /// Hardened via [encodePathSegment] (mobile-security LOW, 2026-09-17 — found
  /// by `scripts/forbid_unencoded_path_interpolation.sh`, NOT by the audit that
  /// prompted it; the audit named only the four bare-[Uri.encodeComponent]
  /// sites, and these two had no encoding at all).
  ///
  /// [oblastId] / [cityId] reach here from route and profile state, are
  /// interpolated into a hand-built path, and are issued on the shared
  /// [dioProvider] Dio — so a dot-segment would survive into Dio's
  /// `Uri.parse(url).normalizePath()` and retarget the read. These endpoints
  /// are public, but the Dio is the same instance that carries the bearer
  /// token on every other call, and `/locations/oblasts/../..` collapsing onto
  /// a different `/api/v1/` resource is the same shape regardless.
  ///
  /// BEHAVIOUR NOTE: an EMPTY id now throws [UnknownFailure] here instead of
  /// issuing `/api/v1/locations/oblasts//cities` and surfacing whatever the
  /// backend returned for it. Both are error states the cascade already
  /// renders through its `error:` branch; every caller passes a server-issued
  /// UUID (`oblast.id` / `city.id`, or a persisted profile field), so this is
  /// unreachable in practice. Encoding a well-formed UUID is a no-op.
  @override
  Future<List<City>> fetchCities(String oblastId) => _fetchList(
    path:
        '/api/v1/locations/oblasts/'
        '${encodePathSegment(oblastId, 'oblastId', logTag: 'location.repository')}'
        '/cities',
    mapper: City.fromResponse,
    operation: 'fetchCities',
  );

  /// See [fetchCities] for why [cityId] is encoded and what an empty id does.
  @override
  Future<List<CityDistrict>> fetchDistricts(String cityId) => _fetchList(
    path:
        '/api/v1/locations/cities/'
        '${encodePathSegment(cityId, 'cityId', logTag: 'location.repository')}'
        '/districts',
    mapper: CityDistrict.fromResponse,
    operation: 'fetchDistricts',
  );

  /// See [LocationRepository.searchSettlements].
  ///
  /// The term travels as a Dio QUERY PARAMETER, never interpolated into the
  /// path — so `encodePathSegment` (which guards the two id-bearing paths
  /// above) has nothing to do here: Dio percent-encodes the value, a dot
  /// segment in a query string cannot retarget the read, and the server
  /// additionally rejects the Cc/Cf/Zl/Zp classes.
  @override
  Future<List<Settlement>> searchSettlements(
    String query, {
    CancelToken? cancelToken,
  }) {
    final String bounded = boundSearchQuery(query, kSettlementQueryMaxLength);
    return _fetchList(
      path: '/api/v1/settlements',
      // Blank means "the major list" to the server, and omitting the parameter
      // entirely says that more plainly than `query=`.
      queryParameters: bounded.isEmpty
          ? null
          : <String, dynamic>{'query': bounded},
      mapper: Settlement.fromResponse,
      operation: 'searchSettlements',
      cancelToken: cancelToken,
    );
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Shared GET → envelope-unwrap → list-map pipeline for all three endpoints.
  ///
  /// [mapper] converts a single raw element map to its domain model. Any
  /// [DioException] is mapped to a typed [Failure]; a malformed envelope
  /// (missing or non-list `data`) surfaces as [UnknownFailure].
  Future<List<T>> _fetchList<T>({
    required String path,
    required T Function(Map<String, dynamic>) mapper,
    required String operation,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        path,
        queryParameters: queryParameters,
        cancelToken: cancelToken,
      );
      final data = response.data?['data'];
      if (data is! List) {
        throw const UnknownFailure(
          cause: 'locations response missing a "data" list',
        );
      }
      return data
          .cast<Map<String, dynamic>>()
          .map(mapper)
          .toList(growable: false);
    } on DioException catch (e, st) {
      // A deliberate cancellation (a superseded autocomplete query) is not a
      // failure worth a WARNING-level log line per keystroke.
      if (kDebugMode && e.type != DioExceptionType.cancel) {
        log(
          '$operation failed: ${e.type} ${e.response?.statusCode}',
          name: 'location.repository',
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  /// Maps a [DioException] to a typed [Failure].
  ///
  /// If [ErrorMapperInterceptor] has already attached a [Failure] as
  /// `e.error`, that value is re-thrown directly; otherwise the Dio type is
  /// inspected so connectivity issues surface as [NetworkFailure] and
  /// everything else as [ServerFailure]. Raw [DioException] never escapes.
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

/// Provides the [LocationRepository] singleton used by the locality providers.
///
/// Returns [HttpLocationRepository] backed by the authenticated [dioProvider].
/// Override in tests with a mocktail mock — never construct
/// [HttpLocationRepository] directly in tests.
@Riverpod(keepAlive: true)
LocationRepository locationRepository(Ref ref) =>
    HttpLocationRepository(ref.watch(dioProvider));

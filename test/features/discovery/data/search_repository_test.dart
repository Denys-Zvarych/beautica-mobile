// Phase 13.2 — Unit tests for [HttpSearchRepository] + the search mappers.
//
// Strategy:
//   All tests mock [SearchControllerApi] with mocktail and construct
//   [HttpSearchRepository] directly (no Riverpod overhead — pure Dart units).
//
// Coverage (first cut — mobile-qa will harden/extend):
//   1. searchMasters — success mapping (id/name/rating/price/location)
//   2. searchSalons  — success mapping (id/name/price band; avgRating null)
//   3. searchMasters — empty page
//   4. searchMasters — 400 → ValidationFailure
//   5. searchMasters — connection error → NetworkFailure
//   6. searchMasters — null masterId → ServerFailure (mapper guard)
//   7. mapper        — salon priceMin == priceMax (single value)
//   8. mapper        — salon priceMin/priceMax both null (no price)
//   9. mapper        — master missing avgRating defaults to 0.0

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/discovery/data/search_mapper.dart';
import 'package:beautica_mobile/features/discovery/data/search_repository.dart';
import 'package:beautica_mobile/features/discovery/domain/search_filters.dart';
import 'package:built_collection/built_collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// ── Mocks ──────────────────────────────────────────────────────────────────

class _MockSearchControllerApi extends Mock implements SearchControllerApi {}

// ── Helpers ─────────────────────────────────────────────────────────────────

const _masterPath = '/api/v1/search/masters';
const _salonPath = '/api/v1/search/salons';

MasterSearchResult _buildMasterDto({
  String? masterId = 'master-1',
  String? firstName = 'Олена',
  String? lastName = 'Коваль',
  String? avatarUrl = 'https://cdn/a.png',
  double? avgRating = 4.8,
  int? reviewCount = 12,
  String? cityLabel = 'Київ',
  String? districtLabel = 'Печерський',
  num? minEffectivePrice = 350,
}) =>
    (MasterSearchResultBuilder()
          ..masterId = masterId
          ..firstName = firstName
          ..lastName = lastName
          ..avatarUrl = avatarUrl
          ..avgRating = avgRating
          ..reviewCount = reviewCount
          ..cityLabel = cityLabel
          ..districtLabel = districtLabel
          ..minEffectivePrice = minEffectivePrice)
        .build();

SalonSearchResult _buildSalonDto({
  String? salonId = 'salon-1',
  String? name = 'Beauty Bar',
  String? avatarUrl = 'https://cdn/s.png',
  String? cityLabel = 'Львів',
  String? districtLabel = 'Галицький',
  num? priceMin = 400,
  num? priceMax = 900,
}) =>
    (SalonSearchResultBuilder()
          ..salonId = salonId
          ..name = name
          ..avatarUrl = avatarUrl
          ..cityLabel = cityLabel
          ..districtLabel = districtLabel
          ..priceMin = priceMin
          ..priceMax = priceMax)
        .build();

Response<ApiResponsePageResponseMasterSearchResult> _masterResponse(
  List<MasterSearchResult> items, {
  int page = 0,
  int totalPages = 1,
  int? totalElements,
}) {
  final body = ApiResponsePageResponseMasterSearchResult(
    (b) => b
      ..success = true
      ..data.replace(
        PageResponseMasterSearchResult(
          (p) => p
            ..success = true
            ..data = ListBuilder<MasterSearchResult>(items)
            ..page = page
            ..size = items.length
            ..totalPages = totalPages
            ..totalElements = totalElements ?? items.length,
        ),
      ),
  );
  return Response<ApiResponsePageResponseMasterSearchResult>(
    data: body,
    requestOptions: RequestOptions(path: _masterPath),
    statusCode: 200,
  );
}

Response<ApiResponsePageResponseSalonSearchResult> _salonResponse(
  List<SalonSearchResult> items, {
  int page = 0,
  int totalPages = 1,
}) {
  final body = ApiResponsePageResponseSalonSearchResult(
    (b) => b
      ..success = true
      ..data.replace(
        PageResponseSalonSearchResult(
          (p) => p
            ..success = true
            ..data = ListBuilder<SalonSearchResult>(items)
            ..page = page
            ..size = items.length
            ..totalPages = totalPages
            ..totalElements = items.length,
        ),
      ),
  );
  return Response<ApiResponsePageResponseSalonSearchResult>(
    data: body,
    requestOptions: RequestOptions(path: _salonPath),
    statusCode: 200,
  );
}

DioException _dioBadResponse(int statusCode, String path) => DioException(
  requestOptions: RequestOptions(path: path),
  response: Response<Object?>(
    requestOptions: RequestOptions(path: path),
    statusCode: statusCode,
  ),
  type: DioExceptionType.badResponse,
);

// ── Test suite ───────────────────────────────────────────────────────────────

void main() {
  late _MockSearchControllerApi api;
  late HttpSearchRepository repository;

  const filters = SearchFilters();

  setUp(() {
    api = _MockSearchControllerApi();
    repository = HttpSearchRepository(api);
    registerFallbackValue(MasterSearchRequest((b) => b..page = 0));
    registerFallbackValue(SalonSearchRequest((b) => b..page = 0));
  });

  // ── 1. searchMasters — success mapping ──────────────────────────────────────

  group('searchMasters', () {
    test('maps a populated page to domain MasterSearchItems', () async {
      when(
        () => api.searchMasters(request: any(named: 'request')),
      ).thenAnswer((_) async => _masterResponse([_buildMasterDto()]));

      final page = await repository.searchMasters(filters: filters, page: 0);

      expect(page.items, hasLength(1));
      final item = page.items.single;
      expect(item.masterId, 'master-1');
      expect(item.firstName, 'Олена');
      expect(item.lastName, 'Коваль');
      expect(item.avatarUrl, 'https://cdn/a.png');
      expect(item.avgRating, 4.8);
      expect(item.reviewCount, 12);
      expect(item.cityLabel, 'Київ');
      expect(item.districtLabel, 'Печерський');
      expect(item.minEffectivePrice, 350.0);
      expect(page.page, 0);
      expect(page.totalPages, 1);
      expect(page.totalElements, 1);
    });

    // ── 3. searchMasters — empty page ─────────────────────────────────────────

    test('returns an empty page when the backend matches nothing', () async {
      when(
        () => api.searchMasters(request: any(named: 'request')),
      ).thenAnswer((_) async => _masterResponse([], totalPages: 0));

      final page = await repository.searchMasters(filters: filters, page: 0);

      expect(page.items, isEmpty);
      expect(page.totalPages, 0);
      expect(page.hasMore, isFalse);
    });

    // ── 4. searchMasters — 400 → ValidationFailure ────────────────────────────

    test('maps a 400 response to ValidationFailure', () async {
      when(
        () => api.searchMasters(request: any(named: 'request')),
      ).thenThrow(_dioBadResponse(400, _masterPath));

      expect(
        () => repository.searchMasters(filters: filters, page: 0),
        throwsA(isA<ValidationFailure>()),
      );
    });

    // ── 5. searchMasters — connection error → NetworkFailure ──────────────────

    test('maps a connection error to NetworkFailure', () async {
      when(() => api.searchMasters(request: any(named: 'request'))).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: _masterPath),
          type: DioExceptionType.connectionError,
        ),
      );

      expect(
        () => repository.searchMasters(filters: filters, page: 0),
        throwsA(isA<NetworkFailure>()),
      );
    });

    // ── 6. searchMasters — null masterId → ServerFailure ──────────────────────

    test('maps a null masterId to ServerFailure (mapper guard)', () async {
      when(() => api.searchMasters(request: any(named: 'request'))).thenAnswer(
        (_) async => _masterResponse([_buildMasterDto(masterId: null)]),
      );

      expect(
        () => repository.searchMasters(filters: filters, page: 0),
        throwsA(isA<ServerFailure>()),
      );
    });

    test(
      'empty page carries totalElements == 0 (no items, no match)',
      () async {
        when(
          () => api.searchMasters(request: any(named: 'request')),
        ).thenAnswer((_) async => _masterResponse([], page: 0, totalPages: 0));

        final page = await repository.searchMasters(filters: filters, page: 0);

        expect(page.items, isEmpty);
        expect(page.totalElements, 0);
        expect(page.totalPages, 0);
        expect(page.page, 0);
        expect(page.hasMore, isFalse);
      },
    );

    test('maps a 422 response to ValidationFailure', () async {
      when(
        () => api.searchMasters(request: any(named: 'request')),
      ).thenThrow(_dioBadResponse(422, _masterPath));

      expect(
        () => repository.searchMasters(filters: filters, page: 0),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('maps a receive timeout to NetworkFailure', () async {
      when(() => api.searchMasters(request: any(named: 'request'))).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: _masterPath),
          type: DioExceptionType.receiveTimeout,
        ),
      );

      expect(
        () => repository.searchMasters(filters: filters, page: 0),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test(
      'minEffectivePrice is delivered as a double (not the raw num)',
      () async {
        when(
          () => api.searchMasters(request: any(named: 'request')),
        ).thenAnswer(
          (_) async =>
              _masterResponse([_buildMasterDto(minEffectivePrice: 350)]),
        );

        final page = await repository.searchMasters(filters: filters, page: 0);

        final price = page.items.single.minEffectivePrice;
        expect(price, isA<double>());
        expect(price, 350.0);
      },
    );
  });

  // ── Request translation — the `query` is NEVER serialized (decision 7) ───────
  //
  // The discovery search endpoints expose NO free-text param in v1. The repo
  // must drop [SearchFilters.query] entirely while still forwarding the real
  // filters (category / location / price / rating). These tests capture the
  // request DTO actually handed to [SearchControllerApi] and assert that the
  // structured filters are present — and that there is nowhere for the inert
  // query to leak (the generated request DTO has no `query` field at all).

  group('request translation (query never sent)', () {
    const richFilters = SearchFilters(
      query: 'free text that must never reach the wire',
      categoryKey: 'HAIR',
      cityId: 'city-7',
      districtId: 'district-3',
      minPrice: 200,
      maxPrice: 800,
      minRating: 4.0,
    );

    test('searchMasters forwards structured filters; the request DTO exposes '
        'no query field for the inert free-text to leak into', () async {
      when(
        () => api.searchMasters(request: any(named: 'request')),
      ).thenAnswer((_) async => _masterResponse([_buildMasterDto()]));

      await repository.searchMasters(filters: richFilters, page: 2);

      final captured =
          verify(
                () => api.searchMasters(request: captureAny(named: 'request')),
              ).captured.single
              as MasterSearchRequest;

      // Structured filters ARE forwarded.
      expect(captured.category, 'HAIR');
      expect(captured.location?.cityId, 'city-7');
      expect(captured.location?.districtId, 'district-3');
      expect(captured.minPrice, 200);
      expect(captured.maxPrice, 800);
      expect(captured.minRating, 4.0);
      expect(captured.page, 2);
      expect(captured.size, kSearchPageSize);

      // The inert free-text query has no carrier on the request DTO. This is the
      // structural lock for decision 7: even a populated SearchFilters.query
      // cannot be serialized because MasterSearchRequest has no such property.
      // (Verified against api/lib/src/model/master_search_request.dart:
      //  location/category/minPrice/maxPrice/minRating/page/size only.)
      expect(
        captured.toString().toLowerCase(),
        isNot(contains('free text that must never reach the wire')),
        reason: 'the inert SearchFilters.query must never appear on the wire',
      );
    });

    test(
      'searchSalons forwards category + location only; price/rating and the '
      'inert query are dropped (salon request is location+category+paging)',
      () async {
        when(
          () => api.searchSalons(request: any(named: 'request')),
        ).thenAnswer((_) async => _salonResponse([_buildSalonDto()]));

        await repository.searchSalons(filters: richFilters, page: 1);

        final captured =
            verify(
                  () => api.searchSalons(request: captureAny(named: 'request')),
                ).captured.single
                as SalonSearchRequest;

        expect(captured.category, 'HAIR');
        expect(captured.location?.cityId, 'city-7');
        expect(captured.location?.districtId, 'district-3');
        expect(captured.page, 1);
        expect(captured.size, kSearchPageSize);

        // SalonSearchRequest carries no price/rating/query fields — structurally
        // these cannot be forwarded. The free-text query likewise cannot leak.
        expect(
          captured.toString().toLowerCase(),
          isNot(contains('free text that must never reach the wire')),
          reason: 'the inert SearchFilters.query must never appear on the wire',
        );
      },
    );

    test('empty filters produce a request with paging only (no location, no '
        'category) — query stays unset', () async {
      when(
        () => api.searchMasters(request: any(named: 'request')),
      ).thenAnswer((_) async => _masterResponse([]));

      await repository.searchMasters(filters: const SearchFilters(), page: 0);

      final captured =
          verify(
                () => api.searchMasters(request: captureAny(named: 'request')),
              ).captured.single
              as MasterSearchRequest;

      expect(captured.location, isNull);
      expect(captured.category, isNull);
      expect(captured.minPrice, isNull);
      expect(captured.maxPrice, isNull);
      expect(captured.minRating, isNull);
      expect(captured.page, 0);
      expect(captured.size, kSearchPageSize);
    });
  });

  // ── 2. searchSalons — success mapping ───────────────────────────────────────

  group('searchSalons', () {
    test('maps a populated page; avgRating is null (DTO omits it)', () async {
      when(
        () => api.searchSalons(request: any(named: 'request')),
      ).thenAnswer((_) async => _salonResponse([_buildSalonDto()]));

      final page = await repository.searchSalons(filters: filters, page: 0);

      expect(page.items, hasLength(1));
      final item = page.items.single;
      expect(item.salonId, 'salon-1');
      expect(item.name, 'Beauty Bar');
      expect(item.avatarUrl, 'https://cdn/s.png');
      expect(item.avgRating, isNull);
      expect(item.cityLabel, 'Львів');
      expect(item.priceMin, 400.0);
      expect(item.priceMax, 900.0);
    });

    test('maps a null salonId to ServerFailure (mapper guard)', () async {
      when(() => api.searchSalons(request: any(named: 'request'))).thenAnswer(
        (_) async => _salonResponse([_buildSalonDto(salonId: null)]),
      );

      expect(
        () => repository.searchSalons(filters: filters, page: 0),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('returns an empty page when the backend matches nothing', () async {
      when(
        () => api.searchSalons(request: any(named: 'request')),
      ).thenAnswer((_) async => _salonResponse([], totalPages: 0));

      final page = await repository.searchSalons(filters: filters, page: 0);

      expect(page.items, isEmpty);
      expect(page.totalElements, 0);
      expect(page.hasMore, isFalse);
    });

    test('maps a 400 response to ValidationFailure', () async {
      when(
        () => api.searchSalons(request: any(named: 'request')),
      ).thenThrow(_dioBadResponse(400, _salonPath));

      expect(
        () => repository.searchSalons(filters: filters, page: 0),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('maps a connection error to NetworkFailure', () async {
      when(() => api.searchSalons(request: any(named: 'request'))).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: _salonPath),
          type: DioExceptionType.connectionError,
        ),
      );

      expect(
        () => repository.searchSalons(filters: filters, page: 0),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('priceMin/priceMax are delivered as doubles (not raw num)', () async {
      when(
        () => api.searchSalons(request: any(named: 'request')),
      ).thenAnswer((_) async => _salonResponse([_buildSalonDto()]));

      final page = await repository.searchSalons(filters: filters, page: 0);

      final item = page.items.single;
      expect(item.priceMin, isA<double>());
      expect(item.priceMax, isA<double>());
      expect(item.priceMin, 400.0);
      expect(item.priceMax, 900.0);
    });
  });

  // ── Mapper-level edge cases ──────────────────────────────────────────────────

  group('SalonSearchMapper', () {
    // ── 7. priceMin == priceMax ───────────────────────────────────────────────

    test('carries equal priceMin/priceMax through unchanged', () {
      final item = SalonSearchMapper.fromDto(
        _buildSalonDto(priceMin: 500, priceMax: 500),
      );
      expect(item.priceMin, 500.0);
      expect(item.priceMax, 500.0);
    });

    // ── 8. both prices null ───────────────────────────────────────────────────

    test('carries both-null prices as null (no price)', () {
      final item = SalonSearchMapper.fromDto(
        _buildSalonDto(priceMin: null, priceMax: null),
      );
      expect(item.priceMin, isNull);
      expect(item.priceMax, isNull);
    });
  });

  group('MasterSearchMapper', () {
    // ── 9. missing avgRating defaults to 0.0 ──────────────────────────────────

    test('defaults a missing avgRating to 0.0', () {
      final item = MasterSearchMapper.fromDto(_buildMasterDto(avgRating: null));
      expect(item.avgRating, 0.0);
    });

    test('converts a null minEffectivePrice to null (no "від" anchor)', () {
      final item = MasterSearchMapper.fromDto(
        _buildMasterDto(minEffectivePrice: null),
      );
      expect(item.minEffectivePrice, isNull);
    });
  });
}

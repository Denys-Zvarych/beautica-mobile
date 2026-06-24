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
import 'package:beautica_mobile/features/discovery/presentation/widgets/result_card_text.dart'
    show kServiceNamesSeparator;
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
  List<String>? serviceNames = const ['Манікюр', 'Педикюр'],
}) {
  final b = MasterSearchResultBuilder()
    ..masterId = masterId
    ..firstName = firstName
    ..lastName = lastName
    ..avatarUrl = avatarUrl
    ..avgRating = avgRating
    ..reviewCount = reviewCount
    ..cityLabel = cityLabel
    ..districtLabel = districtLabel
    ..minEffectivePrice = minEffectivePrice;
  if (serviceNames != null) {
    b.serviceNames = ListBuilder<String>(serviceNames);
  }
  return b.build();
}

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
      expect(item.serviceNames, <String>['Манікюр', 'Педикюр']);
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

  // ── Request translation — q / sort / location / price ARE forwarded ──────────
  //
  // The search contract now exposes a free-text `q`, an allow-listed `sort`, and
  // (salon side) a `minPrice`/`maxPrice` band. These tests capture the request
  // DTO handed to [SearchControllerApi] and assert each new param reaches the
  // wire with the right value, and that the `q` normalisation (trim / empty →
  // null) is applied.

  group('request translation', () {
    const richFilters = SearchFilters(
      query: 'Манікюр',
      categoryKey: 'HAIR',
      cityId: 'city-7',
      districtId: 'district-3',
      minPrice: 200,
      maxPrice: 800,
      minRating: 4.0,
      sort: SearchSort.priceAsc,
    );

    test(
      'searchMasters forwards q, sort, location, category, price, rating',
      () async {
        when(
          () => api.searchMasters(request: any(named: 'request')),
        ).thenAnswer((_) async => _masterResponse([_buildMasterDto()]));

        await repository.searchMasters(filters: richFilters, page: 2);

        final captured =
            verify(
                  () =>
                      api.searchMasters(request: captureAny(named: 'request')),
                ).captured.single
                as MasterSearchRequest;

        expect(captured.q, 'Манікюр');
        expect(captured.sort, MasterSearchRequestSortEnum.PRICE_ASC);
        expect(captured.category, 'HAIR');
        expect(captured.location?.cityId, 'city-7');
        expect(captured.location?.districtId, 'district-3');
        expect(captured.minPrice, 200);
        expect(captured.maxPrice, 800);
        expect(captured.minRating, 4.0);
        expect(captured.page, 2);
        expect(captured.size, kSearchPageSize);
      },
    );

    test(
      'searchSalons forwards q, sort, location, category, AND the price band',
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

        expect(captured.q, 'Манікюр');
        expect(captured.sort, SalonSearchRequestSortEnum.PRICE_ASC);
        expect(captured.category, 'HAIR');
        expect(captured.location?.cityId, 'city-7');
        expect(captured.location?.districtId, 'district-3');
        // Item 3: salon price band is now forwarded (previously dropped).
        expect(captured.minPrice, 200);
        expect(captured.maxPrice, 800);
        expect(captured.page, 1);
        expect(captured.size, kSearchPageSize);
      },
    );

    test(
      'a blank/whitespace query is normalised to null (q omitted)',
      () async {
        when(
          () => api.searchMasters(request: any(named: 'request')),
        ).thenAnswer((_) async => _masterResponse([]));

        await repository.searchMasters(
          filters: const SearchFilters(query: '   '),
          page: 0,
        );

        final captured =
            verify(
                  () =>
                      api.searchMasters(request: captureAny(named: 'request')),
                ).captured.single
                as MasterSearchRequest;

        expect(captured.q, isNull);
      },
    );

    test(
      'a query with surrounding whitespace is trimmed before sending',
      () async {
        when(
          () => api.searchSalons(request: any(named: 'request')),
        ).thenAnswer((_) async => _salonResponse([]));

        await repository.searchSalons(
          filters: const SearchFilters(query: '  педикюр  '),
          page: 0,
        );

        final captured =
            verify(
                  () => api.searchSalons(request: captureAny(named: 'request')),
                ).captured.single
                as SalonSearchRequest;

        expect(captured.q, 'педикюр');
      },
    );

    // Every SearchSort enum constant must serialize to its exact backend wire
    // string on BOTH endpoints. The repository routes the value through
    // `…SortEnum.valueOf(f.sort.wireValue)`; a drift in wireValue (or a missing
    // enum constant) would surface a wrong `?sort=` and silently mis-order the
    // results. RATING_DESC + PRICE_ASC are exercised elsewhere; this table makes
    // PRICE_DESC and REVIEWS_DESC non-permissive too.
    const Map<
      SearchSort,
      (MasterSearchRequestSortEnum, SalonSearchRequestSortEnum)
    >
    sortWireMap =
        <SearchSort, (MasterSearchRequestSortEnum, SalonSearchRequestSortEnum)>{
          SearchSort.ratingDesc: (
            MasterSearchRequestSortEnum.RATING_DESC,
            SalonSearchRequestSortEnum.RATING_DESC,
          ),
          SearchSort.priceAsc: (
            MasterSearchRequestSortEnum.PRICE_ASC,
            SalonSearchRequestSortEnum.PRICE_ASC,
          ),
          SearchSort.priceDesc: (
            MasterSearchRequestSortEnum.PRICE_DESC,
            SalonSearchRequestSortEnum.PRICE_DESC,
          ),
          SearchSort.reviewsDesc: (
            MasterSearchRequestSortEnum.REVIEWS_DESC,
            SalonSearchRequestSortEnum.REVIEWS_DESC,
          ),
        };

    for (final MapEntry<
          SearchSort,
          (MasterSearchRequestSortEnum, SalonSearchRequestSortEnum)
        >
        entry
        in sortWireMap.entries) {
      final SearchSort sort = entry.key;
      final MasterSearchRequestSortEnum masterWire = entry.value.$1;
      final SalonSearchRequestSortEnum salonWire = entry.value.$2;

      test(
        'sort=${sort.name} maps to ${masterWire.name} on BOTH endpoints',
        () async {
          when(
            () => api.searchMasters(request: any(named: 'request')),
          ).thenAnswer((_) async => _masterResponse([]));
          when(
            () => api.searchSalons(request: any(named: 'request')),
          ).thenAnswer((_) async => _salonResponse([]));

          final filtersForSort = SearchFilters(sort: sort);
          await repository.searchMasters(filters: filtersForSort, page: 0);
          await repository.searchSalons(filters: filtersForSort, page: 0);

          final master =
              verify(
                    () => api.searchMasters(
                      request: captureAny(named: 'request'),
                    ),
                  ).captured.single
                  as MasterSearchRequest;
          final salon =
              verify(
                    () =>
                        api.searchSalons(request: captureAny(named: 'request')),
                  ).captured.single
                  as SalonSearchRequest;

          expect(master.sort, masterWire);
          expect(salon.sort, salonWire);
          // The enum's wireValue is the literal `?sort=` token — assert it too so a
          // rename on the Dart side can't drift silently from the backend constant.
          expect(sort.wireValue, masterWire.name);
          expect(sort.wireValue, salonWire.name);
        },
      );
    }

    test('master endpoint forwards the minPrice/maxPrice band', () async {
      when(
        () => api.searchMasters(request: any(named: 'request')),
      ).thenAnswer((_) async => _masterResponse([]));

      await repository.searchMasters(
        filters: const SearchFilters(minPrice: 150, maxPrice: 650),
        page: 0,
      );

      final captured =
          verify(
                () => api.searchMasters(request: captureAny(named: 'request')),
              ).captured.single
              as MasterSearchRequest;

      expect(captured.minPrice, 150);
      expect(captured.maxPrice, 650);
    });

    test(
      'a district-only location reaches the wire on BOTH endpoints',
      () async {
        const located = SearchFilters(
          cityId: 'city-9',
          districtId: 'district-4',
        );
        when(
          () => api.searchMasters(request: any(named: 'request')),
        ).thenAnswer((_) async => _masterResponse([]));
        when(
          () => api.searchSalons(request: any(named: 'request')),
        ).thenAnswer((_) async => _salonResponse([]));

        await repository.searchMasters(filters: located, page: 0);
        await repository.searchSalons(filters: located, page: 0);

        final master =
            verify(
                  () =>
                      api.searchMasters(request: captureAny(named: 'request')),
                ).captured.single
                as MasterSearchRequest;
        final salon =
            verify(
                  () => api.searchSalons(request: captureAny(named: 'request')),
                ).captured.single
                as SalonSearchRequest;

        expect(master.location?.cityId, 'city-9');
        expect(master.location?.districtId, 'district-4');
        expect(salon.location?.cityId, 'city-9');
        expect(salon.location?.districtId, 'district-4');
      },
    );

    test('default filters send sort=RATING_DESC on both endpoints', () async {
      when(
        () => api.searchMasters(request: any(named: 'request')),
      ).thenAnswer((_) async => _masterResponse([]));
      when(
        () => api.searchSalons(request: any(named: 'request')),
      ).thenAnswer((_) async => _salonResponse([]));

      await repository.searchMasters(filters: const SearchFilters(), page: 0);
      await repository.searchSalons(filters: const SearchFilters(), page: 0);

      final master =
          verify(
                () => api.searchMasters(request: captureAny(named: 'request')),
              ).captured.single
              as MasterSearchRequest;
      final salon =
          verify(
                () => api.searchSalons(request: captureAny(named: 'request')),
              ).captured.single
              as SalonSearchRequest;

      expect(master.sort, MasterSearchRequestSortEnum.RATING_DESC);
      expect(salon.sort, SalonSearchRequestSortEnum.RATING_DESC);
    });

    test('Item 1 — a picked city reaches the wire as location.cityId on BOTH '
        'master and salon requests', () async {
      const located = SearchFilters(cityId: 'city-42');
      when(
        () => api.searchMasters(request: any(named: 'request')),
      ).thenAnswer((_) async => _masterResponse([]));
      when(
        () => api.searchSalons(request: any(named: 'request')),
      ).thenAnswer((_) async => _salonResponse([]));

      await repository.searchMasters(filters: located, page: 0);
      await repository.searchSalons(filters: located, page: 0);

      final master =
          verify(
                () => api.searchMasters(request: captureAny(named: 'request')),
              ).captured.single
              as MasterSearchRequest;
      final salon =
          verify(
                () => api.searchSalons(request: captureAny(named: 'request')),
              ).captured.single
              as SalonSearchRequest;

      expect(master.location?.cityId, 'city-42');
      expect(master.location?.districtId, isNull);
      expect(salon.location?.cityId, 'city-42');
      expect(salon.location?.districtId, isNull);
    });

    test(
      'empty filters produce a request with paging + default sort only',
      () async {
        when(
          () => api.searchMasters(request: any(named: 'request')),
        ).thenAnswer((_) async => _masterResponse([]));

        await repository.searchMasters(filters: const SearchFilters(), page: 0);

        final captured =
            verify(
                  () =>
                      api.searchMasters(request: captureAny(named: 'request')),
                ).captured.single
                as MasterSearchRequest;

        expect(captured.q, isNull);
        expect(captured.location, isNull);
        expect(captured.category, isNull);
        expect(captured.minPrice, isNull);
        expect(captured.maxPrice, isNull);
        expect(captured.minRating, isNull);
        expect(captured.sort, MasterSearchRequestSortEnum.RATING_DESC);
        expect(captured.page, 0);
        expect(captured.size, kSearchPageSize);
      },
    );
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

    // ── Item 4 — serviceNames mapping ─────────────────────────────────────────

    test('maps a populated serviceNames list through, order preserved', () {
      final item = MasterSearchMapper.fromDto(
        _buildMasterDto(serviceNames: const ['Стрижка', 'Фарбування']),
      );
      expect(item.serviceNames, <String>['Стрижка', 'Фарбування']);
    });

    test('maps an absent serviceNames (null DTO field) to an empty list', () {
      // serviceNames: null skips setting the builder field → BuiltList is null.
      final item = MasterSearchMapper.fromDto(
        _buildMasterDto(serviceNames: null),
      );
      expect(item.serviceNames, isEmpty);
    });

    test('maps an empty serviceNames list to an empty list', () {
      final item = MasterSearchMapper.fromDto(
        _buildMasterDto(serviceNames: const <String>[]),
      );
      expect(item.serviceNames, isEmpty);
    });

    // ── Services preview line — OBSERVABLE join behaviour ─────────────────────
    //
    // The card surfaces the master's top service names as one `' · '`-joined
    // line. A perf change is landing that precomputes this line in the mapper
    // (instead of join()-ing per build()); these tests assert the OBSERVABLE
    // joined string the card must render, so they survive that refactor without
    // coupling to where the join happens. The expected line is built from the
    // domain `serviceNames` + the shared `kServiceNamesSeparator` so a separator
    // change updates the contract in exactly one place.

    String? expectedServicesLine(List<String> names) =>
        names.isEmpty ? null : names.join(kServiceNamesSeparator);

    test('two names join into a single « · »-separated preview line', () {
      final item = MasterSearchMapper.fromDto(
        _buildMasterDto(serviceNames: const ['Манікюр', 'Педикюр']),
      );
      expect(expectedServicesLine(item.serviceNames), 'Манікюр · Педикюр');
    });

    test('no names yield a null preview line (no placeholder)', () {
      final item = MasterSearchMapper.fromDto(
        _buildMasterDto(serviceNames: const <String>[]),
      );
      expect(expectedServicesLine(item.serviceNames), isNull);
    });

    test('the backend cap of ≤3 names is carried through verbatim', () {
      // The custom-preferred ≤3 trim is resolved backend-side; the mapper must
      // neither pad nor truncate. A 3-name payload arrives and joins to 3.
      final item = MasterSearchMapper.fromDto(
        _buildMasterDto(
          serviceNames: const ['Манікюр', 'Педикюр', 'Нарощування'],
        ),
      );
      expect(item.serviceNames, hasLength(3));
      expect(
        expectedServicesLine(item.serviceNames),
        'Манікюр · Педикюр · Нарощування',
      );
    });
  });
}

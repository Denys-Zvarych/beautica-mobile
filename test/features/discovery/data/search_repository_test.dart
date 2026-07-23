// Phase 13.2 / 19.x — Unit tests for [HttpSearchRepository] + the search mappers.
//
// WIRE-FORMAT REGRESSION CONTEXT (the bug this file now pins)
// ----------------------------------------------------------
// Symptom: client discovery "filter by city" returned masters from ALL regions.
// Root cause: the OpenAPI-generated `SearchControllerApi` serialised the whole
// search DTO as ONE object query param named `request`; Dio bracket-nested it to
// `request[location][cityId]=<uuid>`, which Spring's `@ModelAttribute` binder
// cannot read → the backend bound an all-null request → an unfiltered all-regions
// 200. Fix: [HttpSearchRepository] now issues GET `/api/v1/search/masters` and
// `/api/v1/search/salons` through the shared [Dio] with a FLAT dot-notation query
// map (`location.cityId=<uuid>`, `sort=…`, `page=…`, …) and deserialises the
// response through the same `standardSerializers`. Constructor changed from
// `HttpSearchRepository(SearchControllerApi)` to `HttpSearchRepository(Dio,
// Serializers)`.
//
// STRATEGY
// --------
// Mock [Dio] with mocktail and construct [HttpSearchRepository] directly (pure
// Dart unit — no Riverpod). `Dio.get<Object>` is stubbed to return a [Response]
// whose `data` is the JSON-collection form of the envelope (produced via
// `standardSerializers.serialize`, exactly what the real Dio JSON transformer
// yields), so response parsing into the domain models is exercised end to end.
// The request side is asserted by CAPTURING the `path` + `queryParameters`
// handed to `Dio.get` and checking the FLAT keys — this is what locks the wire.
//
// Coverage:
//   • Response parsing — populated page, empty page, double coercion, mapper
//     guards (null id → ServerFailure) for BOTH masters and salons.
//   • Error mapping — 400/422 → ValidationFailure, connection/timeout →
//     NetworkFailure (the same DioException → Failure table as before).
//   • Request translation (FLAT wire) — q / category / location / sort /
//     minPrice / maxPrice / minRating / page / size; null/blank fields OMITTED.
//   • REGRESSION — a picked city reaches the wire as the literal dotted key
//     `location.cityId` (NOT `request[location][cityId]`) on BOTH endpoints, the
//     rendered query string contains `location.cityId=<uuid>` and contains NO
//     `request` / `[` / `]` / `%5B` bracket-encoding. This assertion FAILS the
//     instant anyone reverts to the object-query encoding.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/discovery/data/search_mapper.dart';
import 'package:beautica_mobile/features/discovery/data/search_repository.dart';
import 'package:beautica_mobile/features/discovery/domain/search_filters.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/result_card_text.dart'
    show kServiceNamesSeparator;
import 'package:built_collection/built_collection.dart';
import 'package:built_value/serializer.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// ── Mocks ──────────────────────────────────────────────────────────────────

class _MockDio extends Mock implements Dio {}

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
  num? priceMax,
  String? street,
  String? buildingNo,
  List<String>? serviceNames = const ['Манікюр', 'Педикюр'],
  List<String>? matchedServiceNames,
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
    ..minEffectivePrice = minEffectivePrice
    ..priceMax = priceMax
    ..street = street
    ..buildingNo = buildingNo;
  if (serviceNames != null) {
    b.serviceNames = ListBuilder<String>(serviceNames);
  }
  if (matchedServiceNames != null) {
    b.matchedServiceNames = ListBuilder<String>(matchedServiceNames);
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
  String? street,
  String? buildingNo,
  List<String>? serviceNames,
  List<String>? matchedServiceNames,
}) {
  final b = SalonSearchResultBuilder()
    ..salonId = salonId
    ..name = name
    ..avatarUrl = avatarUrl
    ..cityLabel = cityLabel
    ..districtLabel = districtLabel
    ..priceMin = priceMin
    ..priceMax = priceMax
    ..street = street
    ..buildingNo = buildingNo;
  if (serviceNames != null) {
    b.serviceNames = ListBuilder<String>(serviceNames);
  }
  if (matchedServiceNames != null) {
    b.matchedServiceNames = ListBuilder<String>(matchedServiceNames);
  }
  return b.build();
}

/// The exact wire form the real Dio JSON transformer hands the repository: the
/// JSON-collection (Map/List of primitives) serialization of the typed envelope.
/// The repository's `_deserialize` re-hydrates it via `standardSerializers`, so
/// feeding the SERIALIZED form (not the built object) exercises the real parse
/// path — a deserialization fault would surface here exactly as in production.
Object _serializeMasterEnvelope(
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
  return standardSerializers.serialize(
    body,
    specifiedType: const FullType(ApiResponsePageResponseMasterSearchResult),
  )!;
}

Object _serializeSalonEnvelope(
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
  return standardSerializers.serialize(
    body,
    specifiedType: const FullType(ApiResponsePageResponseSalonSearchResult),
  )!;
}

Response<Object> _masterResponse(
  List<MasterSearchResult> items, {
  int page = 0,
  int totalPages = 1,
  int? totalElements,
}) => Response<Object>(
  data: _serializeMasterEnvelope(
    items,
    page: page,
    totalPages: totalPages,
    totalElements: totalElements,
  ),
  requestOptions: RequestOptions(path: _masterPath),
  statusCode: 200,
);

Response<Object> _salonResponse(
  List<SalonSearchResult> items, {
  int page = 0,
  int totalPages = 1,
}) => Response<Object>(
  data: _serializeSalonEnvelope(items, page: page, totalPages: totalPages),
  requestOptions: RequestOptions(path: _salonPath),
  statusCode: 200,
);

DioException _dioBadResponse(int statusCode, String path) => DioException(
  requestOptions: RequestOptions(path: path),
  response: Response<Object?>(
    requestOptions: RequestOptions(path: path),
    statusCode: statusCode,
  ),
  type: DioExceptionType.badResponse,
);

void main() {
  late _MockDio dio;
  late HttpSearchRepository repository;

  const filters = SearchFilters();

  setUp(() {
    dio = _MockDio();
    repository = HttpSearchRepository(dio, standardSerializers);
    // `queryParameters` is a Map<String, dynamic> matched with any(); register a
    // fallback so mocktail can synthesise it for the matcher.
    registerFallbackValue(<String, dynamic>{});
  });

  // ── stub helpers: arm Dio.get for the masters / salons GET ──────────────────

  void stubMasters(Response<Object> response) {
    when(
      () => dio.get<Object>(
        _masterPath,
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer((_) async => response);
  }

  void stubMastersThrows(Object error) {
    when(
      () => dio.get<Object>(
        _masterPath,
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenThrow(error);
  }

  void stubSalons(Response<Object> response) {
    when(
      () => dio.get<Object>(
        _salonPath,
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer((_) async => response);
  }

  void stubSalonsThrows(Object error) {
    when(
      () => dio.get<Object>(
        _salonPath,
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenThrow(error);
  }

  /// Captures the FLAT query map the repository handed `Dio.get` for [path].
  Map<String, dynamic> capturedQuery(String path) {
    final captured = verify(
      () => dio.get<Object>(
        path,
        queryParameters: captureAny(named: 'queryParameters'),
      ),
    ).captured.single;
    return Map<String, dynamic>.from(captured as Map);
  }

  // ── searchMasters — response parsing ────────────────────────────────────────

  group('searchMasters response parsing', () {
    test('maps a populated page to domain MasterSearchItems', () async {
      stubMasters(_masterResponse([_buildMasterDto()]));

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

    test('returns an empty page when the backend matches nothing', () async {
      stubMasters(_masterResponse([], totalPages: 0));

      final page = await repository.searchMasters(filters: filters, page: 0);

      expect(page.items, isEmpty);
      expect(page.totalPages, 0);
      expect(page.hasMore, isFalse);
    });

    test(
      'empty page carries totalElements == 0 (no items, no match)',
      () async {
        stubMasters(_masterResponse([], page: 0, totalPages: 0));

        final page = await repository.searchMasters(filters: filters, page: 0);

        expect(page.items, isEmpty);
        expect(page.totalElements, 0);
        expect(page.totalPages, 0);
        expect(page.page, 0);
        expect(page.hasMore, isFalse);
      },
    );

    test('maps a 400 response to ValidationFailure', () async {
      stubMastersThrows(_dioBadResponse(400, _masterPath));

      expect(
        () => repository.searchMasters(filters: filters, page: 0),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('maps a 422 response to ValidationFailure', () async {
      stubMastersThrows(_dioBadResponse(422, _masterPath));

      expect(
        () => repository.searchMasters(filters: filters, page: 0),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('maps a connection error to NetworkFailure', () async {
      stubMastersThrows(
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

    test('maps a receive timeout to NetworkFailure', () async {
      stubMastersThrows(
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

    test('maps a null masterId to ServerFailure (mapper guard)', () async {
      stubMasters(_masterResponse([_buildMasterDto(masterId: null)]));

      expect(
        () => repository.searchMasters(filters: filters, page: 0),
        throwsA(isA<ServerFailure>()),
      );
    });

    test(
      'minEffectivePrice is delivered as a double (not the raw num)',
      () async {
        stubMasters(_masterResponse([_buildMasterDto(minEffectivePrice: 350)]));

        final page = await repository.searchMasters(filters: filters, page: 0);

        final price = page.items.single.minEffectivePrice;
        expect(price, isA<double>());
        expect(price, 350.0);
      },
    );
  });

  // ── searchSalons — response parsing ─────────────────────────────────────────

  group('searchSalons response parsing', () {
    test('maps a populated page; avgRating is null (DTO omits it)', () async {
      stubSalons(_salonResponse([_buildSalonDto()]));

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
      stubSalons(_salonResponse([_buildSalonDto(salonId: null)]));

      expect(
        () => repository.searchSalons(filters: filters, page: 0),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('returns an empty page when the backend matches nothing', () async {
      stubSalons(_salonResponse([], totalPages: 0));

      final page = await repository.searchSalons(filters: filters, page: 0);

      expect(page.items, isEmpty);
      expect(page.totalElements, 0);
      expect(page.hasMore, isFalse);
    });

    test('maps a 400 response to ValidationFailure', () async {
      stubSalonsThrows(_dioBadResponse(400, _salonPath));

      expect(
        () => repository.searchSalons(filters: filters, page: 0),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('maps a connection error to NetworkFailure', () async {
      stubSalonsThrows(
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
      stubSalons(_salonResponse([_buildSalonDto()]));

      final page = await repository.searchSalons(filters: filters, page: 0);

      final item = page.items.single;
      expect(item.priceMin, isA<double>());
      expect(item.priceMax, isA<double>());
      expect(item.priceMin, 400.0);
      expect(item.priceMax, 900.0);
    });
  });

  // ── Request translation — FLAT @ModelAttribute-bindable wire ────────────────
  //
  // These capture the `path` + `queryParameters` handed to `Dio.get` and assert
  // every param reaches the wire as a FLAT key with the exact backend field name
  // (`q`, `category`, `location.cityId`, `location.districtId`, `sort`,
  // `minPrice`, `maxPrice`, `minRating`, `page`, `size`). Null/blank filters are
  // OMITTED (the backend treats an absent key as "no constraint").

  group('request translation (flat wire)', () {
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
      'searchMasters forwards q, sort, location, category, price, rating, paging',
      () async {
        stubMasters(_masterResponse([_buildMasterDto()]));

        await repository.searchMasters(filters: richFilters, page: 2);

        final q = capturedQuery(_masterPath);
        expect(q['q'], 'Манікюр');
        expect(q['sort'], 'PRICE_ASC');
        expect(q['category'], 'HAIR');
        expect(q['location.cityId'], 'city-7');
        expect(q['location.districtId'], 'district-3');
        expect(q['minPrice'], '200.0');
        expect(q['maxPrice'], '800.0');
        expect(q['minRating'], '4.0');
        expect(q['page'], 2);
        expect(q['size'], kSearchPageSize);
      },
    );

    test('searchSalons forwards q, sort, location, category AND the price band '
        '(but NOT minRating — salon endpoint has no rating filter)', () async {
      stubSalons(_salonResponse([_buildSalonDto()]));

      await repository.searchSalons(filters: richFilters, page: 1);

      final q = capturedQuery(_salonPath);
      expect(q['q'], 'Манікюр');
      expect(q['sort'], 'PRICE_ASC');
      expect(q['category'], 'HAIR');
      expect(q['location.cityId'], 'city-7');
      expect(q['location.districtId'], 'district-3');
      expect(q['minPrice'], '200.0');
      expect(q['maxPrice'], '800.0');
      expect(q['page'], 1);
      expect(q['size'], kSearchPageSize);
      // minRating is intentionally absent on the salon endpoint.
      expect(q.containsKey('minRating'), isFalse);
    });

    test(
      'a blank/whitespace query is normalised to null (q OMITTED)',
      () async {
        stubMasters(_masterResponse([]));

        await repository.searchMasters(
          filters: const SearchFilters(query: '   '),
          page: 0,
        );

        final q = capturedQuery(_masterPath);
        expect(q.containsKey('q'), isFalse);
      },
    );

    test(
      'a query with surrounding whitespace is trimmed before sending',
      () async {
        stubSalons(_salonResponse([]));

        await repository.searchSalons(
          filters: const SearchFilters(query: '  педикюр  '),
          page: 0,
        );

        final q = capturedQuery(_salonPath);
        expect(q['q'], 'педикюр');
      },
    );

    test(
      'empty filters send paging + default sort ONLY (every optional omitted)',
      () async {
        stubMasters(_masterResponse([]));

        await repository.searchMasters(filters: const SearchFilters(), page: 0);

        final q = capturedQuery(_masterPath);
        expect(q['page'], 0);
        expect(q['size'], kSearchPageSize);
        expect(q['sort'], 'RATING_DESC');
        // Nothing else reaches the wire — null/blank filters are dropped.
        expect(q.containsKey('q'), isFalse);
        expect(q.containsKey('category'), isFalse);
        expect(q.containsKey('location.cityId'), isFalse);
        expect(q.containsKey('location.districtId'), isFalse);
        expect(q.containsKey('minPrice'), isFalse);
        expect(q.containsKey('maxPrice'), isFalse);
        expect(q.containsKey('minRating'), isFalse);
      },
    );

    test('Phase 13.11 — serviceTypeSlugs emitted (SORTED list) on the master '
        'endpoint when populated, omitted when empty', () async {
      stubMasters(_masterResponse([]));

      await repository.searchMasters(
        // Insertion order intentionally NOT alphabetical to prove the repo
        // sorts before emitting (deterministic wire).
        filters: const SearchFilters(
          serviceTypeSlugs: <String>{'manicure', 'brows', 'lashes'},
        ),
        page: 0,
      );

      final q = capturedQuery(_masterPath);
      expect(q['serviceTypeSlugs'], <String>['brows', 'lashes', 'manicure']);
    });

    test('Phase 13.11 — serviceTypeSlugs emitted (SORTED list) on the salon '
        'endpoint when populated', () async {
      stubSalons(_salonResponse([]));

      await repository.searchSalons(
        filters: const SearchFilters(
          serviceTypeSlugs: <String>{'pedicure', 'manicure'},
        ),
        page: 0,
      );

      final q = capturedQuery(_salonPath);
      expect(q['serviceTypeSlugs'], <String>['manicure', 'pedicure']);
    });

    test(
      'Phase 13.11 — an empty serviceTypeSlugs set is OMITTED from the wire',
      () async {
        stubMasters(_masterResponse([]));
        stubSalons(_salonResponse([]));

        await repository.searchMasters(filters: const SearchFilters(), page: 0);
        await repository.searchSalons(filters: const SearchFilters(), page: 0);

        expect(
          capturedQuery(_masterPath).containsKey('serviceTypeSlugs'),
          isFalse,
        );
        expect(
          capturedQuery(_salonPath).containsKey('serviceTypeSlugs'),
          isFalse,
        );
      },
    );

    test('default filters send sort=RATING_DESC on BOTH endpoints', () async {
      stubMasters(_masterResponse([]));
      stubSalons(_salonResponse([]));

      await repository.searchMasters(filters: const SearchFilters(), page: 0);
      await repository.searchSalons(filters: const SearchFilters(), page: 0);

      expect(capturedQuery(_masterPath)['sort'], 'RATING_DESC');
      expect(capturedQuery(_salonPath)['sort'], 'RATING_DESC');
    });

    test('master endpoint forwards the minPrice/maxPrice band', () async {
      stubMasters(_masterResponse([]));

      await repository.searchMasters(
        filters: const SearchFilters(minPrice: 150, maxPrice: 650),
        page: 0,
      );

      final q = capturedQuery(_masterPath);
      expect(q['minPrice'], '150.0');
      expect(q['maxPrice'], '650.0');
    });

    // Every SearchSort enum constant must serialise to its exact backend wire
    // string on BOTH endpoints. The repository writes `f.sort.wireValue` to the
    // `sort` key verbatim; a drift in wireValue (or a missing enum constant)
    // would surface a wrong `?sort=` token and silently mis-order results.
    const Map<SearchSort, String> sortWireMap = <SearchSort, String>{
      SearchSort.ratingDesc: 'RATING_DESC',
      SearchSort.priceAsc: 'PRICE_ASC',
      SearchSort.priceDesc: 'PRICE_DESC',
      SearchSort.reviewsDesc: 'REVIEWS_DESC',
    };

    for (final MapEntry<SearchSort, String> entry in sortWireMap.entries) {
      final SearchSort sort = entry.key;
      final String wire = entry.value;

      test('sort=${sort.name} maps to $wire on BOTH endpoints', () async {
        stubMasters(_masterResponse([]));
        stubSalons(_salonResponse([]));

        final filtersForSort = SearchFilters(sort: sort);
        await repository.searchMasters(filters: filtersForSort, page: 0);
        await repository.searchSalons(filters: filtersForSort, page: 0);

        expect(capturedQuery(_masterPath)['sort'], wire);
        expect(capturedQuery(_salonPath)['sort'], wire);
        // The enum's wireValue is the literal `sort=` token — assert it too so a
        // rename on the Dart side cannot drift from the backend constant.
        expect(sort.wireValue, wire);
      });
    }
  });

  // ── REGRESSION — the city filter must reach the wire FLAT, never bracketed ──
  //
  // This is the test the original bug demanded: it pins the exact wire format so
  // a future change / OpenAPI regenerate can never silently re-break the city
  // filter by reverting to the object-query (`request[location][cityId]=…`)
  // encoding the @ModelAttribute binder cannot read.

  group('city filter wire-format regression', () {
    const located = SearchFilters(
      cityId: 'b3f1c2d4-0000-4aaa-bbbb-ccccdddd1111',
      districtId: 'a1a2a3a4-0000-4bbb-cccc-ddddeeee2222',
    );

    /// Asserts the captured FLAT query map for [path] scopes the search to the
    /// picked city/district via literal DOTTED keys and carries NO bracketed /
    /// object-query encoding. Also renders the final URI and re-asserts the wire
    /// string contains `location.cityId=<uuid>` and NO `request` / `[`/`]`/`%5B`.
    void expectCityScopedFlatWire(String path) {
      final q = capturedQuery(path);

      // The picked ids reach the wire under the EXACT backend field names.
      expect(
        q['location.cityId'],
        'b3f1c2d4-0000-4aaa-bbbb-ccccdddd1111',
        reason:
            'city must scope the search via the literal dotted key '
            '`location.cityId` the @ModelAttribute binder reads',
      );
      expect(q['location.districtId'], 'a1a2a3a4-0000-4bbb-cccc-ddddeeee2222');

      // No object-query encoding survives: no `request` wrapper key, and no key
      // contains a `[` / `]` bracket. THIS is the assertion that fails the
      // instant someone reverts to the generated SearchControllerApi encoding
      // (which produced `request[location][cityId]=…`).
      expect(
        q.containsKey('request'),
        isFalse,
        reason: 'a `request` object-query wrapper key is the reverted bug',
      );
      for (final String key in q.keys) {
        expect(
          key.contains('['),
          isFalse,
          reason: 'bracket-nested key "$key" cannot bind @ModelAttribute',
        );
        expect(key.contains(']'), isFalse, reason: 'bracketed key "$key"');
        expect(
          key.startsWith('request'),
          isFalse,
          reason: 'object-query wrapper key "$key"',
        );
      }

      // Render the final query string Dio would put on the wire and assert the
      // ground-truth bytes: city present FLAT, no bracket-encoding at all.
      final String queryString = Uri(
        queryParameters: q.map((k, v) => MapEntry<String, String>(k, '$v')),
      ).query;
      expect(
        queryString,
        contains('location.cityId=b3f1c2d4-0000-4aaa-bbbb-ccccdddd1111'),
        reason: 'the city must appear FLAT in the rendered query string',
      );
      expect(
        queryString.contains('request'),
        isFalse,
        reason: 'no `request` object-query wrapper in the wire string',
      );
      expect(
        queryString.contains('%5B') || queryString.contains('['),
        isFalse,
        reason: 'no `[` / `%5B` bracket-encoding in the wire string',
      );
    }

    test(
      'a picked city+district reaches /search/masters as flat location.* keys, '
      'never bracket-nested',
      () async {
        stubMasters(_masterResponse([]));

        await repository.searchMasters(filters: located, page: 0);

        expectCityScopedFlatWire(_masterPath);
      },
    );

    test(
      'a picked city+district reaches /search/salons as flat location.* keys, '
      'never bracket-nested',
      () async {
        stubSalons(_salonResponse([]));

        await repository.searchSalons(filters: located, page: 0);

        expectCityScopedFlatWire(_salonPath);
      },
    );

    test(
      'a city-only filter sends location.cityId and OMITS location.districtId '
      'on BOTH endpoints',
      () async {
        const cityOnly = SearchFilters(cityId: 'city-42');
        stubMasters(_masterResponse([]));
        stubSalons(_salonResponse([]));

        await repository.searchMasters(filters: cityOnly, page: 0);
        await repository.searchSalons(filters: cityOnly, page: 0);

        final master = capturedQuery(_masterPath);
        expect(master['location.cityId'], 'city-42');
        expect(master.containsKey('location.districtId'), isFalse);

        final salon = capturedQuery(_salonPath);
        expect(salon['location.cityId'], 'city-42');
        expect(salon.containsKey('location.districtId'), isFalse);
      },
    );

    test('the search GET hits the documented paths', () async {
      stubMasters(_masterResponse([]));
      stubSalons(_salonResponse([]));

      await repository.searchMasters(filters: located, page: 0);
      await repository.searchSalons(filters: located, page: 0);

      // capturedQuery(path) itself verifies Dio.get was called with that exact
      // path; an extra explicit assertion documents the contract.
      verify(
        () => dio.get<Object>(
          _masterPath,
          queryParameters: any(named: 'queryParameters'),
        ),
      ).called(1);
      verify(
        () => dio.get<Object>(
          _salonPath,
          queryParameters: any(named: 'queryParameters'),
        ),
      ).called(1);
    });
  });

  // ── Item 4 — oblastId is UI-only; it must NEVER reach the wire ──────────────
  //
  // The region (oblast) narrows the city PICKER and labels the applied-filter
  // chips, but there is no whole-region search: the cascade always resolves to a
  // flat location.cityId (+ optional location.districtId). The repository sends
  // those FLAT keys and must NOT emit any `oblastId` / `location.oblastId` key.
  // A future "forward the oblast too" change would surface here as a leaked key
  // the @ModelAttribute binder does not expect.

  group('oblastId is UI-only (never sent to the wire)', () {
    const withOblast = SearchFilters(
      oblastId: 'oblast-kyiv',
      cityId: 'city-kyiv',
      districtId: 'dist-pechersk',
    );

    test(
      'searchMasters sends location.cityId/districtId but NO oblast key',
      () async {
        stubMasters(_masterResponse([]));

        await repository.searchMasters(filters: withOblast, page: 0);

        final q = capturedQuery(_masterPath);
        // The flat location keys reach the wire …
        expect(q['location.cityId'], 'city-kyiv');
        expect(q['location.districtId'], 'dist-pechersk');
        // … but the oblast id does NOT, under any spelling.
        expect(q.containsKey('oblastId'), isFalse);
        expect(q.containsKey('location.oblastId'), isFalse);
        expect(
          q.keys.where((String k) => k.toLowerCase().contains('oblast')),
          isEmpty,
          reason: 'the oblast is UI-only — no oblast key may reach the request',
        );
      },
    );

    test(
      'searchSalons sends location.cityId/districtId but NO oblast key',
      () async {
        stubSalons(_salonResponse([]));

        await repository.searchSalons(filters: withOblast, page: 0);

        final q = capturedQuery(_salonPath);
        expect(q['location.cityId'], 'city-kyiv');
        expect(q['location.districtId'], 'dist-pechersk');
        expect(q.containsKey('oblastId'), isFalse);
        expect(q.containsKey('location.oblastId'), isFalse);
        expect(
          q.keys.where((String k) => k.toLowerCase().contains('oblast')),
          isEmpty,
        );
      },
    );

    test(
      'a district-optional selection (oblast + city, no district) sends ONLY '
      'location.cityId',
      () async {
        const cityNoDistrict = SearchFilters(
          oblastId: 'oblast-kyiv',
          cityId: 'city-kyiv',
        );
        stubMasters(_masterResponse([]));

        await repository.searchMasters(filters: cityNoDistrict, page: 0);

        final q = capturedQuery(_masterPath);
        expect(q['location.cityId'], 'city-kyiv');
        expect(q.containsKey('location.districtId'), isFalse);
        expect(
          q.keys.where((String k) => k.toLowerCase().contains('oblast')),
          isEmpty,
        );
      },
    );
  });

  // ── Mapper-level edge cases ──────────────────────────────────────────────────

  group('SalonSearchMapper', () {
    test('carries equal priceMin/priceMax through unchanged', () {
      final item = SalonSearchMapper.fromDto(
        _buildSalonDto(priceMin: 500, priceMax: 500),
      );
      expect(item.priceMin, 500.0);
      expect(item.priceMax, 500.0);
    });

    test('carries both-null prices as null (no price)', () {
      final item = SalonSearchMapper.fromDto(
        _buildSalonDto(priceMin: null, priceMax: null),
      );
      expect(item.priceMin, isNull);
      expect(item.priceMax, isNull);
    });

    // ── Item 6 — addressLine pre-join (street + buildingNo) ───────────────────
    test('builds addressLine «street, buildingNo» from both fields', () {
      final item = SalonSearchMapper.fromDto(
        _buildSalonDto(street: 'вул. Сагайдачного', buildingNo: '10А'),
      );
      expect(item.street, 'вул. Сагайдачного');
      expect(item.buildingNo, '10А');
      expect(item.addressLine, 'вул. Сагайдачного, 10А');
    });

    test('addressLine is the street alone when buildingNo is absent', () {
      final item = SalonSearchMapper.fromDto(
        _buildSalonDto(street: 'вул. Сагайдачного', buildingNo: null),
      );
      expect(item.addressLine, 'вул. Сагайдачного');
    });

    test('null street → null addressLine (card falls back to locality)', () {
      final item = SalonSearchMapper.fromDto(
        _buildSalonDto(street: null, buildingNo: '10А'),
      );
      expect(
        item.addressLine,
        isNull,
        reason:
            'a building number with no street is not a usable address — the '
            'mapper emits null so the card renders the locality instead.',
      );
    });

    // ── Item 7 — servicesLine pre-join from serviceNames ──────────────────────
    test('builds the « · »-joined servicesLine from serviceNames', () {
      final item = SalonSearchMapper.fromDto(
        _buildSalonDto(serviceNames: const ['Манікюр', 'Стрижка']),
      );
      expect(item.serviceNames, <String>['Манікюр', 'Стрижка']);
      expect(item.servicesLine, 'Манікюр · Стрижка');
    });

    test('null/empty serviceNames → null servicesLine (line omitted)', () {
      final absent = SalonSearchMapper.fromDto(
        _buildSalonDto(serviceNames: null),
      );
      expect(absent.serviceNames, isEmpty);
      expect(absent.servicesLine, isNull);

      final empty = SalonSearchMapper.fromDto(
        _buildSalonDto(serviceNames: const <String>[]),
      );
      expect(empty.servicesLine, isNull);
    });

    // Phase 13.12 — matchedServiceNames → matchedServicesLine.
    test('matchedServiceNames join into matchedServicesLine when present', () {
      final item = SalonSearchMapper.fromDto(
        _buildSalonDto(
          serviceNames: const ['Манікюр', 'Педикюр'],
          matchedServiceNames: const ['Педикюр'],
        ),
      );
      expect(item.matchedServicesLine, 'Педикюр');
    });

    test('absent/empty matchedServiceNames → null matchedServicesLine', () {
      final absent = SalonSearchMapper.fromDto(_buildSalonDto());
      expect(absent.matchedServicesLine, isNull);

      final empty = SalonSearchMapper.fromDto(
        _buildSalonDto(matchedServiceNames: const <String>[]),
      );
      expect(empty.matchedServicesLine, isNull);
    });
  });

  group('MasterSearchMapper', () {
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

    // ── Item 2 — priceMax is mapped (drives the «від» decision on the card) ───
    test('maps priceMax as a double (not the raw num)', () {
      final item = MasterSearchMapper.fromDto(
        _buildMasterDto(minEffectivePrice: 350, priceMax: 900),
      );
      expect(item.priceMax, isA<double>());
      expect(item.priceMax, 900.0);
    });

    test('a null priceMax maps to null (single fixed price on the card)', () {
      final item = MasterSearchMapper.fromDto(
        _buildMasterDto(minEffectivePrice: 350, priceMax: null),
      );
      expect(item.priceMax, isNull);
    });

    // ── Item 6 — addressLine pre-join (street + buildingNo) ───────────────────
    test('builds addressLine «street, buildingNo» from both fields', () {
      final item = MasterSearchMapper.fromDto(
        _buildMasterDto(street: 'вул. Хрещатик', buildingNo: '22'),
      );
      expect(item.street, 'вул. Хрещатик');
      expect(item.buildingNo, '22');
      expect(item.addressLine, 'вул. Хрещатик, 22');
    });

    test('null street → null addressLine (card falls back to locality)', () {
      final item = MasterSearchMapper.fromDto(
        _buildMasterDto(street: null, buildingNo: '22'),
      );
      expect(
        item.addressLine,
        isNull,
        reason:
            'an anonymous caller gets a null street → the mapper emits a null '
            'addressLine so the card renders the city/district locality.',
      );
    });

    test('the precomputed servicesLine mirrors the joined serviceNames', () {
      final item = MasterSearchMapper.fromDto(
        _buildMasterDto(serviceNames: const ['Манікюр', 'Педикюр']),
      );
      expect(item.servicesLine, 'Манікюр · Педикюр');
    });

    test('maps a populated serviceNames list through, order preserved', () {
      final item = MasterSearchMapper.fromDto(
        _buildMasterDto(serviceNames: const ['Стрижка', 'Фарбування']),
      );
      expect(item.serviceNames, <String>['Стрижка', 'Фарбування']);
    });

    test('maps an absent serviceNames (null DTO field) to an empty list', () {
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

    // Phase 13.12 — matchedServiceNames → matchedServicesLine (≤3, ' · ').
    test('matchedServiceNames join into matchedServicesLine when present', () {
      final item = MasterSearchMapper.fromDto(
        _buildMasterDto(
          serviceNames: const ['Манікюр', 'Педикюр', 'Брови'],
          matchedServiceNames: const ['Манікюр', 'Брови'],
        ),
      );
      expect(item.matchedServicesLine, 'Манікюр · Брови');
    });

    test('absent/empty matchedServiceNames → null matchedServicesLine', () {
      final absent = MasterSearchMapper.fromDto(_buildMasterDto());
      expect(
        absent.matchedServicesLine,
        isNull,
        reason: 'no filter active → backend omits matchedServiceNames → null',
      );

      final empty = MasterSearchMapper.fromDto(
        _buildMasterDto(matchedServiceNames: const <String>[]),
      );
      expect(empty.matchedServicesLine, isNull);
    });
  });
}

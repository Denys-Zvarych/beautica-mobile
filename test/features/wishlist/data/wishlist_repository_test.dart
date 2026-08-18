// Phase 237 — TIER 2 unit tests for [HttpWishlistRepository].
//
// Strategy mirrors `passport_repository_test.dart`: mocktail-mock the generated
// [FavoriteControllerApi]. No real Dio, no ProviderScope, no widget tree.
//
// FAILURE SHAPE: every `thenAnswer((_) async => throw …)`, never `thenThrow`.
// A Dio-backed call ALWAYS fails asynchronously; a synchronous throw is a shape
// the real transport cannot produce, and it bypasses the async machinery a
// caller one layer up depends on.

import 'package:beautica_api/beautica_api.dart' as api;
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/wishlist/data/wishlist_repository.dart';
import 'package:beautica_mobile/features/wishlist/domain/wishlist_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockFavoriteApi extends Mock implements api.FavoriteControllerApi {}

const String _path = '/api/v1/favorites/services';

RequestOptions _reqOptions() => RequestOptions(path: _path);

api.FavoriteServiceResponse _row({
  required String id,
  String priceDisplay = 'від 600 до 900 ₴',
}) => api.FavoriteServiceResponse(
  (api.FavoriteServiceResponseBuilder b) => b
    ..masterServiceId = id
    ..masterId = 'm-$id'
    ..serviceName = 'Послуга $id'
    ..masterFirstName = 'Олена'
    ..masterLastName = 'Ковальчук'
    ..durationMinutes = 60
    ..priceDisplay = priceDisplay,
);

Response<api.ApiResponsePageResponseFavoriteServiceResponse> _ok(
  List<api.FavoriteServiceResponse> rows,
) => Response<api.ApiResponsePageResponseFavoriteServiceResponse>(
  requestOptions: _reqOptions(),
  statusCode: 200,
  data: api.ApiResponsePageResponseFavoriteServiceResponse(
    (api.ApiResponsePageResponseFavoriteServiceResponseBuilder b) => b
      ..success = true
      ..data.success = true
      ..data.page = 0
      ..data.size = 20
      ..data.totalElements = rows.length
      ..data.totalPages = 1
      ..data.data.replace(rows),
  ),
);

/// A 200 whose envelope carries a null `data` page — a malformed success the
/// repository must convert into a [ServerFailure] rather than dereference.
Response<api.ApiResponsePageResponseFavoriteServiceResponse> _okNullData() =>
    Response<api.ApiResponsePageResponseFavoriteServiceResponse>(
      requestOptions: _reqOptions(),
      statusCode: 200,
      data: api.ApiResponsePageResponseFavoriteServiceResponse(
        (api.ApiResponsePageResponseFavoriteServiceResponseBuilder b) =>
            b..success = true,
      ),
    );

DioException _dio(DioExceptionType type, {int? status, Object? error}) =>
    DioException(
      requestOptions: _reqOptions(),
      type: type,
      error: error,
      response: status == null
          ? null
          : Response<dynamic>(
              requestOptions: _reqOptions(),
              statusCode: status,
            ),
    );

void main() {
  late _MockFavoriteApi apiMock;
  late HttpWishlistRepository repo;

  setUpAll(() {
    registerFallbackValue(api.Pageable((api.PageableBuilder b) => b..page = 0));
  });

  setUp(() {
    apiMock = _MockFavoriteApi();
    repo = HttpWishlistRepository(apiMock);
  });

  group('happy path', () {
    test('unwraps the page envelope and maps every row', () async {
      when(
        () => apiMock.listServiceFavorites(pageable: any(named: 'pageable')),
      ).thenAnswer(
        (_) async =>
            _ok(<api.FavoriteServiceResponse>[_row(id: 'a'), _row(id: 'b')]),
      );

      final List<WishlistService> out = await repo.getMyWishlist();

      expect(out, hasLength(2));
      expect(out.first.masterServiceId, 'a');
      expect(out.last.masterServiceId, 'b');
    });

    test('the pre-formatted price survives the whole data layer', () async {
      // End-to-end for the one rule this feature is most likely to break: the
      // repository must not touch the band any more than the mapper does.
      when(
        () => apiMock.listServiceFavorites(pageable: any(named: 'pageable')),
      ).thenAnswer(
        (_) async => _ok(<api.FavoriteServiceResponse>[
          _row(id: 'a', priceDisplay: 'від 600 до 900 ₴'),
        ]),
      );

      final List<WishlistService> out = await repo.getMyWishlist();
      expect(out.single.priceDisplay, 'від 600 до 900 ₴');
    });

    test('it asks for page 0 at the endpoint default size', () async {
      when(
        () => apiMock.listServiceFavorites(pageable: any(named: 'pageable')),
      ).thenAnswer((_) async => _ok(const <api.FavoriteServiceResponse>[]));

      await repo.getMyWishlist();

      final api.Pageable sent =
          verify(
                () => apiMock.listServiceFavorites(
                  pageable: captureAny(named: 'pageable'),
                ),
              ).captured.single
              as api.Pageable;
      expect(sent.page, 0);
      expect(sent.size, 20);
    });

    test('an ABSENT rows list is an empty wish list, not an error', () async {
      when(
        () => apiMock.listServiceFavorites(pageable: any(named: 'pageable')),
      ).thenAnswer(
        (_) async =>
            Response<api.ApiResponsePageResponseFavoriteServiceResponse>(
              requestOptions: _reqOptions(),
              statusCode: 200,
              data: api.ApiResponsePageResponseFavoriteServiceResponse(
                (api.ApiResponsePageResponseFavoriteServiceResponseBuilder b) =>
                    b
                      ..success = true
                      ..data.success = true
                      ..data.totalElements = 0,
              ),
            ),
      );

      expect(await repo.getMyWishlist(), isEmpty);
    });
  });

  group('should_throwServerFailure_when_envelopeDataIsNull', () {
    test(
      'a null page envelope is a ServerFailure, not a null dereference',
      () async {
        when(
          () => apiMock.listServiceFavorites(pageable: any(named: 'pageable')),
        ).thenAnswer((_) async => _okNullData());

        await expectLater(
          repo.getMyWishlist(),
          throwsA(
            isA<ServerFailure>().having(
              (ServerFailure f) => f.statusCode,
              'statusCode',
              isNull,
            ),
          ),
        );
      },
    );

    test('a malformed row is DROPPED, not propagated — the landmine this phase '
        'fixes', () async {
      // Phase F: `WishlistMapper.fromDtoList` now catches a per-row mapper
      // failure and drops just that row (see its own doc for the decision).
      // Before that fix, a single row missing its ids threw out of the
      // mapper, propagated through `List.map`, and blanked the WHOLE
      // page — this test used to pin exactly that (a thrown ServerFailure
      // for one bad row among the response). It now pins the opposite: one
      // bad row costs one entry, not the page.
      when(
        () => apiMock.listServiceFavorites(pageable: any(named: 'pageable')),
      ).thenAnswer(
        (_) async => _ok(<api.FavoriteServiceResponse>[
          api.FavoriteServiceResponse(
            (api.FavoriteServiceResponseBuilder b) => b..serviceName = 'X',
          ),
        ]),
      );

      expect(await repo.getMyWishlist(), isEmpty);
    });

    test(
      'a malformed row does NOT cost its good neighbours on the same page',
      () async {
        when(
          () => apiMock.listServiceFavorites(pageable: any(named: 'pageable')),
        ).thenAnswer(
          (_) async => _ok(<api.FavoriteServiceResponse>[
            _row(id: 'a'),
            // Missing masterServiceId/masterId — the malformed row.
            api.FavoriteServiceResponse(
              (api.FavoriteServiceResponseBuilder b) => b..serviceName = 'X',
            ),
            _row(id: 'b'),
          ]),
        );

        final List<WishlistService> out = await repo.getMyWishlist();
        expect(
          out.map((WishlistService s) => s.favoriteTargetId).toList(),
          <String>['a', 'b'],
        );
      },
    );
  });

  group('should_mapNetworkFailure_when_dioTimesOut', () {
    for (final DioExceptionType type in <DioExceptionType>[
      DioExceptionType.connectionError,
      DioExceptionType.connectionTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.receiveTimeout,
    ]) {
      test('$type → NetworkFailure', () async {
        when(
          () => apiMock.listServiceFavorites(pageable: any(named: 'pageable')),
        ).thenAnswer((_) async => throw _dio(type));

        await expectLater(repo.getMyWishlist(), throwsA(isA<NetworkFailure>()));
      });
    }
  });

  group('other transport errors', () {
    test('a 500 becomes a ServerFailure carrying the status', () async {
      when(
        () => apiMock.listServiceFavorites(pageable: any(named: 'pageable')),
      ).thenAnswer(
        (_) async => throw _dio(DioExceptionType.badResponse, status: 500),
      );

      await expectLater(
        repo.getMyWishlist(),
        throwsA(
          isA<ServerFailure>().having(
            (ServerFailure f) => f.statusCode,
            'statusCode',
            500,
          ),
        ),
      );
    });

    test(
      'an interceptor-attached Failure is preferred over the Dio type',
      () async {
        const NotFoundFailure attached = NotFoundFailure();
        when(
          () => apiMock.listServiceFavorites(pageable: any(named: 'pageable')),
        ).thenAnswer(
          (_) async => throw _dio(
            DioExceptionType.badResponse,
            status: 404,
            error: attached,
          ),
        );

        await expectLater(repo.getMyWishlist(), throwsA(same(attached)));
      },
    );

    test('a raw DioException never escapes', () async {
      when(
        () => apiMock.listServiceFavorites(pageable: any(named: 'pageable')),
      ).thenAnswer((_) async => throw _dio(DioExceptionType.unknown));

      await expectLater(repo.getMyWishlist(), throwsA(isA<Failure>()));
      await expectLater(
        repo.getMyWishlist(),
        throwsA(isNot(isA<DioException>())),
      );
    });
  });
}

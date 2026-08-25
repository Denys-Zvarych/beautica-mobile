// Phase 110 (13.9) wire-up — mobile-qa gap-closure — TIER 2 unit tests for
// [HttpTimelineRepository].
//
// WHY THIS FILE EXISTS
// --------------------
// `beautyTimelineProvider` used to be a hard-coded placeholder returning
// `const <TimelineEntry>[]` — nothing in `test/` ever called the network, so
// the endpoint that had been live since backend 19.5 was never exercised by
// the app. This file pins the transport half of the chain the same way
// `test/features/passport/data/passport_repository_test.dart` pins
// `HttpPassportRepository` — the header there literally says this repository
// "mirrors [HttpPassportRepository] exactly", so this file matches that
// one's structure rather than inventing a different shape.
//
// Strategy: mocktail-mock the generated [ClientControllerApi]. No real Dio,
// no ProviderScope, no widget tree.
//
// FAILURE SHAPE: every `thenAnswer((_) async => throw …)`, never `thenThrow`.
// A Dio-backed call ALWAYS fails asynchronously; a synchronous throw is a
// shape the real transport cannot produce. It happens not to matter for this
// plain class (no Riverpod retry machinery is in play here — that lives one
// layer up, in `beautyTimelineProvider`, covered by the widget/integration
// tiers), but matching the real shape costs nothing and keeps the two
// "retry" mechanisms in this codebase from being conflated (see
// `passport_repository_test.dart`'s own header for the same note).

import 'package:beautica_api/beautica_api.dart' as api;
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/home/data/timeline_repository.dart';
import 'package:beautica_mobile/features/home/domain/home_hub_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockClientControllerApi extends Mock
    implements api.ClientControllerApi {}

const String _path = '/api/v1/clients/me/timeline';

RequestOptions _reqOptions() => RequestOptions(path: _path);

/// The exact page the repository must request — `page=0, size=20` — per the
/// explicit-size policy documented on `HttpTimelineRepository._pageSize`: a
/// future backend `@PageableDefault` change must never silently resize the
/// rail. Used both to STUB the mock permissively (`any()`) and, via
/// `captureAny`, to pin the actually-sent value without over-constraining
/// the stub match.
api.Pageable _pageable({required int page, required int size}) => api.Pageable(
  (b) => b
    ..page = page
    ..size = size,
);

/// A fully populated 200 envelope carrying two rows.
Response<api.ApiResponsePageResponseTimelineItemResponse> _okPopulated() =>
    Response<api.ApiResponsePageResponseTimelineItemResponse>(
      requestOptions: _reqOptions(),
      statusCode: 200,
      data: api.ApiResponsePageResponseTimelineItemResponse(
        (b) => b
          ..success = true
          ..data.success = true
          ..data.page = 0
          ..data.size = 20
          ..data.totalElements = 2
          ..data.totalPages = 1
          ..data.data.replace(<api.TimelineItemResponse>[
            api.TimelineItemResponse(
              (tb) => tb
                ..bookingId = 'bkg-1'
                ..categoryKey = 'NAIL_SERVICE'
                ..categoryName = 'Манікюр'
                ..date = api.Date(2026, 6, 18)
                ..masterId = 'master-1'
                ..serviceName = 'Класичний манікюр',
            ),
            api.TimelineItemResponse(
              (tb) => tb
                ..bookingId = 'bkg-2'
                ..categoryKey = 'BROW'
                ..categoryName = 'Брови'
                ..date = api.Date(2026, 5, 12)
                ..masterId = 'master-1'
                ..serviceName = 'Корекція брів',
            ),
          ]),
      ),
    );

/// A 200 whose page envelope carries NO rows list at all (`data.data`
/// untouched) — an ABSENT rows list, distinct from an empty one, but the
/// repository must treat both identically: an empty timeline, not an error.
Response<api.ApiResponsePageResponseTimelineItemResponse> _okAbsentRows() =>
    Response<api.ApiResponsePageResponseTimelineItemResponse>(
      requestOptions: _reqOptions(),
      statusCode: 200,
      data: api.ApiResponsePageResponseTimelineItemResponse(
        (b) => b
          ..success = true
          ..data.success = true
          ..data.page = 0
          ..data.size = 20,
      ),
    );

/// A 200 whose outer envelope carries a null `data` (the page itself is
/// missing) — a malformed success the repository must convert into a
/// [ServerFailure] rather than dereference.
Response<api.ApiResponsePageResponseTimelineItemResponse> _okNullData() =>
    Response<api.ApiResponsePageResponseTimelineItemResponse>(
      requestOptions: _reqOptions(),
      statusCode: 200,
      data: api.ApiResponsePageResponseTimelineItemResponse(
        (b) => b..success = true,
      ),
    );

DioException _dioError(
  DioExceptionType type, {
  int? statusCode,
  Object? error,
}) => DioException(
  requestOptions: _reqOptions(),
  type: type,
  error: error,
  response: statusCode == null
      ? null
      : Response<dynamic>(
          requestOptions: _reqOptions(),
          statusCode: statusCode,
        ),
);

void main() {
  late _MockClientControllerApi clientApi;
  late HttpTimelineRepository repository;

  setUpAll(() {
    // Needed because `any(named: 'pageable')` / `captureAny(named:
    // 'pageable')` are used below with a Built-value argument type.
    registerFallbackValue(_pageable(page: 0, size: 1));
  });

  setUp(() {
    clientApi = _MockClientControllerApi();
    repository = HttpTimelineRepository(clientApi);
  });

  group('HttpTimelineRepository.getMyTimeline — the requested page', () {
    // THE PIN mobile-security's MEDIUM finding named directly: nothing
    // proved the repository actually requests `page=0, size=20` rather than
    // relying on the endpoint's own `@PageableDefault`. Captures the REAL
    // argument rather than stubbing an exact-equality `Pageable` so a
    // built_value equality quirk can't mask a mismatch either way.
    test('requests page=0, size=20 explicitly — never relies on the backend '
        'default', () async {
      when(
        () => clientApi.getTimeline(pageable: any(named: 'pageable')),
      ).thenAnswer((_) async => _okPopulated());

      await repository.getMyTimeline();

      final captured = verify(
        () => clientApi.getTimeline(pageable: captureAny(named: 'pageable')),
      ).captured;
      expect(captured, hasLength(1));
      final api.Pageable sent = captured.single as api.Pageable;
      expect(sent.page, 0, reason: 'the rail always requests the FIRST page');
      expect(
        sent.size,
        20,
        reason:
            'the rail pins size=20 explicitly so a future backend '
            '@PageableDefault change cannot silently resize it',
      );
    });
  });

  group('HttpTimelineRepository.getMyTimeline — success', () {
    // THE HEADLINE REGRESSION GUARD at this tier. The deleted placeholder
    // satisfied the same shape while calling nothing and returning
    // `const <TimelineEntry>[]` unconditionally. Both halves of this test
    // kill it: the `verify` proves the endpoint is actually hit, and the
    // value assertions prove the response reaches the domain model.
    test('calls the API once and maps the populated envelope to the domain, '
        'most-recent-first', () async {
      when(
        () => clientApi.getTimeline(pageable: any(named: 'pageable')),
      ).thenAnswer((_) async => _okPopulated());

      final List<TimelineEntry> entries = await repository.getMyTimeline();

      verify(
        () => clientApi.getTimeline(pageable: any(named: 'pageable')),
      ).called(1);
      expect(entries, hasLength(2));
      // 18 Jun is more recent than 12 May — even though the fixture above
      // already lists it first, this pins the REPOSITORY's end-to-end
      // output (mapper sort included), not just the wire order.
      expect(entries.first.category, 'Манікюр');
      expect(entries.last.category, 'Брови');
    });

    // An ABSENT rows list (the envelope itself arrived, but carries no
    // `data` array) is an EMPTY timeline, not an error — see
    // `timeline_repository.dart`'s inline comment on this exact branch.
    test('a page envelope with an ABSENT rows list resolves to an empty list, '
        'not a throw', () async {
      when(
        () => clientApi.getTimeline(pageable: any(named: 'pageable')),
      ).thenAnswer((_) async => _okAbsentRows());

      final List<TimelineEntry> entries = await repository.getMyTimeline();

      expect(entries, isEmpty);
    });
  });

  group('HttpTimelineRepository.getMyTimeline — failure mapping', () {
    test('a 200 with a null envelope body throws ServerFailure', () async {
      when(
        () => clientApi.getTimeline(pageable: any(named: 'pageable')),
      ).thenAnswer((_) async => _okNullData());

      await expectLater(
        repository.getMyTimeline(),
        throwsA(isA<ServerFailure>()),
      );
    });

    test(
      'a 500 badResponse throws ServerFailure carrying the status code',
      () async {
        when(
          () => clientApi.getTimeline(pageable: any(named: 'pageable')),
        ).thenAnswer(
          (_) async =>
              throw _dioError(DioExceptionType.badResponse, statusCode: 500),
        );

        await expectLater(
          repository.getMyTimeline(),
          throwsA(
            isA<ServerFailure>().having((f) => f.statusCode, 'statusCode', 500),
          ),
        );
      },
    );

    test('a cancel DioExceptionType throws ServerFailure (badResponse/cancel/'
        'badCertificate/unknown all map together)', () async {
      when(
        () => clientApi.getTimeline(pageable: any(named: 'pageable')),
      ).thenAnswer((_) async => throw _dioError(DioExceptionType.cancel));

      await expectLater(
        repository.getMyTimeline(),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('a badCertificate DioExceptionType throws ServerFailure', () async {
      when(
        () => clientApi.getTimeline(pageable: any(named: 'pageable')),
      ).thenAnswer(
        (_) async => throw _dioError(DioExceptionType.badCertificate),
      );

      await expectLater(
        repository.getMyTimeline(),
        throwsA(isA<ServerFailure>()),
      );
    });

    test(
      'a connectionError throws NetworkFailure, NOT ServerFailure',
      () async {
        when(
          () => clientApi.getTimeline(pageable: any(named: 'pageable')),
        ).thenAnswer(
          (_) async => throw _dioError(DioExceptionType.connectionError),
        );

        await expectLater(
          repository.getMyTimeline(),
          throwsA(isA<NetworkFailure>()),
        );
      },
    );

    test('a connectionTimeout throws NetworkFailure', () async {
      when(
        () => clientApi.getTimeline(pageable: any(named: 'pageable')),
      ).thenAnswer(
        (_) async => throw _dioError(DioExceptionType.connectionTimeout),
      );

      await expectLater(
        repository.getMyTimeline(),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('a sendTimeout throws NetworkFailure', () async {
      when(
        () => clientApi.getTimeline(pageable: any(named: 'pageable')),
      ).thenAnswer((_) async => throw _dioError(DioExceptionType.sendTimeout));

      await expectLater(
        repository.getMyTimeline(),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('a receiveTimeout throws NetworkFailure', () async {
      when(
        () => clientApi.getTimeline(pageable: any(named: 'pageable')),
      ).thenAnswer(
        (_) async => throw _dioError(DioExceptionType.receiveTimeout),
      );

      await expectLater(
        repository.getMyTimeline(),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('a Failure already attached by ErrorMapperInterceptor is rethrown '
        'as-is (the e.error is Failure passthrough)', () async {
      // The shared interceptor maps 401 → UnauthorizedFailure and hangs it
      // on `DioException.error`. The repository must surface THAT, not
      // flatten it into a generic ServerFailure — an expired session has
      // to stay distinguishable from a server fault.
      when(
        () => clientApi.getTimeline(pageable: any(named: 'pageable')),
      ).thenAnswer(
        (_) async => throw _dioError(
          DioExceptionType.badResponse,
          statusCode: 401,
          error: const UnauthorizedFailure(),
        ),
      );

      await expectLater(
        repository.getMyTimeline(),
        throwsA(isA<UnauthorizedFailure>()),
      );
    });

    test('a raw DioException never escapes the repository', () async {
      when(
        () => clientApi.getTimeline(pageable: any(named: 'pageable')),
      ).thenAnswer((_) async => throw _dioError(DioExceptionType.unknown));

      // The screen's error state is driven by typed failures; a leaked
      // DioException would bypass every `on Failure` handler upstream.
      await expectLater(
        repository.getMyTimeline(),
        throwsA(allOf(isA<Failure>(), isNot(isA<DioException>()))),
      );
    });

    test(
      'does NOT retry internally — one failed GET is one API call',
      () async {
        when(
          () => clientApi.getTimeline(pageable: any(named: 'pageable')),
        ).thenAnswer(
          (_) async =>
              throw _dioError(DioExceptionType.badResponse, statusCode: 500),
        );

        await expectLater(repository.getMyTimeline(), throwsA(isA<Failure>()));

        // The retry affordance is the SCREEN's (`_CardErrorState`'s
        // `ref.invalidate(beautyTimelineProvider)`); a hidden loop here
        // would multiply load and desync the two mechanisms.
        verify(
          () => clientApi.getTimeline(pageable: any(named: 'pageable')),
        ).called(1);
      },
    );
  });
}

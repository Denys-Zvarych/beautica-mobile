// Phase 13.8 wire-up — TIER 2 unit tests for [HttpPassportRepository].
//
// WHY THIS FILE EXISTS
// --------------------
// `HttpPassportRepository` did not exist before the wire-up: the provider bound
// a `PlaceholderPassportRepository` whose `getMyPassport()` returned
// `Passport.empty(memberSinceYear: 2024)` unconditionally and never touched the network. There was
// therefore no repository test at all, and the endpoint that had been live
// since backend 19.5 was never called by the app. This file pins the transport
// half of the chain — the API is actually invoked, its envelope is unwrapped,
// and every transport error becomes a TYPED [Failure] rather than a raw
// [DioException] leaking to the screen.
//
// Strategy: mocktail-mock the generated [ClientControllerApi]. No real Dio, no
// ProviderScope, no widget tree.
//
// FAILURE SHAPE: every `thenAnswer((_) async => throw …)`, never `thenThrow`.
// A Dio-backed call ALWAYS fails asynchronously; a synchronous throw is a shape
// the real transport cannot produce. It happens not to matter for this plain
// class (no Riverpod retry machinery is in play here — that lives one layer up,
// see passport_wireup_test.dart), but matching the real shape costs nothing and
// keeps the two "retry" mechanisms in this codebase from being conflated.

import 'package:beautica_api/beautica_api.dart' as api;
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/passport/data/passport_repository.dart';
import 'package:beautica_mobile/features/passport/domain/passport.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockClientControllerApi extends Mock
    implements api.ClientControllerApi {}

const String _path = '/api/v1/clients/me/passport';

RequestOptions _reqOptions() => RequestOptions(path: _path);

/// A fully populated 200 envelope. Deliberately distinguishable from
/// [Passport.empty] in EVERY field asserted downstream, so no assertion can
/// pass by coincidentally matching the empty passport.
Response<api.ApiResponsePassportResponse> _okPopulated() =>
    Response<api.ApiResponsePassportResponse>(
      requestOptions: _reqOptions(),
      statusCode: 200,
      data: api.ApiResponsePassportResponse(
        (b) => b
          ..success = true
          ..data.favoriteDistricts.replace(<String>['Центр', 'Сихів'])
          ..data.favoriteCities.replace(<String>['Львів', 'Київ'])
          ..data.bookingsConsidered = 7
          ..data.reviewsWritten = 3
          ..data.memberSinceYear = 2021
          ..data.budget.avg = 600
          ..data.budget.min = 400
          ..data.budget.max = 800
          ..data.budget.currency = 'UAH',
      ),
    );

/// A 200 whose envelope carries a null `data` — a malformed success the
/// repository must convert into a [ServerFailure] rather than dereference.
Response<api.ApiResponsePassportResponse> _okNullData() =>
    Response<api.ApiResponsePassportResponse>(
      requestOptions: _reqOptions(),
      statusCode: 200,
      data: api.ApiResponsePassportResponse((b) => b..success = true),
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
  late HttpPassportRepository repository;

  setUp(() {
    clientApi = _MockClientControllerApi();
    repository = HttpPassportRepository(clientApi);
  });

  group('HttpPassportRepository.getMyPassport — success', () {
    // THE HEADLINE REGRESSION GUARD at this tier. The deleted placeholder
    // satisfied the same `PassportRepository` interface while calling nothing
    // and returning `Passport.empty(memberSinceYear: 2024)`. Both halves of this test kill it: the
    // `verify` proves the endpoint is actually hit, and the value assertions
    // prove the response reaches the domain model.
    test(
      'calls the API once and maps the populated envelope to the domain',
      () async {
        when(
          () => clientApi.getPassport(),
        ).thenAnswer((_) async => _okPopulated());

        final Passport p = await repository.getMyPassport();

        verify(() => clientApi.getPassport()).called(1);
        expect(p.favoriteDistricts, <String>['Центр', 'Сихів']);
        expect(p.bookingsConsidered, 7);
        expect(p.budget!.max, 800.0);
        expect(p.budget!.currency, 'UAH');
        expect(
          p.isEmpty,
          isFalse,
          reason:
              'a populated response must not read as the empty passport — the '
              'placeholder repository this replaced returned Passport.empty(memberSinceYear: 2024) '
              'for every client, forever',
        );
      },
    );

    test('maps a genuinely empty envelope to the empty passport', () async {
      when(() => clientApi.getPassport()).thenAnswer(
        (_) async => Response<api.ApiResponsePassportResponse>(
          requestOptions: _reqOptions(),
          statusCode: 200,
          data: api.ApiResponsePassportResponse(
            (b) => b
              ..success = true
              ..data.favoriteDistricts.replace(const <String>[])
              ..data.favoriteCities.replace(const <String>[])
              ..data.bookingsConsidered = 0
              ..data.reviewsWritten = 0
              ..data.memberSinceYear = 2024,
          ),
        ),
      );

      final Passport p = await repository.getMyPassport();

      expect(p, Passport.empty(memberSinceYear: 2024));
      expect(p.isEmpty, isTrue);
    });
  });

  group('HttpPassportRepository.getMyPassport — failure mapping', () {
    test('a 200 with a null envelope body throws ServerFailure', () async {
      when(
        () => clientApi.getPassport(),
      ).thenAnswer((_) async => _okNullData());

      await expectLater(
        repository.getMyPassport(),
        throwsA(isA<ServerFailure>()),
      );
    });

    test(
      'a 500 badResponse throws ServerFailure carrying the status code',
      () async {
        when(() => clientApi.getPassport()).thenAnswer(
          (_) async =>
              throw _dioError(DioExceptionType.badResponse, statusCode: 500),
        );

        await expectLater(
          repository.getMyPassport(),
          throwsA(
            isA<ServerFailure>().having((f) => f.statusCode, 'statusCode', 500),
          ),
        );
      },
    );

    test(
      'a connectionError throws NetworkFailure, NOT ServerFailure',
      () async {
        when(() => clientApi.getPassport()).thenAnswer(
          (_) async => throw _dioError(DioExceptionType.connectionError),
        );

        await expectLater(
          repository.getMyPassport(),
          throwsA(isA<NetworkFailure>()),
        );
      },
    );

    test('a receiveTimeout throws NetworkFailure', () async {
      when(() => clientApi.getPassport()).thenAnswer(
        (_) async => throw _dioError(DioExceptionType.receiveTimeout),
      );

      await expectLater(
        repository.getMyPassport(),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test(
      'a Failure already attached by ErrorMapperInterceptor is rethrown as-is',
      () async {
        // The shared interceptor maps 401 → UnauthorizedFailure and hangs it on
        // `DioException.error`. The repository must surface THAT, not flatten
        // it into a generic ServerFailure — an expired session has to stay
        // distinguishable from a server fault.
        when(() => clientApi.getPassport()).thenAnswer(
          (_) async => throw _dioError(
            DioExceptionType.badResponse,
            statusCode: 401,
            error: const UnauthorizedFailure(),
          ),
        );

        await expectLater(
          repository.getMyPassport(),
          throwsA(isA<UnauthorizedFailure>()),
        );
      },
    );

    test('a raw DioException never escapes the repository', () async {
      when(
        () => clientApi.getPassport(),
      ).thenAnswer((_) async => throw _dioError(DioExceptionType.unknown));

      // The screen's error state is driven by typed failures; a leaked
      // DioException would bypass every `on Failure` handler upstream.
      await expectLater(
        repository.getMyPassport(),
        throwsA(allOf(isA<Failure>(), isNot(isA<DioException>()))),
      );
    });

    test(
      'does NOT retry internally — one failed GET is one API call',
      () async {
        when(() => clientApi.getPassport()).thenAnswer(
          (_) async =>
              throw _dioError(DioExceptionType.badResponse, statusCode: 500),
        );

        await expectLater(repository.getMyPassport(), throwsA(isA<Failure>()));

        // The retry affordance is the SCREEN's (`passport_retry_button`); a
        // hidden loop here would multiply load and desync the two mechanisms.
        verify(() => clientApi.getPassport()).called(1);
      },
    );
  });
}

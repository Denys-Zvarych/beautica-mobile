// Unit tests for HttpUserRepository.deleteMyAccount's error mapping
// (`_mapDeleteAccountException`, user_repository.dart).
//
// Phase 489 — a 409 whose body carries `data.code == OWNER_HAS_ACTIVE_SALONS`
// maps to AccountDeleteOwnerHasActiveSalonsFailure; every OTHER 409 keeps the
// failure the ErrorMapperInterceptor already attached (unchanged behaviour).
// The 422 / 429 arms are pinned alongside so the new 409 arm's position in
// the chain cannot silently shadow them.
//
// The generated UserControllerApi is mocked (mocktail); failures are thrown
// ASYNCHRONOUSLY (`thenAnswer((_) async => throw …)`) — the shape a real Dio
// call has (M13). Layer: Unit.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/user/data/user_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDio extends Mock implements Dio {}

class _MockUserApi extends Mock implements UserControllerApi {}

final RequestOptions _req = RequestOptions(path: '/api/v1/users/me');

/// A `DELETE /users/me` bad response with [status] and [body], carrying
/// [attached] as `e.error` (what ErrorMapperInterceptor sets in the app).
DioException _badResponse(int status, Object? body, {Object? attached}) =>
    DioException(
      requestOptions: _req,
      type: DioExceptionType.badResponse,
      error: attached,
      response: Response<Object?>(
        requestOptions: _req,
        statusCode: status,
        data: body,
      ),
    );

Map<String, dynamic> _envelopeWithCode(String code) => <String, dynamic>{
  'success': false,
  'data': <String, dynamic>{'code': code},
  'message': 'conflict',
};

void main() {
  late _MockUserApi api;
  late HttpUserRepository repo;

  setUp(() {
    api = _MockUserApi();
    repo = HttpUserRepository(_MockDio(), api);
  });

  void stubThrow(DioException e) {
    when(() => api.deleteMyAccount()).thenAnswer((_) async => throw e);
  }

  group('deleteMyAccount — phase 489 409 mapping', () {
    test(
      '409 OWNER_HAS_ACTIVE_SALONS → '
      'AccountDeleteOwnerHasActiveSalonsFailure carrying the DioException',
      () async {
        final DioException e = _badResponse(
          409,
          _envelopeWithCode(kOwnerHasActiveSalonsCode),
          attached: const ServerFailure(statusCode: 409),
        );
        stubThrow(e);

        final Object? thrown = await repo.deleteMyAccount().then<Object?>(
          (_) => null,
          onError: (Object err) => err,
        );

        expect(thrown, isA<AccountDeleteOwnerHasActiveSalonsFailure>());
        expect((thrown! as Failure).cause, same(e));
        verify(() => api.deleteMyAccount()).called(1);
      },
    );

    test('409 with a DIFFERENT data.code keeps the interceptor failure '
        '(unchanged)', () async {
      const ServerFailure attached = ServerFailure(statusCode: 409);
      stubThrow(
        _badResponse(
          409,
          _envelopeWithCode('SOME_OTHER_CONFLICT'),
          attached: attached,
        ),
      );

      await expectLater(repo.deleteMyAccount(), throwsA(same(attached)));
    });

    test(
      '409 with no body keeps the interceptor failure (unchanged)',
      () async {
        const ServerFailure attached = ServerFailure(statusCode: 409);
        stubThrow(_badResponse(409, null, attached: attached));

        await expectLater(repo.deleteMyAccount(), throwsA(same(attached)));
      },
    );

    test('409 whose `data` is not a map (code at top level) is NOT the '
        'owner failure', () async {
      const ServerFailure attached = ServerFailure(statusCode: 409);
      stubThrow(
        _badResponse(409, <String, dynamic>{
          'success': false,
          'code': kOwnerHasActiveSalonsCode,
          'data': null,
        }, attached: attached),
      );

      await expectLater(repo.deleteMyAccount(), throwsA(same(attached)));
    });

    test('OWNER_HAS_ACTIVE_SALONS body on a NON-409 status is NOT the owner '
        'failure', () async {
      const ServerFailure attached = ServerFailure(statusCode: 400);
      stubThrow(
        _badResponse(
          400,
          _envelopeWithCode(kOwnerHasActiveSalonsCode),
          attached: attached,
        ),
      );

      await expectLater(repo.deleteMyAccount(), throwsA(same(attached)));
    });

    test('409 OWNER_HAS_ACTIVE_SALONS with no interceptor failure attached '
        'still maps to the owner failure', () async {
      stubThrow(
        _badResponse(409, _envelopeWithCode(kOwnerHasActiveSalonsCode)),
      );

      await expectLater(
        repo.deleteMyAccount(),
        throwsA(isA<AccountDeleteOwnerHasActiveSalonsFailure>()),
      );
    });
  });

  group('deleteMyAccount — neighbouring arms stay intact', () {
    test('success resolves and calls the API once', () async {
      when(() => api.deleteMyAccount()).thenAnswer(
        (_) async => Response<void>(requestOptions: _req, statusCode: 204),
      );

      await repo.deleteMyAccount();

      verify(() => api.deleteMyAccount()).called(1);
    });

    test(
      '422 → AccountDeleteBookingLimitFailure with the server message',
      () async {
        stubThrow(
          _badResponse(
            422,
            null,
            attached: const ValidationFailure(
              fieldErrors: <String, String>{},
              serverMessage: 'Понад 50 записів',
            ),
          ),
        );

        final Object? thrown = await repo.deleteMyAccount().then<Object?>(
          (_) => null,
          onError: (Object err) => err,
        );

        expect(thrown, isA<AccountDeleteBookingLimitFailure>());
        expect(
          (thrown! as AccountDeleteBookingLimitFailure).serverMessage,
          'Понад 50 записів',
        );
      },
    );

    test('429 → AccountDeleteRateLimitedFailure', () async {
      stubThrow(_badResponse(429, null));

      await expectLater(
        repo.deleteMyAccount(),
        throwsA(isA<AccountDeleteRateLimitedFailure>()),
      );
    });

    test('connection error → NetworkFailure', () async {
      stubThrow(
        DioException(
          requestOptions: _req,
          type: DioExceptionType.connectionError,
        ),
      );

      await expectLater(repo.deleteMyAccount(), throwsA(isA<NetworkFailure>()));
    });
  });
}

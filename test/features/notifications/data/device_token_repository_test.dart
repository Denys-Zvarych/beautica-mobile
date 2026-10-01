// Phase 067 — DeviceTokenRepository: wire bodies + Failure mapping.

import 'package:beautica_api/beautica_api.dart' as api;
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/notifications/data/device_token_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockApi extends Mock implements api.DeviceControllerApi {}

RequestOptions _ro() => RequestOptions(path: '/api/v1/devices/token');

Response<void> _ok() => Response<void>(requestOptions: _ro(), statusCode: 204);

void main() {
  setUpAll(() {
    registerFallbackValue(
      api.RegisterDeviceTokenRequest(
        (b) => b
          ..token = 't'
          ..platform = 'ANDROID',
      ),
    );
    registerFallbackValue(
      api.UnregisterDeviceTokenRequest((b) => b..token = 't'),
    );
  });

  test('register sends {token, platform: ANDROID}', () async {
    final mock = _MockApi();
    when(
      () => mock.registerToken(
        registerDeviceTokenRequest: any(named: 'registerDeviceTokenRequest'),
      ),
    ).thenAnswer((_) async => _ok());

    await HttpDeviceTokenRepository(mock).register('abc:DEF-1_2');

    final req =
        verify(
              () => mock.registerToken(
                registerDeviceTokenRequest: captureAny(
                  named: 'registerDeviceTokenRequest',
                ),
              ),
            ).captured.single
            as api.RegisterDeviceTokenRequest;
    expect(req.token, 'abc:DEF-1_2');
    expect(req.platform, 'ANDROID');
  });

  test('register threads the CancelToken to the API call', () async {
    final mock = _MockApi();
    final cancel = CancelToken();
    when(
      () => mock.registerToken(
        registerDeviceTokenRequest: any(named: 'registerDeviceTokenRequest'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async => _ok());

    await HttpDeviceTokenRepository(mock).register('t', cancelToken: cancel);

    verify(
      () => mock.registerToken(
        registerDeviceTokenRequest: any(named: 'registerDeviceTokenRequest'),
        cancelToken: cancel,
      ),
    ).called(1);
  });

  test('a register aborted through its CancelToken throws '
      'DeviceTokenRegisterCancelled, not a Failure', () async {
    final mock = _MockApi();
    final cancel = CancelToken();
    when(
      () => mock.registerToken(
        registerDeviceTokenRequest: any(named: 'registerDeviceTokenRequest'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenThrow(
      DioException.requestCancelled(requestOptions: _ro(), reason: 'x'),
    );

    await expectLater(
      HttpDeviceTokenRepository(mock).register('t', cancelToken: cancel),
      throwsA(isA<DeviceTokenRegisterCancelled>()),
    );
  });

  test('a non-cancel register failure is still a ServerFailure', () async {
    final mock = _MockApi();
    when(
      () => mock.registerToken(
        registerDeviceTokenRequest: any(named: 'registerDeviceTokenRequest'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenThrow(
      DioException(
        requestOptions: _ro(),
        type: DioExceptionType.badResponse,
        response: Response<void>(requestOptions: _ro(), statusCode: 500),
      ),
    );

    await expectLater(
      HttpDeviceTokenRepository(mock).register('t'),
      throwsA(isA<ServerFailure>()),
    );
  });

  test('unregister sends {token}', () async {
    final mock = _MockApi();
    when(
      () => mock.unregisterToken(
        unregisterDeviceTokenRequest: any(
          named: 'unregisterDeviceTokenRequest',
        ),
        headers: any(named: 'headers'),
      ),
    ).thenAnswer((_) async => _ok());

    await HttpDeviceTokenRepository(mock).unregister('tok');

    // A forced logout DELETEs with a possibly dead access token: the 401 must
    // not re-enter RefreshInterceptor (refresh -> nested logout).
    final captured = verify(
      () => mock.unregisterToken(
        unregisterDeviceTokenRequest: captureAny(
          named: 'unregisterDeviceTokenRequest',
        ),
        headers: captureAny(named: 'headers'),
      ),
    ).captured;
    final req = captured[0] as api.UnregisterDeviceTokenRequest;
    expect((captured[1] as Map<String, dynamic>)['X-No-Retry'], 'true');
    expect(req.token, 'tok');
  });

  test('DioException maps to a typed Failure (never raw)', () async {
    final mock = _MockApi();
    when(
      () => mock.registerToken(
        registerDeviceTokenRequest: any(named: 'registerDeviceTokenRequest'),
      ),
    ).thenThrow(
      DioException(
        requestOptions: _ro(),
        type: DioExceptionType.connectionError,
      ),
    );
    await expectLater(
      HttpDeviceTokenRepository(mock).register('t'),
      throwsA(isA<NetworkFailure>()),
    );

    when(
      () => mock.registerToken(
        registerDeviceTokenRequest: any(named: 'registerDeviceTokenRequest'),
      ),
    ).thenThrow(
      DioException(
        requestOptions: _ro(),
        type: DioExceptionType.badResponse,
        response: Response<void>(requestOptions: _ro(), statusCode: 500),
      ),
    );
    await expectLater(
      HttpDeviceTokenRepository(mock).register('t'),
      throwsA(isA<ServerFailure>()),
    );
  });
}

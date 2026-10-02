// Phase 067 — FCM device-token registration over the generated
// [DeviceControllerApi] (`POST` / `DELETE /api/v1/devices/token`, both 204).
//
// Registration is an idempotent upsert on the backend: re-registering a token
// that belongs to another account (shared device) rebinds it to the caller.
// Methods throw a typed [Failure]; callers swallow it (D3). The token value is
// NEVER logged.

import 'package:beautica_api/beautica_api.dart' as api;
import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/errors/failures.dart';
import '../../../core/network/api_client_provider.dart';

part 'device_token_repository.g.dart';

/// Wire value of the only platform push supports (backend `DevicePlatform`).
const String kDevicePlatformAndroid = 'ANDROID';

/// A register POST aborted through its own [CancelToken] (logout / user
/// switch). An intentional outcome, NOT a server fault: deliberately not a
/// [Failure], so callers can tell it apart and never log it as an error.
final class DeviceTokenRegisterCancelled implements Exception {
  const DeviceTokenRegisterCancelled();

  @override
  String toString() => 'DeviceTokenRegisterCancelled';
}

abstract interface class DeviceTokenRepository {
  /// Registers (or rebinds to the caller) [token]. Idempotent.
  ///
  /// [cancelToken] aborts the in-flight POST (logout / user switch); the
  /// aborted call throws [DeviceTokenRegisterCancelled] (not a [Failure]).
  Future<void> register(String token, {CancelToken? cancelToken});

  /// Deactivates [token] for the caller. Idempotent.
  Future<void> unregister(String token);
}

final class HttpDeviceTokenRepository implements DeviceTokenRepository {
  HttpDeviceTokenRepository(this._api);

  final api.DeviceControllerApi _api;

  @override
  Future<void> register(String token, {CancelToken? cancelToken}) async {
    try {
      await _guard(() async {
        await _api.registerToken(
          cancelToken: cancelToken,
          registerDeviceTokenRequest: api.RegisterDeviceTokenRequest(
            (b) => b
              ..token = token
              ..platform = kDevicePlatformAndroid,
          ),
        );
      });
    } on Failure catch (f) {
      final Object? cause = f is ServerFailure ? f.cause : null;
      if (cause is DioException && cause.type == DioExceptionType.cancel) {
        throw const DeviceTokenRegisterCancelled();
      }
      rethrow;
    }
  }

  @override
  Future<void> unregister(String token) => _guard(() async {
    await _api.unregisterToken(
      unregisterDeviceTokenRequest: api.UnregisterDeviceTokenRequest(
        (b) => b..token = token,
      ),
      // Forced logout runs this with a possibly dead access token: a 401 must
      // NOT trigger RefreshInterceptor's refresh → nested logout().
      headers: const <String, dynamic>{'X-No-Retry': 'true'},
    );
  });

  Future<void> _guard(Future<void> Function() body) async {
    try {
      await body();
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Failure _map(DioException e) {
    if (e.error is Failure) return e.error as Failure;
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return NetworkFailure(cause: e);
      case DioExceptionType.badCertificate:
        return CertificateFailure(cause: e);
      case DioExceptionType.badResponse:
      case DioExceptionType.cancel:
      case DioExceptionType.unknown:
        return ServerFailure(statusCode: e.response?.statusCode, cause: e);
    }
  }
}

@Riverpod(keepAlive: true)
DeviceTokenRepository deviceTokenRepository(Ref ref) =>
    HttpDeviceTokenRepository(ref.watch(deviceApiProvider));

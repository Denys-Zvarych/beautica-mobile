// CLIENT profile repository — read + partial-update of the authenticated
// CLIENT's own `/users/me` profile.
//
// Mirrors [MasterRepository] in shape (interface + Http impl + provider + the
// idempotent-PATCH single-retry + DioException → typed Failure mapping). The
// two differences vs the master repository are intentional:
//   • The PATCH target is `PATCH /api/v1/users/me` (the shared, CLIENT-callable
//     profile endpoint) via the generated [UserControllerApi.updateMe], NOT the
//     master-only `/independent-masters/me*` endpoints.
//   • [updateMyProfile] NEVER sends the `instagram` key — clients have no
//     Instagram field. (The generated [UpdateProfileRequest] carries an
//     `instagram` property, but this repository leaves it unset so it is omitted
//     from the wire body.)
//
// Merge-onto-cache (partial update) contract — same discipline as the master
// edit screens: each client edit screen owns only a slice of the profile
// (Personal → name; Contacts → phone; Location → city/district/address). The
// repository builds the PATCH body by overlaying ONLY the keys the slice owns
// onto the cached profile so editing one section never clobbers another:
//   • firstName / lastName / phoneNumber are sent only when non-null on the
//     [ClientProfileUpdate] (a screen that does not own them leaves them null).
//   • the locality keys (cityId / districtId) are sent ONLY when
//     `update.touchesLocation` is true — and then EXACTLY as carried, including
//     a null cityId (CLIENT location is optional, so null clears the city). When
//     false they are omitted and the server-side location is preserved. The
//     free-text address keys (street / buildingNo / locationNote) are NEVER sent
//     from the client — the CLIENT only edits the locality cascade, so the
//     backend always preserves any existing address values.
//
// Every method either resolves successfully or throws a [Failure] subclass from
// `core/errors/failures.dart`. Raw [DioException]s are caught here and never
// escape.

import 'dart:developer';

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/api_client_provider.dart';
import 'package:beautica_mobile/features/auth/data/user_mapper.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/home/domain/client_profile_update.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'client_profile_repository.g.dart';

/// Contract for the CLIENT profile read + edit layer.
///
/// Every method either resolves successfully or throws a [Failure] subclass.
/// Raw [DioException]s are caught inside the implementation and never escape.
abstract interface class ClientProfileRepository {
  /// Fetches the authenticated CLIENT's own profile via `GET /api/v1/users/me`.
  ///
  /// The backend resolves the user from the JWT, so no id is passed. Throws a
  /// typed [Failure] on any transport or server error.
  Future<User> getMyProfile();

  /// Persists a partial update to the CLIENT's profile via
  /// `PATCH /api/v1/users/me`.
  ///
  /// Only the fields the calling edit screen owns are sent (see the merge-onto-
  /// cache contract in the file header). The `instagram` key is NEVER sent.
  /// Throws a typed [Failure] on any transport or server error; throws
  /// [ValidationFailure] with [fieldErrors] when the backend returns HTTP 422.
  Future<void> updateMyProfile(ClientProfileUpdate update);
}

/// HTTP implementation of [ClientProfileRepository].
///
/// Inject via [clientProfileRepositoryProvider] — never construct directly.
/// Both read and update go through the generated [UserControllerApi] so that
/// built_value (de)serialization handles the request/response envelopes.
final class HttpClientProfileRepository implements ClientProfileRepository {
  HttpClientProfileRepository(this._userApi);

  final UserControllerApi _userApi;

  @override
  Future<User> getMyProfile() async {
    try {
      final res = await _userApi.getMe();
      final dto = res.data?.data;
      if (dto == null) {
        if (kDebugMode) {
          log(
            'getMyProfile: ApiResponseUserProfileResponse.data is null',
            name: 'client.profile.repository',
            level: 1000,
          );
        }
        throw const ServerFailure(statusCode: null);
      }
      return UserMapper.fromProfileDto(dto);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'getMyProfile failed: ${e.type} ${e.response?.statusCode}',
          name: 'client.profile.repository',
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  @override
  Future<void> updateMyProfile(ClientProfileUpdate update) async {
    // Build the request overlaying ONLY the keys the slice owns. Built_value
    // omits any property left unset on the builder, so leaving a field untouched
    // here means the key is absent from the wire body and the server preserves
    // its current value. CRITICAL: `instagram` is never set — clients have no
    // Instagram field.
    final request = UpdateProfileRequest((b) {
      final firstName = update.firstName?.trim();
      if (firstName != null) b.firstName = firstName;

      final lastName = update.lastName?.trim();
      if (lastName != null) b.lastName = lastName;

      final phone = update.phoneNumber?.trim();
      if (phone != null && phone.isNotEmpty) b.phoneNumber = phone;

      if (update.touchesLocation) {
        // CLIENT location is OPTIONAL — send cityId/districtId exactly as
        // carried, including null (null clears the city server-side; the
        // backend's validateClientLocality permits a null city for clients).
        //
        // The free-text address keys (street / buildingNo / locationNote) are
        // deliberately NEVER set here: a CLIENT only edits the locality cascade,
        // so leaving these unset omits them from the wire body and the backend
        // preserves any existing values (Optional null-means-keep semantics).
        b.cityId = update.cityId;
        b.districtId = update.districtId;
      }
    });

    await _runIdempotentUpdate(request);
  }

  /// Runs the idempotent `PATCH /users/me` upsert with a bounded single retry
  /// for transient auth/network failures — same discipline as
  /// [HttpMasterRepository]. A transient [UnauthorizedFailure] (a 401 that
  /// triggered a token refresh) or [NetworkFailure] (a single transport hiccup)
  /// replays once; everything else surfaces on the first failure so the retry
  /// can never hide a genuine logout. All raw errors are wrapped so nothing but
  /// a [Failure] escapes.
  Future<void> _runIdempotentUpdate(UpdateProfileRequest request) async {
    var attemptedRetry = false;
    while (true) {
      try {
        await _userApi.updateMe(updateProfileRequest: request);
        return;
      } on Failure catch (f) {
        if (!attemptedRetry &&
            (f is UnauthorizedFailure || f is NetworkFailure)) {
          attemptedRetry = true;
          continue;
        }
        rethrow;
      } on DioException catch (e, st) {
        if (kDebugMode) {
          log(
            'updateMyProfile failed: ${e.type} ${e.response?.statusCode}',
            name: 'client.profile.repository',
            level: 900,
            stackTrace: st,
          );
        }
        final failure = _mapDioException(e);
        if (!attemptedRetry &&
            (failure is UnauthorizedFailure || failure is NetworkFailure)) {
          attemptedRetry = true;
          continue;
        }
        throw failure;
      } catch (e, st) {
        if (kDebugMode) {
          log(
            'updateMyProfile unexpected error: ${e.runtimeType}',
            name: 'client.profile.repository',
            level: 1000,
            error: e,
            stackTrace: st,
          );
        }
        throw ServerFailure(cause: e);
      }
    }
  }

  /// Maps a [DioException] to a typed [Failure]. If [ErrorMapperInterceptor]
  /// already attached a [Failure] as `e.error`, that value is re-thrown
  /// directly; otherwise the Dio type is inspected. Raw [DioException] never
  /// escapes.
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

/// Provides the [ClientProfileRepository] singleton backed by the generated
/// [UserControllerApi].
///
/// Override in tests with a mocktail mock — never construct
/// [HttpClientProfileRepository] directly in tests.
@Riverpod(keepAlive: true)
ClientProfileRepository clientProfileRepository(Ref ref) =>
    HttpClientProfileRepository(ref.watch(userApiProvider));

// Phase 3.2 — Riverpod providers for generated API classes.
// Phase 4.1 — Added [masterApiProvider] for [MasterControllerApi].
// Phase 13.8 wire-up — Added [clientApiProvider] for [ClientControllerApi]
// (`GET /clients/me/passport`).
// Phase 413 — Added [bookingLinksApiProvider] for [BookingLinksApi].
//
// Wires the generated API classes with the singleton [dioProvider] Dio
// instance and [standardSerializers] from the generated package. Kept alive
// because these API objects are stateless value types — keeping them alive
// avoids repeated construction on every provider read.

import 'package:beautica_api/beautica_api.dart';
import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'dio_provider.dart';

part 'api_client_provider.g.dart';

/// Provides the generated [AuthControllerApi] singleton.
///
/// Backed by the authenticated [dioProvider] Dio instance (which carries
/// the full interceptor chain) and the generated [standardSerializers] with
/// [StandardJsonPlugin] applied, so all JSON maps arrive/depart as plain
/// Dart maps with no built_value key prefixes.
@Riverpod(keepAlive: true)
AuthControllerApi authApi(Ref ref) =>
    AuthControllerApi(ref.watch(dioProvider), standardSerializers);

/// Provides the generated [UserControllerApi] singleton.
///
/// Same Dio instance and serializers as [authApiProvider].
@Riverpod(keepAlive: true)
UserControllerApi userApi(Ref ref) =>
    UserControllerApi(ref.watch(dioProvider), standardSerializers);

/// Provides the generated [MasterControllerApi] singleton.
///
/// Used by [HttpMasterRepository.getMyProfile] to fetch master profile data
/// via `GET /masters/{masterId}`. Same Dio instance and serializers as the
/// other API providers in this file.
@Riverpod(keepAlive: true)
MasterControllerApi masterApi(Ref ref) =>
    MasterControllerApi(ref.watch(dioProvider), standardSerializers);

/// Provides the generated [ClientControllerApi] singleton.
///
/// Used by `HttpPassportRepository.getMyPassport` to fetch the CLIENT's derived
/// beauty passport via `GET /clients/me/passport`. Same Dio instance and
/// serializers as the other API providers in this file.
@Riverpod(keepAlive: true)
ClientControllerApi clientApi(Ref ref) =>
    ClientControllerApi(ref.watch(dioProvider), standardSerializers);

/// Provides the generated [NotificationsApi] singleton (phase 359) for the
/// in-app notification feed. The generated enums carry an
/// `unknown_default_open_api` fallback, so `standardSerializers` already
/// tolerates a new backend `type` / `kind`.
@Riverpod(keepAlive: true)
NotificationsApi notificationsApi(Ref ref) =>
    NotificationsApi(ref.watch(dioProvider), standardSerializers);

/// Provides the generated [DeviceControllerApi] singleton (phase 067) for FCM
/// token registration (`POST` / `DELETE /devices/token`).
@Riverpod(keepAlive: true)
DeviceControllerApi deviceApi(Ref ref) =>
    DeviceControllerApi(ref.watch(dioProvider), standardSerializers);

/// Provides the generated [BookingLinksApi] singleton (phase 413) for
/// `GET /booking-links/mine` — the caller's shareable public booking links.
@Riverpod(keepAlive: true)
BookingLinksApi bookingLinksApi(Ref ref) =>
    BookingLinksApi(ref.watch(dioProvider), standardSerializers);

/// How long the forced-update check may wait for `GET /app/config` (phase 438
/// D2) before the gate fails OPEN.
const Duration kAppConfigTimeout = Duration(seconds: 3);

/// Provides the generated [AppConfigApi] (phase 438) for the forced-update
/// gate's `GET /api/v1/app/config`.
///
/// A [Dio.clone] of the main [dioProvider] instance: it SHARES the cert-pinned
/// `httpClientAdapter` and the interceptor chain (so `X-Request-Id` /
/// `X-App-Version` ride along), and only shortens the connect / receive
/// timeouts to [kAppConfigTimeout]. Never a second unpinned client.
@Riverpod(keepAlive: true)
AppConfigApi appConfigApi(Ref ref) {
  final Dio main = ref.watch(dioProvider);
  final Dio dio = main.clone(
    options: main.options.copyWith(
      connectTimeout: kAppConfigTimeout,
      receiveTimeout: kAppConfigTimeout,
    ),
  );
  return AppConfigApi(dio, standardSerializers);
}

// Phase 3.2 — Riverpod providers for generated API classes.
// Phase 4.1 — Added [masterApiProvider] for [MasterControllerApi].
// Phase 13.8 wire-up — Added [clientApiProvider] for [ClientControllerApi]
// (`GET /clients/me/passport`).
//
// Wires the generated API classes with the singleton [dioProvider] Dio
// instance and [standardSerializers] from the generated package. Kept alive
// because these API objects are stateless value types — keeping them alive
// avoids repeated construction on every provider read.

import 'package:beautica_api/beautica_api.dart';
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

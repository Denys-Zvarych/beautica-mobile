// Phase 3.2 — Riverpod providers for generated API classes.
//
// Wires the generated [AuthControllerApi] and [UserControllerApi] with the
// singleton [dioProvider] Dio instance and [standardSerializers] from the
// generated package. Kept alive because these API objects are stateless
// value types — keeping them alive avoids repeated construction on every
// provider read.
//
// All other generated API classes (MasterControllerApi, etc.) will be added
// here as their respective features ship in later phases.

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

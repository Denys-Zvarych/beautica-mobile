// Phase 2.3 — AuthRepository Riverpod provider.
// Phase 2.8 — SecureStorage injected so HttpAuthRepository can logout().
// Phase 3.2 — Re-pointed to generated AuthControllerApi / UserControllerApi
//             instead of raw Dio + SecureStorage. SecureStorage is no longer
//             needed directly; the generated logout() uses the Bearer token
//             that AuthInterceptor injects from the Riverpod state.
//
// Wires [HttpAuthRepository] with the generated API singletons from
// [authApiProvider] and [userApiProvider]. Kept alive for the app lifetime
// because the repository is referenced by the auth interceptor and multiple
// features (login, registration, profile).
//
// Tests override this provider with a fake via ProviderScope overrides —
// never construct [HttpAuthRepository] directly in tests.

import 'package:beautica_mobile/core/network/api_client_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'auth_repository.dart';
import 'http_auth_repository.dart';

part 'auth_repository_provider.g.dart';

/// Provides the [AuthRepository] singleton used throughout the app.
///
/// Returns [HttpAuthRepository] backed by the generated [authApiProvider]
/// and [userApiProvider]. Override in tests with a [FakeAuthRepository] or
/// mocktail mock.
@Riverpod(keepAlive: true)
AuthRepository authRepository(Ref ref) =>
    HttpAuthRepository(ref.watch(authApiProvider), ref.watch(userApiProvider));

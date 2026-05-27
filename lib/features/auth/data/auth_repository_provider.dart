// Phase 2.3 — AuthRepository Riverpod provider.
// Phase 2.8 — SecureStorage injected so HttpAuthRepository can logout().
//
// Wires [HttpAuthRepository] with the singleton [dioProvider] Dio instance
// and [secureStorageProvider] for refresh-token revocation on logout.
// Kept alive for the app lifetime because the repository is referenced by
// the auth interceptor and multiple features (login, registration, profile).
//
// Tests override this provider with a fake via ProviderScope overrides —
// never construct [HttpAuthRepository] directly in tests.

import 'package:beautica_mobile/core/network/dio_provider.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'auth_repository.dart';
import 'http_auth_repository.dart';

part 'auth_repository_provider.g.dart';

/// Provides the [AuthRepository] singleton used throughout the app.
///
/// Returns [HttpAuthRepository] backed by the authenticated [dioProvider]
/// and [secureStorageProvider] for refresh-token revocation on logout.
/// Override in tests with a [FakeAuthRepository] or mocktail mock.
@Riverpod(keepAlive: true)
AuthRepository authRepository(Ref ref) => HttpAuthRepository(
  ref.watch(dioProvider),
  ref.watch(secureStorageProvider),
);

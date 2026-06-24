// Phase 13.4 — Riverpod wiring for the favorites repository.
//
// Exposes [favoriteApiProvider] (the generated [FavoriteControllerApi]
// singleton) and [favoriteRepositoryProvider] (the [HttpFavoriteRepository]
// backed by it). Both follow the established pattern in
// `api_client_provider.dart`: built from the shared authenticated [dioProvider]
// + the generated [standardSerializers], and kept alive to avoid
// re-construction on every read.
//
// Override [favoriteRepositoryProvider] with a mocktail mock in tests — never
// construct [HttpFavoriteRepository] directly in production code.

import 'package:beautica_api/beautica_api.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/core/network/dio_provider.dart';

import 'favorite_repository.dart';

part 'favorite_repository_provider.g.dart';

/// Provides the generated [FavoriteControllerApi] singleton.
@Riverpod(keepAlive: true)
FavoriteControllerApi favoriteApi(Ref ref) =>
    FavoriteControllerApi(ref.watch(dioProvider), standardSerializers);

/// Provides the [FavoriteRepository] singleton backed by [favoriteApiProvider].
///
/// Kept alive so the toggle notifier (13.4) and the Favorites screen (13.10)
/// share a single repository instance.
@Riverpod(keepAlive: true)
FavoriteRepository favoriteRepository(Ref ref) =>
    HttpFavoriteRepository(ref.watch(favoriteApiProvider));

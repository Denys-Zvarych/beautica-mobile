// Phase 13.2 — Riverpod wiring for the discovery search repository.
//
// Exposes [searchApiProvider] (the generated [SearchControllerApi] singleton)
// and [searchRepositoryProvider] (the [HttpSearchRepository] backed by it).
// Both follow the established pattern in `service_repository.dart`: the API
// client is built from the shared authenticated [dioProvider] + the generated
// [standardSerializers], and both providers are kept alive to avoid
// re-construction on every read.
//
// Override [searchRepositoryProvider] with a mocktail mock in tests — never
// construct [HttpSearchRepository] directly in production code.

import 'package:beautica_api/beautica_api.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/core/network/dio_provider.dart';

import 'search_repository.dart';

part 'search_repository_provider.g.dart';

/// Provides the generated [SearchControllerApi] singleton.
///
/// Same authenticated Dio instance and serializers as the other API providers
/// in `core/network/api_client_provider.dart`. Kept alive to avoid
/// re-construction on every provider read.
@Riverpod(keepAlive: true)
SearchControllerApi searchApi(Ref ref) =>
    SearchControllerApi(ref.watch(dioProvider), standardSerializers);

/// Provides the [SearchRepository] singleton backed by [searchApiProvider].
///
/// Kept alive so the discovery screens (13.3+) share a single repository
/// instance. The search endpoints are unauthenticated/public-browse on the
/// backend, so there is no master-id readiness guard here (unlike the service
/// repository).
@Riverpod(keepAlive: true)
SearchRepository searchRepository(Ref ref) =>
    HttpSearchRepository(ref.watch(searchApiProvider));

// Phase 13.2 — Riverpod wiring for the discovery search repository.
//
// Exposes [searchRepositoryProvider] (the [HttpSearchRepository]). The
// repository issues the search GETs directly through the shared authenticated
// [dioProvider] with a FLAT dot-notation query map (the generated
// `SearchControllerApi` object-query encoding bracket-nests the params and the
// backend's `@ModelAttribute` binding silently drops every filter — see
// `search_repository.dart` header). Responses are still deserialized through the
// generated [standardSerializers]. Kept alive to avoid re-construction on every
// read.
//
// Override [searchRepositoryProvider] with a mocktail mock in tests — never
// construct [HttpSearchRepository] directly in production code.

import 'package:beautica_api/beautica_api.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/core/network/dio_provider.dart';

import 'search_repository.dart';

part 'search_repository_provider.g.dart';

/// Provides the [SearchRepository] singleton.
///
/// Built from the shared authenticated [dioProvider] (so the interceptor chain
/// — auth, logging, error-mapping, refresh — applies) and the generated
/// [standardSerializers] for response deserialization. Kept alive so the
/// discovery screens (13.3+) share a single repository instance. The search
/// endpoints are unauthenticated/public-browse on the backend, so there is no
/// master-id readiness guard here (unlike the service repository).
@Riverpod(keepAlive: true)
SearchRepository searchRepository(Ref ref) =>
    HttpSearchRepository(ref.watch(dioProvider), standardSerializers);

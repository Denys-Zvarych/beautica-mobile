// Phase 13.x (Variant A redesign) — second-level service options provider.
//
// Feeds the «Послуги · {category}» chip drawer that opens beneath a selected
// category in the Variant A search rail. Returns the bookable service types for
// a given platform-category slug (e.g. `HAIR` → Стрижка / Фарбування / …),
// fetched live from the backend.
//
// Backed by [CategoryServiceRepository] → `GET /api/v1/service-types?
// categoryName={slug}` (public, items ordered nameUk ASC). The slug is the rail
// tile's `ServiceCategoryOption.name`. The drawer consumer handles the
// loading / error / data states of the returned [AsyncValue].

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/features/services/data/service_repository.dart'
    show serviceCatalogApiProvider;

import '../domain/category_service_option.dart';
import 'category_service_repository.dart';

part 'category_service_providers.g.dart';

/// Provides the [CategoryServiceRepository] singleton.
///
/// Backed by the shared, keep-alive [serviceCatalogApiProvider] (built from the
/// authenticated [dioProvider] + generated serializers, with NO transitive
/// dependency on the master-only profile provider — safe for CLIENT callers).
/// Kept alive so the discovery search surface shares one repository instance.
///
/// Override with a mocktail mock in tests — never construct
/// [HttpCategoryServiceRepository] directly in production code.
@Riverpod(keepAlive: true)
CategoryServiceRepository categoryServiceRepository(Ref ref) =>
    HttpCategoryServiceRepository(ref.watch(serviceCatalogApiProvider));

/// Async list of bookable service types for the given platform-category [slug].
///
/// Resolves via [CategoryServiceRepository.fetchServices]. Maps each
/// `PlatformServiceTypeResponse{slug, nameUk}` → `CategoryServiceOption{key,
/// displayName}`. Errors surface as the [AsyncValue]'s error so the drawer can
/// show an inline retry; an empty list collapses the drawer.
///
/// [keepAlive: true] mirrors [approvedCategoriesProvider] (the sibling that
/// feeds the rail): the platform taxonomy is small and changes rarely, so the
/// per-slug result is cached in the root container and shared across rebuilds
/// rather than re-fetched on every drawer reveal.
@Riverpod(keepAlive: true)
Future<List<CategoryServiceOption>> categoryServiceOptions(
  Ref ref,
  String slug,
) {
  return ref.watch(categoryServiceRepositoryProvider).fetchServices(slug);
}

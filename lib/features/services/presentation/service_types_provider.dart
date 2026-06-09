// Phase 16.2 — service-types provider: a Riverpod family keyed by the platform
// category slug, returning the second-level service types for the picker.
//
// The picker (Phase 16.4) watches `serviceTypesProvider(categoryName)` and the
// create-form wiring (Phase 16.3) reads the resolved options to pre-fill the
// service name.
//
// A category with no service types resolves to an empty list (not an error) —
// the repository degrades gracefully and the picker shows an empty/explanatory
// state rather than a failure surface.

import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/service_type_option.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'service_types_provider.g.dart';

/// Async list of platform service types under [categoryName], for the
/// second-level service-type picker.
///
/// Keyed by the platform-category wire slug (e.g. `EYELASH`). Returns an empty
/// list for a category that has no service types — never an error for the
/// empty case. Transport errors surface as the future's error state, mapped to
/// the feature's typed [Failure] subclasses by [ServiceRepository].
///
/// Auto-disposes (no [keepAlive]): when the picker tears down (form closed,
/// category toggled off) the entry is dropped, so re-entering the form issues a
/// fresh fetch. This is what lets a newly-approved type under an *existing*
/// category appear without an app restart — the previous timer-bounded keepAlive
/// pinned each category's list for 3 minutes and masked new approvals. The
/// services list screen additionally invalidates this family on its refresh
/// surfaces (entry / pop-back / pull-to-refresh) to cover the kept-alive route.
@riverpod
Future<List<ServiceTypeOption>> serviceTypes(Ref ref, String categoryName) =>
    ref.watch(serviceRepositoryProvider).fetchServiceTypes(categoryName);

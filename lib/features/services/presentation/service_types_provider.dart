// Phase 16.2 — service-types provider: a Riverpod family keyed by the platform
// category slug, returning the second-level service types for the picker.
//
// The picker (Phase 16.4) watches `serviceTypesProvider(categoryName)` and the
// create-form wiring (Phase 16.3) reads the resolved options to pre-fill the
// service name. The family caches one future per category for the lifetime of
// the form so re-opening the picker for the same category does not re-fetch.
//
// A category with no service types resolves to an empty list (not an error) —
// the repository degrades gracefully and the picker shows an empty/explanatory
// state rather than a failure surface.

import 'dart:async';

import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/service_type_option.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'service_types_provider.g.dart';

/// How long a fetched type list stays cached after its last listener is gone.
///
/// Long enough to span a single form session (toggling the category off→on or
/// flipping between two categories no longer tears down + re-fetches), short
/// enough that a genuinely new session re-fetches a fresh catalog.
const Duration _serviceTypesCacheTtl = Duration(minutes: 3);

/// Async list of platform service types under [categoryName], for the
/// second-level service-type picker.
///
/// Keyed by the platform-category wire slug (e.g. `EYELASH`). Returns an empty
/// list for a category that has no service types — never an error for the
/// empty case. Transport errors surface as the future's error state, mapped to
/// the feature's typed [Failure] subclasses by [ServiceRepository].
///
/// Caching (Phase 16.4 perf): a timer-bounded [keepAlive] holds each category's
/// result for [_serviceTypesCacheTtl] after the last listener drops, then lets
/// the entry auto-dispose. This preserves Phase 16.2's "fresh catalog per form
/// session" intent (a later session re-fetches) while avoiding a refetch storm
/// when the picker is gated behind a category toggle — toggling the category
/// off→on, or flipping between two categories within one session, now reuses
/// the cached list instead of re-hitting [ServiceRepository.fetchServiceTypes].
@riverpod
Future<List<ServiceTypeOption>> serviceTypes(Ref ref, String categoryName) {
  final link = ref.keepAlive();
  final Timer timer = Timer(_serviceTypesCacheTtl, link.close);
  ref.onDispose(timer.cancel);
  return ref.watch(serviceRepositoryProvider).fetchServiceTypes(categoryName);
}

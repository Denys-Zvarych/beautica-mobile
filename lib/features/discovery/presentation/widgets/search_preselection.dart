// Shared helper for the discovery → booking service pre-selection handoff.
//
// Resolves the human-readable Ukrainian display names for the service-type
// slugs in an active [SearchFilters] set, drawn from the already-loaded
// second-level [categoryServiceOptionsProvider] list. Those labels are a
// DEFENSIVE fallback carried alongside the slugs into
// [PendingServicePreselection] — the booking flow matches a catalogue tile by
// its `serviceTypeSlug` first and only falls back to the label when a tile has
// no slug of its own.
//
// Read-only: uses `ref.read` (a one-shot read at navigation time) against the
// keep-alive options provider the filter screen already populated. When the
// options are not loaded (or no category is selected) the label set is empty —
// the slugs still travel, so pre-selection still works via exact slug match.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/category_service_providers.dart';
import '../../domain/category_service_option.dart';
import '../../domain/search_filters.dart';

/// Resolves the display-name labels for [filters.serviceTypeSlugs] from the
/// loaded category service options. Returns an empty set when the category or
/// its options are unavailable.
Set<String> resolveServiceTypeLabels(WidgetRef ref, SearchFilters filters) {
  final String? categoryKey = filters.categoryKey;
  if (categoryKey == null || filters.serviceTypeSlugs.isEmpty) {
    return const <String>{};
  }
  final List<CategoryServiceOption>? options = ref
      .read(categoryServiceOptionsProvider(categoryKey))
      .value;
  if (options == null || options.isEmpty) return const <String>{};

  final Map<String, String> labelBySlug = <String, String>{
    for (final CategoryServiceOption o in options) o.key: o.displayName,
  };
  return <String>{
    for (final String slug in filters.serviceTypeSlugs)
      if (labelBySlug[slug] case final String label) label,
  };
}

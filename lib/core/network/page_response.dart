// Phase 14.0 — Generic paged-result envelope shared across data-layer
// repositories.
//
// Hand-written (not freezed) — a generic `@freezed class PageResponse<T>` is
// brittle with the current freezed/build_runner toolchain (the generated
// mixin trips on the type parameter). This mirrors the identical, already
// battle-tested pattern in `features/discovery/domain/search_filters.dart`'s
// `SearchPage<T>`, promoted to `core/network/` because more than one feature
// now needs a plain "page of domain models" wrapper (see
// `features/booking/data/booking_repository.dart`).
//
// [SearchPage] is NOT replaced by this type — it stays local to the discovery
// feature to avoid an unrelated churn to its call sites. New paged reads
// should prefer [PageResponse].
//
// Pure Dart: no Flutter imports.

import 'package:flutter/foundation.dart' show immutable;

/// An immutable, generic page of domain-model results.
///
/// Carries the items plus the paging metadata a caller needs to decide
/// whether more pages remain.
@immutable
class PageResponse<T> {
  const PageResponse({
    required this.items,
    required this.page,
    required this.totalPages,
    required this.totalElements,
  });

  /// The results on this page. Empty for a no-match page (still a valid page).
  final List<T> items;

  /// Zero-based index of this page.
  final int page;

  /// Total number of pages available.
  final int totalPages;

  /// Total number of matching elements across all pages.
  final int totalElements;

  /// Whether a subsequent page exists (`page < totalPages - 1`).
  bool get hasMore => page < totalPages - 1;

  PageResponse<T> copyWith({
    List<T>? items,
    int? page,
    int? totalPages,
    int? totalElements,
  }) {
    return PageResponse<T>(
      items: items ?? this.items,
      page: page ?? this.page,
      totalPages: totalPages ?? this.totalPages,
      totalElements: totalElements ?? this.totalElements,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PageResponse<T> &&
        _listEquals(other.items, items) &&
        other.page == page &&
        other.totalPages == totalPages &&
        other.totalElements == totalElements;
  }

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(items), page, totalPages, totalElements);

  @override
  String toString() =>
      'PageResponse<$T>(items: ${items.length}, page: $page, '
      'totalPages: $totalPages, totalElements: $totalElements)';
}

/// Order-sensitive element-wise list equality used by [PageResponse].
bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

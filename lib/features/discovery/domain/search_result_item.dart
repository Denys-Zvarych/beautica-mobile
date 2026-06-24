// Phase 13.4 — Unified search result item (master | salon).
//
// The results list renders masters AND salons (the approved preview mixes two
// master cards and one salon card). [SearchResultItem] is a thin sealed wrapper
// over the two existing domain models so the notifier can hold one ordered list
// and the screen can switch on the variant to pick the right card.
//
// Pure Dart: no Flutter imports.

import 'package:flutter/foundation.dart';

import 'master_search_item.dart';
import 'salon_search_item.dart';

/// A single entry in the merged discovery results list.
@immutable
sealed class SearchResultItem {
  const SearchResultItem();

  /// Stable identity for list keys + de-duplication across page appends.
  String get id;
}

/// A master result, wrapping [MasterSearchItem].
final class MasterResultItem extends SearchResultItem {
  const MasterResultItem(this.master);

  final MasterSearchItem master;

  @override
  String get id => 'master:${master.masterId}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MasterResultItem && other.master == master;

  @override
  int get hashCode => master.hashCode;
}

/// A salon result, wrapping [SalonSearchItem].
final class SalonResultItem extends SearchResultItem {
  const SalonResultItem(this.salon);

  final SalonSearchItem salon;

  @override
  String get id => 'salon:${salon.salonId}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SalonResultItem && other.salon == salon;

  @override
  int get hashCode => salon.hashCode;
}

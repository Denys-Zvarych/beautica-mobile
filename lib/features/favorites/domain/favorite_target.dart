// Phase 13.4 — Favorite target value object.
//
// Pure-Dart description of what a favorite points at: a master, a salon or a
// master's service, plus its id. The data layer translates
// [FavoriteTargetType] into the generated `AddFavoriteRequestTargetTypeEnum`
// wire value (MASTER | SALON | SERVICE) — the generated enum never escapes the
// data layer.
//
// Pure Dart: no Flutter, no generated-API imports.

import 'package:flutter/foundation.dart';

/// The kind of entity a favorite refers to.
enum FavoriteTargetType {
  /// An INDEPENDENT_MASTER (search/masters result, public master profile).
  master,

  /// A salon (search/salons result, public salon profile).
  salon,

  /// A single service offered by a master (the beauty wish list). The id is the
  /// `masterServiceId`, not the catalogue service-type id.
  service,
}

/// An immutable (type, id) pair identifying a favorite target.
///
/// Used as the optimistic-toggle key and the argument to
/// `FavoriteRepository.add` / `.remove`. Value-equal so the toggle notifier can
/// key its in-flight/pending sets on it.
@immutable
class FavoriteTarget {
  const FavoriteTarget({required this.type, required this.id});

  /// Whether this target is a master or a salon.
  final FavoriteTargetType type;

  /// Backend-assigned UUID of the master, salon or master-service.
  final String id;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FavoriteTarget && other.type == type && other.id == id;

  @override
  int get hashCode => Object.hash(type, id);

  @override
  String toString() => 'FavoriteTarget(${type.name}, $id)';
}

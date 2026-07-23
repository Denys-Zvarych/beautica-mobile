// Fake [FavoriteRepository] for the favorite-toggle notifier unit tests.
//
// Captures every add/remove call (so a test can assert no double-fire) and
// lets each method's outcome be configured independently:
//   - default            → succeeds immediately (resolves to void).
//   - `addResult` / `removeResult` set to a [Failure] → that call throws it,
//     driving the notifier's revert-on-error branch.
//   - `addDelay` / `removeDelay` set to a (non-completing or controllable)
//     Future → the call awaits it before resolving, so a test can inspect the
//     optimistic intermediate state (pending == true) BEFORE the future settles.
//
// Mirrors the configurable-field + captured-call style of [FakeAuthRepository].

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/favorites/data/favorite_repository.dart';
import 'package:beautica_mobile/features/favorites/domain/favorite_target.dart';

/// In-memory [FavoriteRepository] implementation for tests.
final class FakeFavoriteRepository implements FavoriteRepository {
  /// When a [Failure], the next [add] throws it; otherwise [add] succeeds.
  Failure? addResult;

  /// When a [Failure], the next [remove] throws it; otherwise [remove] succeeds.
  Failure? removeResult;

  /// When non-null, [add] awaits this before resolving — lets a test observe the
  /// pending/optimistic state while the call is in flight.
  Future<void>? addDelay;

  /// When non-null, [remove] awaits this before resolving.
  Future<void>? removeDelay;

  /// Every target passed to [add], in call order.
  final List<FavoriteTarget> addCalls = <FavoriteTarget>[];

  /// Every target passed to [remove], in call order.
  final List<FavoriteTarget> removeCalls = <FavoriteTarget>[];

  @override
  Future<void> add(FavoriteTarget target) async {
    addCalls.add(target);
    if (addDelay != null) await addDelay!;
    final Failure? failure = addResult;
    if (failure != null) throw failure;
  }

  @override
  Future<void> remove(FavoriteTarget target) async {
    removeCalls.add(target);
    if (removeDelay != null) await removeDelay!;
    final Failure? failure = removeResult;
    if (failure != null) throw failure;
  }
}

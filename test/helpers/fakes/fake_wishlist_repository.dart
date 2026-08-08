// Phase 237 — in-memory [WishlistRepository] fake.
//
// Mirrors `fake_favorite_repository.dart`'s shape: a scripted result plus a
// call log, no mocktail stubbing at the test site.
//
// ## THE THROW IS ASYNCHRONOUS ON PURPOSE
//
// [failure] is raised AFTER an `await`, never from the synchronous body. A
// synchronous `thenThrow` bypasses Riverpod's async machinery entirely: the
// error surfaces before the provider ever enters its loading state, so a test
// asserting on `hasError` can pass without the code path under test having run
// at all. Compounding that, `AsyncLoading(retrying: true)` ALREADY satisfies
// `hasError`, so `hasError` alone is never sufficient evidence — assert on the
// error's TYPE.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/wishlist/data/wishlist_repository.dart';
import 'package:beautica_mobile/features/wishlist/domain/wishlist_service.dart';

/// A scriptable [WishlistRepository] for widget and notifier tests.
class FakeWishlistRepository implements WishlistRepository {
  FakeWishlistRepository({
    List<WishlistService>? services,
    this.failure,
    this.delay = Duration.zero,
  }) : services = services ?? const <WishlistService>[];

  /// What [getMyWishlist] resolves with when [failure] is null.
  List<WishlistService> services;

  /// When non-null, [getMyWishlist] throws this instead of resolving —
  /// asynchronously; see the file header.
  Failure? failure;

  /// Artificial latency, so a test can observe the loading state.
  Duration delay;

  /// How many times [getMyWishlist] has been called. Lets a test prove a
  /// mutation did NOT trigger a refetch.
  int getCallCount = 0;

  @override
  Future<List<WishlistService>> getMyWishlist() async {
    getCallCount++;
    // Always yield at least one microtask so the throw below can never be
    // synchronous — see the file header.
    await Future<void>.delayed(delay);
    final Failure? f = failure;
    if (f != null) throw f;
    return services;
  }
}

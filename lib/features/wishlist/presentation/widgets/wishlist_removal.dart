// Phases 238 + 239 — the un-favourite gesture, shared by both wish-list
// surfaces.
//
// The passport page's two-card line and the full-list page run the SAME
// sequence, so it lives here once rather than being written twice and drifting.
//
// ## Why a local `_removing` set exists ON TOP of an optimistic notifier
//
// `wishlistNotifier.removeService` is already optimistic: it drops the entry
// from `state` before the wire call. That makes the entry vanish INSTANTLY,
// which is correct for data and wrong for motion — the approved design gives
// the client a beat to see the removal land (a heart pop, then the row
// collapsing and the list re-flowing). So the id is parked in a local set
// FIRST, the exit animation plays against that flag, and only then is the
// notifier told. The provider is still the single source of truth for WHAT is
// in the list; this set only says WHICH entries are mid-exit.
//
// ## The set is cleared unconditionally, including on failure
//
// `removeService` restores a failed removal at its original index. If the id
// stayed in `_removing`, the restored entry would be permanently invisible on
// this surface (collapsed by an animation flag) while still present in state —
// a silent data/UI divergence that no test of the notifier alone would catch.
// So the `finally`-shaped clear runs on both paths, and the restored row simply
// animates back in.
//
// ## `mounted` after every await
//
// Both awaits here bracket a `setState` on a screen the user can navigate away
// from mid-animation — the full-list page is a pushed leaf with a swipe-back
// gesture, and 260 ms is comfortably long enough to get out.
//
// ## Audit cycle 3 — the collapse delay is an injectable seam, not a bare
//    `Future.delayed`
//
// `integration_test/wishlist_flow_test.dart`'s last-favourite regression test
// asserts a MID-FLIGHT state — animation started, wire call not yet sent —
// which used to be reached by racing two `tester.pump(fixedDuration)` calls
// against this method's own real-clock `Future.delayed`. Under
// `IntegrationTestWidgetsFlutterBinding` (which `flutter test -d
// flutter-tester` still runs on — it extends `LiveTestWidgetsFlutterBinding`,
// a REAL clock, regardless of the headless device) that is a genuine race,
// not a virtual-clock-deterministic wait: it failed once and passed on
// reruns. [wishlistRemovalDelayProvider] exists so a test can hold that
// window open EXPLICITLY via a [Completer] it controls, instead of guessing a
// wall-clock offset that must land strictly between two real timers. It
// changes nothing about production behaviour — the default IS
// `Future.delayed(WishlistRemovable.duration)`.

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/errors/failures.dart';
import '../../../../shared/feedback/show_velvet_snack.dart';
import '../../application/wishlist_notifier.dart';
import 'wishlist_removable.dart';

part 'wishlist_removal.g.dart';

/// The delay awaited between the exit animation starting and the wire call
/// that actually removes the entry.
///
/// Production always resolves after [WishlistRemovable.duration] — the same
/// duration the row's collapse animates over, so the request fires exactly
/// when the row finishes collapsing. Tests override this provider with a
/// [Completer]-backed future so that window can be opened and closed
/// EXPLICITLY rather than raced against a real timer — see the file header.
@riverpod
Future<void> Function() wishlistRemovalDelay(Ref ref) =>
    () => Future<void>.delayed(WishlistRemovable.duration);

/// Adds the shared un-favourite sequence to a wish-list surface's [State].
///
/// Mix into a `ConsumerState`; render entries whose id is in [removingIds] in
/// their exit state and call [requestRemoval] from the heart.
mixin WishlistRemovalHost<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  final Set<String> _removing = <String>{};

  static const String _tag = 'feature.wishlist';

  /// Entries currently playing their exit animation. Still present in provider
  /// state; not yet gone.
  Set<String> get removingIds => _removing;

  /// How many entries are still genuinely saved — the list minus those on their
  /// way out.
  ///
  /// The counter pill and the «Показати всі (N)» button both read THIS rather
  /// than `items.length`, so the number ticks down with the animation instead
  /// of jumping a beat after it.
  int visibleCount(int total) => total - _removing.length;

  /// Plays the exit animation for [masterServiceId], then un-favourites it.
  ///
  /// A second tap on an entry already leaving is a no-op — the notifier would
  /// also ignore it, but returning here avoids starting a second animation
  /// against the same flag.
  Future<void> requestRemoval(String masterServiceId) async {
    if (_removing.contains(masterServiceId)) return;
    setState(() => _removing.add(masterServiceId));

    await ref.read(wishlistRemovalDelayProvider)();
    if (!mounted) return;

    final Failure? failure = await ref
        .read(wishlistProvider.notifier)
        .removeService(masterServiceId);
    if (!mounted) return;

    // Cleared on BOTH paths — see the file header.
    setState(() => _removing.remove(masterServiceId));

    if (failure == null) return;
    if (kDebugMode) {
      log(
        'un-favourite failed for $masterServiceId — entry restored',
        name: _tag,
        level: 900,
      );
    }
    showErrorSnack(context, failure.userMessage(context));
  }
}

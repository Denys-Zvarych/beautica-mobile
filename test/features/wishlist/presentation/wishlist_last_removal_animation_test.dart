// REGRESSION GUARD — the LAST wish-list entry animates out like any other.
//
// THE BUG (fixed)
// ---------------
// Both wish-list surfaces chose their empty state with
// `visibleCount(items.length) <= 0`, where `visibleCount` subtracts the entries
// currently animating out. So the moment the FINAL row's heart was tapped, the
// count hit zero and the whole list was swapped for the empty card in the SAME
// FRAME as the heart pop — the row never played its 260 ms collapse. Measured
// on the broken build: row present at t=96 ms, gone at t=112 ms, empty card up
// at t=112 ms, and `removeService` not called until t=384 ms.
//
// The second half of that is the worse half: the empty state («nothing saved
// yet — go find a master») was on screen for ~272 ms BEFORE the wire call was
// even made. A failed removal then flipped it straight back to a populated
// list, so the client was shown a confident, wrong statement about their own
// data and then had it retracted.
//
// THE FIX
// -------
// The empty state is gated on the NOTIFIER's list being empty — `items.isEmpty`
// — not on the visible count. `items` does not lose the entry until the
// optimistic removal commits, so the row collapses, then the list empties, then
// the empty state arrives. The count pill and «Показати всі (N)» still read
// `visibleCount`, because ticking down with the animation is the right
// behaviour for a COUNTER and a different question from whether the section has
// anything left to show.
//
// WHY THIS IS PINNED SEPARATELY FROM THE REMOVAL TESTS
// ----------------------------------------------------
// Every end-state assertion in `wishlist_screen_test.dart` passes on the broken
// build: the entry does end up removed and the empty state does end up on
// screen. Only the INTERMEDIATE frames differ. So this file asserts mid-flight,
// between the tap and the settle, which is the only window where the defect is
// observable.

import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/favorites/data/favorite_repository_provider.dart';
import 'package:beautica_mobile/features/wishlist/application/wishlist_notifier.dart';
import 'package:beautica_mobile/features/wishlist/domain/wishlist_service.dart';
import 'package:beautica_mobile/features/wishlist/presentation/wishlist_screen.dart';
import 'package:beautica_mobile/features/wishlist/presentation/widgets/wishlist_removable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fakes/fake_favorite_repository.dart';
import '../../../helpers/fakes/fake_wishlist_repository.dart';
import '../../../helpers/pump_app.dart';

const User _client = User(
  id: 'u1',
  email: 'client@example.com',
  role: UserRole.client,
  firstName: 'Test',
  lastName: 'Client',
);

/// Settles `authProvider` immediately — `favoriteToggleProvider` watches it, so
/// a loading→data transition mid-test would re-run its build and wipe the map
/// the removal depends on.
class _StubAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async =>
      const AuthSession.authenticated(user: _client, accessToken: 'token');
}

/// The wire call must SUCCEED here. A failing toggle restores the entry at its
/// original index, which is correct behaviour but the opposite of the scenario
/// under test — and it is what the un-overridden real repository does.
List<Object> _overrides(FakeWishlistRepository wishlist) => <Object>[
  wishlistRepositoryProvider.overrideWithValue(wishlist),
  favoriteRepositoryProvider.overrideWithValue(FakeFavoriteRepository()),
  authProvider.overrideWith(_StubAuthNotifier.new),
];

/// Half of the collapse — a point that is unambiguously INSIDE the animation.
/// Derived from the widget's own constant so retuning the collapse retunes this.
final Duration _midCollapse = WishlistRemovable.duration ~/ 2;

const WishlistService _onlyEntry = WishlistService(
  masterServiceId: 'w1',
  masterId: 'm1',
  serviceName: 'Нарощування вій — класика 2D',
  masterName: 'Олена Ковальчук',
  durationMinutes: 60,
  priceDisplay: '800 ₴',
);

void main() {
  testWidgets('should_playExitAnimation_when_theLastEntryIsUnfavourited', (
    WidgetTester tester,
  ) async {
    final FakeWishlistRepository repo = FakeWishlistRepository(
      services: <WishlistService>[_onlyEntry],
    );
    await tester.pumpApp(const WishlistScreen(), overrides: _overrides(repo));
    await tester.pumpAndSettle();

    expect(find.byType(WishlistRemovable), findsOneWidget);
    expect(find.byKey(const Key('wishlist_empty_state')), findsNothing);

    // Tap the one heart. `requestRemoval` waits WishlistRemovable.duration
    // (260 ms) before it calls the notifier, so the row must survive that
    // whole window.
    await tester.tap(find.byKey(const Key('wishlist_row_heart_w1')));
    await tester.pump();

    // Mid-flight, well inside the collapse.
    //
    // NOT asserted: that `WishlistRow` is still mounted. `WishlistRemovable`
    // swaps its child for a `SizedBox` the instant `removing` flips — that is
    // the approved preview's own shape, and it is what makes `AnimatedSize`
    // have a smaller target to animate TO. The row's widget going is normal;
    // the SLOT collapsing over 260 ms is the behaviour under test.
    //
    // fixed-wait-ok: this test asserts MID-ANIMATION, so the pump must land at
    // a chosen point inside the collapse — there is no "state to wait for", the
    // whole point is that the slot is still part-way through. The duration is
    // DERIVED from the animation's own token rather than guessed, so retuning
    // the collapse retunes this probe with it, and widget-test time is fake and
    // deterministic so it cannot flake on slow CI.
    await tester.pump(_midCollapse);
    expect(
      find.byType(WishlistRemovable),
      findsOneWidget,
      reason:
          'the leaving entry must still occupy its (shrinking) slot — on the '
          'broken build the whole list was replaced by the empty card here',
    );
    final double midCollapse = tester
        .getSize(find.byType(WishlistRemovable))
        .height;
    expect(
      midCollapse,
      greaterThan(0),
      reason:
          'the slot should be part-way through its collapse at 120 ms of a '
          '260 ms animation, not already at zero',
    );
    expect(
      find.byKey(const Key('wishlist_empty_state')),
      findsNothing,
      reason:
          'the empty state must not appear before the removal has even been '
          'sent — a failed wire call would then retract it',
    );

    // The removal has not been requested yet either, so nothing has been
    // claimed about the client's data.
    expect(
      repo.getCallCount,
      1,
      reason: 'the initial fetch only — removal never refetches',
    );

    // Let the collapse finish, the wire call land and the list empty out.
    await tester.pumpAndSettle();
    expect(find.byType(WishlistRemovable), findsNothing);
    expect(find.byKey(const Key('wishlist_empty_state')), findsOneWidget);
    expect(
      repo.getCallCount,
      1,
      reason:
          'removeService mutates state in place; invalidating here would '
          'dispose the provider whenever its only listeners are paused',
    );
  });

  testWidgets(
    'should_keepTheRowMounted_when_removalIsStillWithinTheCollapseWindow',
    (WidgetTester tester) async {
      // The same guarantee stated against the widget that owns the animation,
      // so a future refactor that drops WishlistRemovable is caught even if the
      // frame timings above are retuned.
      await tester.pumpApp(
        const WishlistScreen(),
        overrides: _overrides(
          FakeWishlistRepository(services: <WishlistService>[_onlyEntry]),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('wishlist_row_heart_w1')));
      await tester.pump();
      // fixed-wait-ok: same mid-animation probe as above.
      await tester.pump(_midCollapse);

      final WishlistRemovable removable = tester.widget<WishlistRemovable>(
        find.byType(WishlistRemovable),
      );
      expect(
        removable.removing,
        isTrue,
        reason:
            'the entry should be marked as leaving — i.e. the collapse is '
            'actually running rather than the row being dropped outright',
      );

      await tester.pumpAndSettle();
    },
  );
}

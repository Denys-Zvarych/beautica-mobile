// Regression guard for the compact wish-list card's HEADER ROW HEIGHT.
//
// mobile-qa finding, tap-target-fix audit (2026-08-11): `WishlistHeartButton`
// grew its own outer extent from a 32dp painted square to a 48dp tap target
// by wrapping the heart in `Padding` (see `wishlist_heart_button.dart`'s doc
// comment and `wishlist_heart_button_tap_target_test.dart`). That widget's
// own comment discusses the fix's cost at BOTH shipped call sites, but only
// describes `wishlist_row.dart`'s HORIZONTAL cost (16dp off the name column,
// pinned in `wishlist_row_test.dart`'s `_kNameColumn360`). It does not mention
// that `wishlist_compact_card.dart`'s header `Row` — `[HubAvatar(32dp),
// Spacer, WishlistHeartButton]` — sizes its cross axis to its TALLEST child,
// so the same fix grew this card's header, and therefore the WHOLE card
// (`wishlist_section.dart` lays both cards out inside one `IntrinsicHeight`
// row), 16dp taller. Nothing below the header shifted position in a way any
// existing test noticed:
//
//   * `no_truncation_regression_test.dart`'s 360/320 dp matrix asserts that
//     names still wrap without truncating or painting outside their box —
//     it says nothing about the header's own height.
//   * `passport_screen_test.dart` measures the card's WIDTH (half-row / full
//     row) but never its height.
//   * the install-wide `installOverflowGuard` (see `pump_app.dart`) only
//     fires once a `RenderFlex` runs OUT of room — a header that grows again
//     and still fits inside whatever the `IntrinsicHeight` row allows would
//     ship silently.
//
// So this file pins the DRIVER directly: the header `Row`'s own height.
//
// WHY THE FLOOR IS RE-DERIVED, NOT IMPORTED
// ------------------------------------------
// `48` here is the same Android/iOS platform tap-target floor
// `wishlist_heart_button_tap_target_test.dart`'s `_kPlatformMinTapExtent`
// re-derives rather than imports from `wishlist_heart_button.dart`'s private
// `_kMinTapExtent` — same reasoning: importing the implementation constant
// would mean a regression IN that constant is invisible to the test that
// exists to catch drift away from it.
//
// MUTATION-PROVEN: with `wishlist_heart_button.dart`'s `Padding(all:
// _kTapPad)` wrapper removed (bare 32×32 `SizedBox` as the heart's
// `GestureDetector` child, matching the pre-fix shape), the header `Row`'s
// height drops to 32dp (`HubAvatar`'s own size, now the tallest child) and
// the assertion below fails. Restoring the wrapper makes it pass again.
//
// Layer: Widget. No providers — [WishlistCompactCard] is a `StatelessWidget`.

import 'package:beautica_mobile/features/home/presentation/widgets/hub_widgets.dart';
import 'package:beautica_mobile/features/wishlist/domain/wishlist_service.dart';
import 'package:beautica_mobile/features/wishlist/presentation/widgets/wishlist_compact_card.dart';
import 'package:beautica_mobile/features/wishlist/presentation/widgets/wishlist_heart_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

/// Same platform floor as `wishlist_heart_button_tap_target_test.dart`'s
/// `_kPlatformMinTapExtent` — re-derived rather than imported; see the file
/// header for why.
const double _kPlatformMinTapExtent = 48;

/// `HubAvatar`'s size on this card (`WishlistCompactCard._kAvatar`, private
/// to that file — mirrored here rather than exported, same policy
/// `wishlist_row_test.dart` uses for `WishlistRow._kMetaGlyph`).
const double _kCardAvatar = 32;

WishlistService _entry() => const WishlistService(
  masterServiceId: 'ms-1',
  masterId: 'm-1',
  serviceName: 'Ламінування та фарбування брів',
  masterName: 'Анастасія Мельниченко',
  durationMinutes: 60,
  priceDisplay: '800 ₴',
);

void main() {
  Future<void> pumpCard(WidgetTester tester) async {
    await tester.pumpApp(
      Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 150,
          child: WishlistCompactCard(
            item: _entry(),
            onBook: () {},
            onUnfavourite: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    "the header row's height is bound by the heart's 48dp tap target, "
    "not the 32dp avatar",
    (tester) async {
      await pumpCard(tester);

      final Rect headerRect = tester.getRect(
        find
            .ancestor(
              of: find.byType(WishlistHeartButton),
              matching: find.byType(Row),
            )
            .first,
      );

      expect(
        headerRect.height,
        moreOrLessEquals(_kPlatformMinTapExtent, epsilon: 0.5),
        reason:
            'the header Row measured ${headerRect.height}dp tall. A `Row` '
            'sizes to its tallest child — this pins that the heart\'s tap '
            'target (48dp) is currently that child, not the ${_kCardAvatar}dp '
            'avatar. A further, currently harmless increase to either child '
            'would move this number and should be a deliberate change, not a '
            'silent one.',
      );

      // Sanity check the claim above is actually about the taller child, not
      // a coincidence: the avatar's own box is unchanged at 32dp.
      final Rect avatarRect = tester.getRect(find.byType(HubAvatar));
      expect(avatarRect.height, moreOrLessEquals(_kCardAvatar, epsilon: 0.5));
      expect(
        headerRect.height,
        greaterThan(avatarRect.height),
        reason:
            'the header is now taller than its avatar — that gap IS the '
            '16dp the tap-target fix added',
      );
    },
  );
}

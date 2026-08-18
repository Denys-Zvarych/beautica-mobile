// mobile-qa — regression guard for the "stretched rating card" layout bug.
//
// BUG (fixed, see git history on my_rating_screen.dart): the `Expanded` at
// the top of MyRatingScreen's body hands its subtree a TIGHT vertical
// constraint (min == max == remaining screen height). `RepaintBoundary` +
// `Padding` pass that constraint through unchanged. `RatingSummaryCard`
// (rated branch) wraps its `Row` in `IntrinsicHeight`, which lays the row out
// at its true intrinsic height (~120dp) but then reports its OWN size via
// `constraints.constrain(child.size)` — under a tight constraint this forces
// the reported (and PAINTED) height to the full remaining viewport, even
// though the content stays pinned at the top. `NeumorphicCard`'s opaque
// `DecoratedBox` then paints that oversized box: a huge, mostly-empty card.
// The identical mechanism hit the error branch (`RenderFlex.constrain()`
// despite `mainAxisSize.min`) and the empty branch (`mainAxisSize.max`
// `Column` inside `HubFlatCard`).
//
// FIX: the `error:` and `data:` (rated + empty) branches of the
// `async.when(...)` are each wrapped in `SingleChildScrollView`, which hands
// its child UNBOUNDED height — `constrain()` becomes a no-op, so the card
// reports and paints its true intrinsic size and scrolls instead of
// stretching/overflowing. `loading:` is deliberately left unwrapped: its
// `Center`-ed spinner relies on the tight constraint to stay vertically
// centred in the full remaining height.
//
// WHY THIS FILE EXISTS (not just re-running the old suite): every existing
// assertion in my_rating_screen_test.dart finds a widget by Key/type/text and
// asserts PRESENCE. A card that renders correctly but is absurdly oversized
// satisfies every one of those assertions — which is exactly what shipped.
// Nothing in the suite measured rendered SIZE. These tests close that gap by
// asserting `tester.getSize(...).height` directly, under a viewport tall
// enough (2400dp) that a stretch is unmistakable, against a bound tight
// enough that "less than the viewport" cannot accidentally pass (a 2399dp
// card would still satisfy `< 2400`).
//
// Calibration (measured via this suite, both branches, at height: 2400):
//   fixed   — rated 165dp / empty 85dp / error 147dp / loading 2228dp
//   BROKEN  — rated 2292dp / empty 2228dp / error 2228dp / loading 2228dp
// _kMaxCardHeight (300dp) sits ~2x above the largest real measurement (165)
// for margin against l10n string-length/locale variance, and ~7x below the
// smallest broken measurement (2228) — no broken render can slip under it.

import 'dart:async';

import 'package:beautica_mobile/features/rating/application/my_rating_notifier.dart';
import 'package:beautica_mobile/features/rating/domain/client_rating.dart';
import 'package:beautica_mobile/features/rating/presentation/my_rating_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/pump_app.dart';

/// Deliberately tall viewport — see calibration note above. Tall enough that
/// a full-height stretch is 2000+dp, unmistakably distinct from the ~100-200dp
/// a correctly-wrapping card actually needs.
const double _kTallViewportHeight = 2400;

/// Sane absolute ceiling for a content card under [_kTallViewportHeight] — NOT
/// `< _kTallViewportHeight` (a 2399dp box would satisfy that). See the file
/// header for the calibration numbers this bound is chosen against.
const double _kMaxCardHeight = 300;

/// Floor for the LOADING branch, which must intentionally fill almost all of
/// the remaining body height (its spinner is `Center`-ed under a tight
/// constraint by design — see the file header). Well below the calibrated
/// 2228dp so minor padding/top-bar tweaks don't make this test brittle, but
/// far above any plausible shrink-wrapped-spinner height (a bare
/// `CircularProgressIndicator` is ~36-48dp).
const double _kMinLoadingFillHeight = 2000;

void main() {
  group(
    'MyRatingScreen — card height under a tall viewport (stretch guard)',
    () {
      testWidgets(
        'rated state: RatingSummaryCard reports its true intrinsic height, '
        'not a stretch to fill the viewport',
        (tester) async {
          await tester.pumpApp(
            const MyRatingScreen(),
            overrides: <Object>[
              myRatingProvider.overrideWith(
                (ref) async => const ClientRating(
                  avgRating: 4.7,
                  reviewCount: 12,
                  distribution: <int>[7, 3, 1, 1, 0],
                ),
              ),
            ],
            height: _kTallViewportHeight,
          );
          await tester.pumpAndSettle();

          final double height = tester
              .getSize(find.byKey(const Key('my_rating_display')))
              .height;

          expect(
            height,
            lessThan(_kMaxCardHeight),
            reason:
                'RatingSummaryCard must lay out at its content-driven height '
                '(~165dp measured) under a $_kTallViewportHeight dp viewport. '
                'Regressing the SingleChildScrollView wrapper around the '
                "data: branch reproduces the shipped bug: the card's opaque "
                'NeumorphicCard background stretches to ~$_kTallViewportHeight '
                'dp while its content stays pinned at the top — a bound of '
                '"< viewport height" would NOT catch that, only an absolute '
                'ceiling does.',
          );
          // Sanity floor — a card reporting ~0 height would also be a bug
          // (content silently collapsed), and would otherwise satisfy the
          // ceiling assertion above for the wrong reason.
          expect(height, greaterThan(50));
        },
      );

      testWidgets(
        'empty state: HubFlatCard/HubEmptyState reports its true intrinsic '
        'height, not a stretch to fill the viewport',
        (tester) async {
          await tester.pumpApp(
            const MyRatingScreen(),
            overrides: <Object>[
              myRatingProvider.overrideWith(
                (ref) async => const ClientRating(),
              ),
            ],
            height: _kTallViewportHeight,
          );
          await tester.pumpAndSettle();

          final double height = tester
              .getSize(find.byKey(const Key('my_rating_empty_state')))
              .height;

          expect(
            height,
            lessThan(_kMaxCardHeight),
            reason:
                'the empty state (HubEmptyState inside HubFlatCard, a plain '
                '`Column` with default mainAxisSize.max) must not stretch to '
                'the viewport height (~85dp measured) — same tight-constraint '
                'mechanism as the rated branch, fixed by the same '
                'SingleChildScrollView wrapper around the shared data: branch.',
          );
          expect(height, greaterThan(20));
        },
      );

      testWidgets(
        'error state: _RatingError column reports its true intrinsic height, '
        'not a stretch to fill the viewport',
        (tester) async {
          await tester.pumpApp(
            const MyRatingScreen(),
            overrides: <Object>[
              myRatingProvider.overrideWith((ref) async {
                throw Exception('boom');
              }),
            ],
            height: _kTallViewportHeight,
            retry: (_, _) => null,
          );
          await tester.pumpAndSettle();

          final double height = tester
              .getSize(find.byKey(const Key('my_rating_error_state')))
              .height;

          expect(
            height,
            lessThan(_kMaxCardHeight),
            reason:
                'the error column (`mainAxisSize.min`, ~147dp measured) must '
                'not be forced to the viewport height by RenderFlex.constrain() '
                '— this is the branch that used to CRASH (RenderFlex overflow) '
                "rather than silently stretch, before the error: branch's own "
                'SingleChildScrollView wrapper was added.',
          );
          expect(height, greaterThan(50));
        },
      );

      testWidgets(
        'loading state DOES fill the remaining viewport — intentional, not a '
        'regression: a future "consistency" refactor that scroll-wraps '
        'loading too must fail this test',
        (tester) async {
          await tester.pumpApp(
            const MyRatingScreen(),
            overrides: <Object>[
              myRatingProvider.overrideWith(
                (ref) => Completer<ClientRating>().future,
              ),
            ],
            height: _kTallViewportHeight,
          );
          await tester.pump();

          final double height = tester
              .getSize(find.byKey(const Key('my_rating_loading')))
              .height;

          expect(
            height,
            greaterThan(_kMinLoadingFillHeight),
            reason:
                'the loading spinner is deliberately CENTERED across the full '
                'remaining tight-constrained height (~2228dp measured at '
                '$_kTallViewportHeight dp viewport) — NOT wrapped in '
                'SingleChildScrollView like the error/data branches. If a '
                'future refactor "for consistency" wraps loading: in a scroll '
                'view too, the spinner would shrink-wrap to its own intrinsic '
                'size (~48dp) and pin to the top instead of staying centred — '
                'this assertion pins the intentional behaviour so that change '
                'gets caught, not shipped as a silent UX regression.',
          );
        },
      );
    },
  );
}

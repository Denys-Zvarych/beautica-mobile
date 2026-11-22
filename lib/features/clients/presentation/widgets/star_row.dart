// M510 — a read-only five-star row, composed of the shipped single-star
// [RatingStar] (REUSE-FIRST): a filled star is `RatingStar(rating: 5)`, an
// empty one `RatingStar(rating: null)`. Decorative — the surrounding row
// carries the screen-reader text.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/shared/widgets/rating_star.dart';

class StarRow extends StatelessWidget {
  const StarRow({super.key, required this.stars, this.size = 16});

  /// Filled stars, 0..5.
  final int stars;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int i = 1; i <= 5; i++)
            RatingStar(
              rating: i <= stars ? 5 : null,
              size: size,
              showLabel: false,
            ),
        ],
      ),
    );
  }
}

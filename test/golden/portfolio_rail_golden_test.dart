// PortfolioRail goldens — phase 404 (9.9). One PNG per scenario (shared
// photo-state harness: allow-listed `media.test` host, fake cache serving a
// solid image), so a later scenario never moves an earlier baseline.
//
//   • portfolio_rail_placeholder — `photos: null`, the pre-404 render. SEED:
//     must never move (the screen goldens pin the same path in context).
//   • portfolio_rail_three_photos — three real tiles (D1).
//   • portfolio_rail_own_empty — owner surface, empty list (D3).
//   • portfolio_rail_error — owner surface, failed read (D2 inline retry).

import 'package:beautica_mobile/core/media/portfolio/portfolio_photo.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/shared/widgets/portfolio_rail.dart';
import 'package:flutter/widgets.dart';

import 'helpers/photo_state_golden.dart';

const Size _kSize = Size(360, 130);

Widget _frame(Widget rail) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
  child: SizedBox(width: double.infinity, child: rail),
);

void main() {
  registerPhotoGoldenMedia();

  photoGolden(
    'portfolio_rail_placeholder',
    () => _frame(const PortfolioRail()),
    size: _kSize,
  );

  photoGolden(
    'portfolio_rail_three_photos',
    () => _frame(
      const PortfolioRail(
        photos: <PortfolioPhoto>[
          PortfolioPhoto(id: 'p1', url: kGoldenAllowedUrl),
          PortfolioPhoto(id: 'p2', url: kGoldenAllowedUrl),
          PortfolioPhoto(id: 'p3', url: kGoldenAllowedUrl),
        ],
      ),
    ),
    size: _kSize,
  );

  photoGolden(
    'portfolio_rail_own_empty',
    () => _frame(const PortfolioRail(photos: <PortfolioPhoto>[])),
    size: _kSize,
  );

  photoGolden(
    'portfolio_rail_error',
    () => _frame(PortfolioRail(onRetry: () {})),
    size: _kSize,
  );
}

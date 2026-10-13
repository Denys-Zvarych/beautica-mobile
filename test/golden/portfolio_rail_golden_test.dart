// PortfolioRail goldens — phase 404 (9.9). One PNG per scenario (shared
// photo-state harness: allow-listed `media.test` host, fake cache serving a
// solid image), so a later scenario never moves an earlier baseline.
//
//   • portfolio_rail_placeholder — `photos: null`, the pre-404 render. SEED:
//     must never move (the screen goldens pin the same path in context).
//   • portfolio_rail_three_photos — three real tiles (D1).
//   • portfolio_rail_own_empty — owner surface, empty list (D3).
//   • portfolio_rail_error — owner surface, failed read (D2 inline retry).
//
// Phase 405 (9.10) — EDITOR scenarios (new PNGs; the four above must not
// move — every read-only caller passes none of the editor params):
//   • portfolio_rail_editor — «Портфоліо · 4/30», add tile, one uploading
//     tile (40 %), one failed tile (retry + discard), then the photos with
//     their remove badges (the second photo sits past the 360 dp edge, as on
//     a phone — the rail scrolls);
//   • portfolio_rail_editor_at_cap — 30 photos: «30/30», NO add tile.

import 'dart:io';

import 'package:beautica_mobile/core/media/portfolio/portfolio_edit_controller.dart'
    show PendingPortfolioUpload;
import 'package:beautica_mobile/core/media/portfolio/portfolio_photo.dart';
import 'package:beautica_mobile/core/media/upload/upload_failure.dart';
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

  // Scratch-shaped path that does not exist → the gradient fallback renders
  // under the overlays (no file I/O in a golden).
  final File scratch = File('/nonexistent/media_upload/kept.jpg');

  photoGolden(
    'portfolio_rail_editor',
    () => _frame(
      PortfolioRail(
        photos: const <PortfolioPhoto>[
          PortfolioPhoto(id: 'p1', url: kGoldenAllowedUrl),
          PortfolioPhoto(id: 'p2', url: kGoldenAllowedUrl),
        ],
        pending: <PendingPortfolioUpload>[
          PendingPortfolioUpload(id: 'u1', file: scratch, progress: 0.4),
          PendingPortfolioUpload(
            id: 'f1',
            file: scratch,
            failure: const UploadNetworkFailure(),
          ),
        ],
        onAdd: () {},
        onDelete: (_) {},
        onRetryPending: (_) {},
        onDiscardPending: (_) {},
        showCount: true,
      ),
    ),
    size: _kSize,
  );

  photoGolden(
    'portfolio_rail_editor_at_cap',
    () => _frame(
      PortfolioRail(
        photos: <PortfolioPhoto>[
          for (int i = 0; i < kPortfolioMaxPhotos; i++)
            PortfolioPhoto(id: 'p$i', url: kGoldenAllowedUrl),
        ],
        onAdd: () {},
        onDelete: (_) {},
        showCount: true,
      ),
    ),
    size: _kSize,
  );
}

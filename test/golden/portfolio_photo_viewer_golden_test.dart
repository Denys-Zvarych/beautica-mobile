// PortfolioPhotoViewer golden — phase 407 (9.12). The viewer chrome on a
// phone-sized box: black backdrop, the photo fitted (contain) in the page,
// the «3 / 3» indicator pill top-left and the close button top-right.
//
//   • portfolio_photo_viewer_3_of_3 — 3 photos, opened on index 2 (the spec's
//     scenario). Shared photo-state harness: allow-listed `media.test` host,
//     fake cache serving a solid image.

import 'package:beautica_mobile/core/media/portfolio/portfolio_photo.dart';
import 'package:beautica_mobile/shared/widgets/portfolio_photo_viewer.dart';
import 'package:flutter/widgets.dart';

import 'helpers/photo_state_golden.dart';

void main() {
  registerPhotoGoldenMedia();

  photoGolden(
    'portfolio_photo_viewer_3_of_3',
    () => const PortfolioPhotoViewer(
      photos: <PortfolioPhoto>[
        PortfolioPhoto(id: 'p1', url: kGoldenAllowedUrl),
        PortfolioPhoto(id: 'p2', url: kGoldenAllowedUrl),
        PortfolioPhoto(id: 'p3', url: kGoldenAllowedUrl),
      ],
      initialIndex: 2,
    ),
    size: const Size(360, 640),
  );
}

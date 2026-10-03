// PhotoThumbnail goldens — phase 072. `photo_thumbnail_default` is the SEED of
// today's render and must never move.

import 'package:beautica_mobile/features/services/presentation/widgets/service_category_list.dart';

import 'package:flutter/widgets.dart' show Size;

import 'helpers/photo_state_golden.dart';

void main() {
  registerPhotoGoldenMedia();

  photoGolden(
    'photo_thumbnail_default',
    () => const PhotoThumbnail(),
    size: const Size(120, 80),
  );

  photoGolden(
    'photo_thumbnail_url',
    () => const PhotoThumbnail(photoUrl: kGoldenAllowedUrl),
    size: const Size(120, 80),
  );
}

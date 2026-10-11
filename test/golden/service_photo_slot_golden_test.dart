// ServicePhotoSlot goldens — phase 072. empty / filled(no real image) /
// non-interactive are the SEED of today's render and must never move.

import 'package:beautica_mobile/features/services/presentation/widgets/service_photo_slot.dart';
import 'package:flutter/widgets.dart';

import 'helpers/photo_state_golden.dart';

Widget _slot(Widget slot) => SizedBox(width: 280, child: slot);

void main() {
  registerPhotoGoldenMedia();

  photoGolden(
    'service_photo_slot_empty',
    () => _slot(ServicePhotoSlot(onTap: () {})),
    size: const Size(360, 300),
  );
  photoGolden(
    'service_photo_slot_filled_placeholder',
    () => _slot(ServicePhotoSlot(imageUrl: 'placeholder', onTap: () {})),
    size: const Size(360, 300),
  );
  photoGolden(
    'service_photo_slot_non_interactive',
    () => _slot(const ServicePhotoSlot()),
    size: const Size(360, 300),
  );

  photoGolden(
    'service_photo_slot_url',
    () => _slot(ServicePhotoSlot(imageUrl: kGoldenAllowedUrl, onTap: () {})),
    size: const Size(360, 300),
  );
  photoGolden(
    'service_photo_slot_uploading_40',
    () => _slot(
      ServicePhotoSlot(
        imageUrl: kGoldenAllowedUrl,
        onTap: () {},
        uploadProgress: 0.4,
      ),
    ),
    size: const Size(360, 300),
  );
  for (final double scale in <double>[1.0, 1.3]) {
    photoGolden(
      'service_photo_slot_failed_${scale == 1.0 ? '1x' : '1_3x'}',
      () => _slot(
        ServicePhotoSlot(
          imageUrl: kGoldenAllowedUrl,
          onTap: () {},
          uploadFailed: true,
          onRetry: () {},
        ),
      ),
      size: const Size(360, 300),
      textScale: scale,
    );
  }
}

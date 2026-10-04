// Phase 9.7 goldens — master photo variants of SalonMasterCard and
// MasterAvatarBadge. Existing (null) baselines for the hosting widgets are
// deliberately untouched; these are NEW files only.

import 'package:beautica_mobile/features/booking/presentation/widgets/master_avatar_badge.dart';
import 'package:beautica_mobile/features/salon/presentation/widgets/salon_master_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_media_cache.dart';
import 'helpers/photo_state_golden.dart';
import 'package:beautica_mobile/core/media/beautica_image.dart';

Widget _card(String? url) => SizedBox(
  width: 170,
  height: kSalonMasterCardHeight,
  child: SalonMasterCard(
    name: 'Олена',
    role: 'Майстер',
    ratingLabel: '4.9',
    avatarIndex: 1,
    imageUrl: url,
    onTap: () {},
  ),
);

void main() {
  registerPhotoGoldenMedia();

  photoGolden('salon_master_card_no_photo', () => _card(null));
  // Phase 368 — worst case at 1.3x: long name, 2-line professional title,
  // rating and photo, in the 320dp-phone column width. The card sizes itself
  // via [salonMasterCardHeight], so it must not overflow (alchemist fails the
  // golden on an overflow exception).
  photoGolden(
    'salon_master_card_worst_case_1_3x',
    () => SizedBox(
      width: 128,
      child: SalonMasterCard(
        name: 'Олександрина-Емілія',
        role: 'Топ-стиліст з фарбування та догляду за волоссям',
        ratingLabel: '4.8',
        avatarIndex: 1,
        imageUrl: kGoldenAllowedUrl,
        onTap: () {},
      ),
    ),
    textScale: 1.3,
  );
  photoGolden('salon_master_card_photo', () => _card(kGoldenAllowedUrl));
  photoGolden(
    'salon_master_card_photo_disallowed_host',
    () => _card(kGoldenDisallowedUrl),
  );
  photoGolden(
    'master_avatar_badge_no_photo',
    () => const MasterAvatarBadge(),
    size: const Size(120, 120),
  );
  photoGolden(
    'master_avatar_badge_photo',
    () => const MasterAvatarBadge(imageUrl: kGoldenAllowedUrl),
    size: const Size(120, 120),
  );
  photoGolden(
    'master_avatar_badge_photo_bordered',
    () => const MasterAvatarBadge(imageUrl: kGoldenAllowedUrl, bordered: true),
    size: const Size(120, 120),
  );

  group('load error', () {
    setUp(
      () => debugMediaCacheManager = FakeMediaCacheManager(mediaFetchError),
    );
    photoGolden(
      'salon_master_card_photo_load_error',
      () => _card(kGoldenAllowedUrl),
    );
    photoGolden(
      'master_avatar_badge_photo_load_error',
      () => const MasterAvatarBadge(imageUrl: kGoldenAllowedUrl),
      size: const Size(120, 120),
    );
  });
}

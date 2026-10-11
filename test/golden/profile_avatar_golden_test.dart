// ProfileAvatar goldens — phase 072. `profile_avatar_default` is the SEED of
// today's no-URL render and must never move; the URL cases are additive.

import 'package:beautica_mobile/features/master/presentation/widgets/profile_avatar.dart';

import 'helpers/photo_state_golden.dart';

void main() {
  registerPhotoGoldenMedia();

  photoGolden('profile_avatar_default', () => const ProfileAvatar());

  photoGolden(
    'profile_avatar_url',
    () => const ProfileAvatar(imageUrl: kGoldenAllowedUrl),
  );
  // A non-allow-listed host must render today's icon well (and fetch nothing).
  photoGolden(
    'profile_avatar_disallowed_url',
    () => const ProfileAvatar(imageUrl: kGoldenDisallowedUrl),
  );
}

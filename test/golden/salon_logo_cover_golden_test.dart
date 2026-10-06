// Phase 369 (9.8) goldens — the salon logo / cover photo variants and the
// owner-only edit affordances. NEW files only: the pre-369 monogram /
// gradient baselines (salon_hub_card, public_salon_profile, …) are untouched
// and still pass byte-identically, which is the proof the change is additive.

import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/core/widgets/upload_state_overlay.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/notifications/presentation/unread_notifications_notifier.dart';
import 'package:beautica_mobile/features/salon/application/my_salons_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_management_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_management_profile_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/widgets/salon_cover_widgets.dart';
import 'package:beautica_mobile/features/salon/presentation/widgets/salon_media_editors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_media_cache.dart';
import '../helpers/fakes/fake_secure_storage.dart';
import 'helpers/photo_state_golden.dart';

const String _kSalonId = 'salon-1';

Widget _logo({String? url, Widget? overlay, bool badge = false}) => SalonLogo(
  diameter: 68,
  monogram: 'В',
  imageUrl: url,
  overlay: overlay,
  editBadge: badge
      ? PhotoEditBadge(
          size: kSalonLogoBadgeSize,
          badgeKey: const Key('salon-logo-edit-badge'),
          onTap: () {},
        )
      : null,
);

Widget _cover({String? url, Widget? overlay}) => SizedBox(
  width: 360,
  child: SalonCover(height: 203, topInset: 0, imageUrl: url, overlay: overlay),
);

const Salon _salon = Salon(
  id: _kSalonId,
  name: 'Салон «Вельвет»',
  street: 'вул. Велика Васильківська',
  buildingNo: '44',
  avgRating: 4.9,
  reviewCount: 128,
  avatarUrl: kGoldenAllowedUrl,
  coverImageUrl: kGoldenAllowedUrl,
);

UserRole _role = UserRole.salonOwner;

class _Auth extends AuthNotifier {
  @override
  Future<AuthSession> build() async => AuthSession.authenticated(
    user: User(
      id: 'viewer-1',
      email: 'v@beautica.ua',
      role: _role,
      firstName: 'Оксана',
      lastName: 'Швець',
      salonId: _role == UserRole.salonAdmin ? _kSalonId : null,
    ),
    accessToken: 't',
  );
}

class _Manage extends SalonManagementProfile {
  @override
  Future<SalonManagementProfileData> build(String salonId) async =>
      (_salon, const <SalonStaffMember>[]);
}

class _MySalons extends MySalons {
  @override
  Future<List<Salon>> build() async => const <Salon>[_salon];
}

List<Object> _screenOverrides() => <Object>[
  authProvider.overrideWith(_Auth.new),
  salonManagementProfileProvider.overrideWith(_Manage.new),
  mySalonsProvider.overrideWith(_MySalons.new),
  hasUnreadNotificationsProvider.overrideWithValue(false),
  secureStorageProvider.overrideWithValue(FakeSecureStorage()),
];

void main() {
  registerPhotoGoldenMedia();

  // ── SalonLogo ─────────────────────────────────────────────────────────────
  photoGolden('salon_logo_monogram', _logo, size: const Size(120, 120));
  photoGolden(
    'salon_logo_photo',
    () => _logo(url: kGoldenAllowedUrl),
    size: const Size(120, 120),
  );
  photoGolden(
    'salon_logo_photo_disallowed_host',
    () => _logo(url: kGoldenDisallowedUrl),
    size: const Size(120, 120),
  );
  photoGolden(
    'salon_logo_owner_badge',
    () => _logo(url: kGoldenAllowedUrl, badge: true),
    size: const Size(120, 120),
  );
  photoGolden(
    'salon_logo_owner_uploading',
    () => _logo(
      url: kGoldenAllowedUrl,
      badge: true,
      overlay: const UploadProgressOverlay(progress: 0.4, circular: true),
    ),
    size: const Size(120, 120),
  );

  // ── SalonCover ────────────────────────────────────────────────────────────
  photoGolden('salon_cover_gradient', _cover, size: const Size(360, 203));
  photoGolden(
    'salon_cover_photo',
    () => _cover(url: kGoldenAllowedUrl),
    size: const Size(360, 203),
  );
  photoGolden(
    'salon_cover_uploading',
    () => _cover(
      url: kGoldenAllowedUrl,
      overlay: const UploadProgressOverlay(progress: 0.6),
    ),
    size: const Size(360, 203),
  );
  photoGolden(
    'salon_cover_failed',
    () => _cover(
      url: kGoldenAllowedUrl,
      overlay: UploadFailedOverlay(onRetry: () {}, showMessage: true),
    ),
    size: const Size(360, 203),
  );

  group('load error', () {
    setUp(
      () => debugMediaCacheManager = FakeMediaCacheManager(mediaFetchError),
    );
    photoGolden(
      'salon_logo_photo_load_error',
      () => _logo(url: kGoldenAllowedUrl),
      size: const Size(120, 120),
    );
    photoGolden(
      'salon_cover_photo_load_error',
      () => _cover(url: kGoldenAllowedUrl),
      size: const Size(360, 203),
    );
  });

  // ── Management hero: owner (badges) vs admin (none) ───────────────────────
  for (final (String name, UserRole role) in <(String, UserRole)>[
    ('salon_manage_hero_owner_badges', UserRole.salonOwner),
    ('salon_manage_hero_admin_no_badges', UserRole.salonAdmin),
  ]) {
    group(name, () {
      setUp(() => _role = role);
      photoGolden(
        name,
        () => const SalonManagementProfileScreen(salonId: _kSalonId),
        size: const Size(360, 460),
        overrides: _screenOverrides(),
      );
    });
  }
}

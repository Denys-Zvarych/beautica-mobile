// Phase 363 — pixel baseline for the «Сповіщення» feed screen.
//
// DRIFT GUARD, NOT ACCEPTANCE. The acceptance for this screen is the user's
// side-by-side review against the approved preview
// (`docs/signup-designs/NotificationsFeed/`) and the compact-card direction of
// 2026-09-30 — a golden generated from the code under review is a picture of
// that code. What these PNGs do pin is the RENDER of the shared primitives the
// row is built from (`PressableSurface`, `NeumorphicGlyphWell`,
// `NeumorphicIconButton(faceSize:)`, `VelvetShadows.flushSmall`,
// `SectionHeader`), so a later edit to any of them that moves this screen shows
// up here.
//
// SCENARIOS (one width, both text scales)
//   • mixed — a provider's feed: an unread row with the ✓ and a salon label,
//     an unread multi-service row, a READ row pressed flush, a NoTarget row,
//     across three day groups («Сьогодні», «Вчора», a dated header). The mark-all
//     strip is showing (unread > 0).
//   • empty — the empty state: the inset bell disc and the «what will arrive»
//     sub-line.
//
// The clock is pinned (`clockProvider`), and the fake repository answers
// without a network, so the render is byte-stable.

import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/notifications/data/notification_repository.dart';
import 'package:beautica_mobile/features/notifications/domain/app_notification.dart';
import 'package:beautica_mobile/features/notifications/presentation/notifications_screen.dart';
import 'package:beautica_mobile/features/notifications/presentation/unread_notifications_notifier.dart';
import '../helpers/fakes/fake_notification_repository.dart';
import 'helpers/golden_pump.dart';

final DateTime _now = DateTime.utc(2026, 9, 30, 12);

NotificationParams _params({
  String counterpart = 'Олена Коваль',
  String service = 'Манікюр',
  int count = 1,
  String? salon,
}) => NotificationParams(
  counterpartName: counterpart,
  serviceName: service,
  serviceCount: count,
  startsAt: DateTime.utc(2026, 10, 3, 11, 30),
  salonName: salon,
);

List<AppNotification> _mixed() => <AppNotification>[
  notif(
    'u1',
    createdAt: DateTime.utc(2026, 9, 30, 11, 40),
    params: _params(salon: 'Beautica Центр'),
  ),
  notif(
    'u2',
    type: AppNotificationType.bookingRescheduled,
    createdAt: DateTime.utc(2026, 9, 30, 9, 5),
    params: _params(counterpart: 'Марія Іванюк', service: 'Стрижка', count: 3),
  ),
  notif(
    'r1',
    type: AppNotificationType.reviewReceived,
    read: true,
    createdAt: DateTime.utc(2026, 9, 29, 15, 20),
    params: _params(counterpart: 'Ірина Мельник', service: 'Педикюр'),
  ),
  notif(
    'gone',
    type: AppNotificationType.bookingCancelledByClient,
    createdAt: DateTime.utc(2026, 9, 29, 8, 10),
    params: NotificationParams.empty,
    target: const NotificationTarget.none(),
  ),
  notif(
    'r2',
    type: AppNotificationType.inviteAccepted,
    read: true,
    createdAt: DateTime.utc(2026, 9, 28, 10),
    params: const NotificationParams(
      subjectName: 'Оксана',
      subjectRole: 'SALON_MASTER',
      salonName: 'Beautica Оболонь',
    ),
    target: const NotificationTarget.salonTeam(salonId: 's2'),
  ),
];

List<Object> _overrides(List<AppNotification> items, int unread) => <Object>[
  authProvider.overrideWith(() => FixedRoleAuth(UserRole.salonOwner)),
  notificationRepositoryProvider.overrideWithValue(
    FakeNotificationRepository(pages: <NotificationPage>[onePage(items)]),
  ),
  unreadNotificationsProvider.overrideWith(() => RecordingUnread(unread)),
  clockProvider.overrideWithValue(() => _now),
];

void main() {
  const double width = 360;

  for (final double scale in kGoldenTextScales) {
    goldenTest(
      'notifications — mixed list ${width.toInt()}dp x$scale',
      fileName: 'notifications_mixed_${widthScaleSuffix(width, scale)}',
      constraints: BoxConstraints.tight(const Size(width, 640)),
      textScaleFactor: scale,
      pumpWidget: goldenPumpWidget(
        width: width,
        overrides: _overrides(_mixed(), 2),
      ),
      builder: () => const NotificationsScreen(),
    );

    goldenTest(
      'notifications — empty ${width.toInt()}dp x$scale',
      fileName: 'notifications_empty_${widthScaleSuffix(width, scale)}',
      constraints: BoxConstraints.tight(const Size(width, 640)),
      textScaleFactor: scale,
      pumpWidget: goldenPumpWidget(
        width: width,
        overrides: _overrides(const <AppNotification>[], 0),
      ),
      builder: () => const NotificationsScreen(),
    );
  }
}

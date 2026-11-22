// MOD-39 / CLI-70 — the client card / «Рейтинг клієнта» avatar's
// «Поскаржитися» in the full-screen photo viewer (target CLIENT_PROFILE).
//
// One gate for both screens: providers only (a client never reaches these
// screens; MOD-35 «a client photo only for providers»), registered clients
// only (a guest has no account and no photo). Own photo and already-reported
// are hidden inside [profilePhotoReport] itself.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/clients/domain/client_summary.dart';
import 'package:beautica_mobile/features/moderation/domain/content_report.dart';
import 'package:beautica_mobile/features/moderation/presentation/widgets/report_sheet.dart'
    show profilePhotoReport;
import 'package:beautica_mobile/shared/widgets/portfolio_photo_viewer.dart'
    show PhotoViewerReport;

/// The viewer report for [client]'s avatar as seen by [role], or `null` (no
/// report button) for a signed-out / client viewer or a guest.
PhotoViewerReport? clientPhotoReport(
  UserRole? role,
  ClientRef client, {
  required String name,
}) {
  if (role == null || role == UserRole.client) return null;
  return switch (client) {
    RegisteredClientRef(:final String userId) => profilePhotoReport(
      targetType: ReportTargetType.clientProfile,
      targetId: userId,
      name: name,
    ),
    GuestClientRef() => null,
  };
}

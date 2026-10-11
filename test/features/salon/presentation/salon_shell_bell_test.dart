// Phase 361 — the owner's bell on the salon shell header is the SAME global
// dot for every owned salon.
//
// The unread count is per USER (never per salon). These tests drive the REAL
// `hasUnreadNotificationsProvider` over a stubbed `unreadNotificationsProvider`
// (so the boolean derivation is exercised, not overridden) and mount the salon
// shell for two different owned salons:
//   * both shells show the dotted bell for the same count;
//   * switching the active salon keeps the dot AND never rebuilds/refetches the
//     unread notifier (a salon-scoped read would).

import 'dart:async';

import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/notifications/presentation/unread_notifications_notifier.dart';
import 'package:beautica_mobile/features/salon/application/my_salons_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_management_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_shell_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/widgets/salon_cover_widgets.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/test_container.dart';

const String _kSalonA = 'bell-salon-a';
const String _kSalonB = 'bell-salon-b';

const _salonA = Salon(id: _kSalonA, name: 'Салон А');
const _salonB = Salon(id: _kSalonB, name: 'Салон Б');

const _owner = User(
  id: 'bell-owner-1',
  email: 'owner@beautica.ua',
  role: UserRole.salonOwner,
  firstName: 'Оксана',
  lastName: 'Власник',
);

class _OwnerAuth extends AuthNotifier {
  @override
  Future<AuthSession> build() async =>
      const AuthSession.authenticated(user: _owner, accessToken: 'tok');
}

class _OwnsBoth extends MySalons {
  @override
  Future<List<Salon>> build() async => const <Salon>[_salonA, _salonB];
}

class _SettledProfileA extends SalonManagementProfile {
  @override
  Future<SalonManagementProfileData> build(String salonId) async =>
      (_salonA, const <SalonStaffMember>[]);
}

class _SettledProfileB extends SalonManagementProfile {
  @override
  Future<SalonManagementProfileData> build(String salonId) async =>
      (_salonB, const <SalonStaffMember>[]);
}

/// Unread count 3, with a build counter — a salon-scoped watch would rebuild
/// (and so re-count) this notifier when the shell's salon changes.
class _CountingUnread extends UnreadNotifications {
  static int builds = 0;

  @override
  FutureOr<int> build() {
    builds++;
    return 3;
  }
}

List<Object> _overrides() => <Object>[
  authProvider.overrideWith(_OwnerAuth.new),
  mySalonsProvider.overrideWith(_OwnsBoth.new),
  salonManagementProfileProvider(_kSalonA).overrideWith(_SettledProfileA.new),
  salonManagementProfileProvider(_kSalonB).overrideWith(_SettledProfileB.new),
  unreadNotificationsProvider.overrideWith(_CountingUnread.new),
];

Widget _app(ProviderContainer container, String salonId) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
        home: SalonShellScreen(salonId: salonId),
      ),
    );

ProviderContainer _container() {
  // `_overrides()` pins its own `unreadNotificationsProvider` (a counting
  // double), which wins over the helper's zero default.
  return makeTestContainer(overrides: _overrides());
}

CoverIconButton _bell(WidgetTester tester) => tester.widget<CoverIconButton>(
  find.byKey(const Key('salon-manage-notifications')),
);

void main() {
  setUp(() => _CountingUnread.builds = 0);

  testWidgets('should_showSameGlobalDot_acrossBothOwnedSalonShells', (
    tester,
  ) async {
    final ProviderContainer container = _container();
    await container.read(authProvider.future);
    for (final String salonId in <String>[_kSalonA, _kSalonB]) {
      // Unmount between shells so each salon gets a FRESH mount.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_app(container, salonId));
      await tester.pumpAndSettle();

      expect(
        _bell(tester).svgIcon,
        BeauticaAssetIcons.notificationUnread,
        reason: 'shell for $salonId must show the global unread dot',
      );
    }
  });

  testWidgets('should_keepDot_when_switchingActiveSalon', (tester) async {
    final ProviderContainer container = _container();
    await container.read(authProvider.future);

    await tester.pumpWidget(_app(container, _kSalonA));
    await tester.pumpAndSettle();
    expect(_bell(tester).svgIcon, BeauticaAssetIcons.notificationUnread);
    final int buildsBefore = _CountingUnread.builds;
    expect(buildsBefore, greaterThan(0));

    await tester.pumpWidget(_app(container, _kSalonB));
    await tester.pumpAndSettle();

    expect(_bell(tester).svgIcon, BeauticaAssetIcons.notificationUnread);
    expect(
      _CountingUnread.builds,
      buildsBefore,
      reason:
          'switching the active salon must not rebuild/refetch the global '
          'unread count',
    );
  });
}

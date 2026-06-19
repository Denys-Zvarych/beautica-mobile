// Location-fix — clientProfile provider unit tests.
//
// The home hub derives [ClientProfileSummary] from the authenticated session's
// [User] (hydrated via repo.me() → UserMapper.fromProfileDto, which now carries
// cityName / phoneNumber). These tests pin the city/phone wiring:
//   • cityName="Київ" / phoneNumber set ⇒ summary.city/phone reflect them.
//   • cityName=null (CLIENT with no location) ⇒ summary.city == '' so the
//     profile card renders its placeholder path.
//
// Strategy: override authProvider with a fixed authenticated session and read
// clientProfileProvider.future from a ProviderContainer (no widget tree).

import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Auth stub
// ---------------------------------------------------------------------------

/// Stubs [authProvider] to a settled, authenticated session carrying [user].
class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this._user);

  final User _user;

  @override
  Future<AuthSession> build() async {
    final session = AuthSession.authenticated(
      user: _user,
      accessToken: 'token',
    );
    state = AsyncData(session);
    return session;
  }
}

ProviderContainer _containerForUser(User user) {
  final container = ProviderContainer(
    overrides: [authProvider.overrideWith(() => _FixedAuthNotifier(user))],
  );
  addTearDown(container.dispose);
  return container;
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _userWithCity = User(
  id: 'usr-1',
  email: 'olena@beautica.test',
  role: UserRole.client,
  firstName: 'Олена',
  lastName: 'Тест',
  cityName: 'Київ',
  phoneNumber: '+380 97 000 00 00',
);

const _userNoCity = User(
  id: 'usr-2',
  email: 'noloc@beautica.test',
  role: UserRole.client,
  firstName: 'Без',
  lastName: 'Міста',
  // cityName / phoneNumber intentionally null — CLIENT location is optional.
);

void main() {
  group('clientProfile provider', () {
    test(
      'cityName="Київ" ⇒ summary.city == "Київ" and phone is wired',
      () async {
        final container = _containerForUser(_userWithCity);

        final summary = await container.read(clientProfileProvider.future);

        expect(summary.city, 'Київ');
        expect(summary.phone, '+380 97 000 00 00');
        expect(summary.firstName, 'Олена');
        expect(summary.lastName, 'Тест');
      },
    );

    test('null cityName ⇒ summary.city == "" (placeholder path)', () async {
      final container = _containerForUser(_userNoCity);

      final summary = await container.read(clientProfileProvider.future);

      expect(
        summary.city,
        '',
        reason:
            'a CLIENT with no city must yield an empty string so the profile '
            'card renders its l10n placeholder instead of "null"',
      );
      expect(summary.phone, '');
    });
  });
}

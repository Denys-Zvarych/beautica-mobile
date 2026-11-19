// M521 (B520, AUTH-21 / AUTH-52) — unit tests for the accept-invite validate
// step ([AcceptInviteNotifier]) and the masked-phone pre-check
// ([InviteDetails.phoneMayMatch]) the phone step runs before any SMS.
//
// The phone → code → ticket → accept sequence itself lives in the screen
// (the ticket never leaves screen memory) and is covered by
// `test/features/auth/presentation/accept_invite_screen_test.dart` (8–9b).

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/invite_details.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/state/accept_invite_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/test_container.dart';

InviteDetails _invite(String masked) => InviteDetails(
  phoneMasked: masked,
  salonName: 'Salon Lumière',
  role: UserRole.salonAdmin,
  expiresAt: DateTime.utc(2030),
);

void main() {
  group('AcceptInviteNotifier (validate)', () {
    test('exposes the masked phone, salon and role the repository '
        'returned, for the token it was built with', () async {
      final repo = FakeAuthRepository()
        ..validateInviteResult = _invite('+380 •• ••• •• 45');
      final container = makeTestContainer(
        overrides: [authRepositoryProvider.overrideWith((_) => repo)],
      );

      final InviteDetails details = await container.read(
        acceptInviteProvider('tok-1').future,
      );

      expect(repo.validateInviteCalls, <String>['tok-1']);
      expect(details.phoneMasked, '+380 •• ••• •• 45');
      expect(details.salonName, 'Salon Lumière');
      expect(details.role, UserRole.salonAdmin);
    });

    test('an invalid / expired token surfaces as AsyncError with the '
        'typed failure', () async {
      final repo = FakeAuthRepository()
        ..validateInviteResult = const ValidationFailure(
          fieldErrors: <String, String>{},
        );
      final container = makeTestContainer(
        overrides: [authRepositoryProvider.overrideWith((_) => repo)],
      );

      await expectLater(
        container.read(acceptInviteProvider('dead').future),
        throwsA(isA<ValidationFailure>()),
      );
    });
  });

  group('InviteDetails.phoneMayMatch (masked-tail pre-check)', () {
    test('matching visible tail → may match', () {
      expect(
        _invite('+380 •• ••• •• 45').phoneMayMatch('+380671234545'),
        isTrue,
      );
    });

    test('different visible tail → certain mismatch', () {
      expect(
        _invite('+380 •• ••• •• 45').phoneMayMatch('+380671234599'),
        isFalse,
      );
    });

    test('a mask with no visible digits at its end never blocks', () {
      expect(_invite('').phoneMayMatch('+380671234599'), isTrue);
      expect(
        _invite('+380 •• ••• •• ••').phoneMayMatch('+380671234599'),
        isTrue,
      );
    });
  });
}

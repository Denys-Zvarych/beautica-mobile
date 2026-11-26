// M544 audit — the undo snack's same-session guard, tested DIRECTLY (no
// snack, no dismissal): «Повернути» bound to user A never runs once the
// signed-in user is B (security INFO, client_removed_snack.dart).

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/client_removed_snack.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/fakes/fake_notification_repository.dart';
import '../../../../helpers/test_container.dart';

void main() {
  late FixedRoleAuth auth;
  late ProviderContainer container;

  setUp(() async {
    auth = FixedRoleAuth(UserRole.independentMaster);
    container = makeTestContainer(
      overrides: <Object>[authProvider.overrideWith(() => auth)],
    );
    await container.read(authProvider.future);
  });

  String? signedIn() => authUserIdOrNull(container.read(authProvider));

  test('same user: the undo runs (restore is called)', () {
    int restores = 0;
    final VoidCallback undo = sameSessionUndo(
      container,
      signedIn(),
      () => restores++,
    );
    undo();
    expect(restores, 1);
  });

  test('another user signed in: the undo does nothing (no restore)', () {
    int restores = 0;
    final VoidCallback undo = sameSessionUndo(
      container,
      signedIn(),
      () => restores++,
    );
    auth.switchUser('someone-else');
    undo();
    expect(restores, 0);
  });
}

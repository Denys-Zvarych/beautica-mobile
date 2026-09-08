// Shared fake [UserRepository] for widget tests — mobile-qa, delete-account
// coverage gap-closure (2026-09-08). Mirrors `fake_salon_repository.dart`'s
// shape: a call counter, an injectable [Failure], and a [Completer] gate so a
// test can observe an in-flight call across a real awaited frame (needed for
// the "spinner is post-consent only" and double-tap-guard tests on
// `runDeleteAccountFlow`).
//
// [updateLocality] is UNIMPLEMENTED — no delete-account test exercises it,
// and every OTHER caller of [UserRepository] in this codebase already goes
// through the real `HttpUserRepository` or a screen-scoped fake of its own,
// so this file stays narrowly scoped to what the delete-account tests need
// rather than growing a second general-purpose user-repository fake.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/user/data/user_repository.dart';

class FakeUserRepository implements UserRepository {
  /// `DELETE /api/v1/users/me` call count.
  int deleteMyAccountCalls = 0;

  /// When set, [deleteMyAccount] throws this instead of succeeding.
  Failure? deleteMyAccountError;

  /// When non-null, [deleteMyAccount] blocks on this until the test
  /// completes it — the only way to observe the in-flight spinner / guard
  /// across a real awaited frame instead of a call resolving synchronously
  /// within one microtask (mirrors `FakeSalonRepository.deleteSalonGate`).
  Completer<void>? deleteMyAccountGate;

  @override
  Future<void> deleteMyAccount() async {
    deleteMyAccountCalls++;
    final Completer<void>? gate = deleteMyAccountGate;
    if (gate != null) await gate.future;
    if (deleteMyAccountError != null) throw deleteMyAccountError!;
  }

  @override
  Future<void> updateLocality({
    required String cityId,
    String? districtId,
    String? street,
    String? buildingNo,
    String? locationNote,
  }) async {
    throw UnimplementedError(
      'FakeUserRepository.updateLocality is not exercised by the '
      'delete-account tests this fake was built for.',
    );
  }
}

// Phase 2.20 — AcceptInviteNotifier.
//
// Auto-dispose family provider: the token is the family argument.
// `build()` validates the invite token against the backend and exposes the
// resulting [InviteDetails] (or an AsyncError if the token is invalid/expired).
// The notifier does NOT own the accept action — that is handled by
// [AuthNotifier.acceptInvite] so the session transition is centralised.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/auth_repository_provider.dart';
import '../domain/invite_details.dart';

part 'accept_invite_notifier.g.dart';

/// Validates [token] against `GET /auth/invite/validate` and exposes the
/// resulting [InviteDetails] as an [AsyncValue].
///
/// Auto-disposed when the screen is removed from the tree — the token is
/// single-use and there is no benefit in keeping the validation result alive
/// beyond the screen's lifetime.
///
/// Generated provider name: `acceptInviteNotifierProvider` (family).
@riverpod
class AcceptInviteNotifier extends _$AcceptInviteNotifier {
  @override
  FutureOr<InviteDetails> build(String token) =>
      ref.read(authRepositoryProvider).validateInvite(token: token);
}

// Invite-accept post-success design (2026-09-01) — LoginNoticeNotifier.
//
// Carries a one-shot, terminal hand-off from a spent/unreachable invite
// (or verification) flow into the login screen: an [InviteHandoffReason]
// plus the invited email, so the login screen can prefill the email field
// and show the right non-"try again" copy.
//
// A PROVIDER — deliberately not go_router `extra` — because it is written
// BEFORE the login screen mounts (`context.go` triggers a full rebuild, and
// `extra` is keyed to the specific navigation call, not to "whoever lands on
// /login next"). A provider is immune to who navigates (the screen calling
// `.show()` directly, vs. a router redirect) so the notice cannot be lost or
// duplicated in a race. `keepAlive` for the same reason: it must survive
// until the login screen's first frame reads and clears it.
//
// No new PII surface: the payload is an enum plus an email the user just
// typed into the invite-accept form themselves.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/errors/failures.dart';

part 'login_notice_notifier.g.dart';

/// The payload [LoginNotice] holds: why the user was handed off to /login,
/// and — if known — the email to prefill.
typedef LoginNoticeState = ({InviteHandoffReason reason, String? email});

/// Riverpod notifier holding a pending [LoginNoticeState] for the login
/// screen to consume.
///
/// `null` when there is nothing to show (the ordinary case). Set by
/// [AcceptInviteScreen] when [AuthNotifier.acceptInvite] surfaces an
/// [InviteHandoffFailure]; read and cleared by [LoginScreen] on its first
/// frame.
@Riverpod(keepAlive: true)
class LoginNotice extends _$LoginNotice {
  @override
  LoginNoticeState? build() => null;

  /// Records a pending hand-off notice. [email] is the address the user was
  /// invited on / just typed, if known.
  void show(InviteHandoffReason reason, {String? email}) {
    state = (reason: reason, email: email);
  }

  /// Clears the notice. Called by [LoginScreen] after its first frame so a
  /// later, unrelated login never re-shows a stale notice.
  void clear() {
    state = null;
  }
}

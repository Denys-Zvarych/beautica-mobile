// M517 (AUTH-D13, AUTH-D19, CLI-04) — the ONE phone-change sequence every
// «Контакти» screen runs (client, admin, independent master, salon master):
// SMS code to the NEW number → the shared code step with the current password
// → the session refresh. The old number stays (login, provider view) until the
// new one is confirmed; nothing is written before that.
//
// A profile save no longer changes the phone (backend B516 PhoneChangeGuard:
// any other number on `PATCH` is 400 PHONE_CHANGE_REQUIRES_OTP), so the
// screens call this instead of sending the new number in their PATCH.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/single_flight.dart';
import '../../../routing/route_names.dart';
import '../domain/contact_verify_args.dart';
import 'auth_notifier.dart';

/// Sends the SMS code to [normalizedPhone] (`+380…`) and opens the code step.
/// Resolves `true` once the new number is confirmed (the session user then
/// refreshes after the caller's navigation), `false` when the user backed
/// out. The caller must leave the screen with `go` on `true`.
///
/// Throws the send's typed failure (e.g. `PhoneIdentityFailure` for a non-UA
/// number, a 429 or App Check) for the caller to render on its phone field.
Future<bool> runPhoneChangeFlow(
  BuildContext context,
  WidgetRef ref, {
  required String normalizedPhone,
}) async {
  final AuthNotifier auth = ref.read(authProvider.notifier);
  await auth.sendPhoneCode(phone: normalizedPhone);
  if (!context.mounted) return false;
  // Always a CHANGE here: an account without a verified phone never reaches a
  // «Контакти» screen — the auth redirect holds it on the blocking add-phone
  // step (AUTH-D12), which runs the code-only first add itself.
  final bool? confirmed = await context.pushOnce<bool>(
    RouteNames.phoneChangeVerify,
    extra: ContactVerifyArgs(
      kind: ContactVerifyKind.phoneChange,
      target: normalizedPhone,
    ),
  );
  if (confirmed != true) return false;
  // The caller navigates away next (go); the session (new phone) refreshes
  // now — a profile-only emission does not refresh the router (see
  // AuthRefreshNotifier / authRouterKey), so it cannot disturb that go.
  unawaited(auth.refreshUser());
  return true;
}

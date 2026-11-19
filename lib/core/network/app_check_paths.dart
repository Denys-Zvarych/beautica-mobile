// M515 (AUTH-D14 / AUTH-54) — the SMS-sending endpoints that carry a Firebase
// App Check token in `X-Firebase-AppCheck`. Pattern of `auth_paths.dart`.
//
// Listed once here for the whole phone-first PR: M517 (phone add / change,
// forgot-password) and M521 (staff invites) reuse this list and add nothing.
// Every OTHER request goes out WITHOUT the header — a token is a short-lived
// credential and is only sent where the backend asks for it.

/// Exact request paths (no query string) that send an SMS.
const Set<String> kAppCheckPaths = <String>{
  '/api/v1/auth/register/phone/otp/send',
  '/api/v1/users/me/phone/otp/send',
  '/api/v1/auth/forgot-password',
  '/api/v1/users/me/change-password/request-otp',
  '/api/v1/auth/invite',
};

/// `/api/v1/salons/{salonId}/invite` — the one dynamic SMS-sending path.
final RegExp _kSalonInvitePath = RegExp(r'^/api/v1/salons/[^/?]+/invite$');

/// Whether [path] (query string ignored) is an SMS-sending endpoint that
/// carries an App Check token.
bool isAppCheckPath(String path) {
  final int q = path.indexOf('?');
  final String base = q == -1 ? path : path.substring(0, q);
  return kAppCheckPaths.contains(base) || _kSalonInvitePath.hasMatch(base);
}

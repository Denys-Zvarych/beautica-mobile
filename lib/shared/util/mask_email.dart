// Phase 2.11 (backlog row 160 gate-crossed) — shared email masking helper.
//
// Originally lived inside `verification_screen.dart` as a private method.
// Extracted here so that [AuthNotifier]'s debug-only `log()` calls can also
// redact PII before printing to the developer console — without copy-pasting
// the same logic in two places.
//
// Behaviour:
//   - `anya@example.com`     → `a***@example.com`
//   - `a@example.com`        → `a***@example.com`
//   - `@example.com`         → `@example.com`   (no local part to redact)
//   - `not-an-email`         → `not-an-email`   (no `@`, returned as-is)
//   - empty string           → empty string

/// Returns [email] with the local part redacted to its first character + `***`.
///
/// Used both in the verification screen UI (to render the recipient in
/// `card-desc`) and in the auth notifier debug logs (to avoid leaking raw
/// PII to the developer console).
String maskEmail(String email) {
  final atIdx = email.indexOf('@');
  if (atIdx <= 0) return email;
  final local = email.substring(0, atIdx);
  final domain = email.substring(atIdx);
  if (local.isEmpty) return email;
  return '${local[0]}***$domain';
}

// M517 — what the shared contact-code step confirms. Carried in go_router
// `extra` (never the URL: a phone / email is PII and query strings reach logs).
//
// Pure Dart.

/// The three contact confirmations the M517 code step serves.
enum ContactVerifyKind {
  /// First phone add (AUTH-D12): SMS code only, no current password
  /// (AUTH-D19) — includes replacing an unverified legacy profile phone.
  phoneAdd,

  /// Phone CHANGE (AUTH-D13): SMS code + current password (AUTH-D19).
  phoneChange,

  /// Notifications email add or change (AUTH-50): emailed code + current
  /// password (AUTH-D19).
  notificationEmail,
}

/// Arguments of the contact-code step: [kind] and the normalised [target]
/// (`+380…` phone, or the trimmed email).
final class ContactVerifyArgs {
  const ContactVerifyArgs({required this.kind, required this.target});

  final ContactVerifyKind kind;
  final String target;

  /// Whether the step asks for the current password (AUTH-D19).
  bool get requiresCurrentPassword => kind != ContactVerifyKind.phoneAdd;
}

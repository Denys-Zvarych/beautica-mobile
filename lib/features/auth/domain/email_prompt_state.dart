// M517 (AUTH-D17, CLI-D09) — the device-local state of the dismissible email
// prompts for ONE account, and the decisions that read it.
//
//   (b) CLIENT booking-success card: shown once, ever ([clientCardShown] is
//       set on the first show).
//
// The provider home card (former (c)) was removed 2026-11-19; any stale
// `providerHiddenAt` / `providerRetired` keys a device still holds are
// ignored on read and dropped on the next write.
//
// Pure Dart.

/// Email-prompt state for one account (see the file header).
final class EmailPromptState {
  const EmailPromptState({this.clientCardShown = false});

  /// Parses one entry of the stored JSON map; anything malformed reads as the
  /// default (the prompt may show once more — never a crash).
  factory EmailPromptState.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return const EmailPromptState();
    return EmailPromptState(clientCardShown: json['clientCardShown'] == true);
  }

  final bool clientCardShown;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'clientCardShown': clientCardShown,
  };

  /// (b) — whether the client card may still show (never shown before).
  bool get clientCardDue => !clientCardShown;

  /// (b) — the state after the client card was shown.
  EmailPromptState withClientCardShown() =>
      const EmailPromptState(clientCardShown: true);
}

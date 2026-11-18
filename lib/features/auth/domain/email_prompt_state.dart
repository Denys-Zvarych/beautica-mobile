// M517 (AUTH-D17, CLI-D09) — the device-local state of the dismissible email
// prompts for ONE account, and the decisions that read it.
//
//   (b) CLIENT booking-success card: shown once, ever ([clientCardShown] is
//       set on the first show).
//   (c) provider home card: either tap hides it ([providerHiddenAt]); it is
//       shown again ONCE when `now >= hiddenAt + 30 days` and the account
//       still has no confirmed email; a tap on that re-show retires it
//       ([providerRetired]).
//
// Pure Dart. Instants only — the 30 days are an absolute span, not calendar
// days (no Kyiv day is derived here).

/// Days after a hide when the provider card shows once more (AUTH-D17 c).
const Duration kProviderEmailCardReshowAfter = Duration(days: 30);

/// Email-prompt state for one account (see the file header).
final class EmailPromptState {
  const EmailPromptState({
    this.clientCardShown = false,
    this.providerHiddenAt,
    this.providerRetired = false,
  });

  /// Parses one entry of the stored JSON map; anything malformed reads as the
  /// default (the prompt may show once more — never a crash).
  factory EmailPromptState.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return const EmailPromptState();
    final Object? hidden = json['providerHiddenAt'];
    return EmailPromptState(
      clientCardShown: json['clientCardShown'] == true,
      providerHiddenAt: hidden is String ? DateTime.tryParse(hidden) : null,
      providerRetired: json['providerRetired'] == true,
    );
  }

  final bool clientCardShown;
  final DateTime? providerHiddenAt;
  final bool providerRetired;

  Map<String, dynamic> toJson() {
    final DateTime? hidden = providerHiddenAt;
    return <String, dynamic>{
      'clientCardShown': clientCardShown,
      if (hidden != null) 'providerHiddenAt': hidden.toUtc().toIso8601String(),
      'providerRetired': providerRetired,
    };
  }

  /// (b) — whether the client card may still show (never shown before).
  bool get clientCardDue => !clientCardShown;

  /// (c) — whether the provider card shows at [now].
  bool providerCardDueAt(DateTime now) {
    if (providerRetired) return false;
    final DateTime? hidden = providerHiddenAt;
    if (hidden == null) return true;
    // instant-ok: a 30-day absolute span since the hide, not a calendar day.
    return !now.isBefore(hidden.add(kProviderEmailCardReshowAfter));
  }

  /// (b) — the state after the client card was shown.
  EmailPromptState withClientCardShown() => EmailPromptState(
    clientCardShown: true,
    providerHiddenAt: providerHiddenAt,
    providerRetired: providerRetired,
  );

  /// (c) — the state after either tap on the provider card at [now]: the
  /// first hide starts the 30-day wait; a hide of the re-show retires it.
  EmailPromptState withProviderCardHidden(DateTime now) =>
      providerHiddenAt == null
      ? EmailPromptState(
          clientCardShown: clientCardShown,
          providerHiddenAt: now,
        )
      : EmailPromptState(
          clientCardShown: clientCardShown,
          providerHiddenAt: providerHiddenAt,
          providerRetired: true,
        );
}

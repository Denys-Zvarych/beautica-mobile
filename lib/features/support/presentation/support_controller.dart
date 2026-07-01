// SupportController — the submit-state notifier for the "Напишіть нам" screen.
//
// Holds the four-state lifecycle of a single contact submission:
//   idle → sending → success | error
//
// The screen watches this controller to swap the form for the spinner state and
// the success card, and to surface a failure as a localized error. Validation
// lives in the screen (instant feedback before submit); this controller just
// drives the network call + state transitions, mapping the repository's typed
// [Failure] into the [SupportSubmitState.error] arm.
//
// The state is a plain sealed enum-of-cases (no AsyncValue) because the screen
// needs an explicit "idle vs sending vs success vs error" distinction, and a
// success carries no data payload — just the email to echo on the success card.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/support/data/support_repository.dart';
import 'package:beautica_mobile/features/support/domain/support_attachment.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'support_controller.g.dart';

/// The submit-state lifecycle of the contact form.
sealed class SupportSubmitState {
  const SupportSubmitState();
}

/// Nothing submitted yet (or reset after an error) — the form is editable.
final class SupportSubmitIdle extends SupportSubmitState {
  const SupportSubmitIdle();
}

/// A submission is in flight — the Send CTA shows its spinner.
final class SupportSubmitSending extends SupportSubmitState {
  const SupportSubmitSending();
}

/// The submission was accepted (backend 202) — the screen shows the success
/// card.
final class SupportSubmitSuccess extends SupportSubmitState {
  const SupportSubmitSuccess();
}

/// The submission failed — [failure] carries the localizable user message.
final class SupportSubmitError extends SupportSubmitState {
  const SupportSubmitError(this.failure);

  final Failure failure;
}

/// Drives a single support-contact submission and exposes its [SupportSubmitState].
@riverpod
class SupportController extends _$SupportController {
  @override
  SupportSubmitState build() => const SupportSubmitIdle();

  /// Submits the support message via [SupportRepository], transitioning the
  /// state idle → sending → success | error.
  ///
  /// The caller (screen) is responsible for client-side validation BEFORE
  /// calling this; the repository / server re-validate. A failure is captured
  /// as [SupportSubmitError]; the screen can clear it back to idle via [reset]
  /// when the user edits the form again.
  Future<void> submit({
    required String message,
    String? subject,
    List<SupportAttachment> attachments = const <SupportAttachment>[],
  }) async {
    if (state is SupportSubmitSending) return;
    state = const SupportSubmitSending();
    try {
      await ref
          .read(supportRepositoryProvider)
          .submitContact(
            message: message,
            subject: subject,
            attachments: attachments,
          );
      state = const SupportSubmitSuccess();
    } on Failure catch (e) {
      state = SupportSubmitError(e);
    }
  }

  /// Clears an error back to the editable idle state (e.g. when the user edits
  /// the form after a failed send).
  void reset() {
    if (state is SupportSubmitError) {
      state = const SupportSubmitIdle();
    }
  }
}

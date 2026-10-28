// Phase 424 — the submit-state notifier behind the report sheet.
//
// idle → sending → sent | error, mirroring `SupportController`. The sheet owns
// form validation (reason picked, «Інше» comment present); this notifier only
// runs the repository call and classifies a failure into the two copies the
// sheet shows (D4): 429 → rate limited, anything else → generic.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/moderation/data/content_report_repository.dart';
import 'package:beautica_mobile/features/moderation/domain/content_report.dart';

part 'report_notifier.g.dart';

/// Which banner the sheet shows for a failed submit.
enum ReportErrorKind {
  /// HTTP 429 — «Забагато скарг, спробуйте пізніше».
  rateLimited,

  /// 404 or anything else — «Не вдалося надіслати скаргу…».
  generic,
}

/// The submit lifecycle of one report sheet.
sealed class ReportSubmitState {
  const ReportSubmitState();
}

/// Nothing submitted yet (or the error was cleared by an edit).
final class ReportSubmitIdle extends ReportSubmitState {
  const ReportSubmitIdle();
}

/// A submit is in flight — the CTA shows its spinner.
final class ReportSubmitSending extends ReportSubmitState {
  const ReportSubmitSending();
}

/// Accepted (201 new or 200 repeat) — the sheet closes with a success snack.
final class ReportSubmitSent extends ReportSubmitState {
  const ReportSubmitSent(this.report);

  final ContentReport report;
}

/// Failed — [kind] picks the banner copy.
final class ReportSubmitError extends ReportSubmitState {
  const ReportSubmitError(this.kind, this.failure);

  final ReportErrorKind kind;
  final Failure failure;
}

/// Classifies [failure] into the sheet's banner copy (phase 424 D4).
ReportErrorKind reportErrorKindOf(Failure failure) => switch (failure) {
  ServerFailure(statusCode: 429) => ReportErrorKind.rateLimited,
  _ => ReportErrorKind.generic,
};

/// Drives one report submission. Auto-disposed with the sheet.
@riverpod
class ReportController extends _$ReportController {
  @override
  ReportSubmitState build() => const ReportSubmitIdle();

  /// Sends [request]; ignored while a submit is already in flight.
  Future<void> submit(ContentReportRequest request) async {
    if (state is ReportSubmitSending) return;
    state = const ReportSubmitSending();
    try {
      final ContentReport report = await ref
          .read(contentReportRepositoryProvider)
          .create(request);
      if (!ref.mounted) return;
      state = ReportSubmitSent(report);
    } on Failure catch (e) {
      if (!ref.mounted) return;
      state = ReportSubmitError(reportErrorKindOf(e), e);
    } catch (e) {
      // Security LOW-3: a non-`Failure` throw (mapper bug, TypeError, …) must
      // still land in a terminal state — otherwise the sheet spins forever.
      // Never logged: the request carries the user's free-text comment.
      if (!ref.mounted) return;
      state = ReportSubmitError(
        ReportErrorKind.generic,
        UnknownFailure(cause: e),
      );
    }
  }

  /// Clears an error back to idle (the user changed the reason / comment).
  void reset() {
    if (state is ReportSubmitError) state = const ReportSubmitIdle();
  }
}

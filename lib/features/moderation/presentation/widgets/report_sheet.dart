// Phase 424 D1 — the shared «Поскаржитися» sheet.
//
// Ported 1:1 from the approved preview
// `docs/signup-designs/UgcSafety/lib/widgets/moderation_widgets.dart`
// (`showReportSheet` / `ReportSheet`). Composed only of existing widgets — no
// new chrome, colour or shadow:
//   • showVelvetSheet(isScrollControlled: true) + VelvetSheetChrome(subtitle:)
//     + VelvetSheetOptionRow           (shared/widgets/velvet_sheet.dart)
//   • MessageArea(lines: 3)             (shared/widgets/message_area.dart)
//   • VelvetBanner(iconSize: 24)        (shared/widgets/velvet_banner.dart)
//   • NeumorphicButton                  (core/widgets/neumorphic.dart)
//   • showVelvetSnack success           (shared/feedback/show_velvet_snack.dart)
// Production swaps the preview's StatefulWidget fake delay for
// [ReportController] and its literals for ARB strings.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/core/media/portfolio/portfolio_photo.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/moderation/application/report_notifier.dart';
import 'package:beautica_mobile/features/moderation/domain/content_report.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:beautica_mobile/shared/widgets/message_area.dart';
import 'package:beautica_mobile/shared/widgets/velvet_banner.dart';
import 'package:beautica_mobile/shared/widgets/velvet_sheet.dart';

/// Opens the report sheet for one piece of content and, once the report is
/// accepted, shows «Дякуємо, ми перевіримо скаргу». Resolves `true` when a
/// report was sent, `null` when the sheet was dismissed.
///
/// [subject] is what is being reported, as the user would name it («Відгук
/// від Олена К.», «Фото з портфоліо») — the sheet's subtitle.
Future<bool?> showReportSheet(
  BuildContext context, {
  required ReportTargetType targetType,
  required String targetId,
  required String subject,
}) async {
  final bool? sent = await showVelvetSheet<bool>(
    context,
    isScrollControlled: true,
    builder: (BuildContext _) => ReportSheet(
      targetType: targetType,
      targetId: targetId,
      subject: subject,
    ),
  );
  if (sent == true && context.mounted) {
    showVelvetSnack(
      context,
      message: AppLocalizations.of(context).reportSent,
      variant: VelvetSnackVariant.success,
    );
  }
  return sent;
}

/// Phase 424 D3 — the `PortfolioPhotoViewer.onReport` every public profile
/// passes: reports the shown [photo] from the viewer's [context].
void reportPortfolioPhoto(BuildContext context, PortfolioPhoto photo) {
  showReportSheet(
    context,
    targetType: ReportTargetType.portfolioPhoto,
    targetId: photo.id,
    subject: AppLocalizations.of(context).reportSubjectPortfolioPhoto,
  );
}

/// Phase 425 D1 — the public master/salon profile «⋯»: opens the report sheet
/// DIRECTLY (no actions sheet — clients never block) for the profile
/// [targetId] of [targetType] (`masterProfile` / `salonProfile`), subtitled
/// «Профіль: [name]».
void reportProfile(
  BuildContext context, {
  required ReportTargetType targetType,
  required String targetId,
  required String name,
}) {
  assert(
    targetType == ReportTargetType.masterProfile ||
        targetType == ReportTargetType.salonProfile,
    'reportProfile: only MASTER_PROFILE / SALON_PROFILE.',
  );
  showReportSheet(
    context,
    targetType: targetType,
    targetId: targetId,
    subject: AppLocalizations.of(context).reportSubjectProfile(name),
  );
}

/// The sheet body: reason rows, optional comment (required for «Інше»), an
/// error banner and the submit CTA.
class ReportSheet extends ConsumerStatefulWidget {
  const ReportSheet({
    super.key,
    required this.targetType,
    required this.targetId,
    required this.subject,
  });

  final ReportTargetType targetType;
  final String targetId;
  final String subject;

  static const Key commentFieldKey = Key('report-comment-field');
  static const Key submitKey = Key('report-submit');
  static const Key bannerKey = Key('report-error-banner');
  static const Key dragBlockerKey = Key('report-drag-blocker');

  /// Tap target of the row for [reason].
  static Key reasonKey(ReportReason reason) =>
      Key('report-reason-${reason.wireName}');

  @override
  ConsumerState<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<ReportSheet> {
  final TextEditingController _comment = TextEditingController();
  ReportReason? _reason;
  bool _showCommentError = false;

  bool get _commentRequired => _reason?.requiresComment ?? false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  void _select(ReportReason reason) {
    setState(() {
      _reason = reason;
      _showCommentError = false;
    });
    ref.read(reportControllerProvider.notifier).reset();
  }

  Future<void> _submit() async {
    final ReportReason? reason = _reason;
    if (reason == null) return;
    final String text = _comment.text.trim();
    if (reason.requiresComment &&
        text.characters.length < kReportOtherCommentMinLength) {
      setState(() => _showCommentError = true);
      return;
    }
    await ref
        .read(reportControllerProvider.notifier)
        .submit(
          ContentReportRequest(
            targetType: widget.targetType,
            targetId: widget.targetId,
            reason: reason,
            comment: text.isEmpty ? null : text,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    ref.listen<ReportSubmitState>(reportControllerProvider, (
      ReportSubmitState? _,
      ReportSubmitState next,
    ) {
      if (next is ReportSubmitSent) {
        ModalRoute.of(context)?.navigator?.pop(true);
      }
    });
    final ReportSubmitState state = ref.watch(reportControllerProvider);
    final bool submitting = state is ReportSubmitSending;
    final String? banner = switch (state) {
      ReportSubmitError(kind: ReportErrorKind.rateLimited) =>
        l10n.reportErrRateLimited,
      ReportSubmitError() => l10n.reportErrGeneric,
      _ => null,
    };

    // While a submit is in flight the sheet cannot be closed — closing it
    // would hide the «Дякуємо…» confirmation of a report that still lands.
    // `PopScope` blocks back, the barrier tap and the body overscroll (all go
    // through `maybePop`); the modal sheet's own drag-to-dismiss calls
    // `Navigator.pop` directly, so a no-op vertical-drag recognizer claims
    // drags on the fixed header first (inner recognizers win the arena). The
    // detector stays in the tree either way, so toggling never remounts the
    // body (scroll offset, typed comment).
    return PopScope(
      canPop: !submitting,
      child: GestureDetector(
        key: ReportSheet.dragBlockerKey,
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: submitting ? (DragStartDetails _) {} : null,
        child: _body(context, l10n, submitting, banner),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    AppLocalizations l10n,
    bool submitting,
    String? banner,
  ) {
    return Padding(
      // Rides above the keyboard (showVelvetSheet isScrollControlled: true).
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: VelvetSheetChrome(
          title: l10n.reportSheetTitle,
          subtitle: widget.subject,
          // Tall enough to overflow on real phones: pulling the body down at
          // its top dismisses too, not only a drag on the fixed header.
          dismissOnOverscroll: true,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(
                l10n.reportSheetReasonLabel,
                style: VelvetText.label(),
              ),
            ),
            for (final ReportReason r in ReportReason.values)
              VelvetSheetOptionRow(
                tapKey: ReportSheet.reasonKey(r),
                label: reportReasonLabel(l10n, r),
                selected: _reason == r,
                onTap: submitting ? () {} : () => _select(r),
              ),
            const SizedBox(height: VelvetSpacing.sm),
            MessageArea(
              fieldKey: ReportSheet.commentFieldKey,
              label: _commentRequired
                  ? l10n.reportCommentLabelRequired
                  : l10n.reportCommentLabelOptional,
              controller: _comment,
              minLength: 0,
              maxLength: kReportCommentMaxLength,
              // Backend `@Size(max = 500)` counts UTF-16 units, not graphemes.
              countUtf16Units: true,
              lines: 3,
              hintText: l10n.reportCommentHint,
              errorText: _showCommentError
                  ? l10n.reportCommentRequiredError
                  : null,
              helperText: l10n.reportCommentHelper,
              onChanged: (_) {
                if (_showCommentError) {
                  setState(() => _showCommentError = false);
                }
              },
            ),
            if (banner != null) ...<Widget>[
              const SizedBox(height: VelvetSpacing.xs),
              VelvetBanner(
                key: ReportSheet.bannerKey,
                icon: Icons.error_outline_rounded,
                color: BrandColors.error,
                iconSize: VelvetSpacing.lg,
                message: banner,
              ),
            ],
            const SizedBox(height: VelvetSpacing.sm),
            NeumorphicButton(
              key: ReportSheet.submitKey,
              label: l10n.reportSubmit,
              icon: Icons.outlined_flag_rounded,
              loading: submitting,
              onPressed: _reason == null ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

/// The uk label of [reason] (backend 395 D3 enum).
String reportReasonLabel(AppLocalizations l10n, ReportReason reason) =>
    switch (reason) {
      ReportReason.spam => l10n.reportReasonSpam,
      ReportReason.offensive => l10n.reportReasonOffensive,
      ReportReason.harassment => l10n.reportReasonHarassment,
      ReportReason.falseInfo => l10n.reportReasonFalseInfo,
      ReportReason.sexualContent => l10n.reportReasonSexualContent,
      ReportReason.other => l10n.reportReasonOther,
    };

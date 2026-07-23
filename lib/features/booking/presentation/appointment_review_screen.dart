// MO-6 — «ВІДГУК ПРО МАЙСТРА» for a multi-service VISIT.
//
// The visit analogue of `leave_review_screen.dart`: a client leaves ONE review
// for a whole COMPLETED visit via `AppointmentRepository.createAppointmentReview`
// (`POST /appointments/{id}/review`), never the per-booking review of a child
// (which the backend would reject). Reached at `/bookings/visit/
// :appointmentId/review` from the visit detail's «Залишити відгук» CTA (MO-5),
// carrying the appointmentId.
//
// It MIRRORS the single-booking review form 1:1 — the SAME shared widgets
// ([MasterFeedbackCard], [StarRatingInput], [ReviewSectionLabel]) and the SAME
// tokens — and reuses every `reviewXxx` l10n key. The only content difference is
// the master card's context line: a service-COUNT summary («2 послуги · 14
// липня») instead of a single service name, since a visit groups N services.
//
// The screen watches `appointmentDetailProvider(appointmentId)` for the master
// header AND the server-computed `canReview` gate: when `!canReview` (the visit
// is not COMPLETED, or was already reviewed — including a stale
// `/bookings/visit/{id}/review` deep link) the form is replaced by the shared
// not-reviewable info state. Submit runs through [appointmentLeaveReviewProvider];
// success pops back to the visit detail with a thank-you snackbar. A stale
// already-reviewed 409 refetches the detail (via the notifier) so the screen
// flips to the not-reviewable state in place; any other error stays on the form
// with a snackbar.
//
// go_router only: pushed under the Записи branch (so it pops back onto that
// branch's own navigator stack).
//
// SEC: renders the master's identity and is a form — acquires the app-wide
// [ScreenProtectionManager] for its lifetime (acquire in initState / release in
// dispose), exactly like `LeaveReviewScreen` / `VisitDetailScreen`.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:beautica_mobile/shared/formatters/service_count_label.dart';

import '../application/appointment_detail_notifier.dart';
import '../application/appointment_leave_review_notifier.dart';
import '../domain/appointment.dart';
import '../domain/appointment_display_x.dart';
import 'widgets/master_feedback_card.dart';
import 'widgets/star_rating_input.dart';

/// The «ВІДГУК ПРО МАЙСТРА» screen for the visit identified by [appointmentId].
class AppointmentReviewScreen extends ConsumerStatefulWidget {
  const AppointmentReviewScreen({super.key, required this.appointmentId});

  final String appointmentId;

  @override
  ConsumerState<AppointmentReviewScreen> createState() =>
      _AppointmentReviewScreenState();
}

class _AppointmentReviewScreenState
    extends ConsumerState<AppointmentReviewScreen> {
  /// UX cap (decision 7) — well under the backend's 2000 max, so no 400 risk.
  /// Identical to the single-booking review form.
  static const int _maxChars = 500;

  // Captured in initState so dispose() never touches `ref` (Riverpod 3.x
  // throws on a post-dispose `ref` read).
  late final ScreenProtectionManager _screenProtection;

  final TextEditingController _comment = TextEditingController();
  int _rating = 0;

  @override
  void initState() {
    super.initState();
    _screenProtection = ref.read(screenProtectionProvider)..acquire();
  }

  @override
  void dispose() {
    _comment.dispose();
    _screenProtection.release();
    super.dispose();
  }

  Future<void> _submit(Appointment appointment) async {
    if (_rating == 0) return;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    await ref
        .read(appointmentLeaveReviewProvider.notifier)
        .submit(
          appointmentId: appointment.id,
          rating: _rating,
          comment: _comment.text,
        );
    if (!mounted) return;

    final AsyncValue<void> result = ref.read(appointmentLeaveReviewProvider);
    if (result.hasError) {
      final Object error = result.error!;
      final String message = error is Failure
          ? error.userMessage(context)
          : l10n.errUnknown;
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(message)));
      // On a stale already-reviewed 409 the notifier already invalidated the
      // detail; watching `appointmentDetailProvider` flips this screen to the
      // not-reviewable state in place. We stay put (no pop) either way.
      return;
    }

    // Success — thank the client and pop back to the visit detail (whose
    // `canReview` the notifier already invalidated to false).
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(l10n.reviewSubmitSuccess)));
    if (context.canPop()) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<Appointment> async = ref.watch(
      appointmentDetailProvider(widget.appointmentId),
    );
    final bool submitting = ref.watch(appointmentLeaveReviewProvider).isLoading;

    return Scaffold(
      backgroundColor: BrandColors.base,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            _TopBar(
              title: l10n.reviewScreenTitle,
              backLabel: l10n.reviewBackSemantics,
            ),
            Expanded(
              child: async.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: BrandColors.accent),
                ),
                error: (Object e, StackTrace _) => _ErrorState(
                  onRetry: () => ref.invalidate(
                    appointmentDetailProvider(widget.appointmentId),
                  ),
                ),
                data: (Appointment appointment) => appointment.canReview
                    ? _Form(
                        appointment: appointment,
                        comment: _comment,
                        rating: _rating,
                        submitting: submitting,
                        maxChars: _maxChars,
                        onRatingChanged: (int value) =>
                            setState(() => _rating = value),
                        onSubmit: () => _submit(appointment),
                      )
                    : const _NotReviewable(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The form body — the master card, the required rating card, the optional
/// comment card, and the pinned submit CTA. Mirrors `LeaveReviewScreen._Form`,
/// swapping the single service name for the visit's service-count context line.
class _Form extends StatelessWidget {
  const _Form({
    required this.appointment,
    required this.comment,
    required this.rating,
    required this.submitting,
    required this.maxChars,
    required this.onRatingChanged,
    required this.onSubmit,
  });

  final Appointment appointment;
  final TextEditingController comment;
  final int rating;
  final bool submitting;
  final int maxChars;
  final ValueChanged<int> onRatingChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String roleLabel =
        appointment.masterProfessionalTitle ??
        (appointment.atSalon
            ? appointment.salonName!
            : l10n.reviewMasterRoleIndependent);
    // The one content difference vs the single-booking form: a service-COUNT
    // summary («2 послуги · 14 липня») — a visit groups N services, not one.
    final String visitContext =
        '${formatServiceCountUk(appointment.items.length)} · '
        '${formatFullDate(appointment.startAt)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              VelvetSpacing.lg,
              VelvetSpacing.xs,
              VelvetSpacing.lg,
              VelvetSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                MasterFeedbackCard(
                  name: appointment.masterName,
                  roleLabel: roleLabel,
                  visitContext: visitContext,
                ),
                const SizedBox(height: VelvetSpacing.lg),
                _RatingCard(rating: rating, onChanged: onRatingChanged),
                const SizedBox(height: VelvetSpacing.md),
                _CommentCard(controller: comment, maxChars: maxChars),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            VelvetSpacing.lg,
            0,
            VelvetSpacing.lg,
            VelvetSpacing.md,
          ),
          child: NeumorphicButton(
            key: const Key('visit-review-submit'),
            label: l10n.reviewSubmitCta,
            icon: Icons.send_rounded,
            loading: submitting,
            onPressed: rating > 0 ? onSubmit : null,
          ),
        ),
      ],
    );
  }
}

/// The required «ВАША ОЦІНКА» rating card — identical to the single-booking
/// review's, reusing the shared [StarRatingInput].
class _RatingCard extends StatelessWidget {
  const _RatingCard({required this.rating, required this.onChanged});

  final int rating;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return NeumorphicCard(
      showBorder: true,
      padding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.md,
        vertical: VelvetSpacing.lg,
      ),
      child: Column(
        children: <Widget>[
          ReviewSectionLabel(
            text: l10n.reviewRatingSection,
            tag: l10n.reviewRatingRequiredTag,
            emphasized: true,
          ),
          const SizedBox(height: VelvetSpacing.md),
          StarRatingInput(
            key: const Key('visit-review-stars'),
            rating: rating,
            onChanged: onChanged,
            labels: <String>[
              l10n.reviewRatingLabel1,
              l10n.reviewRatingLabel2,
              l10n.reviewRatingLabel3,
              l10n.reviewRatingLabel4,
              l10n.reviewRatingLabel5,
            ],
            prompt: l10n.reviewRatingPrompt,
            semanticsLabel: l10n.reviewStarsSemantics,
          ),
        ],
      ),
    );
  }
}

/// The optional «ВАШ ВІДГУК» comment card — identical to the single-booking
/// review's.
class _CommentCard extends StatelessWidget {
  const _CommentCard({required this.controller, required this.maxChars});

  final TextEditingController controller;
  final int maxChars;

  static final TextStyle _fieldStyle = VelvetText.bodyStrong14.copyWith(
    height: 1.45,
  );
  static final TextStyle _hintStyle = VelvetText.bookCommentHint;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return NeumorphicCard(
      showBorder: true,
      padding: const EdgeInsets.all(VelvetSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ReviewSectionLabel(
            text: l10n.reviewCommentSection,
            tag: l10n.reviewCommentOptionalTag,
          ),
          const SizedBox(height: VelvetSpacing.sm),
          NeumorphicInset(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: VelvetSpacing.md,
                vertical: VelvetSpacing.sm,
              ),
              child: TextField(
                key: const Key('visit-review-comment'),
                controller: controller,
                maxLines: 5,
                minLines: 4,
                maxLength: maxChars,
                inputFormatters: <TextInputFormatter>[
                  LengthLimitingTextInputFormatter(maxChars),
                ],
                cursorColor: BrandColors.accentDeep,
                style: _fieldStyle,
                buildCounter:
                    (
                      BuildContext context, {
                      required int currentLength,
                      required int? maxLength,
                      required bool isFocused,
                    }) => null,
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: l10n.reviewCommentHint,
                  hintStyle: _hintStyle,
                ),
              ),
            ),
          ),
          const SizedBox(height: VelvetSpacing.xs),
          Align(
            alignment: Alignment.centerRight,
            child: _CommentCounter(controller: controller, maxChars: maxChars),
          ),
        ],
      ),
    );
  }
}

/// The live `$length / 500` counter — identical to the single-booking review's,
/// scoped to a [ValueListenableBuilder] so a keystroke rebuilds only this leaf.
class _CommentCounter extends StatelessWidget {
  const _CommentCounter({required this.controller, required this.maxChars});

  final TextEditingController controller;
  final int maxChars;

  static final TextStyle _fullStyle = VelvetText.feedbackCounter.copyWith(
    color: BrandColors.error,
  );
  static final TextStyle _activeStyle = VelvetText.feedbackCounter.copyWith(
    color: BrandColors.textSecondary,
  );
  static final TextStyle _emptyStyle = VelvetText.feedbackCounter.copyWith(
    color: BrandColors.muted,
  );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (BuildContext context, TextEditingValue value, _) {
        final int length = value.text.characters.length;
        final TextStyle style = length >= maxChars
            ? _fullStyle
            : (length > 0 ? _activeStyle : _emptyStyle);
        return Text('$length / $maxChars', style: style);
      },
    );
  }
}

/// The top bar — a raised back affordance + the centred, tracked screen title.
/// Mirrors `LeaveReviewScreen._TopBar`.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.backLabel});

  final String title;
  final String backLabel;

  static final TextStyle _titleStyle = VelvetText.subheading().copyWith(
    letterSpacing: 1.4,
    fontWeight: FontWeight.w700,
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.lg,
        VelvetSpacing.sm,
        VelvetSpacing.lg,
        VelvetSpacing.sm,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: NeumorphicIconButton(
              key: const Key('visit-review-back'),
              icon: Icons.arrow_back_ios_new_rounded,
              semanticLabel: backLabel,
              onTap: () {
                if (context.canPop()) context.pop();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 56),
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _titleStyle,
            ),
          ),
        ],
      ),
    );
  }
}

/// The informative state shown when a visit is not reviewable — reached when the
/// visit is not COMPLETED, or after the review was already left (including a
/// stale `/bookings/visit/{id}/review` deep link, or a stale already-reviewed
/// 409 that refetched `canReview: false`). Mirrors
/// `LeaveReviewScreen._NotReviewable`.
class _NotReviewable extends StatelessWidget {
  const _NotReviewable();

  static final TextStyle _titleStyle = VelvetText.headingSm;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              height: 88,
              width: 88,
              decoration: const BoxDecoration(
                color: BrandColors.base,
                shape: BoxShape.circle,
                boxShadow: VelvetShadows.extrudedCard,
              ),
              child: const Icon(
                Icons.reviews_outlined,
                size: 38,
                color: BrandColors.accent,
              ),
            ),
            const SizedBox(height: VelvetSpacing.lg),
            Text(
              l10n.reviewUnavailableTitle,
              textAlign: TextAlign.center,
              style: _titleStyle,
            ),
            const SizedBox(height: VelvetSpacing.sm),
            Text(
              l10n.reviewUnavailableBody,
              textAlign: TextAlign.center,
              style: VelvetText.body(),
            ),
            const SizedBox(height: VelvetSpacing.xl),
            SizedBox(
              width: 220,
              child: NeumorphicButton(
                key: const Key('visit-review-unavailable-back'),
                label: l10n.reviewUnavailableCta,
                icon: Icons.event_note_rounded,
                onPressed: () {
                  if (context.canPop()) context.pop();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The error state for a failed visit fetch — a message + retry, behind the same
/// top bar. Mirrors `LeaveReviewScreen._ErrorState`.
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.cloud_off_rounded,
                size: 48,
                color: BrandColors.muted,
              ),
              const SizedBox(height: VelvetSpacing.md),
              Text(
                l10n.errUnknown,
                textAlign: TextAlign.center,
                style: VelvetText.body(),
              ),
              const SizedBox(height: VelvetSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: NeumorphicButton(
                  key: const Key('visit-review-error-retry'),
                  label: l10n.retryLabel,
                  icon: Icons.refresh_rounded,
                  onPressed: onRetry,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

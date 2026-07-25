// Track 7.x Wave B — «ВІДГУК ПРО КЛІЄНТА», the PROVIDER (master or salon)
// leave-feedback-about-client screen.
//
// Ported from the approved preview
// `docs/signup-designs/LeaveClientFeedback/lib/screens/leave_client_feedback_screen.dart`,
// with the preview's local state / `Navigator` swapped for the project's
// Riverpod notifier + go_router, its duplicated theme/nav/reveal widgets
// mapped onto the real project infra (`NeumorphicCard`/`NeumorphicButton`/
// `NeumorphicInset`, `BrandColors`/`VelvetText`/`Velvet*` tokens, and the
// shared [StarRatingInput]/[ReviewSectionLabel] the CLIENT→MASTER leave-review
// screen already ported), and a real submit against `POST /client-reviews`.
// Mirrors `LeaveReviewScreen`'s structure/wiring shape exactly (see that
// file's header for the general pattern this one repeats for the opposite
// direction).
//
// NOTE — the preview's `ConfidentialityNote` widget was REMOVED from the
// approved design by the user (locked decision, 2026-07-25) and is
// deliberately NOT ported. The inline «Клієнт цього коментаря не побачить»
// reminder beside the comment counter IS still part of the design and is kept.
//
// ## The gating limitation (read before touching this file)
//
// The CLIENT→MASTER mirror gates its form on `Booking.canReview` — a
// server-computed flag `BookingDetailScreen` also uses to show/hide its entry
// CTA. `BookingDetailResponse` carries NO equivalent flag for the PROVIDER
// side: nothing on the wire says whether feedback about this booking's client
// was already left. `BookingDetailScreen`'s provider footer therefore offers
// the entry CTA for EVERY COMPLETED provider booking (see
// `_DetailBody._providerActions`), and this screen has no way to pre-empt a
// duplicate submit. The 409 the backend returns instead
// ([ClientReviewAlreadyExistsFailure]) is caught here and swaps the form for
// the SAME not-reviewable info state a stale CLIENT review deep link shows —
// see [_LeaveClientFeedbackScreenState._submit].
//
// go_router only: pushed at `/master/bookings/:bookingId/review`, nested under
// the provider's own booking-detail route so swipe-back returns to the
// detail. Reached from the detail's COMPLETED-provider-booking entry CTA.
//
// SEC: renders the client's identity and is a form — acquires the app-wide
// [ScreenProtectionManager] for its lifetime, exactly like `LeaveReviewScreen`
// / `BookingDetailScreen`.

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

import '../application/booking_detail_notifier.dart';
import '../application/leave_client_feedback_notifier.dart';
import '../domain/booking.dart';
import '../domain/booking_display_x.dart';
import 'widgets/client_feedback_card.dart';
import 'widgets/master_feedback_card.dart' show ReviewSectionLabel;
import 'widgets/star_rating_input.dart';

/// The «ВІДГУК ПРО КЛІЄНТА» screen for the booking identified by [bookingId].
class LeaveClientFeedbackScreen extends ConsumerStatefulWidget {
  const LeaveClientFeedbackScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  ConsumerState<LeaveClientFeedbackScreen> createState() =>
      _LeaveClientFeedbackScreenState();
}

class _LeaveClientFeedbackScreenState
    extends ConsumerState<LeaveClientFeedbackScreen> {
  /// UX cap — the backend's `providerComment` ceiling (2000 chars).
  static const int _maxChars = 2000;

  // Captured in initState so dispose() never touches `ref` (Riverpod 3.x
  // throws on a post-dispose `ref` read).
  late final ScreenProtectionManager _screenProtection;

  final TextEditingController _comment = TextEditingController();
  // A ValueNotifier rather than plain state — a star tap must only rebuild
  // the rating card + submit CTA's enabled gating, never the whole `_Form`
  // subtree (mobile-perf, mirrors `_CommentFooterRow`'s controller scoping
  // below).
  final ValueNotifier<int> _rating = ValueNotifier<int>(0);

  /// Flipped true on a [ClientReviewAlreadyExistsFailure] — the ONLY signal
  /// this screen ever gets that feedback was already left (see the file
  /// header's gating-limitation note). Once true the form is replaced by the
  /// not-reviewable info state; there is no way back to the form on this
  /// screen instance, matching a genuinely one-shot server rule.
  bool _alreadyReviewed = false;

  @override
  void initState() {
    super.initState();
    _screenProtection = ref.read(screenProtectionProvider)..acquire();
  }

  @override
  void dispose() {
    _comment.dispose();
    _rating.dispose();
    _screenProtection.release();
    super.dispose();
  }

  Future<void> _submit(Booking booking) async {
    if (_rating.value == 0) return;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    await ref
        .read(leaveClientFeedbackProvider.notifier)
        .submit(
          bookingId: booking.id,
          rating: _rating.value,
          comment: _comment.text,
        );
    if (!mounted) return;

    final AsyncValue<void> result = ref.read(leaveClientFeedbackProvider);
    if (result.hasError) {
      final Object error = result.error!;
      // A duplicate submit swaps the form for the not-reviewable info state —
      // the screen swap itself communicates the outcome, no SnackBar needed.
      if (error is ClientReviewAlreadyExistsFailure) {
        setState(() => _alreadyReviewed = true);
        return;
      }
      final String message = error is Failure
          ? error.userMessage(context)
          : l10n.errUnknown;
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    // Success — thank the provider and pop back to the detail.
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(l10n.clientReviewSubmitSuccess)));
    if (context.canPop()) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<Booking> async = ref.watch(
      bookingDetailProvider(widget.bookingId),
    );
    final bool submitting = ref.watch(leaveClientFeedbackProvider).isLoading;

    return Scaffold(
      backgroundColor: BrandColors.base,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            _TopBar(
              title: l10n.clientReviewScreenTitle,
              backLabel: l10n.clientReviewBackSemantics,
            ),
            Expanded(
              child: async.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: BrandColors.accent),
                ),
                error: (Object e, StackTrace _) => _ErrorState(
                  onRetry: () =>
                      ref.invalidate(bookingDetailProvider(widget.bookingId)),
                ),
                data: (Booking booking) => _alreadyReviewed
                    ? const _NotReviewable()
                    : _Form(
                        booking: booking,
                        comment: _comment,
                        rating: _rating,
                        submitting: submitting,
                        maxChars: _maxChars,
                        onRatingChanged: (int value) => _rating.value = value,
                        onSubmit: () => _submit(booking),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The form body — the client card, the required rating card, the optional
/// comment card, and the pinned submit CTA.
class _Form extends StatelessWidget {
  const _Form({
    required this.booking,
    required this.comment,
    required this.rating,
    required this.submitting,
    required this.maxChars,
    required this.onRatingChanged,
    required this.onSubmit,
  });

  final Booking booking;
  final TextEditingController comment;
  // Scoped via [ValueListenableBuilder] around `_RatingCard` and the submit
  // CTA below — a star tap must not rebuild `ClientFeedbackCard` or
  // `_CommentCard` (mobile-perf LOW).
  final ValueNotifier<int> rating;
  final bool submitting;
  final int maxChars;
  final ValueChanged<int> onRatingChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? clientName = booking.clientName;
    final String name = clientName ?? l10n.bookingDetailGuestClient;
    final String roleLabel = booking.isGuestBooking
        ? l10n.bookingDetailGuestBookingLabel
        : l10n.clientReviewRoleLabel;
    final String visitContext =
        '${booking.serviceName} · ${formatFullDate(booking.startAt)}';

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
                ClientFeedbackCard(
                  name: name,
                  roleLabel: roleLabel,
                  visitContext: visitContext,
                  privateChipLabel: l10n.clientReviewPrivateChipLabel,
                  semanticsLabel: '$name, $visitContext',
                ),
                const SizedBox(height: VelvetSpacing.lg),
                ValueListenableBuilder<int>(
                  valueListenable: rating,
                  builder: (BuildContext context, int value, _) =>
                      _RatingCard(rating: value, onChanged: onRatingChanged),
                ),
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
          child: ValueListenableBuilder<int>(
            valueListenable: rating,
            builder: (BuildContext context, int value, _) => NeumorphicButton(
              key: const Key('leave-client-feedback-submit'),
              label: l10n.clientReviewSubmitCta,
              icon: Icons.send_rounded,
              loading: submitting,
              onPressed: value > 0 ? onSubmit : null,
            ),
          ),
        ),
      ],
    );
  }
}

/// The required «ОЦІНКА КЛІЄНТА» rating card.
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
            text: l10n.clientReviewRatingSection,
            tag: l10n.clientReviewRatingRequiredTag,
            emphasized: true,
          ),
          const SizedBox(height: VelvetSpacing.md),
          StarRatingInput(
            key: const Key('leave-client-feedback-stars'),
            rating: rating,
            onChanged: onChanged,
            labels: <String>[
              l10n.clientReviewRatingLabel1,
              l10n.clientReviewRatingLabel2,
              l10n.clientReviewRatingLabel3,
              l10n.clientReviewRatingLabel4,
              l10n.clientReviewRatingLabel5,
            ],
            prompt: l10n.clientReviewRatingPrompt,
            semanticsLabel: l10n.clientReviewStarsSemantics,
          ),
        ],
      ),
    );
  }
}

/// The optional «КОМЕНТАР ПРО КЛІЄНТА» comment card. The client never sees
/// this text — only their aggregate rating number moves.
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
            text: l10n.clientReviewCommentSection,
            tag: l10n.clientReviewCommentOptionalTag,
          ),
          const SizedBox(height: VelvetSpacing.sm),
          NeumorphicInset(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: VelvetSpacing.md,
                vertical: VelvetSpacing.sm,
              ),
              child: TextField(
                key: const Key('leave-client-feedback-comment'),
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
                  hintText: l10n.clientReviewCommentHint,
                  hintStyle: _hintStyle,
                ),
              ),
            ),
          ),
          const SizedBox(height: VelvetSpacing.xs),
          _CommentFooterRow(
            controller: controller,
            maxChars: maxChars,
            privacyNote: l10n.clientReviewCommentPrivacyNote,
          ),
        ],
      ),
    );
  }
}

/// The privacy reminder + live `$length / 2000` counter, on one row — the
/// thing that makes this comment field visibly different from the CLIENT's
/// own leave-review comment. Scoped to a [ValueListenableBuilder] on the
/// shared [TextEditingController] so a keystroke rebuilds only this leaf row —
/// never the client card, star input, or submit CTA (mobile-perf, mirrors
/// `LeaveReviewScreen._CommentCounter`).
class _CommentFooterRow extends StatelessWidget {
  const _CommentFooterRow({
    required this.controller,
    required this.maxChars,
    required this.privacyNote,
  });

  final TextEditingController controller;
  final int maxChars;
  final String privacyNote;

  static final TextStyle _noteStyle = VelvetText.feedback(
    BrandColors.muted,
  ).copyWith(fontSize: 11);
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
        final TextStyle counterStyle = length >= maxChars
            ? _fullStyle
            : (length > 0 ? _activeStyle : _emptyStyle);
        return Row(
          children: <Widget>[
            const Icon(
              Icons.visibility_off_rounded,
              size: 13,
              color: BrandColors.muted,
            ),
            const SizedBox(width: VelvetSpacing.xs),
            Expanded(
              child: Text(
                privacyNote,
                key: const Key('leave-client-feedback-privacy-note'),
                style: _noteStyle,
              ),
            ),
            const SizedBox(width: VelvetSpacing.xs),
            Text('$length / $maxChars', style: counterStyle),
          ],
        );
      },
    );
  }
}

/// The top bar: a raised back affordance on the left and the centred, tracked
/// screen title.
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
              key: const Key('leave-client-feedback-back'),
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

/// The informative state shown once feedback about this booking's client has
/// already been left — reached ONLY via the submit-time 409 (see the file
/// header's gating-limitation note; there is no way to pre-empt this state).
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
                Icons.task_alt_rounded,
                size: 38,
                color: BrandColors.accent,
              ),
            ),
            const SizedBox(height: VelvetSpacing.lg),
            Text(
              l10n.clientReviewUnavailableTitle,
              textAlign: TextAlign.center,
              style: _titleStyle,
            ),
            const SizedBox(height: VelvetSpacing.sm),
            Text(
              l10n.clientReviewUnavailableBody,
              textAlign: TextAlign.center,
              style: VelvetText.body(),
            ),
            const SizedBox(height: VelvetSpacing.xl),
            SizedBox(
              width: 240,
              child: NeumorphicButton(
                key: const Key('leave-client-feedback-unavailable-back'),
                label: l10n.clientReviewUnavailableCta,
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

/// The error state for a failed booking fetch — a message + retry, behind the
/// same top bar.
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
                  key: const Key('leave-client-feedback-error-retry'),
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

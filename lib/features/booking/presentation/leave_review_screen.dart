// Phase 14.6 — «ВІДГУК ПРО МАЙСТРА», the CLIENT leave-review screen.
//
// Ported from the approved preview
// `docs/signup-designs/MasterFeedbackScreen/lib/screens/master_feedback_screen.dart`,
// with the preview's local state / `Navigator` swapped for the project's
// Riverpod notifier + go_router, and its duplicated theme/nav/reveal widgets
// mapped onto the real project infra (`NeumorphicCard`/`NeumorphicButton`/
// `NeumorphicInset`, `BrandColors`/`VelvetText`/`Velvet*` tokens, the shared
// [MasterAvatarBadge], and the shell-owned client bottom nav — this screen
// renders NO footer of its own; the [ClientShell] draws it, since this route
// is NOT the detail route it suppresses the bar on).
//
// The screen watches `bookingDetailProvider(bookingId)` for the master/service/
// date header AND the server-computed `canReview` gate: when `!canReview` (a
// stale `/bookings/{id}/review` deep link opened after a review was already
// left) the form is replaced by an informative state. Submit runs through
// [leaveReviewProvider]; success pops back to the detail with a thank-you
// snackbar, an error stays on the screen with a snackbar.
//
// go_router only: pushed at `/bookings/:bookingId/review`, nested under the
// Записи branch (so it pops back onto that branch's own navigator stack). It is
// ALSO the backend 18.5 `reviewUrl` push deep-link target.
//
// SEC: renders the master's identity and is a form — acquires the app-wide
// [ScreenProtectionManager] for its lifetime (acquire in initState / release in
// dispose), exactly like `BookingDetailScreen`.

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
import 'package:beautica_mobile/features/master/presentation/master_review_invalidation.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';

import '../application/booking_detail_notifier.dart';
import '../application/leave_review_notifier.dart';
import '../domain/booking.dart';
import '../domain/booking_display_x.dart';
import 'widgets/master_feedback_card.dart';
import 'widgets/master_strip.dart';
import 'widgets/star_rating_input.dart';

/// The «ВІДГУК ПРО МАЙСТРА» screen for the booking identified by [bookingId].
class LeaveReviewScreen extends ConsumerStatefulWidget {
  const LeaveReviewScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  ConsumerState<LeaveReviewScreen> createState() => _LeaveReviewScreenState();
}

class _LeaveReviewScreenState extends ConsumerState<LeaveReviewScreen> {
  /// UX cap (decision 7) — well under the backend's 2000 max, so no 400 risk.
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

  Future<void> _submit(Booking booking) async {
    if (_rating == 0) return;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    await ref
        .read(leaveReviewProvider.notifier)
        .submit(bookingId: booking.id, rating: _rating, comment: _comment.text);
    if (!mounted) return;

    final AsyncValue<void> result = ref.read(leaveReviewProvider);
    if (result.hasError) {
      final Object error = result.error!;
      final String message = error is Failure
          ? error.userMessage(context)
          : l10n.errUnknown;
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    // Success. The notifier already invalidated `bookingDetailProvider` (which
    // flips `canReview` to false); the master's public profile, its review
    // summary and its review list are THREE separate keepAlive caches that
    // nothing else refreshes, so fan out to them here before popping —
    // otherwise the client re-opens the master and sees neither their own
    // review nor a moved rating until the 5-minute TTL expires.
    //
    // Done from the screen, not the notifier: the fan-out takes a `WidgetRef`
    // so it structurally cannot run inside a Notifier (see
    // `master_review_invalidation.dart`). `booking` is the full entity here, so
    // `masterId` costs nothing extra.
    invalidateMasterReviewSurfaces(ref, booking.masterId);

    // Thank the client and pop back to the detail.
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(l10n.reviewSubmitSuccess)));
    if (context.canPop()) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<Booking> async = ref.watch(
      bookingDetailProvider(widget.bookingId),
    );
    final bool submitting = ref.watch(leaveReviewProvider).isLoading;

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
                  onRetry: () =>
                      ref.invalidate(bookingDetailProvider(widget.bookingId)),
                ),
                data: (Booking booking) => booking.canReview
                    ? _Form(
                        booking: booking,
                        comment: _comment,
                        rating: _rating,
                        submitting: submitting,
                        maxChars: _maxChars,
                        onRatingChanged: (int value) =>
                            setState(() => _rating = value),
                        onSubmit: () => _submit(booking),
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
  final int rating;
  final bool submitting;
  final int maxChars;
  final ValueChanged<int> onRatingChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String roleLabel =
        booking.masterProfessionalTitle ??
        (booking.atSalon
            ? booking.salonName!
            : l10n.reviewMasterRoleIndependent);
    final String visitContext =
        '${booking.serviceName} · ${formatFullDate(booking.startAt)}';

    // The master's PUBLIC rating, surfaced here so the client can see (and
    // reach) the reviews other clients left before writing their own — the
    // whole reason this screen was a dead end for ratings until now.
    //
    // "No reviews yet" must render «—», never «0.0». Routed through the one
    // `BookingDisplayX.masterDisplayRating` guard that `MasterStrip.fromBooking`
    // also uses, so this screen and «Деталі запису» cannot disagree about what
    // an unrated master looks like.
    final int reviewCount = booking.masterReviewCount ?? 0;
    final double? avgRating = booking.masterDisplayRating;
    final String ratingLabel =
        avgRating?.toStringAsFixed(1) ?? MasterStrip.noRatingLabel;

    // Same guard as `BookingCounterpartyHeader._MasterStrip`: `booking_mapper`
    // can hand us an empty `masterId`, and `/masters//reviews` matches no
    // route, so an empty id leaves the card inert rather than routing the
    // client into go_router's "page not found".
    final String masterId = booking.masterId;

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
                  key: const Key('leave-review-master-card'),
                  name: booking.masterName,
                  roleLabel: roleLabel,
                  visitContext: visitContext,
                  avgRating: avgRating,
                  reviewCount: reviewCount,
                  semanticsLabel:
                      '${l10n.bookingSummaryMasterSemantics(booking.masterName, roleLabel, ratingLabel, l10n.salonReviewCountLabel(reviewCount))}, $visitContext',
                  // TAPPABLE per the policy on `MasterStrip.onTap` — a
                  // review-shaped screen; reading the master's existing
                  // reviews is a natural detour, and `push` brings the client
                  // back with the half-typed comment intact.
                  onTap: masterId.isEmpty
                      ? null
                      : () => context.push(
                          RouteNames.masterPublicReviews(masterId),
                        ),
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
            key: const Key('leave-review-submit'),
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

/// The required «ВАША ОЦІНКА» rating card.
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
            key: const Key('leave-review-stars'),
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

/// The optional «ВАШ ВІДГУК» comment card.
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
                key: const Key('leave-review-comment'),
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

/// The live `$length / 500` counter. Scoped to a [ValueListenableBuilder] on the
/// shared [TextEditingController] so a keystroke rebuilds only this leaf — never
/// the master card, star input, or submit CTA (mobile-perf MEDIUM). The three
/// colour variants are pre-composed statics, so no [TextStyle] is allocated per
/// keystroke (mobile-perf LOW).
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
              key: const Key('leave-review-back'),
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

/// The informative state shown when a booking is not reviewable — reached, for
/// example, via a stale `/bookings/{id}/review` deep link after the review was
/// already left.
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
                key: const Key('leave-review-unavailable-back'),
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
                  key: const Key('leave-review-error-retry'),
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

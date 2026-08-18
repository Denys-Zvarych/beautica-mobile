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
// ## The gating (read before touching this file)
//
// The CLIENT→MASTER mirror gates its form on `Booking.canReview`; this
// PROVIDER→CLIENT direction mirrors it via `Booking.providerCanReviewClient`
// — a server-computed flag now accurate on BOTH `GET /bookings/{id}` and the
// provider rows of `GET /bookings/me` (backend
// `fix/list-provider-can-review-client`, 2026-08-17; the earlier note here
// that "list endpoints hardcode it `false`" is retracted, and the master
// «Архів» page's «Відгук» button is now gated on it — see
// `MasterBookingCard.onReview`'s doc). This screen fetches the single-booking
// endpoint on open via `bookingDetailProvider(bookingId)` and PRE-GATES on
// the real value in `build()`: `providerCanReviewClient == false` renders
// `_NotReviewable` immediately, before the form is ever built, so a master
// who taps «Відгук» on an already-reviewed archive row never types into a
// form that was always going to be rejected.
//
// This screen ALSO keeps its OWN post-submit 409 handling as defense-in-
// depth, not as the primary gate: the pre-gate reads a snapshot at open
// time, so a review landing between this screen loading and the master
// submitting (another device, a race) still slips past it. The 409 the
// backend returns in that case ([ClientReviewAlreadyExistsFailure]) is
// caught in [_LeaveClientFeedbackScreenState._submit] and swaps the form for
// the SAME `_NotReviewable` info state the pre-gate would have shown.
//
// go_router only: pushed at `/master/bookings/:bookingId/review`, registered
// as a STANDALONE top-level route (not nested under the booking-detail
// route — see `app_router.dart`'s registration comment for why a naive
// nesting silently mounted a shadow `BookingDetailScreen` under every push).
// Swipe-back / pop therefore returns to whatever the caller actually had on
// the stack: the detail screen when reached from its COMPLETED-provider-
// booking entry CTA, or the `/master/bookings/archive` list when reached
// from a completed archive row's «Відгук» button
// (`master_archive_screen.dart`'s `_openReview`, which also prefetches
// `bookingDetailProvider` before pushing — that list is fed by
// `GET /bookings/me`, which never warms it, unlike the detail path where the
// still-mounted `BookingDetailScreen` keeps it warm for free).
//
// ## THE POP RESULT IS PART OF THIS SCREEN'S CONTRACT
//
// Every pop site here reports a `bool` upward: `true` means "this booking is
// no longer reviewable by this provider" — the review was just submitted, a
// duplicate submit 409'd, or the pre-gate's own fetch already said `false`.
// `MasterArchiveScreen._openReview` awaits it and, on `true`, rewrites JUST
// that row via `MasterArchiveNotifier.markClientReviewed` (zero network, pages
// and scroll position kept) instead of the bare `ref.invalidate` on the whole
// archive family this screen used to fire (mobile-perf MEDIUM, 2026-08-17 —
// see that method's own doc for the full cost of the invalidate). Callers are
// free to ignore the result: `BookingDetailScreen` does, because [entry] makes
// this screen invalidate `bookingDetailProvider` on its behalf while the pop
// animation runs.
//
// The pop result reaches the ADJACENT caller only. A successful submit
// therefore ALSO deposits the booking id in the session-scoped
// `clientReviewSignalProvider`, which is what reaches a `MasterArchiveScreen`
// sitting further down the stack (archive → detail → review) where no pop
// result can arrive. See that provider's file header and [_submit]'s comment
// for why both exist and why they cannot conflict.
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
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';

import '../application/booking_detail_notifier.dart';
import '../application/client_review_signal_provider.dart';
import '../application/leave_client_feedback_notifier.dart';
import '../domain/booking.dart';
import '../domain/booking_display_x.dart';
import 'widgets/client_feedback_card.dart';
import 'widgets/master_feedback_card.dart' show ReviewSectionLabel;
import 'widgets/star_rating_input.dart';

/// Which surface pushed [LeaveClientFeedbackScreen] — threaded through
/// go_router's `extra` (never the path: the entry point is not part of the
/// resource's identity and must not leak into a deep link) and read back in
/// `app_router.dart`'s route builder.
///
/// It exists for exactly ONE decision: whether a successful submit must
/// invalidate `bookingDetailProvider(bookingId)` before popping. That refetch
/// is REQUIRED for [bookingDetail] (the still-mounted `BookingDetailScreen`
/// underneath `ref.watch`es the same family instance and would otherwise keep
/// serving a cached booking whose `providerCanReviewClient` is stale, keeping
/// its own review CTA alive and re-tappable), and is pure waste for
/// [masterArchive] (nothing on the archive stack watches that family — this
/// screen's own `ref.watch` is the last listener and the autoDispose element
/// dies with the pop, so the `GET /bookings/{id}` it fires is read by nobody;
/// mobile-perf LOW, 2026-08-17). The archive learns what it needs from the pop
/// result instead — see the file header.
enum ClientReviewEntry {
  /// Pushed from `BookingDetailScreen`'s «Залишити відгук про клієнта» CTA.
  /// Also the DEFAULT when `extra` is absent or of another type: it costs one
  /// unnecessary fetch on an unknown entry point, where the other direction
  /// would silently resurrect the stale-CTA bug.
  bookingDetail,

  /// Pushed from a `MasterArchiveScreen` row's «Відгук» slot.
  masterArchive,
}

/// The «ВІДГУК ПРО КЛІЄНТА» screen for the booking identified by [bookingId].
class LeaveClientFeedbackScreen extends ConsumerStatefulWidget {
  const LeaveClientFeedbackScreen({
    super.key,
    required this.bookingId,
    this.entry = ClientReviewEntry.bookingDetail,
  });

  final String bookingId;

  /// Which surface pushed this screen — see [ClientReviewEntry] for the one
  /// behaviour it changes and why the default is the conservative direction.
  final ClientReviewEntry entry;

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
        // A 409 PROVES this client's cached detail diverged from the server:
        // we only got here by tapping a CTA that a fresh
        // `providerCanReviewClient` would never have rendered. Invalidate the
        // shared detail family unconditionally here — unlike the success path
        // below there is no pop, so this is the ONLY signal a
        // `BookingDetailScreen` underneath will get, and this screen's own
        // `ref.watch` is what makes the refetch land (it re-reads the
        // authoritative `false`). That refetch does NOT flash `_LoadingForm`
        // between the form and `_NotReviewable` — see `build`'s `async.when`
        // note for why (and for what was measured rather than assumed there;
        // mobile-security INFO, 2026-08-17).
        //
        // No `ref.invalidate(masterArchiveProvider)` here: the archive learns
        // the row is no longer reviewable from this screen's POP RESULT (see
        // the file header) and patches that one row surgically, instead of
        // dropping every cached filter combination's pages and scroll
        // position.
        ref.invalidate(bookingDetailProvider(widget.bookingId));
        setState(() => _alreadyReviewed = true);
        return;
      }
      final String message = error is Failure
          ? error.userMessage(context)
          : l10n.errUnknown;
      showErrorSnack(context, message);
      return;
    }

    // Success — the backend just flipped `providerCanReviewClient` to false
    // for this booking. Each entry point learns that a different way, and
    // neither way is a bare invalidate of a whole provider family:
    //
    //   • [ClientReviewEntry.bookingDetail] — invalidate
    //     `bookingDetailProvider(id)` BEFORE popping. `BookingDetailScreen`
    //     stays mounted beneath this pushed route and `ref.watch`es the same
    //     family instance; this screen's own live watch is what drives the
    //     refetch (the covered detail screen's consumers are PAUSED), so it
    //     resolves DURING the pop animation and the detail screen resumes
    //     straight onto fresh data with its review CTA already gone — no
    //     loading flash underneath. See [ClientReviewEntry].
    //   • [ClientReviewEntry.masterArchive] — NO invalidate. Nothing on that
    //     stack watches `bookingDetailProvider`, so the refetch would be a
    //     `GET /bookings/{id}` nobody ever reads (mobile-perf LOW,
    //     2026-08-17). The archive instead reads the `true` popped below and
    //     rewrites exactly that one row —
    //     `MasterArchiveNotifier.markClientReviewed`.
    //
    // Deliberately NOT `invalidateBookingViewsAfterProviderClose`: that helper
    // is the fan-out for a STATUS close (decline/complete) and additionally
    // drops `bookingsDayProvider`. Leaving a client review changes no booking
    // status and nothing the day timeline renders, so widening to it would be
    // gratuitous refetching, not a shared contract.
    if (widget.entry == ClientReviewEntry.bookingDetail) {
      ref.invalidate(bookingDetailProvider(widget.bookingId));
    }
    // BOTH mechanisms fire, and that is deliberate — they cover DIFFERENT
    // journeys and cannot conflict (mobile-perf MEDIUM, 2026-08-17 cycle 2):
    //
    //   • the POP RESULT below is the ADJACENT-path patch. It reaches
    //     `MasterArchiveScreen._openReview` synchronously on the frame the pop
    //     lands, so an archive that pushed this screen itself drops the row's
    //     «Відгук» CTA instantly, with no dependence on any provider delivery
    //     ordering.
    //   • this SIGNAL is the NON-adjacent-path patch, and is written
    //     unconditionally — independent of [widget.entry], because the entry
    //     enum only describes who is DIRECTLY underneath. On
    //     archive → detail → review, the archive is two routes down and no pop
    //     result can ever reach it (and a predictive-back gesture through the
    //     detail screen pops `null` anyway). It reads this set instead, on
    //     resume. See `client_review_signal_provider.dart`'s file header.
    //
    // Not accidental duplication, and the second arrival is a genuine no-op —
    // but be precise about WHY, because the obvious reading is wrong (mobile-
    // perf LOW, 2026-08-17 cycle 3). It is NOT frame ordering: whether the
    // pop-result continuation or the archive's resume rebuild runs first is an
    // implementation detail of the scheduler, and both orders must be safe.
    // It is `MasterArchiveNotifier.markClientsReviewed`'s guard, which tests
    // the row's `providerCanReviewClient` FLAG rather than merely the id's
    // presence: once either path has flipped the row to `false`, the other
    // finds nothing patchable, returns without touching `items`, and so emits
    // no state and preserves the list's identity (which
    // `_MasterArchiveScreenState._groupedEntries` memoises on). An
    // id-presence-only guard would still allocate and re-emit here — silently
    // costing an O(n) regroup and a full `ListView` rebuild for no visible
    // change.
    ref.read(clientReviewSignalProvider.notifier).markReviewed(booking.id);
    showSuccessSnack(context, l10n.clientReviewSubmitSuccess);
    // `true` — "no longer reviewable"; see the file header's pop-result
    // contract. Exactly ONE pop on this path: the 409 branch above returned
    // early without popping at all, so a duplicate submit can never report
    // `true` from here.
    if (context.canPop()) context.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<Booking> async = ref.watch(
      bookingDetailProvider(widget.bookingId),
    );
    final bool submitting = ref.watch(leaveClientFeedbackProvider).isLoading;
    // The pop-result this screen reports upward from EVERY manual pop site —
    // see the file header's pop-result contract. `true` once this booking is
    // known not (or no longer) reviewable by this provider: the pre-gate's own
    // fetch said `false`, or a duplicate submit 409'd. Stays `false` while the
    // fetch is still in flight (`async.value` is null then), which is the
    // correct "nothing learned" answer for a master who backs out early.
    final bool notReviewable =
        _alreadyReviewed || async.value?.providerCanReviewClient == false;

    return Scaffold(
      backgroundColor: BrandColors.base,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            _TopBar(
              title: l10n.clientReviewScreenTitle,
              backLabel: l10n.clientReviewBackSemantics,
              popResult: notReviewable,
            ),
            Expanded(
              // NO LOADING FLASH ON A RELOAD. Two paths re-run
              // `bookingDetailProvider(id)` while this screen is mounted and
              // visible: the 409 branch of [_submit] and the detail-entry
              // success branch (whose refetch overlaps the pop animation).
              // Neither may fall back through `_LoadingForm` — that would
              // flash the skeleton between the form and `_NotReviewable`.
              //
              // MEASURED, because the obvious story is wrong: both of those
              // paths are `ref.invalidate`, and `AsyncValue.when` ALREADY
              // skips the loading branch for an invalidate/refresh — that is
              // `skipLoadingOnRefresh`, which defaults to `true`. Deleting the
              // `skipLoadingOnReload: true` below leaves
              // `leave_client_feedback_screen_test.dart`'s frame-by-frame
              // no-flash test GREEN (mutation-verified 2026-08-17, against a
              // deliberately PENDING refetch — so the test is not merely
              // racing a resolved future). It is kept as the guard for the
              // OTHER reload trigger it really does cover: a rebuild caused by
              // one of that provider's own dependencies changing, which
              // `skipLoadingOnRefresh` does NOT skip. The FIRST load is
              // unaffected either way and still shows `_LoadingForm` — both
              // flags apply only once a previous value exists.
              child: async.when(
                skipLoadingOnReload: true,
                loading: () => const _LoadingForm(),
                error: (Object e, StackTrace _) => _ErrorState(
                  onRetry: () =>
                      ref.invalidate(bookingDetailProvider(widget.bookingId)),
                ),
                // Pre-gate: `providerCanReviewClient` is the REAL,
                // server-computed value on this single-booking fetch (see the
                // file header) — false means this booking's client was
                // already reviewed, so the not-reviewable state renders
                // immediately and the form is never built. `_alreadyReviewed`
                // is the SEPARATE post-submit signal (a 409 racing this
                // snapshot) and swaps to the same state once true.
                data: (Booking booking) =>
                    (!booking.providerCanReviewClient || _alreadyReviewed)
                    ? const _NotReviewable(popResult: true)
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

/// The loading state, rendered while `bookingDetailProvider` fetches this
/// booking — shaped like [_Form] (client card / rating card / comment card /
/// pinned submit CTA, same paddings) so the real content replaces it without
/// a layout pop. Same "recessed wells breathing on the taupe base" idiom as
/// `BookingsSkeleton` (`widgets/my_bookings_states.dart`) — deliberately NOT
/// a shimmer or a bare spinner, matching this feature's established loading
/// language.
///
/// This became the COMMON case for the archive→«Відгук» entry path once that
/// tap started prefetching a real `GET /bookings/{id}` (see
/// `master_archive_screen.dart`'s `_openReview`); the detail→review path was
/// already a cache hit (the still-mounted `BookingDetailScreen` keeps
/// `bookingDetailProvider` warm) and rarely shows this at all.
class _LoadingForm extends StatefulWidget {
  const _LoadingForm();

  @override
  State<_LoadingForm> createState() => _LoadingFormState();
}

class _LoadingFormState extends State<_LoadingForm>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final bool disabled =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      if (disabled) {
        _controller.value = 1.0;
      } else {
        _controller.repeat(reverse: true);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Animation<double> curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );

    Widget breathe(Widget content) => AnimatedBuilder(
      animation: curved,
      // 0.55 → 1.0 — same shallow breathe as `BookingsSkeleton`, not a blink.
      builder: (BuildContext context, Widget? child) =>
          Opacity(opacity: 0.55 + curved.value * 0.45, child: child),
      child: content,
    );

    return Semantics(
      key: const Key('leave-client-feedback-loading'),
      label: l10n.clientReviewLoadingSemantics,
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: breathe(
              const SingleChildScrollView(
                physics: NeverScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  VelvetSpacing.lg,
                  VelvetSpacing.xs,
                  VelvetSpacing.lg,
                  VelvetSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _ClientCardWell(),
                    SizedBox(height: VelvetSpacing.lg),
                    _RatingCardWell(),
                    SizedBox(height: VelvetSpacing.md),
                    _CommentCardWell(),
                  ],
                ),
              ),
            ),
          ),
          breathe(
            const Padding(
              padding: EdgeInsets.fromLTRB(
                VelvetSpacing.lg,
                0,
                VelvetSpacing.lg,
                VelvetSpacing.md,
              ),
              child: _Well(
                width: double.infinity,
                height: VelvetSizes.cta,
                radius: VelvetRadii.button,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Silhouette of [ClientFeedbackCard] — a round avatar well + name/role/
/// context line wells.
class _ClientCardWell extends StatelessWidget {
  const _ClientCardWell();

  // Same camel wash as the real card's surface.
  static const Color _cardColor = Color(0xFFEDE4D5);

  @override
  Widget build(BuildContext context) {
    return NeumorphicCard(
      color: _cardColor,
      padding: const EdgeInsets.all(VelvetSpacing.md),
      child: Row(
        children: <Widget>[
          const _Well(width: 48, height: 48, radius: 24),
          const SizedBox(width: VelvetSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _Well(width: _fraction(context, 0.4), height: 15),
                const SizedBox(height: VelvetSpacing.xs),
                _Well(width: _fraction(context, 0.22), height: 12),
                const SizedBox(height: VelvetSpacing.xs),
                _Well(width: _fraction(context, 0.5), height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }

  double _fraction(BuildContext context, double f) =>
      MediaQuery.sizeOf(context).width * f;
}

/// Silhouette of `_RatingCard` — a section-label well + a row of five star
/// wells.
class _RatingCardWell extends StatelessWidget {
  const _RatingCardWell();

  @override
  Widget build(BuildContext context) {
    return const NeumorphicCard(
      showBorder: true,
      padding: EdgeInsets.symmetric(
        horizontal: VelvetSpacing.md,
        vertical: VelvetSpacing.lg,
      ),
      child: Column(
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: _Well(width: 120, height: 12),
          ),
          SizedBox(height: VelvetSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              _Well(width: 36, height: 36, radius: 18),
              _Well(width: 36, height: 36, radius: 18),
              _Well(width: 36, height: 36, radius: 18),
              _Well(width: 36, height: 36, radius: 18),
              _Well(width: 36, height: 36, radius: 18),
            ],
          ),
        ],
      ),
    );
  }
}

/// Silhouette of `_CommentCard` — a section-label well + a tall multi-line
/// well.
class _CommentCardWell extends StatelessWidget {
  const _CommentCardWell();

  @override
  Widget build(BuildContext context) {
    return const NeumorphicCard(
      showBorder: true,
      padding: EdgeInsets.all(VelvetSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: _Well(width: 140, height: 12),
          ),
          SizedBox(height: VelvetSpacing.sm),
          _Well(width: double.infinity, height: 96),
        ],
      ),
    );
  }
}

/// A single recessed placeholder well. Mirrors `_Well` in
/// `widgets/my_bookings_states.dart` (private to that file, so re-declared
/// here rather than imported — see `ARCHITECTURE-mobile.md`'s DRY-on-third-
/// repetition rule; this is the second occurrence, not the third).
class _Well extends StatelessWidget {
  const _Well({required this.width, required this.height, this.radius = 6});

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return NeumorphicInset(
      radius: radius,
      child: SizedBox(width: width, height: height),
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

  // `VelvetText.feedbackMutedSm` is already the muted 11sp variant of the
  // feedback base style, so it renders identically to the previous
  // `VelvetText.feedback(BrandColors.muted)` plus a manual size override —
  // that manual override was redundant (the base is already 11sp) and is
  // exactly the pattern `scripts/forbid_inline_fontsize.sh` disallows.
  // Reusing the cached token avoids both the redundancy and the gate.
  static final TextStyle _noteStyle = VelvetText.feedbackMutedSm;
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
  const _TopBar({
    required this.title,
    required this.backLabel,
    required this.popResult,
  });

  final String title;
  final String backLabel;

  /// Reported to the caller on pop — see the file header's pop-result
  /// contract. `true` once this booking is known not (or no longer) reviewable,
  /// which is what lets `MasterArchiveScreen` drop that row's «Відгук» CTA even
  /// when the master backs out of an already-reviewed booking instead of
  /// submitting.
  final bool popResult;

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
                if (context.canPop()) context.pop(popResult);
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
/// already been left — reached either as a PRE-GATE (the real
/// `providerCanReviewClient` fetched on open is already `false`) or via the
/// post-submit 409 backstop for a race (see the file header's gating note).
class _NotReviewable extends StatelessWidget {
  const _NotReviewable({required this.popResult});

  /// Reported to the caller on pop — see the file header's pop-result
  /// contract. A literal `true` at the only call site (rather than the
  /// `notReviewable` expression [_TopBar] is handed, which is provably `true`
  /// wherever this state renders) so the widget stays `const` and this info
  /// state never rebuilds. A parameter rather than a hardcoded `pop(true)`
  /// inside `build` purely so the contract is visible from the call site.
  final bool popResult;

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
                  if (context.canPop()) context.pop(popResult);
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

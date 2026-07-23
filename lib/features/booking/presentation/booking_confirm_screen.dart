// BookingConfirmScreen: the independent-master booking flow's final
// review-and-submit step (the `/booking/confirm` route).
//
// MO-3 (single-visit rework): the client multi-selects services in Step 1 and
// picks ONE date + ONE start time for the whole visit on the time step. This
// screen reviews the WHOLE visit — the ordered service list, a single visit
// window (`startAt` → `startAt + summed duration`), the summed total (or a
// min–max band when any service is range-priced), and an optional visit-level
// «Коментар для майстра» — then submits it as ONE `POST /appointments`
// (`AppointmentSubmit.submitVisit`), auto-confirmed to CONFIRMED. This REPLACES
// the pre-MO-3 "N `POST /bookings`, one per service" fan-out and its
// per-appointment partial-failure UI.
//
// ERROR HANDLING: one call now, so one clear error state. A failed submit maps
// the typed [Failure] (a 409 `CLIENT_BOOKING_CONFLICT` / `BOOKING_ALREADY_ELAPSED`
// / `DUPLICATE_SERVICE`, a 429 rate-limit, or a generic failure) to ONE inline
// error banner pinned directly above the CTA — the screen stays fully
// interactive so the client can re-tap «Записатись» (reusing the SAME
// idempotency key, so a retry de-duplicates) or back out and re-pick a time.
//
// RESCHEDULE: when `rescheduleBookingId` is non-null the flow moves a single
// EXISTING booking — [services] holds one element and the submit swaps to
// `PATCH /bookings/{id}/reschedule` (`AppointmentSubmit.reschedule`); the
// comment field is hidden (that endpoint has no comment channel).
//
// DATA SOURCE: `BookingConfirmArgs` carries the fully-resolved ordered
// [services] + the single [startAt] + the stable visit idempotency key + the
// master. The master identity + address are re-read from
// `publicMasterProfileProvider(masterId)` — the SAME 5-minute-keepAlive family
// the earlier flow screens already warmed — so reaching this screen normally
// costs zero extra round trips.
//
// SEC: renders the INDEPENDENT master's address (street/buildingNo/city/
// locationNote — for a solo master that may be a HOME address) — acquires the
// app-wide screenshot guard in `initState`. Do not remove in a future audit.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/master/application/public_master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:beautica_mobile/shared/formatters/duration_minutes.dart';
import 'package:beautica_mobile/shared/formatters/service_price_display.dart';
import 'package:beautica_mobile/shared/formatters/street_city_line.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';

import '../application/booking_detail_notifier.dart';
import '../application/booking_notifier.dart';
import '../application/my_bookings_notifier.dart';
import '../domain/booking_confirm_args.dart';
import '../domain/booking_success_args.dart';
import '../domain/booking_tab.dart';
import '../domain/create_appointment_request.dart';
import 'widgets/booking_comment_field.dart';
import 'widgets/booking_cta_footer.dart';
import 'widgets/booking_recap.dart';
import 'widgets/booking_summary_cards.dart';
import 'widgets/booking_top_bar.dart';
import 'widgets/master_strip.dart';

/// Booking flow final review — the single-visit confirm-and-submit screen.
class BookingConfirmScreen extends ConsumerStatefulWidget {
  const BookingConfirmScreen({super.key, required this.args});

  final BookingConfirmArgs args;

  @override
  ConsumerState<BookingConfirmScreen> createState() =>
      _BookingConfirmScreenState();
}

class _BookingConfirmScreenState extends ConsumerState<BookingConfirmScreen> {
  static const int _maxComment = 500;

  final TextEditingController _comment = TextEditingController();

  /// The last submit's failure, or `null` before/after a successful submit —
  /// drives the single inline error banner. Cleared at the start of each
  /// submit.
  Failure? _failure;

  late final ScreenProtectionManager _screenProtection;

  @override
  void initState() {
    super.initState();
    _screenProtection = ref.read(screenProtectionProvider)..acquire();
  }

  @override
  void dispose() {
    _screenProtection.release();
    _comment.dispose();
    super.dispose();
  }

  bool get _isReschedule => widget.args.rescheduleBookingId != null;

  /// The visit's summed duration in minutes — drives the single window's end
  /// time everywhere (confirm window, success window, calendar event).
  /// `widget.args.services` never changes for this screen's life, so it is
  /// summed once (mirrors `BookingSuccessScreen`'s `late final`) rather than
  /// re-folded on each submit-spinner-toggle / failure `setState` rebuild.
  late final int _totalDurationMinutes = widget.args.services.fold<int>(
    0,
    (int sum, MasterService s) => sum + s.durationMinutes,
  );

  /// The visit's ordered service selections, mapped for the summary card once —
  /// `widget.args.services` is immutable for this screen's life, so this is not
  /// re-derived on the submit-spinner-toggle / failure `setState` rebuilds
  /// (mirrors `BookingSuccessScreen`'s `late final _selections`).
  late final List<BookingSelection> _selections = <BookingSelection>[
    for (final MasterService s in widget.args.services)
      BookingSelection(
        name: s.name,
        price: ServicePriceDisplay.format(s),
        duration: DurationMinutes.format(s.durationMinutes),
        durationMinutes: s.durationMinutes,
        priceMin: s.priceMin,
        priceMax: s.priceMax,
      ),
  ];

  Future<void> _submit(Master master, List<MasterService> services) async {
    FocusScope.of(context).unfocus();
    if (_failure != null) setState(() => _failure = null);

    final String? rescheduleId = widget.args.rescheduleBookingId;
    try {
      if (rescheduleId != null) {
        await ref
            .read(appointmentSubmitProvider.notifier)
            .reschedule(rescheduleId, widget.args.startAt);
        if (!mounted) return;
        // A successful RESCHEDULE moved an EXISTING booking — refresh its detail
        // page + the upcoming My Bookings list from the widget layer (a `ref`
        // outside a Notifier), mirroring the cancel flow's post-write
        // invalidation, so a cross-provider invalidate never runs from inside a
        // Notifier (the `forbid_provider_self_invalidation` cycle footgun).
        ref.invalidate(bookingDetailProvider(rescheduleId));
        ref.invalidate(myBookingsProvider(BookingTab.upcoming));
      } else {
        final String? comment = _comment.text.trim().isEmpty
            ? null
            : _comment.text.trim();
        await ref
            .read(appointmentSubmitProvider.notifier)
            .submitVisit(
              CreateAppointmentRequest(
                masterId: widget.args.masterId,
                masterServiceIds: <String>[
                  for (final MasterService s in services) s.id,
                ],
                startAt: widget.args.startAt,
                idempotencyKey: widget.args.idempotencyKey,
                clientComment: comment,
              ),
            );
        if (!mounted) return;
      }
      context.pushReplacement(
        RouteNames.bookingSuccess,
        extra: BookingSuccessArgs(
          master: master,
          services: services,
          startAt: widget.args.startAt,
          isReschedule: rescheduleId != null,
        ),
      );
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() => _failure = failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final AsyncValue<PublicMasterProfileData> asyncData = ref.watch(
      publicMasterProfileProvider(widget.args.masterId),
    );
    final bool inFlight = ref.watch(
      appointmentSubmitProvider.select((AsyncValue<void> s) => s.isLoading),
    );

    // Resolve the master out of the cached profile. The ordered services come
    // straight from the args (already resolved during the selection step); the
    // catalogue read only supplies the master identity + address.
    final Master? master = asyncData.value?.$1;
    final bool ready = master != null;

    final String ctaLabel = inFlight
        ? l10n.bookingSubmitCtaLoading
        : _isReschedule
        ? l10n.bookingRescheduleSubmitCta
        : l10n.bookingSubmitCta;

    return Scaffold(
      backgroundColor: BrandColors.base,
      bottomNavigationBar: ready
          ? BookingCtaFooter(
              key: const Key('booking-confirm-cta-footer'),
              buttonKey: const Key('booking-confirm-submit-cta'),
              label: ctaLabel,
              enabled: true,
              loading: inFlight,
              onPressed: () => _submit(master, widget.args.services),
            )
          : null,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            BookingTopBar(
              title: l10n.bookingConfirmScreenTitle,
              backSemantics: l10n.bookingConfirmBackSemantics,
              onBack: () => context.pop(),
              backKey: const Key('booking-confirm-back'),
            ),
            Expanded(
              child: asyncData.when(
                loading: () => const _LoadingBody(),
                error: (Object e, StackTrace _) => ErrorState(
                  key: const Key('booking-confirm-error-state'),
                  failure: e is Failure ? e : UnknownFailure(cause: e),
                  onRetry: () => ref.invalidate(
                    publicMasterProfileProvider(widget.args.masterId),
                  ),
                ),
                data: (PublicMasterProfileData _) {
                  if (!ready) return const SizedBox.shrink();
                  return _ConfirmBody(
                    master: master,
                    selections: _selections,
                    startAt: widget.args.startAt,
                    totalDurationMinutes: _totalDurationMinutes,
                    comment: _comment,
                    maxComment: _maxComment,
                    // The reschedule endpoint takes only the new start — a
                    // note-to-master input would be silently ignored, so it is
                    // hidden on the reschedule path.
                    showComment: !_isReschedule,
                    failure: _failure,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmBody extends StatelessWidget {
  const _ConfirmBody({
    required this.master,
    required this.selections,
    required this.startAt,
    required this.totalDurationMinutes,
    required this.comment,
    required this.maxComment,
    required this.showComment,
    required this.failure,
  });

  final Master master;
  final List<BookingSelection> selections;
  final DateTime startAt;
  final int totalDurationMinutes;
  final TextEditingController comment;
  final int maxComment;

  /// Whether the optional «Коментар для майстра» field is shown — false on the
  /// reschedule path (the reschedule endpoint has no comment channel).
  final bool showComment;

  /// The last submit failure, or `null` — drives the single inline error
  /// banner pinned at the end of the scroll body (directly above the CTA).
  final Failure? failure;

  @override
  Widget build(BuildContext context) {
    final String? addressLine = formatStreetCityLine(
      street: master.street,
      buildingNo: master.buildingNo,
      city: master.city,
    );
    final String? addressDetail =
        (master.locationNote?.trim().isNotEmpty ?? false)
        ? master.locationNote!.trim()
        : null;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.lg,
        VelvetSpacing.md,
        VelvetSpacing.lg,
        VelvetSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // ONE visit recap: the master identity card, the shared address, the
          // single visit window (start → start + summed duration), the ordered
          // service list and the «Разом» total — all in one card stack.
          BookingSummaryCards(
            key: const Key('booking-confirm-visit-card'),
            masterCard: Hero(
              tag: 'master-strip-${master.id}',
              child: MasterStrip.fromMaster(
                master,
                showRole: true,
                showRating: true,
              ),
            ),
            addressLine: addressLine,
            addressDetail: addressDetail,
            dateLabel: formatFullDate(startAt),
            timeLabel: formatTimeRange(startAt, totalDurationMinutes),
            selections: selections,
          ),
          if (showComment) ...<Widget>[
            const SizedBox(height: VelvetSpacing.md),
            BookingCommentField(
              controller: comment,
              fieldKey: const Key('booking-confirm-comment-field'),
              maxLength: maxComment,
            ),
          ],
          if (failure != null) ...<Widget>[
            const SizedBox(height: VelvetSpacing.md),
            _SubmitErrorBanner(failure: failure!),
          ],
        ],
      ),
    );
  }
}

/// The single inline error banner shown when a submit fails — an error-tone
/// icon + the failure's localized message in a bordered neumorphic card, pinned
/// at the end of the scroll body so it reads directly above the pinned CTA.
class _SubmitErrorBanner extends StatelessWidget {
  const _SubmitErrorBanner({required this.failure});

  final Failure failure;

  @override
  Widget build(BuildContext context) {
    return NeumorphicCard(
      key: const Key('booking-confirm-submit-error'),
      showBorder: true,
      padding: const EdgeInsets.all(VelvetSpacing.sm + 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.error_outline_rounded,
              size: 18,
              color: BrandColors.error,
            ),
          ),
          const SizedBox(width: VelvetSpacing.sm),
          Expanded(
            child: Text(
              failure.userMessage(context),
              style: VelvetText.feedback(BrandColors.error),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loading state
// ---------------------------------------------------------------------------

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmerScope(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          VelvetSpacing.lg,
          VelvetSpacing.md,
          VelvetSpacing.lg,
          VelvetSpacing.lg,
        ),
        children: const <Widget>[
          SkeletonBlock(
            width: double.infinity,
            height: 96,
            radius: VelvetRadii.card,
          ),
          SizedBox(height: VelvetSpacing.md),
          SkeletonBlock(
            width: double.infinity,
            height: 220,
            radius: VelvetRadii.card,
          ),
        ],
      ),
    );
  }
}

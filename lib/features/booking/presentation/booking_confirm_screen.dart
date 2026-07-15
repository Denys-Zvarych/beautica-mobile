// BookingConfirmScreen: the independent-master booking flow's final
// review-and-submit step (the `/booking/confirm` route).
//
// MULTI-SERVICE (the multi-service booking rework): the client picks a
// SEPARATE time for each selected service on `BookingTimeScreen`, so this
// screen now reviews N appointments (one per service) and submits ONE `POST
// /bookings` per appointment (all against the same master, auto-confirmed to
// CONFIRMED). It mirrors `salon_booking_confirm_screen.dart`'s structure — a
// shared master + address header, one card per appointment, a grand total when
// N > 1, an optional «Коментар для майстра» note, a pinned CTA — keyed by
// SERVICE instead of MASTER, and driven by `IndependentBookingSubmit`.
//
// PARTIAL FAILURE (the reason this screen can't just reuse the single-service
// `BookingConfirm` notifier): each service's booking succeeds/fails
// independently. On «Записатись» every appointment is attempted; if ALL
// succeed the screen `pushReplacement`s to the success screen; if SOME fail the
// screen STAYS, each failed card shows its own error, a SnackBar nudges retry,
// and the CTA becomes «Повторити» — re-submitting ONLY the still-failed
// appointments (already-created bookings are never re-sent, and each reuses its
// stable idempotency key so an ambiguously-failed one de-duplicates). Success
// is never claimed while any appointment failed. A 409 (slot taken between pick
// and submit, or the client's own overlapping booking) fails only THAT
// appointment.
//
// DATA SOURCE: `BookingConfirmArgs` carries the fully-resolved appointments
// (service id + chosen start + stable idempotency key) + the master. The
// service DISPLAY objects are resolved by id out of
// `publicMasterProfileProvider(masterId)` — the SAME 5-minute-keepAlive family
// `ServiceSelectorSheet` / `BookingTimeScreen` already warmed earlier in this
// exact flow, so reaching this screen normally costs zero extra round trips.
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

import '../application/booking_notifier.dart';
import '../domain/booking_appointment.dart';
import '../domain/booking_confirm_args.dart';
import '../domain/booking_success_args.dart';
import 'widgets/booking_comment_field.dart';
import 'widgets/booking_cta_footer.dart';
import 'widgets/booking_recap.dart';
import 'widgets/booking_summary_cards.dart';
import 'widgets/booking_top_bar.dart';
import 'widgets/labelled_row.dart';
import 'widgets/master_strip.dart';

/// Booking flow final review — the multi-appointment confirm-and-submit screen.
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

  /// Blocks leaving once at least one appointment has succeeded — the only
  /// safe way forward after a partial success is the «Повторити» retry (which
  /// reuses each still-failed appointment's stable idempotency key). Mirrors
  /// `salon_booking_confirm_screen.dart`.
  void _onBack(bool hasSucceeded) {
    if (hasSucceeded) {
      _showBackBlockedMessage();
      return;
    }
    context.pop();
  }

  void _showBackBlockedMessage() {
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.salonBookingBackBlockedMessage),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _submit(
    Master master,
    List<_ResolvedAppointment> resolved,
  ) async {
    FocusScope.of(context).unfocus();
    final IndependentBookingSubmitState result = await ref
        .read(independentBookingSubmitProvider.notifier)
        .submit(
          widget.args.masterId,
          widget.args.appointments,
          comment: _comment.text,
          rescheduleBookingId: widget.args.rescheduleBookingId,
        );
    if (!mounted) return;
    if (result.allSucceeded(widget.args.appointments)) {
      context.pushReplacement(
        RouteNames.bookingSuccess,
        extra: BookingSuccessArgs(
          master: master,
          appointments: <BookingSuccessAppointment>[
            for (final _ResolvedAppointment r in resolved)
              BookingSuccessAppointment(
                service: r.service,
                start: r.appointment.startAt,
              ),
          ],
          isReschedule: widget.args.rescheduleBookingId != null,
        ),
      );
      return;
    }
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.salonBookingPartialFailureMessage),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final AsyncValue<PublicMasterProfileData> asyncData = ref.watch(
      publicMasterProfileProvider(widget.args.masterId),
    );
    final (bool inFlight, bool hasFailures, bool hasSucceeded) = ref.watch(
      independentBookingSubmitProvider.select(
        (IndependentBookingSubmitState s) =>
            (s.inFlight, s.hasFailures, s.hasSucceeded),
      ),
    );

    // Resolve each appointment's service display object out of the cached
    // profile. Null while loading; a missing service is a defensive
    // broken-flow guard below.
    Master? master;
    List<_ResolvedAppointment>? resolved;
    final PublicMasterProfileData? data = asyncData.value;
    if (data != null) {
      final (Master m, List<MasterService> services) = data;
      master = m;
      final List<_ResolvedAppointment> acc = <_ResolvedAppointment>[];
      for (final BookingAppointment a in widget.args.appointments) {
        final MasterService? service = services
            .where((MasterService s) => s.id == a.serviceId)
            .firstOrNull;
        if (service == null) {
          // A selected service is no longer in the master's catalogue —
          // bail back rather than render a confirmation for a service that
          // no longer exists (mirrors the old single-service guard).
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) context.pop();
          });
          resolved = null;
          break;
        }
        acc.add(_ResolvedAppointment(appointment: a, service: service));
      }
      resolved ??= acc.length == widget.args.appointments.length ? acc : null;
    }

    final bool ready = master != null && resolved != null;
    final bool isReschedule = widget.args.rescheduleBookingId != null;
    final String ctaLabel = inFlight
        ? l10n.bookingSubmitCtaLoading
        : hasFailures
        ? l10n.salonBookingRetryCta
        : isReschedule
        ? l10n.bookingRescheduleSubmitCta
        : l10n.bookingSubmitCta;

    return PopScope(
      canPop: !hasSucceeded,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) _showBackBlockedMessage();
      },
      child: Scaffold(
        backgroundColor: BrandColors.base,
        bottomNavigationBar: ready
            ? BookingCtaFooter(
                key: const Key('booking-confirm-cta-footer'),
                buttonKey: const Key('booking-confirm-submit-cta'),
                label: ctaLabel,
                enabled: true,
                loading: inFlight,
                onPressed: () => _submit(master!, resolved!),
              )
            : null,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              BookingTopBar(
                title: l10n.bookingConfirmScreenTitle,
                backSemantics: l10n.bookingConfirmBackSemantics,
                onBack: () => _onBack(hasSucceeded),
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
                      master: master!,
                      resolved: resolved!,
                      comment: _comment,
                      maxComment: _maxComment,
                      // The reschedule endpoint takes only the new start —
                      // a note-to-master input would be silently ignored, so
                      // it is hidden on the reschedule path.
                      showComment: !isReschedule,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One appointment paired with its resolved service display object.
class _ResolvedAppointment {
  const _ResolvedAppointment({
    required this.appointment,
    required this.service,
  });

  final BookingAppointment appointment;
  final MasterService service;

  BookingSelection get selection => BookingSelection(
    name: service.name,
    price: ServicePriceDisplay.format(service),
    duration: DurationMinutes.format(service.durationMinutes),
    durationMinutes: service.durationMinutes,
    priceMin: service.priceMin,
    priceMax: service.priceMax,
  );
}

class _ConfirmBody extends StatelessWidget {
  const _ConfirmBody({
    required this.master,
    required this.resolved,
    required this.comment,
    required this.maxComment,
    required this.showComment,
  });

  final Master master;
  final List<_ResolvedAppointment> resolved;
  final TextEditingController comment;
  final int maxComment;

  /// Whether the optional «Коментар для майстра» field is shown — false on the
  /// reschedule path (the reschedule endpoint has no comment channel).
  final bool showComment;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String? addressLine = formatStreetCityLine(
      street: master.street,
      buildingNo: master.buildingNo,
      city: master.city,
    );
    final String? addressDetail =
        (master.locationNote?.trim().isNotEmpty ?? false)
        ? master.locationNote!.trim()
        : null;
    final List<BookingSelection> allSelections = <BookingSelection>[
      for (final _ResolvedAppointment r in resolved) r.selection,
    ];

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
          MasterStrip.fromMaster(master, showRole: true, showRating: true),
          const SizedBox(height: VelvetSpacing.md),
          NeumorphicCard(
            key: const Key('booking-confirm-address-card'),
            padding: const EdgeInsets.all(VelvetSpacing.sm + 4),
            child: LabelledRow(
              label: l10n.bookingAddressLabel,
              value: addressLine ?? l10n.bookingAddressUnknown,
              detail: addressDetail,
            ),
          ),
          const SizedBox(height: VelvetSpacing.md),
          for (final _ResolvedAppointment r in resolved) ...<Widget>[
            _AppointmentCard(resolved: r),
            const SizedBox(height: VelvetSpacing.md),
          ],
          if (resolved.length > 1) ...<Widget>[
            NeumorphicCard(
              key: const Key('booking-confirm-grand-total-card'),
              showBorder: true,
              padding: const EdgeInsets.all(VelvetSpacing.sm + 4),
              child: BookingRecap(selections: allSelections, totalOnly: true),
            ),
            const SizedBox(height: VelvetSpacing.md),
          ],
          if (showComment)
            BookingCommentField(
              controller: comment,
              fieldKey: const Key('booking-confirm-comment-field'),
              maxLength: maxComment,
            ),
        ],
      ),
    );
  }
}

/// One appointment card (date/time + service + price) wired to ITS OWN slice
/// of [IndependentBookingSubmitState], rendering an error line when this
/// appointment's own submit failed.
class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({required this.resolved});

  final _ResolvedAppointment resolved;

  @override
  Widget build(BuildContext context) {
    final String serviceId = resolved.appointment.serviceId;
    return Consumer(
      builder: (BuildContext context, WidgetRef ref, Widget? child) {
        final Failure? failure = ref.watch(
          independentBookingSubmitProvider.select(
            (IndependentBookingSubmitState s) => s.failureFor(serviceId),
          ),
        );
        return Column(
          key: ValueKey<String>('booking-confirm-appt-$serviceId'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            BookingSummaryCards(
              showAddress: false,
              dateLabel: formatFullDate(resolved.appointment.startAt),
              timeLabel: formatTimeRange(
                resolved.appointment.startAt,
                resolved.service.durationMinutes,
              ),
              singleSelection: resolved.selection,
              dense: true,
            ),
            if (failure != null) ...<Widget>[
              const SizedBox(height: VelvetSpacing.sm),
              Row(
                key: Key('booking-confirm-appt-error-$serviceId'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.error_outline_rounded,
                      size: 15,
                      color: BrandColors.error,
                    ),
                  ),
                  const SizedBox(width: VelvetSpacing.xs),
                  Expanded(
                    child: Text(
                      failure.userMessage(context),
                      style: VelvetText.feedback(BrandColors.error),
                    ),
                  ),
                ],
              ),
            ],
          ],
        );
      },
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

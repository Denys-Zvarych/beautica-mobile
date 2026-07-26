// MO-8 [mobile-security MEDIUM, fixed] — NOT ROUTED. MO-7 deleted `VisitCard`,
// this screen's only UI entry point, but its `GoRoute` (`/bookings/visit/
// :appointmentId`) stayed registered — reachable via an explicit, component-
// targeted intent (MainActivity is `exported="true"`, `flutter_deeplinking_
// enabled="true"`) straight to the whole-visit cancel below, which the locked
// product decision ("cancel just that one service") deliberately removed.
// The `GoRoute` was unregistered in `app_router.dart`; this file is
// INTENTIONALLY RETAINED (not deleted) pending an open product question —
// whether the whole-visit review journey needs a new entry point. Re-adding
// one requires re-registering a GoRoute in `app_router.dart`.
//
// MO-5 — «Деталі запису» for a multi-service VISIT, opened from a `VisitCard`.
//
// The visit analogue of `booking_detail_screen.dart`: it is backed by
// `GET /appointments/{appointmentId}` (the enriched [Appointment] — ordered
// items, summed totals, mutually-visible notes, `canReview`, locality) instead
// of `GET /bookings/{id}`, and its cancel/review act on the APPOINTMENT
// endpoints (a single-booking cancel/review on an appointment child is 409'd by
// the backend — the client MUST route a visit here).
//
// It reuses the SAME [BookingSuccessScaffold] + [BookingSummaryCards] machinery
// the single-booking detail uses, so the visit reads as one venue, one window,
// one total with the per-service «Послуги» table + summed «Разом» band. The
// status-driven title/subline/actions grammar mirrors the single detail.
//
// SCOPE (MO-5): CLIENT surface only — no provider viewer branch (a visit's
// provider-side management is out of scope), and no add-to-calendar / reschedule
// header affordances (single-booking-only for now). Cancel + review + rebook are
// the visit's action set.
//
// go_router only: pushed at `/bookings/visit/:appointmentId` (nested under the
// Записи branch so it pops back onto that branch's own navigator stack).
//
// SEC: renders the master's/salon's address (PII) alongside the date + per-
// service «Послуги» table and the visit status — acquires the app-wide
// [ScreenProtectionManager] for its lifetime, mirroring every other PII screen.
// (Free-text visit notes are NOT rendered here yet — MO-6 may add them.)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:beautica_mobile/shared/formatters/booking_price_labels.dart';
import 'package:beautica_mobile/shared/formatters/duration_minutes.dart';
import 'package:beautica_mobile/shared/formatters/service_count_label.dart';

import '../application/appointment_detail_notifier.dart';
import '../application/my_bookings_notifier.dart';
import '../data/booking_providers.dart';
import '../domain/appointment.dart';
import '../domain/appointment_display_x.dart';
import '../domain/booking_status.dart';
import '../domain/booking_tab.dart';
import 'widgets/booking_recap.dart';
import 'widgets/booking_status_badge.dart';
import 'widgets/booking_status_medallion.dart';
import 'widgets/booking_summary_cards.dart';
import 'widgets/booking_success_scaffold.dart';
import 'widgets/cancel_booking_dialog.dart';
import 'widgets/master_strip.dart';

/// «Деталі запису» for the visit identified by [appointmentId].
class VisitDetailScreen extends ConsumerStatefulWidget {
  const VisitDetailScreen({super.key, required this.appointmentId});

  final String appointmentId;

  @override
  ConsumerState<VisitDetailScreen> createState() => _VisitDetailScreenState();
}

class _VisitDetailScreenState extends ConsumerState<VisitDetailScreen> {
  // Captured in initState so dispose() never touches `ref` (Riverpod 3.x throws
  // on a post-dispose `ref` read).
  late final ScreenProtectionManager _screenProtection;

  @override
  void initState() {
    super.initState();
    _screenProtection = ref.read(screenProtectionProvider)..acquire();
  }

  @override
  void dispose() {
    _screenProtection.release();
    super.dispose();
  }

  /// «Скасувати запис» opens the visit confirmation — it never cancels anything
  /// itself. The dialog resolves to the client's note (possibly empty) on
  /// confirm, and to `null` on every way of backing out. On confirm it routes to
  /// `AppointmentRepository.cancelAppointment`, which cancels ALL the visit's
  /// services at once — NEVER the per-booking `cancelBooking` (the backend 409s
  /// that on an appointment child).
  Future<void> _confirmCancel(
    BuildContext context,
    Appointment appointment,
  ) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? note = await showCancelVisitDialog(
      context,
      servicesLabel: formatServiceCountUk(appointment.items.length),
      masterName: appointment.masterName,
      dateLabel: formatFullDate(appointment.startAt),
      timeDetail: formatTimeRange(
        appointment.startAt,
        appointment.totalDurationMinutes,
      ),
    );
    if (note == null || !mounted) return; // backed out — nothing happened.

    try {
      await ref
          .read(appointmentRepositoryProvider)
          .cancelAppointment(appointment.id, note: note.isEmpty ? null : note);
    } on BookingAlreadyElapsedFailure catch (failure) {
      // The window elapsed against the SERVER clock between this (possibly
      // stale) screen opening and the confirm tap. Surface the clean localized
      // message AND refetch so it re-renders read-only — never a raw 409.
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(failure.userMessage(context))));
      ref.invalidate(appointmentDetailProvider(appointment.id));
      return;
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(l10n.errUnknown)));
      return;
    }
    if (!mounted) return;

    // Refetch this visit's fresh status and re-partition the two affected tabs
    // (it just left Майбутні and entered Скасовані).
    ref.invalidate(appointmentDetailProvider(appointment.id));
    ref.invalidate(myBookingsProvider(BookingTab.upcoming));
    ref.invalidate(myBookingsProvider(BookingTab.cancelled));
  }

  void _onRebook(Appointment appointment) {
    // Same rebook target as the single-booking detail — the master's own public
    // profile (a visit record carries no independently-addressable venue).
    context.push(RouteNames.masterPublicProfile(appointment.masterId));
  }

  /// «Залишити відгук» — routes the review CTA to the APPOINTMENT review path
  /// with the appointmentId (MO-6 finishes the leave-review wiring). Gated on
  /// `appointment.canReview` at the call site. Never the per-booking review — a
  /// visit is reviewed once, as a whole.
  void _onLeaveReview(Appointment appointment) {
    context.push(RouteNames.appointmentReview(appointment.id));
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<Appointment> async = ref.watch(
      appointmentDetailProvider(widget.appointmentId),
    );

    return async.when(
      loading: () => const _DetailLoading(),
      error: (Object e, StackTrace _) => _DetailError(
        onRetry: () =>
            ref.invalidate(appointmentDetailProvider(widget.appointmentId)),
      ),
      data: (Appointment appointment) => _DetailBody(
        appointment: appointment,
        onCancel: () => _confirmCancel(context, appointment),
        onRebook: () => _onRebook(appointment),
        onLeaveReview: () => _onLeaveReview(appointment),
      ),
    );
  }
}

/// The populated screen — a thin declarative call site over
/// [BookingSuccessScaffold].
class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.appointment,
    required this.onCancel,
    required this.onRebook,
    required this.onLeaveReview,
  });

  final Appointment appointment;
  final VoidCallback onCancel;
  final VoidCallback onRebook;
  final VoidCallback onLeaveReview;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final BookingStatusVisual v = BookingStatusVisual.forStatus(
      appointment.status,
      atSalon: appointment.atSalon,
      l10n: l10n,
    );
    final (String? addressValue, String? addressDetail) =
        appointment.addressBlock;

    // Same title/hero grammar as the single-booking detail (product decisions
    // 2026-07-15/16): the big status TITLE shows only for COMPLETED /
    // NOT_COMPLETED; the top MEDALLION only for NOT_COMPLETED.
    final bool showStatusTitle =
        appointment.status == BookingStatus.completed ||
        appointment.status == BookingStatus.notCompleted;
    final bool showStatusHero =
        appointment.status == BookingStatus.notCompleted;

    return BookingSuccessScaffold(
      title: showStatusTitle ? v.label : null,
      subline: _subline(appointment, l10n),
      canPop: true,
      leading: _BackButton(semanticLabel: l10n.bookingDetailBackSemantics),
      showHero: showStatusHero,
      heroBuilder: showStatusHero
          ? (AnimationController controller) =>
                BookingStatusMedallion(visual: v, controller: controller)
          : null,
      actions: _actions(l10n),
      recapCards: <Widget>[
        BookingSummaryCards(
          masterCard: MasterStrip(
            name: appointment.masterName,
            type: appointment.atSalon
                ? MasterType.salonMaster
                : MasterType.independentMaster,
            professionalTitle: appointment.masterProfessionalTitle,
            showRole: true,
            showRating: false,
          ),
          salonName: appointment.salonName,
          addressLine: addressValue,
          addressDetail: addressDetail,
          hideAddressWhenEmpty: true,
          locationNote: appointment.locationNote,
          dateLabel: formatFullDate(appointment.startAt),
          timeLabel: formatTimeRange(
            appointment.startAt,
            appointment.totalDurationMinutes,
          ),
          // The multi-service «Послуги» table + summed «Разом» band — the visit
          // is exactly the multi-item recap this widget already renders for the
          // salon flow.
          selections: <BookingSelection>[
            for (final AppointmentItem item in appointment.items)
              BookingSelection(
                name: item.serviceName,
                price: formatBookingPrice(
                  price: item.price,
                  priceMax: item.priceMax,
                ),
                duration: DurationMinutes.format(item.durationMinutes),
                durationMinutes: item.durationMinutes,
                priceMin: item.price,
                priceMax: item.priceMax,
              ),
          ],
          dense: true,
          showBorder: true,
          compactText: true,
          showPrice: appointment.showsPrice,
        ),
      ],
    );
  }

  /// One calm sentence per status — reuses the single-booking detail's copy.
  String? _subline(Appointment a, AppLocalizations l10n) {
    switch (a.status) {
      case BookingStatus.confirmed:
        if (a.isPast) return null;
        return l10n.bookingDetailSublineConfirmed;
      case BookingStatus.completed:
        return l10n.bookingDetailSublineCompleted;
      case BookingStatus.notCompleted:
        return l10n.bookingDetailSublineNotCompleted(a.providerGenitive);
      case BookingStatus.cancelled:
        return l10n.bookingDetailSublineCancelled;
      case BookingStatus.declined:
        return a.atSalon
            ? l10n.bookingDetailSublineDeclinedSalon
            : l10n.bookingDetailSublineDeclinedMaster;
      case BookingStatus.unknown:
        return null;
    }
  }

  /// The pinned footer, by status. No reschedule / add-to-calendar for a visit
  /// (MO-5 scope). An empty list renders no footer.
  List<Widget> _actions(AppLocalizations l10n) {
    switch (appointment.status) {
      case BookingStatus.confirmed:
        // An elapsed CONFIRMED visit is read-only — offer rebooking, not a
        // cancel the server would 409.
        if (appointment.isPast) return _rebookActions(l10n);
        return <Widget>[
          _DestructiveSecondaryButton(
            label: l10n.bookingDetailCancelCta,
            icon: Icons.close_rounded,
            onTap: onCancel,
          ),
        ];

      case BookingStatus.completed:
        if (appointment.canReview) {
          return <Widget>[
            NeumorphicButton(
              key: const Key('visit-detail-leave-review'),
              label: l10n.bookingDetailReviewCta,
              icon: Icons.rate_review_rounded,
              onPressed: onLeaveReview,
            ),
            const SizedBox(height: VelvetSpacing.xs),
            NeumorphicButton(
              label: l10n.bookingDetailRebookCta,
              icon: Icons.refresh_rounded,
              onPressed: onRebook,
            ),
          ];
        }
        return _rebookActions(l10n);

      case BookingStatus.cancelled:
      case BookingStatus.declined:
        return _rebookActions(l10n);

      case BookingStatus.notCompleted:
        return const <Widget>[];

      case BookingStatus.unknown:
        return _rebookActions(l10n);
    }
  }

  List<Widget> _rebookActions(AppLocalizations l10n) => <Widget>[
    NeumorphicButton(
      key: const Key('visit-detail-rebook'),
      label: l10n.bookingDetailRebookCta,
      icon: Icons.refresh_rounded,
      onPressed: onRebook,
    ),
  ];
}

/// The un-animated back affordance — mirrors `BookingDetailScreen._BackButton`.
class _BackButton extends StatelessWidget {
  const _BackButton({required this.semanticLabel});

  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return NeumorphicIconButton(
      key: const Key('visit-detail-back'),
      icon: Icons.arrow_back_ios_new_rounded,
      semanticLabel: semanticLabel,
      onTap: () => context.pop(),
    );
  }
}

/// The **destructive** secondary — «Скасувати запис». A quiet base-tone pill
/// with an `error` hairline edge / glyph / label (never a red slab) — mirrors
/// `BookingDetailScreen`'s own destructive secondary.
class _DestructiveSecondaryButton extends StatefulWidget {
  const _DestructiveSecondaryButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_DestructiveSecondaryButton> createState() =>
      _DestructiveSecondaryButtonState();
}

class _DestructiveSecondaryButtonState
    extends State<_DestructiveSecondaryButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        key: const Key('visit-detail-cancel'),
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: VelvetSizes.cta,
          decoration: BoxDecoration(
            color: BrandColors.base,
            borderRadius: BorderRadius.circular(VelvetRadii.button),
            boxShadow: _pressed ? null : VelvetShadows.extrudedButton,
            border: Border.all(
              color: BrandColors.error.withValues(alpha: 0.55),
              width: 1.2,
            ),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(widget.icon, size: 18, color: BrandColors.error),
              const SizedBox(width: VelvetSpacing.xs),
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VelvetText.cta().copyWith(color: BrandColors.error),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Loading skeleton — a centred spinner behind the same un-animated back
/// affordance, so a slow fetch never traps the client without a way out.
class _DetailLoading extends StatelessWidget {
  const _DetailLoading();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: BrandColors.base,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            VelvetSpacing.lg,
            VelvetSpacing.lg,
            VelvetSpacing.lg,
            VelvetSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _BackButton(semanticLabel: l10n.bookingDetailBackSemantics),
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(color: BrandColors.accent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The error state — the failure message + a retry button, behind the same back
/// affordance.
class _DetailError extends StatelessWidget {
  const _DetailError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: BrandColors.base,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            VelvetSpacing.lg,
            VelvetSpacing.lg,
            VelvetSpacing.lg,
            VelvetSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _BackButton(semanticLabel: l10n.bookingDetailBackSemantics),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
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
                            key: const Key('visit-detail-error-retry'),
                            label: l10n.retryLabel,
                            icon: Icons.refresh_rounded,
                            onPressed: onRetry,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

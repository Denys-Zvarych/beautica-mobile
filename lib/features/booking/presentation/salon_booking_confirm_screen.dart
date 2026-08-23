// Phase 271 — SalonBookingConfirmScreen: salon booking flow step 4 (final
// review + submit). Mirrors the independent-master `BookingConfirmScreen`
// (`booking_confirm_screen.dart`) structure — a flat read of each
// appointment, a pinned CTA — extended to the salon's N-master model: a
// single shared salon address card, ONE [SalonAppointmentCard] per assigned
// master (each carrying its own Дата/Час/services/subtotal AND its own
// comment field — see below), a grand total across every master when N > 1,
// and each appointment submitted via the SHARED `AppointmentSubmit
// .submitVisit` — the same submit path, failure mapping, and idempotency
// contract the independent flow uses (NOT a forked salon submit).
//
// CARD RESTORATION (owner-reported regression, 2026-08-22): Phase 271 had
// replaced the per-master `SalonAppointmentCard` (deleted together with the
// notifier it was coupled to) with the generic `BookingSummaryCards
// .fromSchedule` — a REGRESSION versus the originally-approved design, not
// an intended simplification. This pass restores the dedicated per-master
// card (`widgets/salon_appointment_card.dart`, rebuilt WITHOUT the deleted
// notifier coupling — see that file's header) while keeping the shared
// `AppointmentSubmit.submitVisit` write path this screen has used since
// Phase 271. INTERIM STATE remains as Phase 271 documented: this screen
// submits every appointment SEQUENTIALLY and stops at the FIRST
// non-client-conflict failure, with ONE inline error banner (no per-master
// status, no retry-only-the-failed-ones) — full per-master submit status is
// a later phase's job.
//
// Each appointment's stable `idempotencyKey` (minted once per appointment
// when these args were built) means a re-tap after a failure is always safe:
// an already-created appointment's retry de-dupes server-side rather than
// duplicating, even though this screen does not track which ones already
// succeeded.
//
// PER-MASTER COMMENT (owner decision, 2026-08-22, verbatim: "one field per
// master card"): each [SalonAppointmentCard] carries its OWN comment
// controller — that card's text becomes ONLY that appointment's
// `clientComment`, never any other master's. This screen owns the
// controllers' lifecycle: one per appointment, created in `initState` (and
// reconciled in `didUpdateWidget` if `widget.args` ever changes under the
// same `State` — defensive; `widget.args.appointments` is otherwise
// immutable for this screen's life, mirroring `_allSelections` below),
// disposed in `dispose`.
//
// CLIENT-SELF-OVERLAP (owner decision, 2026-08-22, verbatim: "remove the
// bottom error when client already has a booking on same date/time; instead
// display a popup … still proceed? … It's only the client's
// responsibility"): a `ClientBookingConflictFailure` (409
// `CLIENT_BOOKING_CONFLICT`) is intercepted PER APPOINTMENT in `_submitOne`,
// never surfaced as the bottom `_SubmitErrorBanner`. Confirming
// `showClientBookingConflictDialog` resubmits THAT SAME appointment with
// `CreateAppointmentRequest.allowClientOverlap: true` — a ONE-SHOT flag on
// that single resubmit, never sticky state carried onto any other
// appointment or any later booking. Dismissing the dialog throws
// `_SubmitCancelled` (caught in `_submit`, before the `on Failure` clause) —
// nothing else is submitted and the screen is left exactly as it was, no
// banner, so the client can back out and change the date/time. EVERY other
// failure (the generic `ConflictFailure` "slot not available" — a MASTER's
// slot taken by someone else, `NotFoundFailure`, network errors, etc.) is
// UNCHANGED: it still surfaces via the single inline `_SubmitErrorBanner`.
//
// DATA SOURCE: `SalonBookingConfirmArgs` carries the fully-resolved
// appointments forward from `SalonTimeScreen` (the step-3 picks live in an
// autoDispose provider that would be gone by the time this screen mounts) —
// no re-fetch. The salon's ADDRESS is a separate, secondary read via
// `publicSalonProfileProvider(salonId)` — the SAME 5-minute-keepAlive family
// `PublicSalonProfileScreen` / `SalonMasterSelectionScreen` already warmed
// earlier in this exact flow, so reaching this screen normally costs zero
// extra round trips. Being secondary, its loading/error states NEVER block or
// error the whole screen — the address row falls back to
// `l10n.bookingAddressUnknown` (the same fallback `BookingSummaryCards`
// already uses for a master with no address) while the salon profile is
// loading or failed; the appointments themselves always render from `args`.
//
// SEC: renders the salon's address (PII) — acquires the app-wide screenshot
// guard in `initState`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:beautica_mobile/features/salon/application/public_salon_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/street_city_line.dart';

import '../application/booking_notifier.dart';
import '../application/my_bookings_notifier.dart';
import '../domain/booking_tab.dart';
import '../domain/create_appointment_request.dart';
import '../domain/salon_booking_confirm_args.dart';
import 'widgets/booking_cta_footer.dart';
import 'widgets/booking_recap.dart';
import 'widgets/booking_top_bar.dart';
import 'widgets/client_booking_conflict_dialog.dart';
import 'widgets/labelled_row.dart';
import 'widgets/salon_appointment_card.dart';
import 'widgets/salon_avatar_gradients.dart';
import 'widgets/section_rule.dart';

/// Salon booking flow step 4 — review the N appointments and submit them.
class SalonBookingConfirmScreen extends ConsumerStatefulWidget {
  const SalonBookingConfirmScreen({super.key, required this.args});

  final SalonBookingConfirmArgs args;

  @override
  ConsumerState<SalonBookingConfirmScreen> createState() =>
      _SalonBookingConfirmScreenState();
}

class _SalonBookingConfirmScreenState
    extends ConsumerState<SalonBookingConfirmScreen> {
  static const int _maxComment = 500;

  /// One comment controller PER APPOINTMENT, keyed by `masterId` (a salon
  /// booking has exactly one appointment per assigned master — see
  /// `salon_booking_confirm_args.dart`). See the file header's PER-MASTER
  /// COMMENT note.
  final Map<String, TextEditingController> _comments =
      <String, TextEditingController>{};

  /// The last submit's failure, or `null` — drives the single inline error
  /// banner. Cleared at the start of each submit. See the file header: this
  /// screen has no per-master status, so a mid-batch failure surfaces here
  /// and stops the remaining appointments from being attempted. NEVER set for
  /// a `ClientBookingConflictFailure` — that one opens a dialog instead (see
  /// `_submitOne`).
  Failure? _failure;

  // Captured in initState so dispose() never touches `ref` (Riverpod 3.x
  // throws on a post-dispose `ref` read).
  late final ScreenProtectionManager _screenProtection;

  // `widget.args.appointments` never changes for this screen's lifetime, so
  // the flattened grand-total selection list is computed once here instead of
  // on every build() (mobile-perf MEDIUM, Phase 14.18 salon-confirm audit).
  late final List<BookingSelection> _allSelections = widget.args.appointments
      .expand((SalonBookingAppointment a) => a.schedule.services)
      .map(BookingSelection.fromSalonCatalogService)
      .toList();

  @override
  void initState() {
    super.initState();
    _screenProtection = ref.read(screenProtectionProvider)..acquire();
    _syncCommentControllers();
  }

  @override
  void didUpdateWidget(covariant SalonBookingConfirmScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Defensive: `widget.args.appointments` is immutable for this screen's
    // ordinary lifetime (a fresh push always mints a fresh State), but if
    // this `State` were ever reused with a different `args` — e.g. a future
    // caller that reuses a `GlobalKey` — the controller map must not leak a
    // stale entry nor miss a new appointment.
    if (!identical(oldWidget.args, widget.args)) _syncCommentControllers();
  }

  /// Creates a controller for every CURRENT appointment (keyed by masterId)
  /// that doesn't already have one, and disposes+drops any controller for a
  /// masterId no longer present — a 1:1 map to `widget.args.appointments` at
  /// all times, so `dispose()` below never leaks and a resync never
  /// double-creates.
  void _syncCommentControllers() {
    final Set<String> currentIds = widget.args.appointments
        .map((SalonBookingAppointment a) => a.schedule.masterId)
        .toSet();
    _comments.removeWhere((String masterId, TextEditingController c) {
      if (currentIds.contains(masterId)) return false;
      c.dispose();
      return true;
    });
    for (final String masterId in currentIds) {
      _comments.putIfAbsent(masterId, TextEditingController.new);
    }
  }

  TextEditingController _commentFor(String masterId) => _comments[masterId]!;

  @override
  void dispose() {
    _screenProtection.release();
    for (final TextEditingController c in _comments.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Builds THIS appointment's write payload from ITS OWN comment controller
  /// — never any other master's text (see the file header's PER-MASTER
  /// COMMENT note).
  CreateAppointmentRequest _requestFor(
    SalonBookingAppointment appointment, {
    bool allowClientOverlap = false,
  }) {
    final String rawComment = _commentFor(
      appointment.schedule.masterId,
    ).text.trim();
    return CreateAppointmentRequest(
      masterId: appointment.schedule.masterId,
      masterServiceIds: appointment.schedule.orderedMasterServiceIds,
      startAt: appointment.startAt,
      idempotencyKey: appointment.idempotencyKey,
      clientComment: rawComment.isEmpty ? null : rawComment,
      allowClientOverlap: allowClientOverlap,
    );
  }

  /// Submits ONE appointment. On a `ClientBookingConflictFailure`
  /// specifically, opens [showClientBookingConflictDialog] instead of letting
  /// the failure propagate to the bottom banner: confirming resubmits this
  /// SAME appointment with `allowClientOverlap: true`; dismissing throws
  /// [_SubmitCancelled] so `_submit`'s loop stops with no banner and nothing
  /// further is submitted. Every OTHER failure (generic slot-conflict, 404,
  /// network, rate-limit, …) is rethrown unchanged for `_submit`'s `on
  /// Failure` clause to render as the usual inline banner.
  Future<void> _submitOne(SalonBookingAppointment appointment) async {
    final CreateAppointmentRequest request = _requestFor(appointment);
    try {
      await ref.read(appointmentSubmitProvider.notifier).submitVisit(request);
    } on ClientBookingConflictFailure catch (conflict) {
      if (!mounted) throw const _SubmitCancelled();
      final bool proceed =
          await showClientBookingConflictDialog(
            context,
            ClientBookingConflictPreview(
              newServiceNames: appointment.schedule.services
                  .map((s) => s.name)
                  .join(', '),
              newMasterName:
                  '${appointment.schedule.firstName} '
                          '${appointment.schedule.lastName}'
                      .trim(),
              newStart: appointment.startAt,
              newEnd: appointment.startAt.add(
                Duration(minutes: appointment.durationMinutes),
              ),
              conflict: conflict,
            ),
          ) ??
          false;
      if (!proceed) throw const _SubmitCancelled();
      if (!mounted) throw const _SubmitCancelled();
      await ref
          .read(appointmentSubmitProvider.notifier)
          .submitVisit(_requestFor(appointment, allowClientOverlap: true));
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_failure != null) setState(() => _failure = null);

    final List<SalonBookingAppointment> appointments = widget.args.appointments;
    try {
      // Sequential, stops at the first non-client-conflict failure — see the
      // file header. Each appointment reuses its OWN stable idempotency key,
      // so a re-tap after a failure never duplicates an appointment that
      // actually landed.
      for (final SalonBookingAppointment appointment in appointments) {
        await _submitOne(appointment);
      }
      if (!mounted) return;
      // Every appointment landed → invalidate the booking views ONCE, from
      // the widget layer (mirrors the independent flow's `BookingConfirmScreen`
      // — see that screen for the full rationale on why this is a widget-layer
      // `ref`, not a cross-provider notifier invalidate).
      ref.invalidate(myBookingsProvider(BookingTab.upcoming));
      ref.invalidate(nextAppointmentProvider);
      context.pushReplacement(
        RouteNames.salonBookingSuccess,
        extra: SalonBookingSuccessArgs(
          salonId: widget.args.salonId,
          appointments: appointments,
        ),
      );
    } on _SubmitCancelled {
      // The client dismissed the client-self-overlap dialog — submit nothing
      // further, no banner. The screen is left exactly as it was so the
      // client can back out and change the date/time (owner decision — see
      // the file header).
      return;
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() => _failure = failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bool inFlight = ref.watch(
      appointmentSubmitProvider.select((AsyncValue<void> s) => s.isLoading),
    );
    final List<SalonBookingAppointment> appointments = widget.args.appointments;

    // Secondary read — never blocks/errors the whole screen.
    final Salon? salon = ref.watch(
      publicSalonProfileProvider(
        widget.args.salonId,
      ).select((AsyncValue<PublicSalonProfileData> v) => v.value?.$1),
    );
    final String? addressLine = salon == null
        ? null
        : formatStreetCityLine(
            street: salon.street,
            buildingNo: salon.buildingNo,
            city: salon.city,
          );
    final String? addressDetail =
        (salon?.locationNote?.trim().isNotEmpty ?? false)
        ? salon!.locationNote!.trim()
        : null;
    final String? salonName = (salon?.name.trim().isNotEmpty ?? false)
        ? salon!.name.trim()
        : null;

    final String ctaLabel = inFlight
        ? l10n.bookingSubmitCtaLoading
        : l10n.bookingSubmitCta;

    return Scaffold(
      backgroundColor: BrandColors.base,
      bottomNavigationBar: BookingCtaFooter(
        key: const Key('salon-confirm-cta-footer'),
        buttonKey: const Key('salon-confirm-submit-cta'),
        label: ctaLabel,
        enabled: true,
        loading: inFlight,
        onPressed: _submit,
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            BookingTopBar(
              title: l10n.salonBookingConfirmTitle,
              backSemantics: l10n.bookingConfirmBackSemantics,
              onBack: () => context.pop(),
              backKey: const Key('salon-confirm-back'),
            ),
            Expanded(
              child: SingleChildScrollView(
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
                    // The salon identity + address card, above the per-master
                    // recap cards.
                    NeumorphicCard(
                      key: const Key('salon-confirm-address-card'),
                      padding: const EdgeInsets.all(VelvetSpacing.sm + 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          if (salonName != null) ...<Widget>[
                            LabelledRow(
                              key: const Key('salon-confirm-salon-name'),
                              label: l10n.bookingSalonLabel,
                              value: salonName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SectionRule(),
                          ],
                          LabelledRow(
                            label: l10n.bookingAddressLabel,
                            value: addressLine ?? l10n.bookingAddressUnknown,
                            detail: addressDetail,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: VelvetSpacing.md),
                    // Each master's OWN Дата/Час + ordered services + subtotal
                    // + comment field — a dedicated [SalonAppointmentCard] per
                    // assigned master (restored — see the file header).
                    for (int i = 0; i < appointments.length; i++) ...<Widget>[
                      SalonAppointmentCard(
                        key: ValueKey<String>(
                          'salon-confirm-appt-${appointments[i].schedule.masterId}',
                        ),
                        appointment: appointments[i],
                        selections: appointments[i].schedule.services
                            .map(BookingSelection.fromSalonCatalogService)
                            .toList(),
                        avatarGradient: salonAvatarGradient(i),
                        commentController: _commentFor(
                          appointments[i].schedule.masterId,
                        ),
                        commentFieldKey: Key(
                          'salon-confirm-comment-field-'
                          '${appointments[i].schedule.masterId}',
                        ),
                        maxComment: _maxComment,
                      ),
                      const SizedBox(height: VelvetSpacing.md),
                    ],
                    if (appointments.length > 1) ...<Widget>[
                      NeumorphicCard(
                        key: const Key('salon-confirm-grand-total-card'),
                        showBorder: true,
                        padding: const EdgeInsets.all(VelvetSpacing.sm + 4),
                        child: BookingRecap(
                          selections: _allSelections,
                          totalOnly: true,
                        ),
                      ),
                      const SizedBox(height: VelvetSpacing.md),
                    ],
                    if (_failure != null)
                      _SubmitErrorBanner(failure: _failure!),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Thrown when the client dismisses [showClientBookingConflictDialog] instead
/// of proceeding — a benign, non-[Failure] control-flow signal caught by
/// `_submit`'s own `on _SubmitCancelled` clause (checked BEFORE `on
/// Failure`), so it never reaches the bottom error banner. Deliberately not a
/// [Failure]: it is not an error at all, it is the client's explicit choice
/// to back out.
class _SubmitCancelled implements Exception {
  const _SubmitCancelled();
}

/// The single inline error banner shown when a submit fails — mirrors
/// `BookingConfirmScreen`'s banner (the independent flow). NEVER shown for a
/// `ClientBookingConflictFailure` — that one opens
/// `showClientBookingConflictDialog` instead (see `_submitOne`).
class _SubmitErrorBanner extends StatelessWidget {
  const _SubmitErrorBanner({required this.failure});

  final Failure failure;

  @override
  Widget build(BuildContext context) {
    return NeumorphicCard(
      key: const Key('salon-confirm-submit-error'),
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

// Phase 14.18 — SalonBookingConfirmScreen: salon booking flow step 4 (final
// review + submit). Mirrors the independent-master `BookingConfirmScreen`
// (`booking_confirm_screen.dart`) structure — a flat read of the whole
// booking, an optional "Коментар для майстра" note, a pinned CTA — extended
// to the salon's N-master model: a single shared salon address card, ONE
// `SalonAppointmentCard` per assigned master (each carrying its OWN
// Дата/Час/services/subtotal), a grand total across every master when N > 1,
// and N `POST /bookings` calls via `SalonBookingSubmit`.
//
// INFORMATION PARITY (salon booking rework): the independent flow's
// `BookingConfirmScreen` shows address once + date/time + services/subtotal
// for its single booking. The salon flow carries the SAME information, just
// reshaped for N masters: the salon address is identical for every
// appointment (all N masters work at the SAME salon), so it is shown ONCE at
// the top rather than repeated per card (see `_SalonAddressCard` below); each
// master's OWN date/time/services/subtotal still renders per-card (via
// `SalonAppointmentCard`, which now also carries a `BookingRecap` of that
// master's services — see that widget's file header); and a grand total
// across every master's services closes the picture — suppressed when N == 1
// since it would just repeat that one card's own subtotal.
//
// PARTIAL FAILURE (the reason this screen can't just reuse `BookingConfirm`):
// each master's booking succeeds/fails independently. On «Записатись» every
// appointment is attempted; if ALL succeed the screen `pushReplacement`s to
// the salon success screen; if SOME fail the screen STAYS, each failed card
// shows its own error, a SnackBar nudges retry, and the CTA becomes
// «Повторити» — re-submitting ONLY the still-failed appointments (already-
// created bookings are never re-sent, and each reuses its stable idempotency
// key so an ambiguously-failed one de-duplicates). Success is never claimed
// while any appointment failed.
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/salon/application/public_salon_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/street_city_line.dart';

import '../application/salon_booking_submit_notifier.dart';
import '../domain/salon_booking_confirm_args.dart';
import 'widgets/booking_comment_field.dart';
import 'widgets/booking_cta_footer.dart';
import 'widgets/booking_recap.dart';
import 'widgets/booking_top_bar.dart';
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

  final TextEditingController _comment = TextEditingController();

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

  // Per-appointment selection lists, indexed the same as
  // `widget.args.appointments` — computed once here (rather than inside
  // `SalonAppointmentCard.build()`) so the ~2-3 rebuilds a submit pass drives
  // per card (pending → submitting → succeeded/failed, via
  // `_AppointmentCardSlot`'s own scoped `select`) don't reallocate the same
  // small list on every transition (mobile-perf LOW, Phase 14.18 audit).
  late final List<List<BookingSelection>> _selectionsByAppointment = widget
      .args
      .appointments
      .map(
        (SalonBookingAppointment a) => a.schedule.services
            .map(BookingSelection.fromSalonCatalogService)
            .toList(),
      )
      .toList();

  @override
  void initState() {
    super.initState();
    // SEC: this screen renders the salon's address (PII: street/buildingNo/
    // city + free-text locationNote) — guard against screenshots /
    // app-switcher snapshots while it is mounted. Mirrors the INTENTIONAL
    // PRODUCT DECISION on `PublicSalonProfileScreen` — do not remove in a
    // future audit pass.
    _screenProtection = ref.read(screenProtectionProvider)..acquire();
  }

  @override
  void dispose() {
    _screenProtection.release();
    _comment.dispose();
    super.dispose();
  }

  /// Blocks leaving the screen once at least one appointment has succeeded
  /// (see [SalonBookingSubmitState.hasSucceeded]) — the only safe way forward
  /// after a partial success is the «Повторити» retry, which reuses each
  /// still-failed appointment's stable idempotency key. Leaving here would
  /// return to `SalonTimeScreen` with live schedule state, where re-tapping
  /// «Підтвердити» would re-mint fresh keys for the already-created bookings.
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

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final SalonBookingSubmitState result = await ref
        .read(salonBookingSubmitProvider.notifier)
        .submit(widget.args.appointments, comment: _comment.text);
    if (!mounted) return;
    if (result.allSucceeded(widget.args.appointments)) {
      context.pushReplacement(
        RouteNames.salonBookingSuccess,
        extra: SalonBookingSuccessArgs(
          salonId: widget.args.salonId,
          appointments: widget.args.appointments,
        ),
      );
      return;
    }
    // Partial (or total) failure — stay put; each failed card already shows
    // its own error. A floating SnackBar nudges the retry the CTA now offers.
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
    // Screen-level watch is scoped to just the CTA/back-guard flags via
    // `select` — a record has value equality, so the whole card list is NOT
    // rebuilt on each of the N+2 per-master mutations a submit pass makes.
    // Each card watches its OWN (status, failure) through a scoped Consumer
    // below (mobile-perf LOW, Phase 14.18 salon-submit audit).
    final (bool inFlight, bool hasFailures, bool hasSucceeded) = ref.watch(
      salonBookingSubmitProvider.select(
        (SalonBookingSubmitState s) =>
            (s.inFlight, s.hasFailures, s.hasSucceeded),
      ),
    );
    final List<SalonBookingAppointment> appointments = widget.args.appointments;

    // Secondary read — never blocks or errors the whole screen. Scoped via
    // `select` to just the resolved salon so a still-loading/resolving family
    // instance only rebuilds THIS read, not the whole screen (which would
    // reconstruct every `_AppointmentCardSlot` and defeat their own `select`
    // memoization below) — mobile-perf MEDIUM, Phase 14.18 audit. See file
    // header DATA SOURCE note.
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
    // The salon being booked into — read from the SAME secondary
    // `publicSalonProfileProvider` salon the address block already uses (no
    // extra fetch). Null while the profile is loading/failed, exactly like the
    // address; the card then just renders the address alone, as before.
    final String? salonName = (salon?.name.trim().isNotEmpty ?? false)
        ? salon!.name.trim()
        : null;

    final String ctaLabel = inFlight
        ? l10n.bookingSubmitCtaLoading
        : (hasFailures ? l10n.salonBookingRetryCta : l10n.bookingSubmitCta);

    return PopScope(
      // Once any appointment has been created, block the OS/gesture back so a
      // partial success can only be finished via the «Повторити» retry (which
      // reuses stable idempotency keys). Back stays free while nothing has
      // succeeded yet.
      canPop: !hasSucceeded,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) _showBackBlockedMessage();
      },
      child: Scaffold(
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
                onBack: () => _onBack(hasSucceeded),
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
                      NeumorphicCard(
                        key: const Key('salon-confirm-address-card'),
                        padding: const EdgeInsets.all(VelvetSpacing.sm + 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            // «Салон» identity line above the address — the
                            // client sees WHICH salon they're booking into
                            // before submitting. Same salon-name → hairline →
                            // address composition `BookingSummaryCards` uses on
                            // «Деталі запису», so the two surfaces read alike.
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
                      for (int i = 0; i < appointments.length; i++) ...<Widget>[
                        _AppointmentCardSlot(
                          appointment: appointments[i],
                          selections: _selectionsByAppointment[i],
                          position: i,
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
                      BookingCommentField(
                        controller: _comment,
                        fieldKey: const Key('salon-confirm-comment-field'),
                        maxLength: _maxComment,
                      ),
                    ],
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

/// One appointment card wired to ITS OWN slice of [SalonBookingSubmitState].
///
/// Watching `(statusFor(id), failureFor(id), hasFailures, inFlight)` through a
/// scoped [Consumer] + `select` (record → value equality) means an unaffected
/// master's card still memoizes across every other master's mutation during a
/// submit pass. Unlike `hasFailures` (flips at most once per pass, pending →
/// resolved), `inFlight` flips TWICE per pass (`false → true → false`) — but
/// that costs nothing extra: the parent `SalonBookingConfirmScreen.build()`
/// already scopes its own watch to `(inFlight, hasFailures, hasSucceeded)`
/// (see above), so every emission where `inFlight` flips is by construction
/// one where the parent's own tuple changes too. The parent therefore already
/// rebuilds and reconstructs all N `_AppointmentCardSlot`s on both of those
/// transitions regardless of this widget's own `select` — widening this
/// record just makes that already-happening rebuild carry the right value,
/// it does not add a new rebuild wave.
class _AppointmentCardSlot extends StatelessWidget {
  const _AppointmentCardSlot({
    required this.appointment,
    required this.selections,
    required this.position,
  });

  final SalonBookingAppointment appointment;

  /// This appointment's services, pre-mapped once by the parent state's
  /// `_selectionsByAppointment` — a stable identity across this slot's own
  /// submit-status-driven rebuilds (see that field's doc comment).
  final List<BookingSelection> selections;
  final int position;

  @override
  Widget build(BuildContext context) {
    final String masterId = appointment.schedule.masterId;
    return Consumer(
      builder: (BuildContext context, WidgetRef ref, Widget? child) {
        final (
          SalonAppointmentSubmitStatus status,
          Failure? failure,
          bool hasFailures,
          bool inFlight,
        ) = ref.watch(
          salonBookingSubmitProvider.select(
            (SalonBookingSubmitState s) => (
              s.statusFor(masterId),
              s.failureFor(masterId),
              s.hasFailures,
              s.inFlight,
            ),
          ),
        );
        return SalonAppointmentCard(
          key: ValueKey<String>('salon-confirm-appt-$masterId'),
          appointment: appointment,
          selections: selections,
          avatarGradient: salonAvatarGradient(position),
          // `statusFor` returns `pending` before the first submit pass; the
          // card renders no status line for `pending`, so no extra "attempted"
          // gate is needed.
          status: status,
          failure: failure,
          // Gate on progress-or-settled-failure, NOT live-failure-only:
          // `hasFailures` alone means "nothing has failed YET" during the
          // in-between frames of a multi-master submit/retry (see
          // `showSucceededStatus`'s doc comment on `SalonAppointmentCard` for
          // the two windows this closes). Settled-all-succeeded
          // (`inFlight == false`, `hasFailures == false`) still renders
          // nothing, because `_submit()` has no `await` between its last
          // state write and `pushReplacement` — that frame never paints.
          showSucceededStatus: inFlight || hasFailures,
        );
      },
    );
  }
}

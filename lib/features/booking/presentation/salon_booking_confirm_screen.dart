// MO-4 (single-master single-visit rework) — SalonBookingConfirmScreen: salon
// booking flow step 4 (final review + submit).
//
// The salon flow now books ONE visit against ONE chosen master, so this mirrors
// the independent-master `BookingConfirmScreen` almost exactly: the shared
// [BookingSummaryCards] recap (master card + Дата/Час + ordered services +
// «Разом» total/range), an optional «Коментар для майстра», and ONE
// `POST /appointments` via the SHARED `AppointmentSubmit.submitVisit` — the same
// submit path, failure mapping, and idempotency contract the independent flow
// uses (NOT a forked salon submit). This REPLACES the pre-MO-4 N-booking
// fan-out (`SalonBookingSubmit`) and its per-master partial-failure UI.
//
// ERROR HANDLING: one call now, one clear error state. A failed submit maps the
// typed [Failure] (a 409 `CLIENT_BOOKING_CONFLICT`/`BOOKING_ALREADY_ELAPSED`/
// `DUPLICATE_SERVICE`, a 429 rate-limit, or a generic failure) to ONE inline
// error banner pinned above the CTA — the screen stays interactive so the
// client can re-tap «Записатись» (reusing the SAME idempotency key, so a retry
// de-duplicates) or back out and re-pick a time (a fresh key).
//
// The salon's ADDRESS + name is a secondary read via
// `publicSalonProfileProvider(salonId)` (the same 5-minute-keepAlive family
// warmed earlier in this flow) — it never blocks or errors the whole screen;
// the address row falls back to `l10n.bookingAddressUnknown` while loading.
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
import 'widgets/booking_comment_field.dart';
import 'widgets/booking_cta_footer.dart';
import 'widgets/booking_summary_cards.dart';
import 'widgets/booking_top_bar.dart';
import 'widgets/labelled_row.dart';
import 'widgets/salon_avatar_gradients.dart';
import 'widgets/section_rule.dart';

/// Salon booking flow step 4 — review the visit and submit it.
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

  /// The last submit's failure, or `null` — drives the single inline error
  /// banner. Cleared at the start of each submit.
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

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_failure != null) setState(() => _failure = null);

    final String? comment = _comment.text.trim().isEmpty
        ? null
        : _comment.text.trim();
    try {
      await ref
          .read(appointmentSubmitProvider.notifier)
          .submitVisit(
            CreateAppointmentRequest(
              masterId: widget.args.visit.masterId,
              masterServiceIds: widget.args.visit.orderedMasterServiceIds,
              startAt: widget.args.startAt,
              idempotencyKey: widget.args.idempotencyKey,
              clientComment: comment,
            ),
          );
      if (!mounted) return;
      // A newly-created booking is auto-CONFIRMED → lands in the upcoming tab.
      // The client shell keeps the My Bookings branch mounted
      // (`StatefulShellRoute.indexedStack`), so its autoDispose notifier never
      // re-fetches on tab re-select — invalidate it here from the widget layer
      // (mirroring the independent flow's `BookingConfirmScreen`) so the new
      // booking shows without a manual pull-to-refresh. A cross-provider
      // invalidate from a Notifier would trip
      // `forbid_provider_self_invalidation`; this is a widget-layer `ref`, so it
      // is compliant. Also refreshes the Home Hub's own «Найближчий запис»
      // card, which this new booking may now be (Phase 225).
      ref.invalidate(myBookingsProvider(BookingTab.upcoming));
      ref.invalidate(nextAppointmentProvider);
      context.pushReplacement(
        RouteNames.salonBookingSuccess,
        extra: SalonBookingSuccessArgs(
          salonId: widget.args.salonId,
          visit: widget.args.visit,
          startAt: widget.args.startAt,
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
    final bool inFlight = ref.watch(
      appointmentSubmitProvider.select((AsyncValue<void> s) => s.isLoading),
    );

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
                    // The salon identity + address card, above the visit recap.
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
                    // The whole visit: chosen master + Дата/Час + ordered
                    // services + «Разом» total (or min–max band).
                    BookingSummaryCards.fromSchedule(
                      key: const Key('salon-confirm-visit-card'),
                      schedule: widget.args.visit,
                      start: widget.args.startAt,
                      avatarGradient: salonAvatarGradient(0),
                    ),
                    const SizedBox(height: VelvetSpacing.md),
                    BookingCommentField(
                      controller: _comment,
                      fieldKey: const Key('salon-confirm-comment-field'),
                      maxLength: _maxComment,
                    ),
                    if (_failure != null) ...<Widget>[
                      const SizedBox(height: VelvetSpacing.md),
                      _SubmitErrorBanner(failure: _failure!),
                    ],
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

/// The single inline error banner shown when a submit fails — mirrors
/// `BookingConfirmScreen`'s banner (the independent flow).
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

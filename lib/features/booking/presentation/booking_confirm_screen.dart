// Phase 14.2 — BookingConfirmScreen: booking flow Step 3a (final review before
// submit). Replaces the Phase 14.1 `BookingConfirmPlaceholderScreen` stub at
// the same `/booking/confirm` route.
//
// DESIGN SOURCE: `docs/signup-designs/BookingConfirmSuccess/lib/screens/
// booking_confirm_screen.dart` (approved 2026-06-30) — transcribed literally:
// a FLAT, table-style read of the whole booking (master card + Адреса/Дата/Час
// + Послуги/Разом details card, via the shared `BookingSummaryCards`) → an
// optional "Коментар для майстра" note inside a `NeumorphicInset` → a pinned
// camel-gradient "Записатись" CTA.
//
// DATA SOURCE: `BookingConfirmArgs` (Phase 14.1) carries only IDs
// (masterId/serviceId/startAt) — not the full [Master]/[MasterService]
// display objects the preview's screen took as constructor params. Rather
// than re-fetch via a fresh network call, or bloat `BookingConfirmArgs` with
// duplicated payload the slot picker already had, this screen re-watches
// `publicMasterProfileProvider(masterId)` — the SAME family
// `ServiceSelectorSheet` / `SlotDateScreen` / `SlotTimeScreen` already warmed
// earlier in this exact flow (5-minute keepAlive cache, see that provider's
// file header), so reaching this screen normally costs zero extra round
// trips. The target service is then resolved by id out of that cached list.
//
// SUBMIT FLOW: on "Записатись", generates a FRESH `Uuid().v4()` idempotency
// key (never reused — even on retry after a failure, a brand-new key is
// generated on the next tap), calls `BookingConfirmNotifier.confirm(...)`,
// and on success `pushReplacement`s to `/booking/success` (so back can never
// re-reach this screen and re-submit). A `ConflictFailure` (409 — the slot
// was taken between fetch and submit) shows a SnackBar and leaves the screen
// exactly as it was — the user can tap the back button to return to the slot
// picker and choose a different time (this screen never "auto re-opens" the
// picker itself). The back button itself always just cancels the flow
// (`context.pop()`) — no booking is created.

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/features/master/application/public_master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';

import '../application/booking_notifier.dart';
import '../domain/booking.dart';
import '../domain/booking_confirm_args.dart';
import '../domain/booking_success_args.dart';
import '../domain/create_booking_request.dart';
import 'widgets/booking_comment_field.dart';
import 'widgets/booking_cta_footer.dart';
import 'widgets/booking_summary_cards.dart';
import 'widgets/booking_top_bar.dart';

const String _tag = 'feature.booking.confirm';

/// Booking flow Step 3a — the final review-and-submit screen.
class BookingConfirmScreen extends ConsumerStatefulWidget {
  const BookingConfirmScreen({super.key, required this.args});

  final BookingConfirmArgs args;

  @override
  ConsumerState<BookingConfirmScreen> createState() =>
      _BookingConfirmScreenState();
}

class _BookingConfirmScreenState extends ConsumerState<BookingConfirmScreen> {
  static const int _maxComment = 500;
  static const Uuid _uuid = Uuid();

  final TextEditingController _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit(Master master, MasterService service) async {
    FocusScope.of(context).unfocus();
    final String comment = _comment.text.trim();
    // A FRESH key every tap — including a retry after a failed submit. See
    // the file header + `create_booking_request.dart`'s idempotency contract.
    final String idempotencyKey = _uuid.v4();
    final CreateBookingRequest request = CreateBookingRequest(
      masterId: widget.args.masterId,
      serviceId: widget.args.serviceId,
      startAt: widget.args.startAt,
      idempotencyKey: idempotencyKey,
      clientComment: comment.isEmpty ? null : comment,
    );

    try {
      await ref.read(bookingConfirmProvider.notifier).confirm(request);
      if (!mounted) return;
      context.pushReplacement(
        RouteNames.bookingSuccess,
        extra: BookingSuccessArgs(
          master: master,
          service: service,
          start: widget.args.startAt,
        ),
      );
    } catch (e, st) {
      if (kDebugMode) {
        log(
          'booking submit failed: $e',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      final String message = e is Failure
          ? e.userMessage(context)
          : l10n.errUnknown;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final asyncData = ref.watch(
      publicMasterProfileProvider(widget.args.masterId),
    );
    final bool submitting = ref.watch(
      bookingConfirmProvider.select((AsyncValue<Booking?> s) => s.isLoading),
    );

    final PublicMasterProfileData? data = asyncData.value;
    Master? master;
    MasterService? service;
    if (data != null) {
      final (Master m, List<MasterService> services) = data;
      master = m;
      service = services
          .where((MasterService s) => s.id == widget.args.serviceId)
          .firstOrNull;
      if (service == null) {
        // Defensive: the chosen service is no longer in the master's
        // (cached) catalogue — e.g. deactivated between the slot picker and
        // this screen. Mirrors `SlotTimeScreen`'s identical broken-flow
        // guard (`slot_picker_screen.dart`): bail back rather than render a
        // confirmation for a service that no longer exists.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) context.pop();
        });
      }
    }

    return Scaffold(
      backgroundColor: BrandColors.base,
      bottomNavigationBar: (master != null && service != null)
          ? BookingCtaFooter(
              key: const Key('booking-confirm-cta-footer'),
              buttonKey: const Key('booking-confirm-submit-cta'),
              label: submitting
                  ? l10n.bookingSubmitCtaLoading
                  : l10n.bookingSubmitCta,
              enabled: true,
              loading: submitting,
              onPressed: () => _submit(master!, service!),
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
                  if (master == null || service == null) {
                    return const SizedBox.shrink();
                  }
                  return SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                      VelvetSpacing.lg,
                      // Jank fix: matches `SlotTimeScreen`'s established
                      // top-bar-bottom(`sm`) + own-top-inset(`md`) = 24dp
                      // total gap above `MasterStrip` — see
                      // `BookingTopBar`'s file header. Was `VelvetSpacing.sm`
                      // (12dp total, since this screen's old `_TopBar` also
                      // used a tighter `xs` bottom inset), which visibly
                      // hopped the shared-`Hero` master card the instant the
                      // push transition from `SlotTimeScreen` settled.
                      VelvetSpacing.md,
                      VelvetSpacing.lg,
                      VelvetSpacing.md,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        BookingSummaryCards(
                          master: master,
                          service: service,
                          start: widget.args.startAt,
                          // Compact spacing (mobile-dev, booking submit-page
                          // polish pass): the confirm screen previously left
                          // this at its roomy default (32dp section gaps),
                          // meaningfully taller than it needs to be for a
                          // single-service booking. `dense: true` is the
                          // SAME compact mode `BookingSuccessScreen` already
                          // ships (`booking_success_screen.dart`) — reusing
                          // it here (rather than inventing new spacing
                          // constants) keeps the two screens' card rhythm
                          // consistent; it only tightens padding/gaps, never
                          // text or icon sizes (see
                          // `booking_summary_cards.dart` / `booking_recap.dart`).
                          dense: true,
                        ),
                        const SizedBox(height: VelvetSpacing.md),
                        BookingCommentField(
                          controller: _comment,
                          fieldKey: const Key('booking-confirm-comment-field'),
                          maxLength: _maxComment,
                        ),
                      ],
                    ),
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

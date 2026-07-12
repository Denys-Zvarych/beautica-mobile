// Phase 14.2 — BookingSuccessScreen: booking flow Step 3b, the emotional
// payoff shown after `POST /bookings` succeeds.
//
// DESIGN SOURCE: `docs/signup-designs/BookingConfirmSuccess/lib/screens/
// booking_success_screen.dart` (approved 2026-06-30) — transcribed literally:
// an animated check medallion → "Записано!" headline → reassuring subline →
// the SAME `BookingSummaryCards` recap the confirm screen showed (WITHOUT the
// master card, `dense: true`) → a calm "Додати в календар" link → a single
// pinned onward action ("На головну").
//
// The shared celebration structure (PopScope, animated badge, staggered
// title/subline/recap reveal, pinned home button) now lives in
// `widgets/booking_success_scaffold.dart` — composed by BOTH this screen and
// the salon success screen. This screen just supplies its copy, its single
// `BookingSummaryCards` recap, and the (independent-only) "Додати в календар"
// link as the scaffold's `belowRecap`.
//
// DEVIATION — "Мої записи" CTA removed: the preview shipped a second pinned
// action ("Мої записи" → `RouteNames.clientBookings`) alongside "На
// головну". Removed at explicit user request; `RouteNames.clientBookings`
// itself is untouched (still a real, CLIENT-gated route reachable from the
// bottom nav / `QuickLinksCard` — see those call sites) — only this screen's
// button and its l10n key (`bookingSuccessMyBookingsCta`, which had no other
// callers) went away.
//
// SUCCESS ANIMATION: plays the approved preview's real
// `assets/lottie/success.json` at 80 dp via the shared `SuccessLottieBadge`
// (see `widgets/success_lottie_badge.dart`) — smaller than the preview's
// 112 dp slot (not a straight half), a deliberate deviation from the approved
// design at the user's explicit request. Honours `MediaQuery.disableAnimations`
// (handled by the scaffold + badge).
//
// DEVIATION — "Додати в календар": the preview's production notes call for
// `add_2_calendar`/ICS wiring. That package is not in `pubspec.yaml` (checked
// before writing this file) and pulling in a new, unreviewed third-party
// dependency is out of scope for this pass — the link is fully rendered and
// tappable but its action is a documented `// TODO` no-op (see
// `_CalendarLink`).
//
// NAVIGATION: `RouteNames.clientHome` ("/home") is an ALREADY registered
// route (the CLIENT shell's «Головна» branch) — no TODO/no-op needed for the
// button.
//
// NO BACK AFFORDANCE: the shared scaffold wraps everything in
// `PopScope(canPop: false)` so hardware back / iOS edge-swipe is fully blocked
// — the pinned "На головну" button is the only way forward. Combined with
// `BookingConfirmScreen`'s `pushReplacement` (which REMOVES `/booking/confirm`
// from the nav stack rather than pushing on top of it), there is no in-app
// path back to confirm from here at all; see `app_router.dart`'s
// `bookingSuccess` route comment for why no additional `redirect` guard is
// layered on top of this.
//
// SEC (mobile-backlog 2026-07-12): `ConsumerStatefulWidget` (rather than the
// original `StatelessWidget`) so it can acquire the app-wide
// [ScreenProtectionManager] for its lifetime — this screen's recap card
// renders the INDEPENDENT master's address (street/buildingNo/city/
// locationNote, via `BookingSummaryCards.fromMaster` → `formatStreetCityLine`
// — for a solo master that may be a HOME address). Converges this screen (and
// `BookingConfirmScreen`) on the SAME acquire-in-`initState` pattern already
// used by the salon flow's equivalents (`salon_booking_confirm_screen.dart`,
// `salon_booking_success_screen.dart`).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';

import '../domain/booking_success_args.dart';
import 'widgets/booking_success_scaffold.dart';
import 'widgets/booking_summary_cards.dart';

/// Booking flow Step 3b — the post-submit celebration screen.
class BookingSuccessScreen extends ConsumerStatefulWidget {
  const BookingSuccessScreen({super.key, required this.args});

  final BookingSuccessArgs args;

  @override
  ConsumerState<BookingSuccessScreen> createState() =>
      _BookingSuccessScreenState();
}

class _BookingSuccessScreenState extends ConsumerState<BookingSuccessScreen> {
  // Captured in initState so dispose() never touches `ref` (Riverpod 3.x
  // throws on a post-dispose `ref` read).
  late final ScreenProtectionManager _screenProtection;

  @override
  void initState() {
    super.initState();
    // See file header SEC note — mirrors the INTENTIONAL PRODUCT DECISION
    // already applied to `PublicMasterProfileScreen` / the salon success
    // screen. Do not remove in a future audit pass.
    _screenProtection = ref.read(screenProtectionProvider)..acquire();
  }

  @override
  void dispose() {
    _screenProtection.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BookingSuccessScaffold(
      title: l10n.bookingSuccessTitle,
      subline: l10n.bookingSuccessSubline,
      homeButtonKey: const Key('booking-success-home-cta'),
      onHome: () => context.go(RouteNames.clientHome),
      belowRecap: const _CalendarLink(),
      recapCards: <Widget>[
        BookingSummaryCards.fromMaster(
          master: widget.args.master,
          service: widget.args.service,
          start: widget.args.start,
          showMasterCard: false,
          dense: true,
          // See NeumorphicCard.showBorder's doc: this card's fill
          // (BrandColors.base) exactly matches the success Scaffold's
          // backgroundColor, so the extruded shadow alone doesn't read as a
          // distinct shape — opt into the hairline stroke.
          showBorder: true,
          // See BookingSummaryCards.compactText's doc: a further notch smaller
          // than `dense` alone, so the whole success page fits more comfortably
          // within the viewport.
          compactText: true,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Calendar link (no-op — see file header DEVIATION note)
// ---------------------------------------------------------------------------

/// The tertiary onward action — a calm, borderless "Додати в календар" text
/// link. See file header: real OS-calendar wiring is deferred (no
/// `add_2_calendar` dependency added in this pass).
class _CalendarLink extends StatefulWidget {
  const _CalendarLink();

  @override
  State<_CalendarLink> createState() => _CalendarLinkState();
}

class _CalendarLinkState extends State<_CalendarLink> {
  bool _pressed = false;

  void _onTap() {
    // TODO(phase-14.x): wire a real OS calendar event (title = service name,
    // location = master address, window = booked start→end) via
    // `add_2_calendar` or an ICS export once that dependency is reviewed and
    // added to pubspec.yaml. Intentionally a no-op for this pass — see the
    // file header DEVIATION note.
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: l10n.bookingAddCalendarSemantics,
      child: GestureDetector(
        key: const Key('booking-success-add-calendar'),
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          _onTap();
        },
        behavior: HitTestBehavior.opaque,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 120),
          opacity: _pressed ? 0.55 : 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: VelvetSpacing.sm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.calendar_today_rounded,
                  size: 18,
                  color: BrandColors.accentDeep,
                ),
                const SizedBox(width: VelvetSpacing.sm),
                Text(
                  l10n.bookingSuccessAddCalendarCta,
                  style: VelvetText.bookCalendarCta,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

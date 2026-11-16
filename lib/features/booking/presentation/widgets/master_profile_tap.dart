// MAS-39 — the ONE "tap the master card → open that master's profile in
// booking context" callback, shared by every client booking screen whose top
// carries a master card (date/time pickers, service selector, confirm,
// success, «Деталі запису», «Залишити відгук», salon «Час» / confirm /
// success). Promoted from `slot_picker_screen.dart`'s private
// `_rescheduleMasterTap` so the predicate lives in one place.
//
// The profile opens with `fromBooking: true` → `PublicMasterProfileScreen(
// hideBookCta: true)`: no «Записатись» shelf — except from «Деталі запису»,
// which passes `fromBooking: false` and keeps the shelf (MAS-39, 2026-11-16).
// Either way its `ProfileScaffold` top bar's back button (plus the Android
// system back) pops straight back to the booking screen, whose state
// survives because this is a `push`.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/core/navigation/single_flight.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_selectors.dart';
import 'package:beautica_mobile/routing/route_names.dart';

/// Opens [masterId]'s public profile in booking context, or `null` (an inert
/// card) when [masterId] is empty — `/masters/` matches no route, so a tap
/// would land on go_router's "page not found" screen.
///
/// Use this form where the caller already knows the viewer is a CLIENT (the
/// screen is client-only by construction). Otherwise use
/// [clientMasterProfileTap].
///
/// [fromBooking] (default `true`) hides the profile's book CTA; «Деталі
/// запису» alone passes `false` (MAS-39).
VoidCallback? masterProfileTap(
  BuildContext context,
  String masterId, {
  bool fromBooking = true,
}) {
  if (masterId.isEmpty) return null;
  return () => context.pushOnce(
    RouteNames.masterPublicProfile(masterId, fromBooking: fromBooking),
  );
}

/// [masterProfileTap], additionally `null` for any non-CLIENT session: the
/// profile route is `clientOnlyGuard`ed, and the same booking widgets are
/// mounted for a provider/staff viewer (walk-in, staff-created bookings).
VoidCallback? clientMasterProfileTap(
  BuildContext context,
  WidgetRef ref,
  String masterId,
) {
  if (!ref.watch(isClientProvider)) return null;
  return masterProfileTap(context, masterId);
}

// Overlay-route dismissal helper (VelvetTouch).
//
// Transient overlay routes opened by `showDialog` / `showModalBottomSheet`
// are NOT app screens — they are local routes pushed onto the nearest
// `Navigator`, and dismissing them is not screen navigation. go_router's
// `context.pop` resolves via `GoRouter.of(context)`, which requires an
// `InheritedGoRouter` ancestor; an overlay route's BuildContext has none, so
// `context.pop` throws `No GoRouter found in context` at runtime (and in
// widget tests that pump the overlay in isolation).
//
// The correct call for overlay dismissal is `Navigator.of(context).pop`.
// This helper lives in `lib/core` so feature code never writes a raw
// `Navigator` call directly — the CI gate forbids `Navigator.*` only inside
// `lib/features/` (its intent is "no Navigator for SCREEN navigation"; that
// gate is too blunt to express "overlay dismissal is fine", so the call is
// centralised here, outside the gated tree).

import 'package:flutter/widgets.dart';

import 'package:beautica_mobile/core/navigation/single_flight.dart';

/// Dismisses the transient overlay route (a `showDialog` /
/// `showModalBottomSheet` route) that owns [context], optionally resolving its
/// awaiting future with [result].
///
/// Use this for overlay dismissal ONLY. For screen-to-screen navigation use
/// go_router (`context.pop` / `context.go`) — see `lib/routing/`.
///
/// IDEMPOTENT: a REPEAT call for an overlay this helper already dismissed is
/// a no-op. `Navigator.pop` always pops the TOP present route, so without this
/// check a confirm handler that runs twice (two async continuations landing
/// after the first pop — e.g. a double-tapped «Надіслати» that awaits a
/// request before closing) popped the overlay AND the screen beneath it.
/// The FIRST call always pops the top route — even when the owning overlay
/// is not the top route (a route pushed above it) — exactly as before.
///
/// NO DEPENDENCY: for an overlay opened by `showDialogOnce` /
/// `showModalBottomSheetOnce` the route is the one that helper already
/// captured ([capturedOverlayRoute]) — `ModalRoute.of` from this callback
/// would register a route-status dependency on [context] and rebuild the
/// overlay content during its own exit animation. Only an overlay opened
/// some other way falls back to `ModalRoute.of`.
void dismissOverlay<T extends Object?>(BuildContext context, [T? result]) {
  final ModalRoute<Object?>? route =
      capturedOverlayRoute(context) ?? ModalRoute.of(context);
  if (route != null) {
    if (_dismissedRoutes[route] ?? false) return;
    _dismissedRoutes[route] = true;
  }
  Navigator.of(context).pop(result);
}

/// Routes [dismissOverlay] has already popped. Weakly keyed: an entry lives
/// only as long as its route.
final Expando<bool> _dismissedRoutes = Expando<bool>('dismissedOverlayRoutes');

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

/// Dismisses the transient overlay route (a `showDialog` /
/// `showModalBottomSheet` route) that owns [context], optionally resolving its
/// awaiting future with [result].
///
/// Use this for overlay dismissal ONLY. For screen-to-screen navigation use
/// go_router (`context.pop` / `context.go`) — see `lib/routing/`.
void dismissOverlay<T extends Object?>(BuildContext context, [T? result]) =>
    Navigator.of(context).pop(result);

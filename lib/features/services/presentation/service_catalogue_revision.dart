// 2026-09-13 audit (M7, mobile-perf LOW) — a monotonic revision counter for
// "the service catalogue changed".
//
// WHY THIS EXISTS
// ---------------
// `SalonStaffProfileScreen`'s «Послуги» card awaits its `context.push` and
// then invalidates `salonStaffMemberProfileProvider(salonId, memberId)`
// UNCONDITIONALLY. That provider's `build` re-runs
// `getMasterServices(masterId)` (`salon_staff_member_notifier.dart:75-79`), so
// an operator who merely LOOKED at a master's catalogue and came straight back
// paid a full round trip for a screen whose data cannot have changed.
//
// WHY A COUNTER RATHER THAN A POP RESULT
// --------------------------------------
// The obvious shape — have the subtree pop `true` — does not survive contact
// with how the subtree actually exits. `ServicesListScreen` is left through
// the framework's own `AppBar` back button (and the iOS swipe-back gesture
// installed by the theme's `CupertinoPageTransitionsBuilder`), both of which
// call `Navigator.maybePop(context)` with NO result. Making them carry one
// means an explicit `leading:` plus `PopScope(canPop: false)`, and
// `canPop: false` DISABLES the swipe-back gesture — trading a spurious fetch
// for a real interaction regression on every one of that screen's mounts.
//
// So the signal is read from where a mutation actually happens instead: the
// ONE fan-out point every create / edit / delete already calls,
// [invalidateMasterServiceCatalogues]. The caller samples the counter before
// pushing and compares after; equal means nothing in the subtree mutated
// anything and the invalidate is skipped.
//
// DELIBERATE OVER-APPROXIMATION: `invalidateMasterServiceCatalogues` is also
// called from two error-state «retry» handlers, so a retry inside the subtree
// bumps the counter and the caller refreshes. That is the SAME single fetch
// that happens today on every single return, restricted to a path the user had
// to visibly fail into — over-approximating in the safe direction, and
// stamping it at the one fan-out point rather than at five mutation sites is
// what keeps it from drifting.
//
// Root-scoped `keepAlive`: a mutation made inside a salon-scoped
// `ProviderScope` must be visible to the staff-profile screen OUTSIDE that
// scope. This provider is not overridden anywhere, so both resolve the same
// root instance.

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'service_catalogue_revision.g.dart';

/// Increments once per service-catalogue fan-out. The VALUE is meaningless;
/// only "did it change across this push?" is.
@Riverpod(keepAlive: true)
class ServiceCatalogueRevision extends _$ServiceCatalogueRevision {
  @override
  int build() => 0;

  void bump() => state = state + 1;
}

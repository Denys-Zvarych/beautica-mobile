import 'route_names.dart';

/// Locations a deferred navigation (a cold-start push tap or App Link) must
/// wait out: the splash and the pre-session screens. Once the router leaves
/// them for a settled, signed-in surface the deferred target may open.
///
/// Promoted (2026-11-14) from `push_tap_dispatcher.dart`'s private
/// `_holdsPushTap` so the push-tap dispatcher and the App Link replay
/// (`app_link_replay.dart`) share ONE hold list — a screen added here holds
/// both.
bool holdsDeferredNavigation(String location) =>
    location == RouteNames.splash ||
    location == RouteNames.login ||
    location == RouteNames.verification ||
    location == RouteNames.register ||
    location.startsWith('${RouteNames.register}/');

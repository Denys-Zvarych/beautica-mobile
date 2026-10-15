// Single-flight navigation: one tap opens one route.
//
// THE BUG CLASS
// -------------
// A tap handler that pushes a route (or opens a sheet/dialog) is disabled
// only by a REBUILD: `onPressed: busy ? null : …`, `loading: true`, or the
// new route covering the caller. Every one of those lands a frame later.
// Taps that arrive inside that frame — a fast double-tap, or taps queued while
// the UI thread was stalled — all reach the handler, and each one pushes its
// own copy. On the booking flow that meant several confirm screens stacked,
// each minting its own idempotency key: a duplicate booking after "back".
//
// THE FIX
// -------
// [runOnce] takes a lock keyed by the CALLING ELEMENT (the `BuildContext`
// you pass), checked and set synchronously before the action runs. A second
// call from the same element while the first is still open is dropped and
// resolves to `null`, exactly as if the user had dismissed the route.
//
// Why per-Element and not per-Navigator: the pushed screen must still be able
// to push its own routes; only the element that opened it is locked. The lock
// lives in an [Expando], so it dies with the element (no dispose hook, works
// from StatelessWidgets, nothing to leak).
//
// LOCK RELEASE
// ------------
// 1. Normally: when the action's future completes (route popped, sheet
//    dismissed) — released BEFORE the caller's `await` resumes, so a caller
//    can chain a second guarded call on the same context.
// 2. Stack replacement: go_router's `go` replaces the match list WITHOUT
//    completing the futures of the imperative pushes it drops, and a caller
//    that survives the `go` (same page key, or a shell branch page) would
//    hold the lock forever. A flight that opens a route therefore carries a
//    presence probe for THAT route — its go_router match ([pushOnce],
//    identified by the completer go_router created for that very push, and
//    claimed on the first frame after it lands), or the overlay
//    route itself ([showDialogOnce] / [showModalBottomSheetOnce], captured
//    from inside the route). A later call that finds the route GONE treats
//    the lock as stale and releases it. (Flutter itself completes a pageless
//    route's future when it is removed with the page beneath it — pinned by
//    single_flight_test.dart — so for overlays the probe mainly serves the
//    "dismiss, then open the next one in the same handler" case.)
//    A route that has still not landed by the flight's [_landingDeadline] (a
//    push dropped or superseded before it landed) marks its flight stale too:
//    nothing would ever report it gone, and its future may never complete.
//    The deadline is checked LAZILY — only when the next call reads
//    [_Flight.isStale] — so an unsettled flight requests no frames at all.
//
//    Deliberately NOT inferred from the caller's own route ("covered, then
//    current again"): reading `ModalRoute.of(callerContext)` registers a
//    route-status dependency on the CALLER, rebuilding it on every push/pop
//    above it — the exact cost the portfolio rail's perf pins forbid.
// 3. Unmounted caller: [runOnce] on an unmounted context is a no-op returning
//    `null`; a flight whose element unmounts is garbage with the element.
//
// RE-ENTRANCY
// -----------
// The action runs in a [Zone] that remembers which flights it is inside, so a
// guarded helper called FROM a guarded action on the same element (e.g. a
// shared `show…Dialog` that guards itself, called from a guarded handler)
// runs instead of being dropped. Taps are delivered from outside that zone,
// so they are still dropped.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';

final Expando<_Flight> _flights = Expando<_Flight>('singleFlight');

/// Zone key under which the chain of flights an action is running inside is
/// stored (see RE-ENTRANCY above).
const Symbol _zoneKey = #beauticaSingleFlight;

/// How long a flight waits for its route to land. A route that has not
/// landed by then (a push that was dropped, a sheet that never opened) marks
/// its flight STALE, so the next tap proceeds instead of the element staying
/// locked for its whole lifetime behind a future that may never complete.
/// A normal route lands within a frame or two.
const Duration _landingDeadline = Duration(seconds: 2);

/// Wall-clock source for the landing deadline. `package:clock` (which
/// fakeAsync drives) is only a transitive dependency here, so this is a plain
/// `DateTime.now` seam that tests replace to step past the deadline without
/// pumping frames or waiting in real time.
@visibleForTesting
DateTime Function() singleFlightNow = DateTime.now; // instant-ok: absolute-instant deadline for a stuck navigation lock, never a calendar day

final class _Flight {
  _Flight({required this.parent, this.present})
    : deadline = present == null
          ? null
          : singleFlightNow().add(_landingDeadline);

  /// The enclosing flight in the zone chain (re-entrancy bookkeeping).
  final _Flight? parent;

  /// Optional presence probe for the route the flight opens: `null` = not
  /// known yet (not landed / not identified), `true` = the route is up,
  /// `false` = it is GONE. Null for a generic [runOnce] action, whose lock is
  /// released only by its future.
  final bool? Function()? present;

  /// When an unlanded route stops holding the lock. Null for a probe-less
  /// [runOnce] flight.
  final DateTime? deadline;

  bool released = false;

  /// True when the opened route is known to be gone although the action's
  /// future has not completed yet — a stack replacement that never completes
  /// it, or a pop whose completion is still queued as a microtask while the
  /// same handler opens the next route synchronously — or the route has
  /// still not landed past its [deadline] (nothing would ever report it
  /// gone). Read only by the next call, so the deadline costs nothing.
  bool get isStale {
    final bool? Function()? probe = present;
    if (probe == null) return false;
    final bool? up = probe();
    if (up != null) return !up;
    final DateTime? due = deadline;
    return due != null && singleFlightNow().isAfter(due);
  }
}

bool _insideFlight(_Flight flight) {
  for (
    _Flight? f = Zone.current[_zoneKey] as _Flight?;
    f != null;
    f = f.parent
  ) {
    if (identical(f, flight)) return true;
  }
  return false;
}

/// Reads the flight's probe ONCE after the next frame, so a push claims its
/// match while it is still the newest one. Requests no frame: the route's own
/// transition already does, and a route that never lands is caught lazily by
/// [_Flight.isStale]'s deadline instead of by polling.
void _claimAfterFrame(BuildContext context, _Flight flight) {
  // A generic [runOnce] flight has no probe: only its future releases it.
  final bool? Function()? probe = flight.present;
  if (probe == null) return;
  SchedulerBinding.instance.addPostFrameCallback((_) {
    if (flight.released || !context.mounted) return;
    probe();
  });
}

/// Runs [action] unless an earlier [runOnce] on the same [context] (the same
/// Element) is still in flight; a dropped call resolves to `null` without
/// running [action].
///
/// The lock is taken synchronously, before [action] is invoked, so taps
/// delivered in the same frame cannot both get through. It is released when
/// [action]'s future completes (see the file header for the stale-lock
/// rules). Returns `null` immediately when [context] is no longer mounted.
///
/// [present] is an optional probe for the route [action] opens: `null` while
/// it is not known yet (not pushed / not landed), `true` while it is up,
/// `false` once it is gone — a `false` makes a lock still held stale.
/// Without a probe, a generic [runOnce] lock is released only by [action]
/// completing — so wrap only actions whose future does complete (a dialog,
/// a request).
Future<T?> runOnce<T>(
  BuildContext context,
  Future<T?> Function() action, {
  bool? Function()? present,
}) => _runOnce<T>(context, (_Flight _) => action(), present: present);

Future<T?> _runOnce<T>(
  BuildContext context,
  Future<T?> Function(_Flight flight) action, {
  bool? Function()? present,
}) async {
  if (!context.mounted) return null;
  final _Flight? held = _flights[context];
  if (held != null) {
    if (_insideFlight(held)) return action(held);
    if (!held.isStale) return null;
    held.released = true;
    _flights[context] = null;
  }
  final _Flight flight = _Flight(
    parent: Zone.current[_zoneKey] as _Flight?,
    present: present,
  );
  _flights[context] = flight;
  try {
    final Future<T?> future = runZoned(
      () => action(flight),
      zoneValues: <Object?, Object?>{_zoneKey: flight},
    );
    _claimAfterFrame(context, flight);
    return await future;
  } finally {
    flight.released = true;
    if (identical(_flights[context], flight)) _flights[context] = null;
  }
}

/// Whether a [runOnce] flight is currently holding [context]'s lock (a stale
/// lock — see LOCK RELEASE — reads as not open). For callers that must skip
/// side effects they run BEFORE a guarded push (a warm-up, an invalidate)
/// when the push itself would be dropped.
bool isFlightOpen(BuildContext context) {
  final _Flight? f = _flights[context];
  return f != null && !f.released && !f.isStale;
}

/// Collects the completers of every imperative (pushed) match in [list],
/// descending into shell matches.
Set<Completer<Object?>> _imperativeCompleters(RouteMatchList list) {
  final Set<Completer<Object?>> out = Set<Completer<Object?>>.identity();
  void walk(List<RouteMatchBase> matches) {
    for (final RouteMatchBase m in matches) {
      if (m is ImperativeRouteMatch) out.add(m.completer);
      if (m is ShellRouteMatch) walk(m.matches);
    }
  }

  walk(list.matches);
  return out;
}

/// Single-flight go_router navigation. Drop-in replacements for
/// `context.push` / `context.pushNamed`: same arguments, same result, but a
/// second call from the same element while the first route is open is
/// dropped and resolves to `null`.
extension SingleFlightNavigation on BuildContext {
  /// Single-flight `context.push`.
  Future<T?> pushOnce<T extends Object?>(String location, {Object? extra}) {
    final GoRouter router = GoRouter.of(this);
    final _PushProbe probe = _PushProbe(router, location: location);
    return _runOnce<T>(
      this,
      (_Flight _) => probe.track(router.push<T>(location, extra: extra)),
      present: probe.present,
    );
  }

  /// Single-flight `context.pushNamed`.
  Future<T?> pushNamedOnce<T extends Object?>(
    String name, {
    Map<String, String> pathParameters = const <String, String>{},
    Map<String, dynamic> queryParameters = const <String, dynamic>{},
    Object? extra,
  }) {
    final GoRouter router = GoRouter.of(this);
    final _PushProbe probe = _PushProbe(router, name: name);
    return _runOnce<T>(
      this,
      (_Flight _) => probe.track(
        router.pushNamed<T>(
          name,
          pathParameters: pathParameters,
          queryParameters: queryParameters,
          extra: extra,
        ),
      ),
      present: probe.present,
    );
  }
}

/// Completers already claimed by some push's probe — so two same-frame
/// pushes of the SAME location from different elements, identified by the
/// location fallback, claim one match each.
final Expando<bool> _claimed = Expando<bool>('singleFlightClaimed');

/// Path as go_router canonicalises it for matching: no trailing slash
/// (except the root).
String _canonicalPath(String path) => path.length > 1 && path.endsWith('/')
    ? path.substring(0, path.length - 1)
    : path;

/// The go_router presence probe for ONE push: `null` until the push has
/// landed, then whether its match is still in the configuration.
///
/// The match is claimed only if it is THIS push's: identified by the
/// completer go_router creates for the push (read from the information
/// provider synchronously, right after the push call — exact, and it survives
/// a redirect), or — should that not be readable — by a new match for the
/// pushed [location] / [name]. Claiming merely "the first new match" could
/// adopt a concurrent push from another element in the same frame; that
/// route popping would then mark this lock stale while this route is still
/// up, letting a duplicate push through.
final class _PushProbe {
  _PushProbe(this._router, {this.location, this.name})
    : _before = _imperativeCompleters(
        _router.routerDelegate.currentConfiguration,
      );

  final GoRouter _router;
  final String? location;
  final String? name;

  /// Imperative matches that existed BEFORE the push.
  final Set<Completer<Object?>> _before;

  /// The completer go_router created for this push, when readable.
  Object? _pushed;

  /// The claimed match's completer, once the push has landed.
  Completer<Object?>? _mine;

  /// Records this push's identity. Must be called with the push's future
  /// IMMEDIATELY (synchronously) after the push call, before any other push.
  Future<T?> track<T>(Future<T?> pushed) {
    final Object? state = _router.routeInformationProvider.value.state;
    if (state is RouteInformationState<Object?> &&
        state.type == NavigatingType.push) {
      _pushed = state.completer;
    } else if (kDebugMode) {
      // The exact identification path is gone (a go_router upgrade changed
      // what a push leaves in the information provider): the probe falls
      // back to matching by location / name. Loud in development only.
      debugPrint(
        'single_flight: push completer not readable '
        '(state: ${state.runtimeType}); falling back to location matching',
      );
    }
    return pushed;
  }

  bool _isMine(ImperativeRouteMatch m) {
    final Object? pushed = _pushed;
    if (pushed != null) return identical(m.completer, pushed);
    if (_before.contains(m.completer) || _claimed[m.completer] == true) {
      return false;
    }
    final String? n = name;
    if (n != null) return m.route.name == n;
    final String? loc = location;
    if (loc == null) return false;
    return _canonicalPath(m.matches.uri.path) ==
        _canonicalPath(Uri.parse(loc).path);
  }

  bool? present() {
    final RouteMatchList config = _router.routerDelegate.currentConfiguration;
    Completer<Object?>? mine = _mine;
    if (mine == null) {
      final ImperativeRouteMatch? found = _firstImperative(
        config.matches,
        _isMine,
      );
      if (found == null) return null;
      mine = found.completer;
      _claimed[mine] = true;
      _mine = mine;
    }
    return _imperativeCompleters(config).contains(mine);
  }
}

/// First imperative match in [matches] (descending into shell matches) that
/// satisfies [test].
ImperativeRouteMatch? _firstImperative(
  List<RouteMatchBase> matches,
  bool Function(ImperativeRouteMatch m) test,
) {
  for (final RouteMatchBase m in matches) {
    if (m is ImperativeRouteMatch && test(m)) return m;
    if (m is ShellRouteMatch) {
      final ImperativeRouteMatch? inner = _firstImperative(m.matches, test);
      if (inner != null) return inner;
    }
  }
  return null;
}

/// Single-flight [showDialog]: same parameters; a second call from the same
/// [context] while the dialog is open is dropped and resolves to `null`.
Future<T?> showDialogOnce<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useSafeArea = true,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
}) {
  final _OverlayProbe probe = _OverlayProbe();
  return _runOnce<T>(
    context,
    present: probe.present,
    (_Flight _) => showDialog<T>(
      context: context,
      builder: probe.wrap(builder),
      barrierDismissible: barrierDismissible,
      barrierColor: barrierColor,
      barrierLabel: barrierLabel,
      useSafeArea: useSafeArea,
      useRootNavigator: useRootNavigator,
      routeSettings: routeSettings,
    ),
  );
}

/// Single-flight [showModalBottomSheet]: same parameters; a second call from
/// the same [context] while the sheet is open is dropped and resolves to
/// `null`.
Future<T?> showModalBottomSheetOnce<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  Color? barrierColor,
  String? barrierLabel,
  double? elevation,
  ShapeBorder? shape,
  Clip? clipBehavior,
  BoxConstraints? constraints,
  bool isScrollControlled = false,
  bool useRootNavigator = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool? showDragHandle,
  bool useSafeArea = false,
  RouteSettings? routeSettings,
}) {
  final _OverlayProbe probe = _OverlayProbe();
  return _runOnce<T>(
    context,
    present: probe.present,
    (_Flight _) => showModalBottomSheet<T>(
      context: context,
      builder: probe.wrap(builder),
      backgroundColor: backgroundColor,
      barrierColor: barrierColor,
      barrierLabel: barrierLabel,
      elevation: elevation,
      shape: shape,
      clipBehavior: clipBehavior,
      constraints: constraints,
      isScrollControlled: isScrollControlled,
      useRootNavigator: useRootNavigator,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      showDragHandle: showDragHandle,
      useSafeArea: useSafeArea,
      routeSettings: routeSettings,
    ),
  );
}

/// Presence probe for a pageless overlay route (dialog / sheet), captured
/// from INSIDE the route by [_OverlayRouteTap] — the caller never reads
/// `ModalRoute.of` itself (that would register a route-status dependency on
/// the caller and rebuild it on every push/pop above it). Lets a handler that
/// dismisses the overlay and SYNCHRONOUSLY opens the next one on the same
/// context through: the popped route is inactive at once, while its future
/// only completes in a later microtask.
final class _OverlayProbe {
  ModalRoute<Object?>? route;

  bool? present() => route?.isActive;

  WidgetBuilder wrap(WidgetBuilder builder) => (BuildContext context) {
    // Remember the probe under the BUILDER's context too: overlay handlers
    // usually dismiss with that context, which sits ABOVE [_OverlayRouteTap].
    _overlayProbes[context] = this;
    return _OverlayRouteTap(probe: this, child: builder(context));
  };
}

/// Builder context of a [showDialogOnce] / [showModalBottomSheetOnce] route →
/// its probe. Dies with the element.
final Expando<_OverlayProbe> _overlayProbes = Expando<_OverlayProbe>(
  'singleFlightOverlayProbe',
);

/// The overlay route a [showDialogOnce] / [showModalBottomSheetOnce] opened
/// and [context] lives in (its builder context or anything below it), or
/// null when [context] is not inside such a route.
///
/// Unlike `ModalRoute.of`, this registers NO dependency on [context]: it reads
/// the route captured once from inside the overlay, so a dismissal helper
/// calling it from a callback does not make the overlay content rebuild on
/// every route-status change (e.g. throughout its exit animation).
ModalRoute<Object?>? capturedOverlayRoute(BuildContext context) {
  final _OverlayProbe? probe =
      _overlayProbes[context] ??
      context.findAncestorStateOfType<_OverlayRouteTapState>()?.widget.probe;
  return probe?.route;
}

/// Render-free wrapper that records the overlay route it is mounted in. Its
/// own route-status dependency rebuilds only THIS element, which returns the
/// same [child] instance — the overlay content below is not rebuilt.
class _OverlayRouteTap extends StatefulWidget {
  const _OverlayRouteTap({required this.probe, required this.child});

  final _OverlayProbe probe;
  final Widget child;

  @override
  State<_OverlayRouteTap> createState() => _OverlayRouteTapState();
}

class _OverlayRouteTapState extends State<_OverlayRouteTap> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.probe.route ??= ModalRoute.of(context);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

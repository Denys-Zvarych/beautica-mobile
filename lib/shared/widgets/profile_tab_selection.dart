import 'package:flutter/material.dart';

/// Phase 351 (D15) — the one tab-selection mechanism shared by all three
/// master profile screens ([PublicMasterProfileScreen], [MasterProfileScreen],
/// [SalonMasterProfileScreen]).
///
/// The «Про майстра» / «Послуги» / «Відгуки» [ProfileTabBar] is the only way
/// to switch tabs — mirroring the public salon profile's own `switch (tab)` +
/// `KeyedSubtree` mechanism (D2), just factored out so three screens share
/// ONE implementation instead of three hand-copied `int _tab` fields.
///
/// User decision 2026-09-26: the stat cards («Рейтинг» / «Послуги» /
/// «Відгуки») are display-only and never call [selectProfileTab] — the
/// mechanism this mixin previously offered them (a card tap switching tabs
/// in place, plus a reveal-scroll heuristic when the bar was below the fold)
/// is gone. See the phase-351 doc's Decisions for the superseded wording.
///
/// Usage:
/// ```dart
/// class _MyScreenState extends State<MyScreen> with ProfileTabSelection<MyScreen> {
///   @override
///   Widget build(BuildContext context) {
///     return Column(
///       children: [
///         // Isolates the tab switch's rebuild to just this region — see
///         // [ProfileTabSection].
///         ProfileTabSection(
///           notifier: profileTabNotifier,
///           builder: (context, tab) => Column(
///             children: [
///               ProfileTabBar(
///                 selected: tab,
///                 onSelect: selectProfileTab,
///                 ...
///               ),
///               ...tab body switch(tab)...
///             ],
///           ),
///         ),
///       ],
///     );
///   }
///
///   @override
///   void dispose() {
///     disposeProfileTabSelection();
///     super.dispose();
///   }
/// }
/// ```
mixin ProfileTabSelection<T extends StatefulWidget> on State<T> {
  /// The active tab index, as a [ValueNotifier] rather than a plain `State`
  /// field (mobile-perf LOW, Phase 351 audit-fix cycle 1) — [selectProfileTab]
  /// used to call [setState] on the WHOLE screen `State`, rebuilding the
  /// identity card and stat-card row on every tab switch even though neither
  /// depends on [profileTab]. Wrapping only the tab-bar + tab-body region in a
  /// `ValueListenableBuilder` over this notifier (via [ProfileTabSection])
  /// confines the rebuild to that region.
  ///
  /// `0` (`«Про майстра»`, D8) on every fresh open — no route param seeds it.
  /// Survives an in-screen push/pop because the `State` this mixin is applied
  /// to is kept, mirroring the public salon profile's identical `_tab` field.
  final ValueNotifier<int> profileTabNotifier = ValueNotifier<int>(0);

  /// The active tab index. Reads [profileTabNotifier] — kept as a plain
  /// getter (not a rebuild trigger) for call sites that only need the current
  /// value once, e.g. a one-off non-UI read.
  int get profileTab => profileTabNotifier.value;

  /// Selects tab [i]. Updates [profileTabNotifier] directly — never
  /// `setState` — so only [ProfileTabSection]'s `ValueListenableBuilder`
  /// rebuilds; the ancestor screen `State` is never marked dirty by a tab
  /// switch.
  void selectProfileTab(int i) {
    profileTabNotifier.value = i;
  }

  /// Disposes [profileTabNotifier]. Not wired into `dispose()` automatically
  /// (a mixin `dispose()` override would silently reorder every composing
  /// `State`'s existing `dispose()` chain, e.g. relative to
  /// `SingleTickerProviderStateMixin`'s own) — every `State` applying this
  /// mixin must call this explicitly from its own `dispose()`, mirroring how
  /// each one already explicitly releases its `ScreenProtectionManager` and
  /// disposes its `AnimationController`/`CurvedAnimation`s.
  void disposeProfileTabSelection() {
    profileTabNotifier.dispose();
  }
}

/// Isolates a tab switch's rebuild to just the tab-bar + tab-body region
/// (mobile-perf LOW, Phase 351 audit-fix cycle 1) — wraps a
/// [ValueListenableBuilder] around [ProfileTabSelection.profileTabNotifier]
/// so [ProfileTabSelection.selectProfileTab] rebuilds ONLY [builder]'s
/// subtree, never the identity card / stat-card row (or any other sibling)
/// above it. Mirrors `master_reviews_body.dart`'s `_SortableReviewList` — the
/// SAME "isolate the toggled section" pattern, just driven by an external
/// [ValueNotifier] instead of local `State`.
///
/// Every [ProfileTabSelection] screen wraps its tab bar (`ProfileTabBar`) and
/// its tab body (the `switch (tab) { ... }`) in exactly one of these —
/// REUSE-FIRST: one shared isolation widget for all three master profile
/// screens, not three hand-copied `ValueListenableBuilder`s.
class ProfileTabSection extends StatelessWidget {
  const ProfileTabSection({
    super.key,
    required this.notifier,
    required this.builder,
  });

  /// [ProfileTabSelection.profileTabNotifier] of the owning screen `State`.
  final ValueNotifier<int> notifier;

  /// Builds the tab-bar + tab-body region for the current tab index. Called
  /// again only when [notifier]'s value changes — never on an unrelated
  /// ancestor rebuild.
  final Widget Function(BuildContext context, int tab) builder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: notifier,
      builder: (BuildContext context, int tab, Widget? _) =>
          builder(context, tab),
    );
  }
}

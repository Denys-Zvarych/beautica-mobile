import 'package:flutter/material.dart';

/// Phase 351 (D15) — the one card → tab mechanism shared by all three master
/// profile screens ([PublicMasterProfileScreen], [MasterProfileScreen],
/// [SalonMasterProfileScreen]).
///
/// A stat card's `onTap` calls [selectProfileTab] instead of pushing a route:
/// tapping «Рейтинг»/«Відгуки» selects the «Відгуки» tab, tapping «Послуги»
/// selects the «Послуги» tab, all in place — no `IndexedStack`/`TabController`,
/// mirroring the public salon profile's own `switch (tab)` + `KeyedSubtree`
/// mechanism (D2), just factored out so three screens share ONE
/// implementation instead of three hand-copied `int _tab` fields.
///
/// Usage:
/// ```dart
/// class _MyScreenState extends State<MyScreen> with ProfileTabSelection<MyScreen> {
///   @override
///   Widget build(BuildContext context) {
///     return Column(
///       children: [
///         StatTile(
///           onTap: () => selectProfileTab(MasterProfileTab.reviews.index,
///               revealTabBar: true),
///           ...
///         ),
///         // Isolates the tab switch's rebuild to just this region — see
///         // [ProfileTabSection].
///         ProfileTabSection(
///           notifier: profileTabNotifier,
///           builder: (context, tab) => Column(
///             children: [
///               KeyedSubtree(
///                 key: profileTabBarAnchor,
///                 child: ProfileTabBar(
///                   selected: tab,
///                   onSelect: selectProfileTab,
///                   ...
///                 ),
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
  /// confines the rebuild to that region — mirroring `master_reviews_body
  /// .dart`'s `_SortableReviewList`, which isolates its own sort-toggle
  /// rebuild the same way, just with an external notifier instead of local
  /// `State` since a tap can originate from a sibling stat card outside the
  /// isolated subtree.
  ///
  /// `0` (`«Про майстра»`, D8) on every fresh open — no route param seeds it.
  /// Survives an in-screen push/pop because the `State` this mixin is applied
  /// to is kept, mirroring the public salon profile's identical `_tab` field.
  final ValueNotifier<int> profileTabNotifier = ValueNotifier<int>(0);

  /// The active tab index. Reads [profileTabNotifier] — kept as a plain
  /// getter (not a rebuild trigger) for call sites that only need the current
  /// value once, e.g. a one-off non-UI read.
  int get profileTab => profileTabNotifier.value;

  /// Wraps the screen's [ProfileTabBar] via `KeyedSubtree(key:
  /// profileTabBarAnchor, child: ...)` so [selectProfileTab] can scroll it
  /// into view when a card tap selects a tab that is currently off-screen.
  final GlobalKey profileTabBarAnchor = GlobalKey();

  /// Selects tab [i]. Updates [profileTabNotifier] directly — never
  /// `setState` — so only [ProfileTabSection]'s `ValueListenableBuilder`
  /// rebuilds; the ancestor screen `State` is never marked dirty by a tab
  /// switch.
  ///
  /// When [revealTabBar] is `true` (a card tap, never [ProfileTabBar]'s own
  /// `onSelect`), schedules a post-frame [Scrollable.ensureVisible] on
  /// [profileTabBarAnchor] so the tab bar scrolls into view if it currently
  /// sits below the fold. This is a no-op when the bar is already visible —
  /// [Scrollable.ensureVisible] only scrolls the minimum distance needed.
  /// Reduced-motion (`MediaQuery.disableAnimations`) jumps instantly instead
  /// of animating, matching every other motion-gated widget in this app
  /// (e.g. `core/widgets/staggered_reveal.dart`).
  void selectProfileTab(int i, {bool revealTabBar = false}) {
    profileTabNotifier.value = i;
    if (!revealTabBar) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final BuildContext? anchorContext = profileTabBarAnchor.currentContext;
      if (anchorContext == null) return;
      final bool reduceMotion =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      Scrollable.ensureVisible(
        anchorContext,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 250),
      );
    });
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
/// [ValueNotifier] instead of local `State`, because a tab switch can
/// originate from a stat card that lives OUTSIDE this subtree.
///
/// Every [ProfileTabSelection] screen wraps its tab bar (`ProfileTabBar`,
/// inside the `KeyedSubtree(key: profileTabBarAnchor, ...)`) and its tab body
/// (the `switch (tab) { ... }`) in exactly one of these — REUSE-FIRST: one
/// shared isolation widget for all three master profile screens, not three
/// hand-copied `ValueListenableBuilder`s.
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

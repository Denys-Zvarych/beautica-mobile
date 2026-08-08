// Phase 239 — «Усі збережені», the full BEAUTY WISH LIST page.
//
// Transcribed from the approved preview
// `docs/signup-designs/BeautyPassport/lib/screens/wishlist_screen.dart`.
// Preview tokens resolved to the shipped scale; Ukrainian strings routed
// through the ARB; the preview's local list + `Navigator` replaced by
// `wishlistProvider` + go_router.
//
// The overflow destination behind the passport page's «Показати всі (N)»
// button: every favourited service as a full-width [WishlistRow] — THE SAME
// WIDGET, not a second one — where there is room for the duration and the
// person glyph the compact card has to drop.
//
// ## NO `onChanged` PLUMBING — this is the whole point of the shared provider
//
// The preview passes `items` down and reports removals back up via an
// `onChanged` callback because it is a `Navigator`-based mockup with local
// state. That is deliberately NOT ported. Both surfaces `ref.watch` the same
// [wishlistProvider], so the passport page's count pill and two-card line are
// already in sync on return — with no callback, no constructor argument and no
// manual mirroring. Nothing here takes the list as a parameter.
//
// ## `ref.invalidate` IS STILL AVOIDED FOR IN-PLACE MUTATIONS
//
// Riverpod 3 PAUSES covered consumers, and THIS PAGE COVERS THE PASSPORT PAGE.
// Invalidating an autoDispose provider whose only remaining listeners are
// paused DISPOSES it, and the refetch then lands on resume rather than
// immediately — so a removal made here would appear to do nothing until the
// user navigated back. `removeService` mutates state in place instead, which is
// correct on both surfaces at once. The ERROR state's retry invalidates too,
// where the listener is on-screen and visible.
//
// Phase 241's rebook CTA (`WishlistRebookHost.rebook`, mixed in below) is a
// THIRD, deliberately different case: it invalidates only AFTER the pushed
// booking flow's `context.push` has RETURNED — by then this page is the
// active route again (not paused), so the refetch is immediate, not deferred
// to some later resume. That is what makes a rebook of a since-deactivated
// service actually drop the dead entry once the flow reports back.
//
// ## A pushed leaf, so it gets a real back control
//
// Unlike the passport page (a tab root), this page has a back affordance. The
// bar names the page's SCOPE in Ukrainian — «Усі збережені» — so the brand
// literal «Beauty wish list» is carried exactly once per screen, by the section
// header below it.
//
// ## THE BOTTOM NAV IS STILL HERE, AND THAT IS A KNOWN TENSION
//
// The phase doc lists the bottom nav as out of scope on the grounds that "the
// preview's `ClientBottomNav` does not appear on it". It DOES appear: nesting
// this route inside the passport `StatefulShellBranch` — which the same phase
// doc makes an acceptance criterion, and which is what buys swipe-back to the
// still-scrolled passport page — puts the leaf inside `ClientShell`, and the
// shell renders the nav for every route except `/bookings/:id`.
//
// Measured at 390x844: nav top 738 dp against a last-row bottom of 690 dp, so
// nothing is occluded. The live consequence is behavioural rather than visual —
// a nav tap from here switches branch with this leaf still pushed.
//
// Left as-is deliberately: suppressing it means editing shared shell chrome
// (`ClientShell`'s `onBookingDetail` gate), which is a wider blast radius than
// this phase owns and a product call about whether an overflow list should read
// as a focused surface. Recorded here rather than silently absorbed.

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/security/screen_protection.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/brand_colors.dart';
import '../../../core/theme/velvet_geometry.dart';
import '../../../core/theme/velvet_text.dart';
import '../../../core/widgets/neumorphic.dart';
import '../../../core/widgets/staggered_reveal.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/route_names.dart';
import '../../home/presentation/widgets/hub_widgets.dart';
import '../application/wishlist_notifier.dart';
import '../domain/wishlist_service.dart';
import 'widgets/wishlist_count_pill.dart';
import 'widgets/wishlist_rebook.dart';
import 'widgets/wishlist_removable.dart';
import 'widgets/wishlist_removal.dart';
import 'widgets/wishlist_row.dart';
import 'widgets/wishlist_section.dart';
import 'widgets/wishlist_states.dart';

/// The full BEAUTY WISH LIST.
class WishlistScreen extends ConsumerStatefulWidget {
  const WishlistScreen({super.key});

  @override
  ConsumerState<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends ConsumerState<WishlistScreen>
    with WishlistRemovalHost, WishlistRebookHost {
  // Riverpod 3.x rule: never call ref inside dispose(). The manager reference is
  // cached via a late-final ref.read run eagerly in initState (while ref is
  // valid); dispose() then only touches the cached field.
  late final ScreenProtectionManager _protection = ref.read(
    screenProtectionProvider,
  );

  @override
  void initState() {
    super.initState();
    // PII: every row shows master name / service name / price — acquire
    // screen protection so FLAG_SECURE / iOS app-switcher blur is active
    // while mounted. Same pattern as PassportScreen.
    _protection.acquire();
    if (kDebugMode) {
      log(
        'WishlistScreen mounted — screen protection acquired',
        name: 'feature.wishlist',
        level: 800,
      );
    }
  }

  @override
  void dispose() {
    _protection.release();
    if (kDebugMode) {
      log(
        'WishlistScreen disposed — screen protection released',
        name: 'feature.wishlist',
        level: 800,
      );
    }
    super.dispose();
  }

  void _onFindMaster() => context.go(RouteNames.clientSearch);

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<WishlistService>> async = ref.watch(wishlistProvider);

    // Explicit branch order — `isLoading` → `hasError` → value, never
    // `.when()`. `AsyncLoading(retrying: true)` still reports `hasError`, and
    // `ref.invalidate` RETAINS the previous value, so a reload keeps a good
    // list on screen and only a genuine first load shows the skeleton.
    final Widget body;
    if (async.isLoading) {
      final List<WishlistService>? retained = async.value;
      body = retained == null
          ? const WishlistLoadingState()
          : _buildList(retained);
    } else if (async.hasError) {
      body = WishlistErrorState(
        onRetry: () => ref.invalidate(wishlistProvider),
      );
    } else {
      final List<WishlistService>? items = async.value;
      body = items == null ? const WishlistLoadingState() : _buildList(items);
    }

    // No counter when there is no list to count — a failure, or a first load
    // that has not landed. «0» beside either would read as "nothing saved",
    // which is precisely what neither state is saying. A RELOAD keeps its
    // counter: the number on screen is still true.
    final List<WishlistService>? counted = async.value;
    final int? count = counted == null ? null : visibleCount(counted.length);

    return Scaffold(
      key: const Key('client-wishlist-screen'),
      backgroundColor: BrandColors.base,
      body: SafeArea(
        bottom: false,
        child: StaggeredReveal(
          builder: (BuildContext context, RevealFn reveal) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(
                VelvetSpacing.lg,
                VelvetSpacing.sm,
                VelvetSpacing.lg,
                VelvetSpacing.lg,
              ),
              children: <Widget>[
                reveal(start: 0.0, end: 0.4, child: _backBar(l10n)),
                const SizedBox(height: VelvetSpacing.lg),
                reveal(
                  start: 0.05,
                  end: 0.46,
                  child: HubSectionTitle(
                    // The same locked brand literal the passport page carries.
                    title: kBeautyWishListTitle,
                    literal: true,
                    trailing: count == null
                        ? null
                        : WishlistCountPill(count: count),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                reveal(
                  start: 0.08,
                  end: 0.5,
                  child: Text(
                    l10n.wishlistSectionLede,
                    style: VelvetText.body(),
                  ),
                ),
                const SizedBox(height: VelvetSpacing.md),
                reveal(start: 0.12, end: 0.54, child: body),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildList(List<WishlistService> items) {
    // Gated on the PROVIDER's list being empty, NOT on `visibleCount`.
    //
    // `visibleCount` subtracts the entries currently animating out, so keying
    // the empty state on it made the LAST removal skip its own exit animation
    // entirely: the moment the final row entered `removingIds` the count hit
    // zero, this branch swapped the whole list for the empty card, and the row
    // was unmounted in the same frame as the heart pop — measured gone at
    // t=112 ms against a 260 ms collapse. Worse, the empty card then sat on
    // screen for ~272 ms BEFORE `removeService` was even called, so a failed
    // wire call flipped "nothing saved" back into a populated list.
    //
    // `items` is the notifier's own state, which does not lose the entry until
    // the optimistic removal commits — so the row collapses, THEN the list
    // empties, and the empty state arrives naturally. That is exactly what
    // `wishlist_removable.dart`'s header promises.
    if (items.isEmpty) {
      return WishlistEmptyState(onFindMaster: _onFindMaster);
    }
    // `shrinkWrap` + `NeverScrollableScrollPhysics`: this list is nested
    // inside the page's own outer `ListView` (the scrollable is owned there),
    // so this inner list must size itself to its content and never scroll on
    // its own — it is a lazy row BUILDER, not a second scroll surface. The
    // outer `reveal(...)` still wraps this whole widget as one animated
    // block, unchanged from the previous `Column`.
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      itemBuilder: (BuildContext context, int index) {
        final WishlistService item = items[index];
        return WishlistRemovable(
          // Keyed on the entry so the AnimatedSize state follows the ROW it
          // belongs to as the list re-flows. Without it, removing the first
          // entry would hand its half-collapsed animation state to whatever
          // slid up into slot 0.
          key: ValueKey<String>(item.masterServiceId),
          removing: removingIds.contains(item.masterServiceId),
          child: WishlistRow(
            item: item,
            // Phase 241 — WishlistRebookHost, shared verbatim with
            // PassportScreen so the two «Записатись» CTAs can never diverge
            // (see wishlist_rebook.dart).
            onBook: () => rebook(item),
            onUnfavourite: () => requestRemoval(item.masterServiceId),
          ),
        );
      },
    );
  }

  /// Back affordance + page title.
  Widget _backBar(AppLocalizations l10n) {
    return Row(
      children: <Widget>[
        NeumorphicIconButton(
          key: const Key('wishlist_back_button'),
          icon: Icons.arrow_back_rounded,
          semanticLabel: l10n.wishlistBackSemantics,
          // `context.pop()` — the CI gate forbids the Navigator API's own
          // pop/push/of calls under lib/features, and go_router owns this
          // stack.
          onTap: () => context.pop(),
        ),
        const SizedBox(width: VelvetSpacing.md),
        Expanded(
          child: Text(l10n.wishlistPageTitle, style: VelvetText.heading20),
        ),
      ],
    );
  }
}

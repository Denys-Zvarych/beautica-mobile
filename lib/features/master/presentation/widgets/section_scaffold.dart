// Shared chrome for every pushed page in the master settings flow — the hub
// itself and each section edit page. A safe-area aware scaffold with a fixed top
// bar (leading icon + centred title), a scrollable body, and an OPTIONAL pinned
// bottom action area (the Save CTA on the edit pages; absent on the hub and the
// account page).
//
// Header geometry is byte-identical to `MasterEditScreen`'s former top bar and
// `ProfileScaffold`, so navigating profile → hub → section never shifts the
// title. When [footer] is null the body fills to the bottom; when present it
// floats above the base with a soft upward veil so the scrolling form tucks
// under it cleanly.
//
// The body area accepts EITHER an eager box child ([body], what every screen
// passed until the salon invite history arrived) OR a list of [slivers], which
// swaps the `SingleChildScrollView` for a `CustomScrollView` of identical
// physics and padding so a screen with a long list can build it lazily. See
// [SectionScaffold.slivers].
//
// Design source: `docs/signup-designs/ProfileSettingsHub/lib/widgets/
// section_scaffold.dart` — ported 1:1, swapping VelvetColors → BrandColors and
// the local widgets for the production shared widgets.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';

/// Common scaffold for the settings hub + every section page.
class SectionScaffold extends StatelessWidget {
  const SectionScaffold({
    super.key,
    required this.title,
    this.body,
    this.slivers,
    this.footer,
    required this.onBack,
    this.backIcon = Icons.arrow_back_ios_new_rounded,
    required this.backSemanticLabel,
    this.backKey,
  }) : assert(
         (body == null) != (slivers == null),
         'SectionScaffold takes exactly one of `body` (a box child, scrolled '
         'eagerly) or `slivers` (lazily built) — never both, never neither.',
       );

  final String title;

  /// The scrolling content, as a single box widget.
  ///
  /// Optional ONLY so [slivers] can replace it; every caller must still pass
  /// exactly one of the two (asserted in the constructor). Relaxing
  /// `required` breaks no existing call site — all of them pass `body:` and
  /// take the byte-identical [SingleChildScrollView] path they always have.
  final Widget? body;

  /// The scrolling content, as slivers — the LAZY alternative to [body].
  ///
  /// ADDITIVE and optional: null (every pre-existing caller) leaves the
  /// scaffold on its original [SingleChildScrollView], so this parameter
  /// changes nothing for the screens that ship today. When non-null the
  /// body area becomes a [CustomScrollView] with the SAME physics and the
  /// SAME [EdgeInsets] applied through a [SliverPadding], so a screen that
  /// migrates keeps its geometry to the pixel.
  ///
  /// WHY THIS EXISTS (backlog row 739): a long list inside [body] is fully
  /// eager, and a nested `ListView` cannot fix that — inside a
  /// [SingleChildScrollView] it needs `shrinkWrap: true`, which lays out every
  /// child anyway and adds a second viewport that steals drag gestures. Real
  /// laziness has to come from the scaffold's own viewport, which is what this
  /// parameter opens up. Row 739 also records that this is NOT the
  /// "23-consumer rewrite" an earlier in-code note claimed: the default path
  /// is untouched and consumers opt in one at a time.
  ///
  /// The list slivers are grouped under one [SliverPadding] via
  /// [SliverMainAxisGroup], so callers pass plain slivers and never repeat the
  /// scaffold's own inset.
  final List<Widget>? slivers;

  /// Optional pinned bottom action (the Save CTA). Null on the hub + account.
  final Widget? footer;

  /// Back / close action invoked from the top-bar icon button.
  final VoidCallback onBack;

  /// The leading icon — back chevron on section pages, close on the hub.
  final IconData backIcon;
  final String backSemanticLabel;

  /// Optional key for the leading icon button (used by widget tests).
  final Key? backKey;

  // Hoisted styles / geometry — never recompute in build.
  static final TextStyle _titleStyle = VelvetText.subheading();

  /// The scroll inset — shared by BOTH branches so the sliver path lands on
  /// exactly the geometry the box path has always produced.
  static const EdgeInsets _scrollPadding = EdgeInsets.fromLTRB(
    VelvetSpacing.lg,
    VelvetSpacing.md,
    VelvetSpacing.lg,
    VelvetSpacing.xl,
  );

  static const ScrollPhysics _scrollPhysics = BouncingScrollPhysics();

  static const BoxDecoration _footerVeil = BoxDecoration(
    color: BrandColors.base,
    boxShadow: <BoxShadow>[
      BoxShadow(
        color: BrandColors.base,
        offset: Offset(0, -12),
        blurRadius: 18,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final Widget? footer = this.footer;
    final List<Widget>? slivers = this.slivers;
    final Widget body = this.body ?? const SizedBox.shrink();
    return Scaffold(
      backgroundColor: BrandColors.base,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // Top bar — fixed height, identical geometry across all screens.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                VelvetSpacing.lg,
                VelvetSpacing.md,
                VelvetSpacing.lg,
                VelvetSpacing.sm,
              ),
              child: SizedBox(
                height: 48,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: NeumorphicIconButton(
                        key: backKey,
                        icon: backIcon,
                        semanticLabel: backSemanticLabel,
                        onTap: onBack,
                      ),
                    ),
                    Text(
                      title,
                      style: _titleStyle,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: slivers == null
                  ? SingleChildScrollView(
                      physics: _scrollPhysics,
                      padding: _scrollPadding,
                      child: body,
                    )
                  : CustomScrollView(
                      physics: _scrollPhysics,
                      slivers: <Widget>[
                        SliverPadding(
                          padding: _scrollPadding,
                          // One padding around the whole run, so the caller's
                          // slivers sit exactly where a `body` child would.
                          sliver: SliverMainAxisGroup(slivers: slivers),
                        ),
                      ],
                    ),
            ),
            // Pinned footer — base tone + soft top veil so the form scrolls
            // beneath the CTA without a hard cut line. Omitted entirely when
            // there is no footer (hub / account act inline).
            if (footer != null)
              DecoratedBox(
                decoration: _footerVeil,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    VelvetSpacing.lg,
                    VelvetSpacing.sm,
                    VelvetSpacing.lg,
                    VelvetSpacing.md,
                  ),
                  child: footer,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Phase 273 — AppointmentPager: the horizontal, one-master-per-page pager
// shared by the salon booking confirm and success screens.
//
// Ported verbatim (layout, spacing, timing) from
// `docs/signup-designs/SalonBookingConfirm/lib/widgets/appointment_pager.dart`
// — the owner-approved preview — aside from the token-name swap
// (`VelvetColors` -> [BrandColors]; `VelvetSpacing`/`VelvetShadows` already
// share the exact same names in this project's `core/theme/`) and routing the
// two hard-coded Ukrainian semantics strings through [AppLocalizations]
// (this project never inlines a localised string — CLAUDE.md conventions).
//
// One master's card is on screen at a time; a single centred `‹ N / M ›`
// control sits BELOW the card (never wrapped around the master's name — see
// the class doc), swipe still pages, and both dim inert at the ends of the
// visit. With exactly one master the control is not built at all and the
// [PageView] gets [NeverScrollableScrollPhysics] — there is nothing to page
// through.
//
// Each page carries its OWN [SingleChildScrollView]: a card is meant to fit
// one viewport, but that is not a promise across every device size/text-scale
// — so when it doesn't, THAT PAGE scrolls inside its frame while the pager's
// own chrome (the `‹ N / M ›` control) stays put.
//
// RIVERPOD TRAP CHECK (see the porting brief): neither call site's per-page
// content watches an autoDispose provider — `SalonAppointmentCard` and
// `BookingSummaryCards.fromSchedule` are both plain `StatelessWidget`s fed by
// already-resolved `SalonBookingAppointment` data, so an offstage page being
// un-built by [PageView] never disposes/invalidates anything. The screens'
// own secondary `publicSalonProfileProvider` read stays at the SCREEN level,
// outside this pager, so it is never affected by paging either.

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

/// Builds one master's page.
typedef AppointmentPageBuilder =
    Widget Function(BuildContext context, int index);

/// The horizontal pager shared by the salon confirm and success screens —
/// one master per page, swipeable, with one centred `‹ 2 / 3 ›` control
/// directly under the card.
class AppointmentPager extends StatefulWidget {
  const AppointmentPager({
    super.key,
    required this.count,
    required this.pageBuilder,
  });

  /// Number of masters in the visit.
  final int count;

  final AppointmentPageBuilder pageBuilder;

  @override
  State<AppointmentPager> createState() => _AppointmentPagerState();
}

class _AppointmentPagerState extends State<AppointmentPager> {
  late final PageController _controller = PageController();
  int _index = 0;

  bool get _paged => widget.count > 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    // Dismiss the keyboard first: paging with a comment field focused would
    // leave the caret on a card the client can no longer see.
    FocusScope.of(context).unfocus();
    unawaited(
      _controller.animateToPage(
        index.clamp(0, widget.count - 1),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  VoidCallback? get _prev =>
      _paged && _index > 0 ? () => _goTo(_index - 1) : null;

  VoidCallback? get _next =>
      _paged && _index < widget.count - 1 ? () => _goTo(_index + 1) : null;

  @override
  Widget build(BuildContext context) {
    final Widget pages = PageView.builder(
      controller: _controller,
      physics: _paged
          ? const BouncingScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      onPageChanged: (int i) => setState(() => _index = i),
      itemCount: widget.count,
      itemBuilder: (BuildContext context, int i) => SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          VelvetSpacing.lg,
          VelvetSpacing.xs,
          VelvetSpacing.lg,
          VelvetSpacing.md,
        ),
        child: widget.pageBuilder(context, i),
      ),
    );

    if (!_paged) return pages;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(child: pages),
        Padding(
          padding: const EdgeInsets.only(bottom: VelvetSpacing.sm),
          child: PagerCounterControl(
            index: _index,
            count: widget.count,
            onPrev: _prev,
            onNext: _next,
          ),
        ),
      ],
    );
  }
}

/// `‹  2 / 3  ›` — one small raised control, centred, that says both what it
/// pages and how far through the visit the client is.
class PagerCounterControl extends StatelessWidget {
  const PagerCounterControl({
    super.key,
    required this.index,
    required this.count,
    required this.onPrev,
    required this.onNext,
  });

  final int index;
  final int count;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Semantics(
        label: l10n.salonBookingPagerSemantics(index + 1, count),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.xs),
          decoration: BoxDecoration(
            color: BrandColors.base,
            borderRadius: BorderRadius.circular(20),
            boxShadow: VelvetShadows.extrudedSmall,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _PagerArrow(
                tapKey: const Key('appointment-pager-prev'),
                icon: Icons.chevron_left_rounded,
                semanticLabel: l10n.salonBookingPagerPrevious,
                onTap: onPrev,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: VelvetSpacing.xs,
                ),
                // `bookAccentValue14` — the shared "small accent numeric
                // figure" token (accentDeep, w800) — is the closest existing
                // match for a bold "N / M" counter; reused rather than an
                // inline fontSize (forbid_inline_fontsize.sh).
                child: Text(
                  '${index + 1} / $count',
                  style: VelvetText.bookAccentValue14,
                ),
              ),
              _PagerArrow(
                tapKey: const Key('appointment-pager-next'),
                icon: Icons.chevron_right_rounded,
                semanticLabel: l10n.salonBookingPagerNext,
                onTap: onNext,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One paging chevron, as used by both ends of the `‹ 2 / 3 ›` control.
///
/// Mocha while it can move, faint while it cannot — the disabled end is shown,
/// not hidden, so the client can see they are at the first or the last master.
///
/// TRAP (porting brief #2): the [Key] and the tap hit-testing both live on the
/// [GestureDetector] — never on the [AnimatedScale] itself. `RenderTransform`
/// (what `AnimatedScale` builds) never joins the hit-test path, so a `Key`
/// planted at that level would make `find.byKey(...).tap()` a warn-only miss
/// in a widget test and a hard failure in an integration test. Mirrors the
/// established [CalendarButton] recipe (`widgets/calendar_button.dart`): the
/// key sits on the outer, hit-testing [GestureDetector]; `AnimatedScale`
/// stays a purely visual descendant.
class _PagerArrow extends StatefulWidget {
  const _PagerArrow({
    required this.tapKey,
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  /// Applied to the inner, hit-testing [GestureDetector] — never to this
  /// [StatefulWidget] itself, which would leave two widgets sharing one key
  /// (`find.byKey` would then match both and `tester.tap` would throw "too
  /// many elements"). See the class doc's TRAP note.
  final Key tapKey;

  final IconData icon;
  final String semanticLabel;

  /// `null` disables the arrow (an end of the visit).
  final VoidCallback? onTap;

  @override
  State<_PagerArrow> createState() => _PagerArrowState();
}

class _PagerArrowState extends State<_PagerArrow> {
  bool _pressed = false;

  bool get _enabled => widget.onTap != null;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        key: widget.tapKey,
        behavior: HitTestBehavior.opaque,
        onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
        onTapUp: _enabled
            ? (_) {
                setState(() => _pressed = false);
                widget.onTap!.call();
              }
            : null,
        child: RepaintBoundary(
          child: AnimatedScale(
            scale: _pressed ? 0.86 : 1,
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOut,
            child: SizedBox(
              height: 34,
              width: 34,
              child: Icon(
                widget.icon,
                size: 24,
                color: _enabled
                    ? BrandColors.accentDeep
                    : BrandColors.faint.withValues(alpha: 0.55),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Phase 414 — «Посилання для запису» screen (D3–D7).
//
// Design source: `docs/signup-designs/BookingLinks/lib/screens/
// booking_links_screen.dart` — ported 1:1. Preview plumbing swapped:
// `LinksLoad`/`Scenarios` → [bookingLinksProvider]; `Clipboard.setData` →
// [ClipboardService]; the share/setup preview snacks → [ShareService] and
// go_router targets; the preview `StaggeredReveal` → one 1000 ms controller
// with curves pre-built in initState (the hub's `_reveal` pattern).
//
// Access (user decision 2026-10-20): INDEPENDENT_MASTER sees its MASTER card,
// SALON_OWNER one SALON card per salon, SALON_ADMIN its salon's SALON card.
// The role scoping lives in [bookingLinksProvider]; this screen additionally
// closes itself when the role is not allowed or the links are gone /
// switched off (D7) — the route guard is the first line, this the second.
//
// Security (413 audits): only `BookingLink.url` passed through
// [BookingLinkUrl.withUtm] ever reaches the clipboard or the share sheet, and
// the share text is the display name + that URL — nothing else.

import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/share/clipboard_service.dart';
import 'package:beautica_mobile/core/share/share_service.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/role_home.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';

import '../../auth/domain/user_role.dart';
import '../../auth/presentation/auth_notifier.dart';
import '../../master/presentation/widgets/section_scaffold.dart';
import '../domain/booking_link.dart';
import '../domain/booking_link_access.dart';
import '../domain/booking_link_url.dart';
import 'booking_links_provider.dart';
import 'widgets/booking_link_card.dart';

/// «Посилання для запису» — one [BookingLinkCard] per link, backend order.
class BookingLinkScreen extends ConsumerStatefulWidget {
  const BookingLinkScreen({super.key});

  @override
  ConsumerState<BookingLinkScreen> createState() => _BookingLinkScreenState();
}

class _BookingLinkScreenState extends ConsumerState<BookingLinkScreen> {
  bool _closing = false;

  void _close(UserRole? role) {
    if (_closing) return;
    _closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(role == null ? RouteNames.login : roleHomePath(role));
      }
    });
  }

  Future<bool> _copy(BookingLink link) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String url = BookingLinkUrl.withUtm(
      link.url,
      kind: link.kind,
      source: BookingLinkShareSource.copy,
    );
    final bool ok = await ref.read(clipboardServiceProvider).copyText(url);
    if (!mounted) return false;
    if (ok) {
      showSuccessSnack(context, l10n.bookingLinkCopied);
    } else {
      showErrorSnack(context, l10n.bookingLinkCopyFailed);
    }
    return ok;
  }

  Future<void> _share(BookingLink link) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String url = BookingLinkUrl.withUtm(
      link.url,
      kind: link.kind,
      source: BookingLinkShareSource.share,
    );
    final String text = switch (link.kind) {
      BookingLinkKind.master => l10n.bookingLinkShareTextMaster(url),
      BookingLinkKind.salon => l10n.bookingLinkShareTextSalon(
        link.displayName,
        url,
      ),
    };
    final ShareOutcome outcome = await ref
        .read(shareServiceProvider)
        .shareText(text);
    log('share outcome: ${outcome.name}', name: 'feature.booking_links');
    if (!mounted) return;
    if (outcome == ShareOutcome.failed) {
      showErrorSnack(context, l10n.bookingLinkShareFailed);
    }
  }

  /// D6 setup target: services for a MASTER link, the salon «Команда» tab for
  /// a SALON link; `null` when the salon id is missing.
  VoidCallback? _setupFor(BookingLink link) {
    final String? target = switch (link.kind) {
      BookingLinkKind.master => RouteNames.services,
      BookingLinkKind.salon => switch (link.salonId) {
        final String id when id.trim().isNotEmpty => RouteNames.salonShell(
          id,
          openTeam: true,
        ),
        _ => null,
      },
    };
    if (target == null) return null;
    return () => context.go(target);
  }

  void _onBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      final UserRole? role = ref.read(authProvider.select(authUserRoleOrNull));
      context.go(role == null ? RouteNames.login : roleHomePath(role));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final UserRole? role = ref.watch(authProvider.select(authUserRoleOrNull));
    final AsyncValue<BookingLinks> async = ref.watch(bookingLinksProvider);

    if (role != null && !bookingLinksAllowedFor(role)) _close(role);

    final BookingLinks? links = async.value;
    final Widget body;
    if (links != null && !async.hasError) {
      // D7: switched off / emptied while on screen → back out.
      if (!links.isVisible) _close(role);
      body = _LinksBody(
        key: ValueKey<int>(links.links.length),
        intro: l10n.bookingLinksIntro,
        links: links.links,
        cardBuilder: (BookingLink link) => BookingLinkCard(
          key: ValueKey<String>('card-${link.slug}'),
          link: link,
          onCopy: () => _copy(link),
          onShare: () => _share(link),
          onSetup: _setupFor(link),
        ),
      );
    } else if (async.hasError && !async.isLoading) {
      final Object error = async.error ?? const UnknownFailure();
      body = Padding(
        key: const ValueKey<String>('error'),
        padding: const EdgeInsets.only(top: VelvetSpacing.xxl),
        child: ErrorState(
          failure: error is Failure ? error : UnknownFailure(cause: error),
          // The fetch (and its cache) lives in the per-account family; the
          // screen's provider rebuilds because it watches it.
          onRetry: () => ref.invalidate(bookingLinksForAccountProvider),
        ),
      );
    } else {
      body = const _LoadingBody(key: ValueKey<String>('loading'));
    }

    return SectionScaffold(
      title: l10n.bookingLinksTitle,
      backSemanticLabel: l10n.bookingLinksBackSemanticLabel,
      backKey: const Key('btn-back-booking-links'),
      onBack: _onBack,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        child: body,
      ),
    );
  }
}

/// The data body: intro, then the cards 120 ms apart — one 1000 ms
/// controller, curves pre-built in initState (zero allocations in build).
class _LinksBody extends StatefulWidget {
  const _LinksBody({
    super.key,
    required this.intro,
    required this.links,
    required this.cardBuilder,
  });

  final String intro;
  final List<BookingLink> links;
  final Widget Function(BookingLink link) cardBuilder;

  @override
  State<_LinksBody> createState() => _LinksBodyState();
}

class _LinksBodyState extends State<_LinksBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _introAnim;
  late final Animation<Offset> _introSlide;
  late final List<CurvedAnimation> _cardAnims;
  late final List<Animation<Offset>> _cardSlides;

  static final Tween<Offset> _slideTween = Tween<Offset>(
    begin: const Offset(0, 0.035),
    end: Offset.zero,
  );

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _introAnim = _curve(0, 0.4);
    _introSlide = _slideTween.animate(_introAnim);
    _cardAnims = List<CurvedAnimation>.generate(widget.links.length, (int i) {
      final double start = (0.08 + i * 0.12).clamp(0.0, 0.5);
      return _curve(start, (start + 0.5).clamp(0.0, 1.0));
    }, growable: false);
    _cardSlides = List<Animation<Offset>>.generate(
      _cardAnims.length,
      (int i) => _slideTween.animate(_cardAnims[i]),
      growable: false,
    );
    _controller.forward();
  }

  CurvedAnimation _curve(double start, double end) => CurvedAnimation(
    parent: _controller,
    curve: Interval(start, end, curve: Curves.easeOutCubic),
  );

  @override
  void dispose() {
    _introAnim.dispose();
    for (final CurvedAnimation a in _cardAnims) {
      a.dispose();
    }
    _controller.dispose();
    super.dispose();
  }

  Widget _reveal(CurvedAnimation anim, Animation<Offset> slide, Widget child) {
    // dim-decorative: screen entrance fade; 1 at rest
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(position: slide, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = <Widget>[
      _reveal(
        _introAnim,
        _introSlide,
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: VelvetSpacing.lg),
          child: Text(widget.intro, style: VelvetText.body()),
        ),
      ),
    ];
    for (int i = 0; i < widget.links.length; i++) {
      if (i > 0) children.add(const SizedBox(height: VelvetSpacing.lg));
      // The list length is pinned by this widget's key, so [_cardAnims]
      // always has a slot for every card.
      // RepaintBoundary inside the transitions: the fade/slide re-composites
      // the card's layer instead of re-painting its shadows every frame.
      children.add(
        _reveal(
          _cardAnims[i],
          _cardSlides[i],
          RepaintBoundary(child: widget.cardBuilder(widget.links[i])),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

/// D7 loading — the shared shimmer blocks laid out in the card's own geometry
/// so nothing jumps when data lands.
class _LoadingBody extends StatelessWidget {
  const _LoadingBody({super.key});

  @override
  Widget build(BuildContext context) {
    return const SkeletonShimmerScope(
      child: Column(
        key: Key('booking-links-loading'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.only(left: 4, bottom: VelvetSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SkeletonBlock(width: double.infinity, height: 14),
                SizedBox(height: VelvetSpacing.sm),
                SkeletonBlock(width: 180, height: 14),
              ],
            ),
          ),
          _LoadingCard(),
          SizedBox(height: VelvetSpacing.lg),
          _LoadingCard(),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return const NeumorphicCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              SkeletonBlock(width: 42, height: 42, radius: 12),
              SizedBox(width: VelvetSpacing.md),
              SkeletonBlock(width: 150, height: 16),
            ],
          ),
          SizedBox(height: VelvetSpacing.md + 4),
          SkeletonBlock(
            width: double.infinity,
            height: VelvetSizes.field,
            radius: VelvetRadii.field,
          ),
          SizedBox(height: VelvetSpacing.lg),
          Row(
            children: <Widget>[
              Expanded(
                child: SkeletonBlock(
                  width: double.infinity,
                  height: VelvetSizes.cta,
                  radius: VelvetRadii.button,
                ),
              ),
              SizedBox(width: VelvetSpacing.md - 4),
              Expanded(
                child: SkeletonBlock(
                  width: double.infinity,
                  height: VelvetSizes.cta,
                  radius: VelvetRadii.button,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

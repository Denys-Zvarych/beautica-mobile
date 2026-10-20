// Phase 414 — one booking link card (D4 / D6).
//
// Design source: `docs/signup-designs/BookingLinks/lib/widgets/
// booking_link_card.dart` — ported 1:1, swapping VelvetColors → BrandColors,
// the preview's text tokens for the production `VelvetText` scale, and its
// literal strings for ARB keys.
//
// Composed ENTIRELY from existing primitives — no new card/button/row widget:
//
//   NeumorphicCard (§ 9: radius 24, extrudedCard, padding 24)
//   ├─ header   NeumorphicGlyphWell(42) + title            (SettingsRow anatomy)
//   ├─ link     NeumorphicInset (§ 9 field well)            selectable, middle-ellipsised
//   ├─ warning  Icon + PromptLinkText(textAlign: start)    (D6, only !bookable)
//   └─ actions  NeumorphicButton «Поділитися» + SuccessSecondaryButton «Копіювати»
//
// Extension points (planned follow-up: regenerate / revoke): the body is a
// flat list of sections built in [BookingLinkCardState.build] — an extra
// action row slots in after [_Actions] and a "disabled" state can swap the
// link well + actions, both as additive optional params defaulting to the
// current rendering.

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/core/widgets/pressable_surface.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/prompt_link_text.dart';
import 'package:beautica_mobile/shared/widgets/success_secondary_button.dart';

import '../../domain/booking_link.dart';

/// One shareable booking link — title, the link itself, optional
/// not-bookable note, «Поділитися» + «Копіювати».
///
/// [onCopy] resolves `true` once the link is on the clipboard; only then does
/// the in-well check appear (1.6 s). [onSetup] is the D6 «Налаштувати» /
/// «Команда» target; `null` hides the link in the note (the note stays).
class BookingLinkCard extends StatefulWidget {
  const BookingLinkCard({
    super.key,
    required this.link,
    required this.onCopy,
    required this.onShare,
    this.onSetup,
  });

  final BookingLink link;
  final Future<bool> Function() onCopy;
  final VoidCallback onShare;
  final VoidCallback? onSetup;

  /// How long the copied check stays over the link well.
  static const Duration copiedDwell = Duration(milliseconds: 1600);

  @override
  State<BookingLinkCard> createState() => BookingLinkCardState();
}

class BookingLinkCardState extends State<BookingLinkCard> {
  /// Listened to only by the link well, so a copy never rebuilds the header
  /// or the actions.
  final ValueNotifier<bool> _copied = ValueNotifier<bool>(false);
  Timer? _resetTimer;

  Future<void> _copy() async {
    final bool ok = await widget.onCopy();
    if (!ok || !mounted) return;
    _resetTimer?.cancel();
    _copied.value = true;
    _resetTimer = Timer(BookingLinkCard.copiedDwell, () {
      if (mounted) _copied.value = false;
    });
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    _copied.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final BookingLink link = widget.link;
    final bool isSalon = link.kind == BookingLinkKind.salon;
    final String slug = link.slug;

    return NeumorphicCard(
      key: Key('booking-link-card-$slug'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Header — glyph well + title, the same anatomy as a SettingsRow so
          // the card reads as the row it was opened from, now unfolded.
          Row(
            children: <Widget>[
              NeumorphicGlyphWell(
                size: 42,
                child: Icon(
                  isSalon
                      ? Icons.storefront_outlined
                      : Icons.person_outline_rounded,
                  size: 19,
                  color: BrandColors.accentDeep,
                ),
              ),
              const SizedBox(width: VelvetSpacing.md),
              Expanded(
                child: Text(
                  isSalon
                      ? l10n.bookingLinkSalonTitle(link.displayName)
                      : l10n.bookingLinkMasterTitle,
                  style: VelvetText.subheading().copyWith(height: 1.3),
                ),
              ),
            ],
          ),
          const SizedBox(height: VelvetSpacing.md + 4),

          ValueListenableBuilder<bool>(
            valueListenable: _copied,
            builder: (BuildContext context, bool copied, Widget? _) =>
                _LinkWell(link: link, copied: copied),
          ),

          if (!link.bookable) ...<Widget>[
            const SizedBox(height: VelvetSpacing.md),
            _NotBookableNote(
              text: isSalon
                  ? l10n.bookingLinkNotBookableSalon
                  : l10n.bookingLinkNotBookableMaster,
              linkLabel: isSalon
                  ? l10n.bookingLinkSetupTeam
                  : l10n.bookingLinkSetupServices,
              linkKey: Key('link-booking-link-setup-$slug'),
              onTap: widget.onSetup,
            ),
          ],

          const SizedBox(height: VelvetSpacing.lg),
          _Actions(
            slug: slug,
            shareLabel: l10n.bookingLinkShare,
            copyLabel: l10n.bookingLinkCopy,
            onCopy: _copy,
            onShare: widget.onShare,
          ),
        ],
      ),
    );
  }
}

/// «Поділитися» (primary) + «Копіювати» (secondary). Side by side when each
/// button gets >= [_minButton] × text scale; otherwise stacked full-width,
/// primary on top — so a 360 dp phone or a 1.3x text scale never truncates a
/// label. Primary leads in both forms.
class _Actions extends StatelessWidget {
  const _Actions({
    required this.slug,
    required this.shareLabel,
    required this.copyLabel,
    required this.onCopy,
    required this.onShare,
  });

  final String slug;
  final String shareLabel;
  final String copyLabel;
  final VoidCallback onCopy;
  final VoidCallback onShare;

  static const double _gap = VelvetSpacing.md - 4;
  static const double _minButton = 156;

  @override
  Widget build(BuildContext context) {
    // NeumorphicButton's root is an AnimatedScale (a RenderTransform never
    // adds itself to the hit-test path), so the test key rides on a plain
    // SizedBox proxy instead — see `RenderTransform.hitTest`.
    final Widget share = SizedBox(
      key: Key('btn-booking-link-share-$slug'),
      child: NeumorphicButton(
        label: shareLabel,
        icon: Icons.ios_share_rounded,
        onPressed: onShare,
      ),
    );
    final Widget copy = SuccessSecondaryButton(
      buttonKey: Key('btn-booking-link-copy-$slug'),
      label: copyLabel,
      icon: Icons.content_copy_rounded,
      onPressed: onCopy,
    );
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final double scale = MediaQuery.textScalerOf(context).scale(16) / 16;
        final bool sideBySide = (c.maxWidth - _gap) / 2 >= _minButton * scale;
        if (sideBySide) {
          return Row(
            children: <Widget>[
              Expanded(child: share),
              const SizedBox(width: _gap),
              Expanded(child: copy),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            share,
            const SizedBox(height: _gap),
            copy,
          ],
        );
      },
    );
  }
}

/// The recessed link slot — § 9 field well. Single line, selectable,
/// middle-ellipsised on the slug so both its start and its unique tail stay
/// visible (D4).
class _LinkWell extends StatelessWidget {
  const _LinkWell({required this.link, required this.copied});

  final BookingLink link;
  final bool copied;

  static final RegExp _scheme = RegExp(r'^https?://');

  @override
  Widget build(BuildContext context) {
    final String bare = link.url.replaceFirst(_scheme, '');
    final int cut = bare.lastIndexOf('/') + 1;
    return SizedBox(
      height: VelvetSizes.field,
      child: NeumorphicInset(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.md),
          child: Stack(
            alignment: Alignment.centerRight,
            children: <Widget>[
              Align(
                alignment: Alignment.centerLeft,
                child: SelectionArea(
                  child: _MiddleEllipsisUrl(
                    key: Key('booking-link-url-${link.slug}'),
                    host: bare.substring(0, cut),
                    slug: bare.substring(cut),
                  ),
                ),
              ),
              // Copy confirmation rides OVER the end of the URL (on a
              // base-tone chip) so the resting URL gets the full well width.
              // Own layer: the pop-in never re-paints the URL text.
              RepaintBoundary(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutBack,
                  transitionBuilder: (Widget child, Animation<double> a) =>
                      ScaleTransition(
                        scale: a,
                        // dim-decorative: copied-check pop-in/out transition; 1 at rest
                        child: FadeTransition(opacity: a, child: child),
                      ),
                  child: copied
                      ? Container(
                          key: Key('booking-link-copied-${link.slug}'),
                          padding: const EdgeInsets.only(
                            left: VelvetSpacing.sm,
                          ),
                          color: BrandColors.base,
                          child: Icon(
                            Icons.check_circle_rounded,
                            size: 20,
                            color: BrandColors.success,
                            semanticLabel: AppLocalizations.of(
                              context,
                            ).bookingLinkCopiedSemantic,
                          ),
                        )
                      : const SizedBox.shrink(key: ValueKey<String>('rest')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Middle ellipsis by layout, not measurement: host (never shrinks) + slug
/// head (ellipsises at its end) + slug tail (the last [_tail] chars — the
/// part that makes the link unique). Reads `beautica.app/book/olena-kov…x7k2`
/// and stays correct under any font or text scale.
class _MiddleEllipsisUrl extends StatelessWidget {
  const _MiddleEllipsisUrl({super.key, required this.host, required this.slug});

  final String host;
  final String slug;

  static const int _tail = 4;

  static final TextStyle _hostStyle = VelvetText.input().copyWith(
    color: BrandColors.muted,
  );

  static final TextStyle _slugStyle = VelvetText.input().copyWith(
    fontWeight: FontWeight.w800,
  );

  @override
  Widget build(BuildContext context) {
    final bool split = slug.length > _tail * 2;
    final String head = split ? slug.substring(0, slug.length - _tail) : slug;
    final String tail = split ? slug.substring(slug.length - _tail) : '';
    return Semantics(
      label: '$host$slug',
      excludeSemantics: true,
      child: Row(
        children: <Widget>[
          Flexible(
            flex: 0,
            child: Text(
              host,
              style: _hostStyle,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Flexible(
            child: Text(
              head,
              style: _slugStyle,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              // Shrink-wrap to the truncated line so the tail sits flush
              // against the ellipsis (no slack gap).
              textWidthBasis: TextWidthBasis.longestLine,
            ),
          ),
          if (tail.isNotEmpty) Text(tail, style: _slugStyle, maxLines: 1),
        ],
      ),
    );
  }
}

/// D6 inline warning — never a blocking state; actions below stay live.
class _NotBookableNote extends StatelessWidget {
  const _NotBookableNote({
    required this.text,
    required this.linkLabel,
    required this.linkKey,
    required this.onTap,
  });

  final String text;
  final String linkLabel;
  final Key linkKey;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.only(top: 3),
          // Warning hue = VelvetSnackVariant.warning's accent (accentLatte),
          // paired with a glyph so meaning never rides on colour alone.
          child: Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: BrandColors.accentLatte,
          ),
        ),
        const SizedBox(width: VelvetSpacing.sm),
        Expanded(
          child: onTap == null
              ? Text(text, style: VelvetText.body())
              : PromptLinkText(
                  prompt: text,
                  linkLabel: linkLabel,
                  linkKey: linkKey,
                  onTap: onTap,
                  textAlign: TextAlign.start,
                ),
        ),
      ],
    );
  }
}

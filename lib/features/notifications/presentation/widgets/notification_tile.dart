// Phase 363 — one COMPACT row of the «Сповіщення» feed.
//
// ## Built from existing primitives, not a new card style
//
// User direction (2026-09-30): "make the notification card small, not big, use
// already existed best practises". The approved preview drew a 24 dp-radius
// card (~115 dp tall). The app's compact list-row convention is the settings
// row — a raised `VelvetRadii.field` box, `VelvetShadows.extrudedSmall`, a
// square inset glyph well — so this tile is composed from those SAME parts:
//
//   PressableSurface        (core/widgets/pressable_surface.dart) — the press /
//                            scale / shadow-drop shell `SettingsRow` and
//                            `ManagementActionCard` share. Additive hooks used
//                            here: a nullable `onTap` and a `border`.
//   NeumorphicGlyphWell     (same file) — the inset glyph square.
//   NeumorphicIconButton    (core/widgets/neumorphic.dart) — the ✓ button; its
//                            additive `faceSize` keeps the 48×48 dp hit box and
//                            draws a smaller raised face.
//   VelvetShadows.flushSmall — new token: `extrudedSmall` faded to alpha 0.
//
// ## The signature is kept: reading presses a notification into the page
//
// Unread = raised row (`extrudedSmall`), camel-tinted glyph square, w800 title
// and the ✓ button. Read = the SAME row pressed flush: the shadow pair fades to
// alpha 0 over 320 ms (same offsets, so the lerp never jumps), a hairline edge
// takes over, the glyph sinks into an inset well, the title steps down to w600
// secondary brown and the ✓ folds away.
//
// ## Two separate tap targets
// The row body opens the target (phase 364; until then it only marks read). The
// ✓ only marks read and never navigates. A row whose target is gone has no body
// tap and no press feedback.

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/core/widgets/pressable_surface.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

import '../../domain/app_notification.dart';
import '../notification_copy.dart';

/// One compact feed row.
class NotificationTile extends StatefulWidget {
  const NotificationTile({
    super.key,
    required this.item,
    required this.isClient,
    this.onOpen,
    this.onMarkRead,
  });

  /// Key of the ✓ button on the row for [id].
  static Key markReadKey(String id) => Key('notification-mark-read-$id');

  final AppNotification item;

  /// Whether the viewer is a client (decides audience-specific copy).
  final bool isClient;

  /// Row-body tap.
  final VoidCallback? onOpen;

  /// ✓ tap. The button renders only while the row is unread.
  final VoidCallback? onMarkRead;

  static const Duration _flip = Duration(milliseconds: 320);
  static const Curve _curve = Curves.easeOutCubic;
  static const double _glyphSize = 36;
  static const double _glyphIcon = 18;
  static const double _checkFace = 30;
  static const BorderRadius _radius = BorderRadius.all(
    Radius.circular(VelvetRadii.field),
  );

  @override
  State<NotificationTile> createState() => _NotificationTileState();
}

class _NotificationTileState extends State<NotificationTile> {
  /// A read row is drawn with NO shadow once the shadow tween has finished.
  /// `PressableSurface` tweens its decoration (shadow included) over 150 ms
  /// (`AnimatedContainer`); while that runs the faded `flushSmall` pair stays
  /// so the shadow lerps (same offsets, no jump). Afterwards two alpha-0
  /// blurred shadows would still cost a blur pass per row per frame for
  /// nothing. The settle timer below is that tween plus a margin, and never
  /// shorter than it.
  bool _settledRead = false;
  Timer? _settle;

  /// `PressableSurface`'s decoration tween — the real constant, so a change to
  /// the tween trips the assert in [initState].
  static const Duration _shadowTween = PressableSurface.decorationTweenDuration;
  static const Duration _settleAfter = Duration(milliseconds: 200);

  static const List<BoxShadow> _noShadow = <BoxShadow>[];

  static const Duration _flip = NotificationTile._flip;
  static const Curve _curve = NotificationTile._curve;
  static const double _glyphIcon = NotificationTile._glyphIcon;
  static const double _checkFace = NotificationTile._checkFace;
  static const BorderRadius _radius = NotificationTile._radius;

  @override
  void initState() {
    super.initState();
    assert(_settleAfter > _shadowTween, 'settle must outlast the shadow tween');
    // Born read (a fresh page, a refresh): nothing to animate from.
    _settledRead = widget.item.read;
  }

  @override
  void didUpdateWidget(NotificationTile old) {
    super.didUpdateWidget(old);
    final bool wasRead = old.item.read;
    final bool isRead = widget.item.read;
    if (wasRead == isRead) return;
    _settle?.cancel();
    _settle = null;
    _settledRead = false;
    if (isRead) {
      _settle = Timer(_settleAfter, () {
        _settle = null;
        if (mounted) setState(() => _settledRead = true);
      });
    }
  }

  @override
  void dispose() {
    _settle?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppNotification item = widget.item;
    final bool isClient = widget.isClient;
    final VoidCallback? onOpen = widget.onOpen;
    final VoidCallback? onMarkRead = widget.onMarkRead;
    // Phase 364: a row whose target is gone is tappable too — the tap marks it
    // read and says «Запис більше недоступний» (see `openNotification`).
    final bool tappable = onOpen != null;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool unread = !item.read;
    final bool gone = item.target is NoTarget;
    final String title = NotificationCopy.title(
      l10n,
      item.type,
      isClient: isClient,
    );
    final String? body = NotificationCopy.body(l10n, item, isClient: isClient);
    // Rendered whenever the backend sent one: it is null for independent-master
    // and client-side items, present on owner / admin rows.
    final String? salon = NotificationCopy.sanitize(item.params.salonName);
    final bool hasMeta = salon != null || gone;

    return RepaintBoundary(
      child: PressableSurface(
        onTap: tappable ? onOpen : null,
        color: BrandColors.base,
        borderRadius: _radius,
        shadow: unread
            ? VelvetShadows.extrudedSmall
            : _settledRead
            ? _noShadow
            : VelvetShadows.flushSmall,
        border: Border.all(
          color: BrandColors.faint.withValues(alpha: unread ? 0 : 0.45),
        ),
        padding: EdgeInsets.fromLTRB(
          VelvetSpacing.sm + VelvetSpacing.xs,
          VelvetSpacing.xs,
          unread ? VelvetSpacing.xs : VelvetSpacing.sm + VelvetSpacing.xs,
          VelvetSpacing.xs,
        ),
        child: Row(
          children: <Widget>[
            _Glyph(
              icon: NotificationCopy.glyph(item.type),
              unread: unread,
              dimmed: gone,
              unreadLabel: l10n.notificationsUnreadSemantic,
            ),
            const SizedBox(width: VelvetSpacing.sm + VelvetSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: AnimatedDefaultTextStyle(
                          duration: _flip,
                          curve: _curve,
                          style: VelvetText.bodyStrong().copyWith(
                            fontWeight: unread
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: unread
                                ? BrandColors.text
                                : BrandColors.textSecondary,
                          ),
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: VelvetSpacing.sm),
                      Text(
                        NotificationCopy.time(item.createdAt),
                        style: VelvetText.label(),
                      ),
                    ],
                  ),
                  if (body != null)
                    Text(
                      body,
                      style: VelvetText.body(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (hasMeta)
                    Padding(
                      padding: const EdgeInsets.only(top: VelvetSpacing.xs),
                      child: Row(
                        children: <Widget>[
                          if (salon != null)
                            Flexible(child: SalonLabel(name: salon)),
                          if (gone) ...<Widget>[
                            if (salon != null)
                              const SizedBox(width: VelvetSpacing.sm),
                            Flexible(
                              child: _NoTargetHint(
                                label: l10n.notificationsNoTarget,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
            AnimatedSize(
              duration: _flip,
              curve: _curve,
              alignment: Alignment.centerLeft,
              // The read branch keeps the row's height (no jump when a row
              // flips in the middle of the list), only its width folds away.
              child: unread && onMarkRead != null
                  ? Padding(
                      padding: const EdgeInsets.only(left: VelvetSpacing.xs),
                      // `container: true` keeps the ✓ its own semantics node
                      // instead of merging into the row's.
                      child: Semantics(
                        container: true,
                        child: NeumorphicIconButton(
                          key: NotificationTile.markReadKey(item.id),
                          faceSize: _checkFace,
                          iconWidget: const Icon(
                            Icons.check_rounded,
                            size: _glyphIcon,
                            color: BrandColors.accentDeep,
                          ),
                          semanticLabel: l10n.notificationsMarkOneRead,
                          onTap: onMarkRead,
                        ),
                      ),
                    )
                  : const SizedBox(height: NeumorphicIconButton.extent),
            ),
          ],
        ),
      ),
    );
  }
}

/// The type glyph. Unread: a flat camel-tinted square (colour marks "new").
/// Read: an inset well (the glyph has sunk with the row). Gone: faint.
class _Glyph extends StatelessWidget {
  const _Glyph({
    required this.icon,
    required this.unread,
    required this.dimmed,
    required this.unreadLabel,
  });

  final IconData icon;
  final bool unread;
  final bool dimmed;
  final String unreadLabel;

  @override
  Widget build(BuildContext context) {
    final Color glyph = dimmed
        ? BrandColors.faint
        : unread
        ? BrandColors.accentDeep
        : BrandColors.muted;
    return AnimatedSwitcher(
      duration: NotificationTile._flip,
      child: unread
          ? Semantics(
              key: const ValueKey<bool>(true),
              label: unreadLabel,
              child: Container(
                height: NotificationTile._glyphSize,
                width: NotificationTile._glyphSize,
                decoration: BoxDecoration(
                  color: BrandColors.accent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(VelvetRadii.field - 4),
                ),
                child: Icon(
                  icon,
                  size: NotificationTile._glyphIcon,
                  color: glyph,
                ),
              ),
            )
          : NeumorphicGlyphWell(
              key: const ValueKey<bool>(false),
              size: NotificationTile._glyphSize,
              child: Icon(
                icon,
                size: NotificationTile._glyphIcon,
                color: glyph,
              ),
            ),
    );
  }
}

/// The small salon-name label on owner / admin rows (`params.salonName`).
class SalonLabel extends StatelessWidget {
  const SalonLabel({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: BrandColors.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(VelvetRadii.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: VelvetSpacing.sm,
          vertical: 2,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.storefront_rounded,
              size: 12,
              color: BrandColors.accentLatte,
            ),
            const SizedBox(width: VelvetSpacing.xs),
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: VelvetText.label().copyWith(
                  color: BrandColors.textSecondary,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoTargetHint extends StatelessWidget {
  const _NoTargetHint({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(Icons.link_off_rounded, size: 13, color: BrandColors.muted),
        const SizedBox(width: VelvetSpacing.xs),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: VelvetText.label().copyWith(letterSpacing: 0.2),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';

/// Overlay count pill (promoted from the bookings filter button's private
/// `_CountBadge`, Phase 24.7). Excluded from semantics — callers announce the
/// count in their own semantics label.
///
/// Defaults reproduce the filter button exactly: mocha fill, no cap, and the
/// `master-bookings-filter-badge` key. `count <= 0` renders nothing.
class CountBadge extends StatelessWidget {
  // ignore: use_key_in_widget_constructors — `key` is routed to the pill, see _badgeKey.
  const CountBadge({required this.count, this.color, this.maxCount, Key? key})
    : _badgeKey = key ?? const Key('master-bookings-filter-badge');

  /// Keyed on the pill itself (not on this widget) so the key is absent from
  /// the tree when the badge is hidden, exactly as before the promotion.
  final Key _badgeKey;

  final int count;

  /// Fill colour; defaults to [BrandColors.accentDeep].
  final Color? color;

  /// When non-null, a count above this renders `<maxCount>+`.
  final int? maxCount;

  // Mocha, not the design's camel dot — see `VelvetText.filterBadge` for the
  // contrast reason (a dot carries no digit). Const so the default pill
  // allocates no decoration per build.
  static const BorderSide _ring = BorderSide(
    color: BrandColors.base,
    width: 1.5,
  );
  static const BoxDecoration _defaultDecoration = BoxDecoration(
    color: BrandColors.accentDeep,
    borderRadius: BorderRadius.all(Radius.circular(VelvetRadii.pill)),
    border: Border(top: _ring, right: _ring, bottom: _ring, left: _ring),
  );

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final int? cap = maxCount;
    final String label = (cap != null && count > cap) ? '$cap+' : '$count';
    return ExcludeSemantics(
      child: Container(
        key: _badgeKey,
        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.xs),
        decoration: color == null
            ? _defaultDecoration
            : _defaultDecoration.copyWith(color: color),
        child: Text(label, style: VelvetText.filterBadge),
      ),
    );
  }
}

/// Anchors a [CountBadge] to the top-right corner of [child]. Hidden at 0.
class CountBadgeAnchor extends StatelessWidget {
  const CountBadgeAnchor({
    required this.child,
    required this.count,
    this.badgeColor,
    this.maxCount,
    this.badgeKey,
    super.key,
  });

  final Widget child;
  final int count;
  final Color? badgeColor;
  final int? maxCount;
  final Key? badgeKey;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        child,
        if (count > 0)
          Positioned(
            top: -4,
            right: -4,
            child: CountBadge(
              key: badgeKey,
              count: count,
              color: badgeColor,
              maxCount: maxCount,
            ),
          ),
      ],
    );
  }
}

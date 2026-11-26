// M542 — the ONE category-icon renderer (SVC-04).
//
// Drop-in for the `AppIcon(iconAsset, …)` every category row used to render
// by hand. Resolution order:
//   1. the category's remote icon (`iconUrl`, SVC-58) — ONLY when its bytes
//      are already in [categoryIconStoreProvider] (D1); tinted with the SAME
//      `ColorFilter.mode(color, BlendMode.srcIn)` as [AppIcon] (D2);
//   2. otherwise the bundled [asset] the call site already resolved via
//      `categoryIconOrNullFor` (the 22 THIN icons, massage = the owner's
//      drawing; unknown slug → the generic fallback) — rendered by an
//      unchanged [AppIcon], so every current caller is pixel-identical when
//      no remote icon is cached.
// A remote icon that fails to parse is discarded from the store (logged once)
// and the glyph drops back to (2). Both branches paint inside a fixed
// `size × size` box, so the swap never shifts layout.
//
// Riverpod is consulted only when a ProviderScope is an ancestor: many widget
// tests pump category rows bare, and a bare glyph must render exactly the
// bundled icon rather than throw. The check is ONE inherited-widget lookup
// (`ProviderScope.containerOf(listen: false)`, O(1)), not an ancestor walk.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'app_icon.dart';
import 'category_icon_store.dart';

/// Renders one category icon — remote when cached, bundled otherwise.
class CategoryIconGlyph extends StatelessWidget {
  /// [asset] is the bundled fallback (from `categoryIconOrNullFor` /
  /// `categoryIconFor`); [categoryKey] is the backend wire slug used to look
  /// up a cached remote icon. A null/blank key always renders [asset].
  const CategoryIconGlyph(
    this.asset, {
    super.key,
    this.categoryKey,
    this.size = 24.0,
    this.color,
    this.semanticLabel,
  });

  /// Bundled SVG asset path — the offline / old-backend fallback.
  final String asset;

  /// Uppercase wire slug (e.g. `NAIL_SERVICE`); case and whitespace ignored.
  final String? categoryKey;

  /// Rendered width and height in logical pixels — same as [AppIcon.size].
  final double size;

  /// Tint (srcIn); `null` inherits `IconTheme` — same as [AppIcon.color].
  final Color? color;

  /// Screen-reader label; `null` = decorative — same as [AppIcon].
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final Widget bundled = AppIcon(
      asset,
      size: size,
      color: color,
      semanticLabel: semanticLabel,
    );
    final String? key = normaliseCategoryIconKey(categoryKey);
    if (key == null) return bundled;
    if (!_hasProviderScope(context)) return bundled;
    return Consumer(
      builder: (BuildContext context, WidgetRef ref, Widget? _) {
        final CategoryIconBytes? remote = ref.watch(
          categoryIconStoreProvider.select(
            (Map<String, CategoryIconBytes> m) => m[key],
          ),
        );
        if (remote == null) return bundled;
        final Color? effectiveColor = color ?? IconTheme.of(context).color;
        return SizedBox.square(
          dimension: size,
          child: SvgPicture.memory(
            remote.bytes,
            key: ValueKey<String>(remote.url),
            width: size,
            height: size,
            colorFilter: effectiveColor == null
                ? null
                : ColorFilter.mode(effectiveColor, BlendMode.srcIn),
            semanticsLabel: semanticLabel,
            placeholderBuilder: (BuildContext _) => bundled,
            errorBuilder: (BuildContext _, Object _, StackTrace _) {
              // Post-frame: mutating a provider during build is illegal.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!context.mounted) return;
                ref.read(categoryIconStoreProvider.notifier).discard(key);
              });
              return bundled;
            },
          ),
        );
      },
    );
  }
}

/// Whether a ProviderScope is above [context] — an O(1) inherited lookup
/// that registers no dependency. `containerOf` signals absence only by
/// throwing [StateError], hence the catch.
bool _hasProviderScope(BuildContext context) {
  try {
    ProviderScope.containerOf(context, listen: false);
    return true;
  } on StateError {
    return false;
  }
}

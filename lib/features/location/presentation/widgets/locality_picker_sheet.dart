// Phase 2.18 — Locality bottom-sheet picker (VelvetTouch redesign).
//
// A generic modal bottom sheet that lists selectable locality items
// (Oblast / City / CityDistrict) and returns the chosen one via
// `context.pop(item)` (go_router). Mirrors the sheet behaviour described in
// docs/signup-designs/sign-up-step-3-address.html step 5:
//   - drag handle bar at the top,
//   - debounced (200 ms) case-insensitive search on the localized name,
//   - scrollable list of selectable rows,
//   - empty state ("Нічого не знайдено") when the query matches nothing,
//   - AsyncError state with a Retry button,
//   - tap a row → context.pop(item).
//
// Sheet height is clamped to 80% of the screen. Surface = BrandColors.base
// (warm taupe), 16 px top-corner radius — VelvetTouch neumorphic treatment.
// No glassmorphism, no BackdropFilter, no dark gradients. All paint objects
// are hoisted; the search RegExp is avoided in favour of a cheap lowercase
// substring match.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
// `ProviderListenable` (the type accepted by `ref.watch`) is exported from the
// misc barrel rather than the top-level flutter_riverpod barrel in 3.x.
import 'package:flutter_riverpod/misc.dart';

/// Opens the locality picker bottom sheet and resolves with the selected item,
/// or null if the sheet was dismissed without a selection.
///
/// [provider] supplies the async list; [labelOf] extracts the searchable +
/// displayed name from each item; [idOf] extracts the item's stable UUID
/// (used only for tile keys — never displayed); [titleLabel] is the sheet
/// header (reusing the row's label, e.g. "Місто"); [onRetry] is invoked when
/// the user taps Retry in the error state (typically `ref.invalidate(provider)`).
Future<T?> showLocalityPickerSheet<T>({
  required BuildContext context,
  required ProviderListenable<AsyncValue<List<T>>> provider,
  required String Function(T) labelOf,
  required String Function(T) idOf,
  required String titleLabel,
  required VoidCallback onRetry,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    // Explicit dismiss affordances: tapping the scrim closes the sheet, AND the
    // header carries an explicit close (X) button (Defect 6) — with the keyboard
    // open the scrim can be unreachable, so the X is the reliable escape route.
    isDismissible: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x99000000), // ~60% black scrim for legibility
    builder: (_) => _LocalityPickerSheet<T>(
      provider: provider,
      labelOf: labelOf,
      idOf: idOf,
      titleLabel: titleLabel,
      onRetry: onRetry,
    ),
  );
}

class _LocalityPickerSheet<T> extends ConsumerStatefulWidget {
  const _LocalityPickerSheet({
    required this.provider,
    required this.labelOf,
    required this.idOf,
    required this.titleLabel,
    required this.onRetry,
  });

  final ProviderListenable<AsyncValue<List<T>>> provider;
  final String Function(T) labelOf;
  final String Function(T) idOf;
  final String titleLabel;
  final VoidCallback onRetry;

  @override
  ConsumerState<_LocalityPickerSheet<T>> createState() =>
      _LocalityPickerSheetState<T>();
}

class _LocalityPickerSheetState<T>
    extends ConsumerState<_LocalityPickerSheet<T>> {
  static const _kSheetRadius = BorderRadius.vertical(top: Radius.circular(16));

  /// VelvetTouch warm-taupe sheet surface — matches the neumorphic base tone
  /// used on every screen so the sheet reads as a native surface extension.
  static const _kSheetDecoration = BoxDecoration(
    color: BrandColors.base,
    borderRadius: _kSheetRadius,
  );

  static const _kSearchRadius = BorderRadius.all(Radius.circular(12));
  static const _kSearchDebounce = Duration(milliseconds: 200);

  // Hoisted TextStyle instances — each copyWith() allocates; hoist to avoid
  // per-build allocation during keyboard viewInsets animation rebuilds. (P1-1/2)
  static final TextStyle _searchHintStyle = VelvetText.input().copyWith(
    color: BrandColors.muted,
  );
  static final TextStyle _emptyStyle = VelvetText.body().copyWith(
    color: BrandColors.muted,
  );

  final TextEditingController _searchController = TextEditingController();

  /// The committed (debounced) lowercase query used for filtering.
  String _query = '';
  Timer? _debounce;

  // --- Memoized filter -------------------------------------------------------
  // The keyboard slide-open drives many rebuilds (viewInsets animation) with an
  // unchanged query; cache the O(n) substring scan and recompute only when the
  // source list identity OR the committed query changes.
  List<T>? _filterCache;
  List<T>? _filterCacheItems;
  String? _filterCacheQuery;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String raw) {
    _debounce?.cancel();
    _debounce = Timer(_kSearchDebounce, () {
      if (!mounted) return;
      setState(() => _query = raw.trim().toLowerCase());
    });
  }

  List<T> _filter(List<T> items) {
    // Serve the cached result while neither the source list identity nor the
    // committed query has changed (avoids re-scanning during keyboard anim).
    if (identical(items, _filterCacheItems) &&
        _query == _filterCacheQuery &&
        _filterCache != null) {
      return _filterCache!;
    }
    final result = _query.isEmpty
        ? items
        : items
              .where(
                (item) => widget.labelOf(item).toLowerCase().contains(_query),
              )
              .toList(growable: false);
    _filterCacheItems = items;
    _filterCacheQuery = _query;
    _filterCache = result;
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final mediaQuery = MediaQuery.of(context);
    final maxHeight = mediaQuery.size.height * 0.8;
    final async = ref.watch(widget.provider);

    return Padding(
      // Lift the sheet above the on-screen keyboard while searching.
      padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        // Clip the whole gradient + glass + list stack to the 16 px top radius
        // (Defect 1). Without this, the rounded look came only from the
        // DecoratedBox borderRadius, leaving the square corners outside the
        // radius painting the dark scrim as black wedges.
        child: ClipRRect(
          borderRadius: _kSheetRadius,
          child: DecoratedBox(
            // VelvetTouch warm-taupe surface — no glassmorphism, no gradient.
            decoration: _kSheetDecoration,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle — visible on the warm taupe base.
                const Padding(
                  padding: EdgeInsets.only(
                    top: VelvetSpacing.sm,
                    bottom: VelvetSpacing.xs,
                  ),
                  child: _DragHandle(color: BrandColors.faint),
                ),
                // Header: title on the left, explicit close (X) on the right.
                // The close button is the reliable dismiss affordance when the
                // keyboard is open and the scrim is unreachable (Defect 6).
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    VelvetSpacing.md,
                    VelvetSpacing.xs,
                    VelvetSpacing.xs,
                    VelvetSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.titleLabel,
                          style: VelvetText.heading(),
                        ),
                      ),
                      IconButton(
                        key: const Key('locality_picker_close'),
                        icon: const Icon(Icons.close_rounded),
                        iconSize: 20,
                        color: BrandColors.accentDeep,
                        tooltip: l10n.localityPickerClose,
                        // 44×44 hit target (touch-target-size); visual glyph 20.
                        constraints: const BoxConstraints(
                          minWidth: 44,
                          minHeight: 44,
                        ),
                        onPressed: () => context.pop(),
                      ),
                    ],
                  ),
                ),
                // Search field — soft white inset on warm taupe base.
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    VelvetSpacing.md,
                    0,
                    VelvetSpacing.md,
                    VelvetSpacing.sm,
                  ),
                  child: TextField(
                    key: const Key('locality_picker_search'),
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    autocorrect: false,
                    textInputAction: TextInputAction.search,
                    style: VelvetText.input(),
                    cursorColor: BrandColors.accent,
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: BrandColors.white.withValues(alpha: 0.5),
                      hintText: l10n.localitySearchHint,
                      hintStyle: _searchHintStyle,
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        size: 20,
                        color: BrandColors.muted,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: VelvetSpacing.sm,
                      ),
                      enabledBorder: const OutlineInputBorder(
                        borderRadius: _kSearchRadius,
                        borderSide: BorderSide(color: BrandColors.faint),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: _kSearchRadius,
                        borderSide: BorderSide(color: BrandColors.accent),
                      ),
                    ),
                  ),
                ),
                Flexible(
                  child: async.when(
                    loading: () => const _SheetLoading(),
                    error: (err, _) => _SheetError(
                      failure: err,
                      onRetry: widget.onRetry,
                      retryLabel: l10n.localityRetry,
                    ),
                    data: (items) {
                      final filtered = _filter(items);
                      if (filtered.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(VelvetSpacing.xl),
                            child: Text(
                              l10n.localitySearchEmpty,
                              key: const Key('locality_picker_empty'),
                              style: _emptyStyle,
                            ),
                          ),
                        );
                      }
                      // Isolate fling-scroll repaints from the surface layer
                      // behind the list (it never changes on scroll).
                      return RepaintBoundary(
                        child: ListView.builder(
                          padding: const EdgeInsets.only(
                            bottom: VelvetSpacing.md,
                          ),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final item = filtered[index];
                            final label = widget.labelOf(item);
                            // Key off the item's stable UUID — unique within the
                            // list (homonymous settlements share a `nameUk`,
                            // which would collide on a label-derived key) and
                            // not user-facing. Stable across filtered reorder.
                            return LocalityPickerTile(
                              key: ValueKey(
                                'locality_picker_tile_${widget.idOf(item)}',
                              ),
                              label: label,
                              onTap: () => context.pop(item),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A single selectable row inside the locality picker sheet.
class LocalityPickerTile extends StatelessWidget {
  const LocalityPickerTile({
    required this.label,
    required this.onTap,
    super.key,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: BrandColors.accent.withValues(alpha: 0.12),
        highlightColor: BrandColors.accent.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: VelvetSpacing.md,
            vertical: VelvetSpacing.md,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VelvetText.body(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.all(Radius.circular(2)),
      ),
    );
  }
}

class _SheetLoading extends StatelessWidget {
  const _SheetLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(VelvetSpacing.xl),
      child: Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: BrandColors.accent,
          ),
        ),
      ),
    );
  }
}

class _SheetError extends StatelessWidget {
  const _SheetError({
    required this.failure,
    required this.onRetry,
    required this.retryLabel,
  });

  final Object failure;
  final VoidCallback onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final message = failure is Failure
        ? (failure as Failure).userMessage(context)
        : AppLocalizations.of(context).errUnknown;
    return Padding(
      padding: const EdgeInsets.all(VelvetSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Announce the error to screen readers (role=alert equivalent).
          Semantics(
            liveRegion: true,
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: VelvetText.body(),
            ),
          ),
          const SizedBox(height: VelvetSpacing.md),
          TextButton(
            key: const Key('locality_picker_retry'),
            onPressed: onRetry,
            style: TextButton.styleFrom(
              foregroundColor: BrandColors.accentDeep,
            ),
            child: Text(retryLabel),
          ),
        ],
      ),
    );
  }
}

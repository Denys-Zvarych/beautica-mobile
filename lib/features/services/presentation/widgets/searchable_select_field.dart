// Phase 16.6 — Reusable searchable single-select dropdown FIELD (VelvetTouch).
//
// Replaces the chip-wrap taxonomy selectors on the service form (category +
// service-type) with a neumorphic dropdown field that, when tapped, opens a
// searchable modal bottom sheet. Type-to-search filters the option list
// case- and diacritic-insensitively on the Ukrainian display label; tapping a
// row selects it and closes the sheet (single-select).
//
// The widget owns NO selection state — the closed field renders whatever
// [selectedLabel] the caller passes, and a tap that produces a value is routed
// back through [onSelected] (or, for the closed-field tap path that lands on a
// menu row, through the sheet's own pop result). This keeps the form's existing
// single-source-of-truth handlers intact (Phase 16.3/16.4).
//
// State plumbing (the spinner fix):
//   - The FIELD reflects the option provider's async state via [fieldState]:
//     `idle` (chevron), `loading` (inset spinner), or `error` (error icon +
//     error tint). A category selected but whose types are still loading/failed
//     therefore never strands the user on a bare chevron with no signal.
//   - The MENU reflects the same three async states: a contextual, ESCAPABLE
//     spinner (the sheet header X always dismisses it), a calm empty state, and
//     an error state with a Retry button that re-invokes [onMenuRetry]
//     (typically `ref.invalidate(provider)`).
//
// VelvetTouch craft mirrors `locality_picker_sheet.dart` verbatim: warm taupe
// surface (#E6DDD0), 16 px top radius, drag handle, header title + close X, a
// soft white-inset search field with a search prefix icon, InkWell option rows.
// No glassmorphism, no gradient, no BackdropFilter.

import 'dart:async';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// One selectable option in a [SearchableSelectField] menu.
///
/// [value] is the wire identifier routed back on selection; [label] is the
/// Ukrainian display string both shown and searched; [key] is the stable widget
/// key applied to the option row (so existing tests can find an option by the
/// same key the old chip used).
@immutable
class SelectOption<T> {
  const SelectOption({
    required this.value,
    required this.label,
    required this.rowKey,
  });

  final T value;
  final String label;
  final Key rowKey;
}

/// Async load state of the option list, surfaced both on the closed FIELD and
/// inside the open MENU so a hang/failure degrades to a visible, escapable
/// retry state instead of an un-actionable infinite spinner.
enum SelectFieldState { idle, loading, error }

/// A neumorphic searchable single-select dropdown field.
///
/// Generic over the option value type [T]. The closed field shows
/// [selectedLabel] (or [placeholder] when null), a trailing affordance that
/// reflects [fieldState], and — when [enabled] — opens a searchable modal
/// bottom sheet on tap. The sheet lists [options], filters them as the user
/// types, and pops the chosen value, which is then routed to [onSelected].
class SearchableSelectField<T> extends StatelessWidget {
  const SearchableSelectField({
    super.key,
    required this.fieldKey,
    required this.label,
    required this.menuTitle,
    required this.placeholder,
    required this.searchHint,
    required this.emptyLabel,
    required this.errorLabel,
    required this.retryLabel,
    required this.selectedLabel,
    required this.fieldState,
    required this.options,
    required this.onSelected,
    required this.onMenuRetry,
    this.loadingLabel,
    this.errorText,
    this.menuFooter,
    this.enabled = true,
  });

  /// Stable key applied to the tappable closed field (interaction target).
  final Key fieldKey;

  /// Uppercased section label rendered above the field (e.g. "КАТЕГОРІЯ").
  final String label;

  /// Title shown in the bottom-sheet header.
  final String menuTitle;

  /// Hint shown in the closed field when nothing is selected.
  final String placeholder;

  /// Placeholder inside the menu's search input.
  final String searchHint;

  /// Calm empty-state text when a search query matches nothing.
  final String emptyLabel;

  /// Error text shown both in the menu error state and (optionally) the field.
  final String errorLabel;

  /// Retry button label in the menu error state.
  final String retryLabel;

  /// The currently-selected option's display label, or null when none.
  final String? selectedLabel;

  /// Async state of the option provider — drives the field/menu affordance.
  final SelectFieldState fieldState;

  /// The resolved options (used only when [fieldState] is [SelectFieldState.idle]).
  final List<SelectOption<T>> options;

  /// Called with the chosen value when the user taps an option row.
  final ValueChanged<T> onSelected;

  /// Invoked when the user taps Retry in the menu's error state. Typically
  /// `ref.invalidate(provider)`.
  final VoidCallback onMenuRetry;

  /// Text shown in the closed field while [fieldState] is loading. When null,
  /// the placeholder is shown with a trailing spinner instead.
  final String? loadingLabel;

  /// Inline required/validation error rendered beneath the field (red row).
  /// Independent of [fieldState] — this is the form-level field error.
  final String? errorText;

  /// Optional action row pinned to the bottom of the menu (e.g. the
  /// "suggest a category" affordance). Receives the sheet's context so it can
  /// close the sheet before opening a follow-up dialog.
  final Widget Function(BuildContext sheetContext)? menuFooter;

  /// Suppresses the open-on-tap while a submit is in flight.
  final bool enabled;

  // Section-label style — hoisted to avoid per-frame TextStyle allocations.
  static final TextStyle _labelStyle = VelvetText.label();

  // Selected-value style — espresso input weight.
  static final TextStyle _valueStyle = VelvetText.input();

  // Placeholder style — muted, matching the field hint convention.
  static final TextStyle _placeholderStyle = VelvetText.input().copyWith(
    color: BrandColors.placeholder,
  );

  // Error-tinted value style for the field's error state.
  static final TextStyle _errorValueStyle = VelvetText.input().copyWith(
    color: BrandColors.error,
  );

  static final TextStyle _fieldErrorStyle = VelvetText.feedback(
    BrandColors.error,
  );

  Future<void> _openMenu(BuildContext context) async {
    final T? picked = await showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x99000000),
      builder: (_) => _SearchableSelectSheet<T>(
        title: menuTitle,
        searchHint: searchHint,
        emptyLabel: emptyLabel,
        errorLabel: errorLabel,
        retryLabel: retryLabel,
        state: fieldState,
        options: options,
        onRetry: onMenuRetry,
        menuFooter: menuFooter,
      ),
    );
    if (picked != null) {
      onSelected(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool hasError = errorText != null;
    final bool isErrorState = fieldState == SelectFieldState.error;
    final bool isLoadingState = fieldState == SelectFieldState.loading;

    final String displayText;
    final TextStyle displayStyle;
    if (isErrorState) {
      displayText = errorLabel;
      displayStyle = _errorValueStyle;
    } else if (isLoadingState && selectedLabel == null) {
      displayText = loadingLabel ?? placeholder;
      displayStyle = _placeholderStyle;
    } else if (selectedLabel != null) {
      displayText = selectedLabel!;
      displayStyle = _valueStyle;
    } else {
      displayText = placeholder;
      displayStyle = _placeholderStyle;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(
            left: VelvetSpacing.xs,
            bottom: VelvetSpacing.sm,
          ),
          child: Text(label.toUpperCase(), style: _labelStyle),
        ),
        Semantics(
          button: true,
          enabled: enabled,
          label: label,
          value: selectedLabel ?? placeholder,
          child: GestureDetector(
            key: fieldKey,
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? () => _openMenu(context) : null,
            child: NeumorphicInset(
              radius: VelvetRadii.field,
              hasError: hasError || isErrorState,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: VelvetSpacing.md,
                  vertical: VelvetSpacing.sm + 2,
                ),
                child: SizedBox(
                  height: VelvetSizes.field - 2 * (VelvetSpacing.sm + 2),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          displayText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: displayStyle,
                        ),
                      ),
                      const SizedBox(width: VelvetSpacing.sm),
                      _FieldAffordance(state: fieldState),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(
              left: VelvetSpacing.xs,
              right: VelvetSpacing.xs,
              top: VelvetSpacing.sm - 2,
            ),
            child: Semantics(
              liveRegion: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 15,
                    color: BrandColors.error,
                  ),
                  const SizedBox(width: VelvetSpacing.xs + 2),
                  Expanded(child: Text(errorText!, style: _fieldErrorStyle)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// The trailing affordance inside the closed field: a chevron when idle, a
/// small spinner while the option list loads, an error glyph when it failed.
class _FieldAffordance extends StatelessWidget {
  const _FieldAffordance({required this.state});

  final SelectFieldState state;

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case SelectFieldState.loading:
        return const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: BrandColors.accent,
          ),
        );
      case SelectFieldState.error:
        return const Icon(
          Icons.error_outline_rounded,
          size: 20,
          color: BrandColors.error,
        );
      case SelectFieldState.idle:
        return const Icon(
          Icons.keyboard_arrow_down_rounded,
          size: 22,
          color: BrandColors.muted,
        );
    }
  }
}

// ---------------------------------------------------------------------------
// The searchable bottom-sheet menu.
//
// Mirrors `locality_picker_sheet.dart`: warm taupe surface, drag handle, header
// with a close X, a soft white-inset search field, then the filtered option
// rows. The three async states (loading / empty-or-data / error) are rendered
// inside the scrollable area; the header X is ALWAYS available so a hung load
// can be escaped. Returns the chosen value via `Navigator.pop(value)`.
// ---------------------------------------------------------------------------

class _SearchableSelectSheet<T> extends StatefulWidget {
  const _SearchableSelectSheet({
    required this.title,
    required this.searchHint,
    required this.emptyLabel,
    required this.errorLabel,
    required this.retryLabel,
    required this.state,
    required this.options,
    required this.onRetry,
    required this.menuFooter,
  });

  final String title;
  final String searchHint;
  final String emptyLabel;
  final String errorLabel;
  final String retryLabel;
  final SelectFieldState state;
  final List<SelectOption<T>> options;
  final VoidCallback onRetry;
  final Widget Function(BuildContext sheetContext)? menuFooter;

  @override
  State<_SearchableSelectSheet<T>> createState() =>
      _SearchableSelectSheetState<T>();
}

class _SearchableSelectSheetState<T> extends State<_SearchableSelectSheet<T>> {
  static const _kSheetRadius = BorderRadius.vertical(top: Radius.circular(16));
  static const _kSheetDecoration = BoxDecoration(
    color: BrandColors.base,
    borderRadius: _kSheetRadius,
  );
  static const _kSearchRadius = BorderRadius.all(Radius.circular(12));
  static const _kSearchDebounce = Duration(milliseconds: 180);

  static final TextStyle _searchHintStyle = VelvetText.input().copyWith(
    color: BrandColors.muted,
  );
  static final TextStyle _emptyStyle = VelvetText.body().copyWith(
    color: BrandColors.muted,
  );

  final TextEditingController _searchController = TextEditingController();

  /// The committed (debounced) folded query used for filtering.
  String _query = '';
  Timer? _debounce;

  /// Folded form of each option's label, aligned 1:1 with [widget.options] by
  /// index. Precomputed ONCE per option set (here + in [didUpdateWidget]) so a
  /// keystroke-driven [_filter] is a cheap `contains` instead of re-folding
  /// every label on every debounced commit (M1 perf fix).
  late List<String> _foldedLabels = _buildFoldedLabels(widget.options);

  static List<String> _buildFoldedLabels<T>(List<SelectOption<T>> options) {
    return List<String>.generate(
      options.length,
      (i) => _fold(options[i].label),
      growable: false,
    );
  }

  @override
  void didUpdateWidget(covariant _SearchableSelectSheet<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Rebuild the folded cache only when the option set actually changes —
    // identity check first (same list instance ⇒ no work).
    if (!identical(oldWidget.options, widget.options)) {
      _foldedLabels = _buildFoldedLabels(widget.options);
    }
  }

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
      setState(() => _query = _fold(raw));
    });
  }

  /// Case- and (Ukrainian/Latin) diacritic-insensitive folding for matching.
  /// Lowercases and strips common combining accents so e.g. "ї" matches "i"-ish
  /// queries and accented Latin (é → e) is reachable from plain ASCII.
  static String _fold(String input) {
    final String lower = input.trim().toLowerCase();
    final StringBuffer sb = StringBuffer();
    for (final int rune in lower.runes) {
      sb.writeCharCode(_foldRune(rune));
    }
    return sb.toString();
  }

  static int _foldRune(int rune) {
    // Strip combining diacritical marks (U+0300–U+036F) → fold to a space so a
    // decomposed accented label still matches a plain-ASCII query.
    if (rune >= 0x0300 && rune <= 0x036F) {
      return 0x0020;
    }
    return _baseLatin[rune] ?? rune;
  }

  // A small fold table for the accented Latin characters that realistically
  // appear in Ukrainian/transliterated category labels. Cyrillic is compared
  // as-is (already lowercased), which is the correct UA behaviour.
  static const Map<int, int> _baseLatin = <int, int>{
    0x00E9: 0x0065, // é → e
    0x00E8: 0x0065, // è → e
    0x00EA: 0x0065, // ê → e
    0x00EB: 0x0065, // ë → e
    0x00E1: 0x0061, // á → a
    0x00E0: 0x0061, // à → a
    0x00E2: 0x0061, // â → a
    0x00E4: 0x0061, // ä → a
    0x00ED: 0x0069, // í → i
    0x00EC: 0x0069, // ì → i
    0x00EF: 0x0069, // ï → i
    0x00F3: 0x006F, // ó → o
    0x00F4: 0x006F, // ô → o
    0x00F6: 0x006F, // ö → o
    0x00FA: 0x0075, // ú → u
    0x00FC: 0x0075, // ü → u
    0x00E7: 0x0063, // ç → c
    0x00F1: 0x006E, // ñ → n
  };

  List<SelectOption<T>> _filter() {
    if (_query.isEmpty) return widget.options;
    final List<SelectOption<T>> options = widget.options;
    final List<SelectOption<T>> result = <SelectOption<T>>[];
    for (int i = 0; i < options.length; i++) {
      if (_foldedLabels[i].contains(_query)) {
        result.add(options[i]);
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final maxHeight = mediaQuery.size.height * 0.8;

    return Padding(
      padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: ClipRRect(
          borderRadius: _kSheetRadius,
          child: DecoratedBox(
            decoration: _kSheetDecoration,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.only(
                    top: VelvetSpacing.sm,
                    bottom: VelvetSpacing.xs,
                  ),
                  child: _DragHandle(color: BrandColors.faint),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    VelvetSpacing.md,
                    VelvetSpacing.xs,
                    VelvetSpacing.xs,
                    VelvetSpacing.sm,
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(widget.title, style: VelvetText.heading()),
                      ),
                      IconButton(
                        key: const Key('select-menu-close'),
                        icon: const Icon(Icons.close_rounded),
                        iconSize: 20,
                        color: BrandColors.accentDeep,
                        constraints: const BoxConstraints(
                          minWidth: 44,
                          minHeight: 44,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                // Search field — hidden while loading/error since there is no
                // list to filter; this keeps the focus on the state affordance.
                if (widget.state == SelectFieldState.idle)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      VelvetSpacing.md,
                      0,
                      VelvetSpacing.md,
                      VelvetSpacing.sm,
                    ),
                    child: TextField(
                      key: const Key('select-menu-search'),
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
                        hintText: widget.searchHint,
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
                Flexible(child: _body(context)),
                if (widget.menuFooter != null) widget.menuFooter!(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    switch (widget.state) {
      case SelectFieldState.loading:
        return const _SheetLoading();
      case SelectFieldState.error:
        return _SheetError(
          message: widget.errorLabel,
          retryLabel: widget.retryLabel,
          onRetry: () {
            // Close the sheet then re-invoke the caller's retry (which
            // invalidates the provider). The field's affordance reflects the
            // re-load; re-opening shows the fresh list — and the user is never
            // trapped on a spinner with no exit.
            Navigator.of(context).pop();
            widget.onRetry();
          },
        );
      case SelectFieldState.idle:
        final List<SelectOption<T>> filtered = _filter();
        if (filtered.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(VelvetSpacing.xl),
              child: Text(
                widget.emptyLabel,
                key: const Key('select-menu-empty'),
                style: _emptyStyle,
              ),
            ),
          );
        }
        return RepaintBoundary(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: VelvetSpacing.sm),
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final SelectOption<T> option = filtered[index];
              return _SelectOptionTile<T>(
                key: option.rowKey,
                label: option.label,
                onTap: () => Navigator.of(context).pop(option.value),
              );
            },
          ),
        );
    }
  }
}

/// A single selectable option row inside the dropdown menu.
class _SelectOptionTile<T> extends StatelessWidget {
  const _SelectOptionTile({
    super.key,
    required this.label,
    required this.onTap,
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
        child: Semantics(
          button: true,
          label: label,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: VelvetSpacing.md,
              vertical: VelvetSpacing.md,
            ),
            child: Row(
              children: <Widget>[
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
      ),
    );
  }
}

/// The optional bottom action row of the menu — a soft inset pill with a
/// leading "+" so it reads as an additive affordance, not a selectable option.
/// Used by the category menu to surface "suggest a category".
class SelectMenuActionRow extends StatelessWidget {
  const SelectMenuActionRow({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  static final TextStyle _labelStyle = VelvetText.pill();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.md,
        VelvetSpacing.xs,
        VelvetSpacing.md,
        VelvetSpacing.md,
      ),
      child: Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          child: NeumorphicInset(
            radius: VelvetRadii.field,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: VelvetSpacing.md,
                vertical: VelvetSpacing.md,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(
                    Icons.add_rounded,
                    size: 18,
                    color: BrandColors.accentDeep,
                  ),
                  const SizedBox(width: VelvetSpacing.sm),
                  Flexible(child: Text(label, style: _labelStyle)),
                ],
              ),
            ),
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
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(VelvetSpacing.xl),
      child: Column(
        key: const Key('select-menu-loading'),
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: BrandColors.accent,
            ),
          ),
          const SizedBox(height: VelvetSpacing.md),
          Text(
            l10n.loadingLabel,
            style: VelvetText.body().copyWith(color: BrandColors.muted),
          ),
        ],
      ),
    );
  }
}

class _SheetError extends StatelessWidget {
  const _SheetError({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(VelvetSpacing.xl),
      child: Column(
        key: const Key('select-menu-error'),
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Semantics(
            liveRegion: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.error_outline_rounded,
                  size: 18,
                  color: BrandColors.error,
                ),
                const SizedBox(width: VelvetSpacing.sm),
                Flexible(
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: VelvetText.feedback(BrandColors.error),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: VelvetSpacing.md),
          TextButton(
            key: const Key('select-menu-retry'),
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

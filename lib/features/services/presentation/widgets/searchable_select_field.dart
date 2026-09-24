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

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/navigation/overlay_navigation.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/util/bounded_query.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// ADDITIVE (Phase 346) — turns the menu's client-side filter into a
/// SERVER-side autocomplete.
///
/// `SearchableSelectField` was built for a bounded option list held in memory:
/// the caller resolves every option up front and the sheet narrows it with a
/// `contains` on a folded label. A 25 698-row settlement table cannot be that
/// list, so this descriptor swaps ONLY the source of the rows and leaves every
/// other behaviour — the sheet chrome, the search input, the empty state, the
/// loading and error states, the option rows, the pop-with-value contract —
/// exactly where it already is. Passing `null` (every pre-346 caller) keeps the
/// in-memory path byte-for-byte unchanged.
///
/// Why extension rather than a second searchable field: forking would give the
/// app two sheets that must be fixed twice, which is precisely what
/// REUSE-FIRST exists to stop. The three things a remote source genuinely needs
/// and an in-memory one does not are all captured here.
@immutable
class SearchableSelectSource<T> {
  const SearchableSelectSource({
    required this.debounce,
    required this.belowMinimumLabel,
    required this.isSearchable,
    required this.resolve,
    required this.onRetry,
    this.maxQueryLength,
    this.throttleCooldownOf,
  });

  /// How long the field waits after the last keystroke before it APPLIES the
  /// query — i.e. before the family key changes and a request is issued.
  ///
  /// Meaningfully longer than the in-memory path's 180 ms, because what sits
  /// behind it is a network round trip rather than a list scan.
  final Duration debounce;

  /// Shown INSTEAD of a result list when the applied query is non-blank but
  /// [isSearchable] rejects it. No request is issued in that state.
  final String belowMinimumLabel;

  /// Whether the server can serve this term at all. A blank term must return
  /// `true` — it is the pre-typing default list, not an error.
  final bool Function(String query) isSearchable;

  /// Resolves the rows for one APPLIED query. Called inside a `Consumer`, so
  /// the sheet re-renders through loading -> data/error on its own.
  final AsyncValue<List<SelectOption<T>>> Function(WidgetRef ref, String query)
  resolve;

  /// Invoked from the menu's error state. Receives the applied query so the
  /// caller can invalidate the exact family key that failed.
  final void Function(WidgetRef ref, String query) onRetry;

  /// ADDITIVE — the longest term the server accepts, or `null` for no cap.
  ///
  /// When set, the search input carries a `LengthLimitingTextInputFormatter`
  /// at this length AND the committed query is [boundSearchQuery]-ed to it, so
  /// the applied family key, the [isSearchable] check and the text the
  /// repository sends (which applies the same idempotent bound) are one and
  /// the same string.
  final int? maxQueryLength;

  /// ADDITIVE — answers "is this error a server rate limit, and if so how long
  /// must the sheet stay quiet?".
  ///
  /// Returns the cooldown for a throttle error, `null` for anything else.
  /// While a cooldown runs the sheet issues NO request (keystrokes are held,
  /// not committed), shows the error's own `Failure.userMessage` with no
  /// Retry button. When the cooldown elapses, text typed meanwhile is applied
  /// once; an UNCHANGED query is not re-issued — the Retry button returns
  /// instead. Never an automatic retry of the throttled request.
  /// `null` (the default) keeps the plain error-with-Retry behaviour.
  final Duration? Function(Object error)? throttleCooldownOf;
}

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
    this.leadingIcon,
    this.labelSuffix,
    this.optionMaxLines = 1,
    this.source,
    this.onClear,
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

  /// Additive — an optional leading glyph rendered before the field's text
  /// (before [selectedLabel]/[placeholder]), inside its own 20×20 slot with
  /// a `VelvetSpacing.sm` trailing gap. `null` (every pre-existing caller —
  /// this generic field is also used for the service-type select, which has
  /// no icon concept) renders no slot at all and lays out byte-identically
  /// to before this field existed. The only current caller is the category
  /// dropdown (an `accentDeep`-tinted category glyph from the shared
  /// `categoryIconFor` resolver), which itself passes `null` whenever
  /// nothing is selected — see that call site's doc.
  final Widget? leadingIcon;

  /// ADDITIVE — an optional inline widget appended to the RIGHT of the section
  /// [label] (an "— необов'язково" tag, a "?" tip icon). `null` (every
  /// pre-existing caller) renders the label row exactly as before: a bare
  /// `Text` with no `Row` wrapper at all, so nothing shifts by a pixel.
  final Widget? labelSuffix;

  /// ADDITIVE — how many lines ONE option row may occupy before it ellipsises.
  ///
  /// Defaults to `1`, the pre-346 rendering. The settlement picker passes `2`
  /// because its three-part disambiguating label («Миколаївка, Пищанська
  /// громада, Вінницька») is the whole point of the row and must WRAP rather
  /// than truncate — an ellipsised label would cut off exactly the segment that
  /// tells two identically-named villages apart (phase-346 D4).
  final int optionMaxLines;

  /// ADDITIVE — when non-null, the menu sources its rows from the server on a
  /// debounced query instead of filtering [options] in memory.
  ///
  /// [options] and [fieldState] are then unused by the MENU (the field's own
  /// affordance still honours [fieldState], which a remote caller leaves
  /// `idle`). See [SearchableSelectSource].
  final SearchableSelectSource<T>? source;

  /// ADDITIVE — when non-null AND something is selected, the trailing chevron
  /// becomes a tappable «×» that invokes this instead.
  ///
  /// `null` (every pre-existing caller) keeps the chevron and no clear
  /// affordance at all, which is correct for a REQUIRED field: the service-form
  /// pickers have no "no category" state to return to. A discovery FILTER does
  /// — an unset settlement is a nationwide search — so that caller passes one.
  final VoidCallback? onClear;

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
        optionMaxLines: optionMaxLines,
        source: source,
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
          child: labelSuffix == null
              ? Text(label.toUpperCase(), style: _labelStyle)
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Flexible(
                      child: Text(label.toUpperCase(), style: _labelStyle),
                    ),
                    labelSuffix!,
                  ],
                ),
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
                      if (leadingIcon != null) ...<Widget>[
                        SizedBox(width: 20, height: 20, child: leadingIcon),
                        const SizedBox(width: VelvetSpacing.sm),
                      ],
                      Expanded(
                        child: Text(
                          displayText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: displayStyle,
                        ),
                      ),
                      const SizedBox(width: VelvetSpacing.sm),
                      _FieldAffordance(
                        state: fieldState,
                        onClear: selectedLabel == null ? null : onClear,
                      ),
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
  const _FieldAffordance({required this.state, this.onClear});

  final SelectFieldState state;

  /// Non-null only when the field is clearable AND currently holds a value.
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final VoidCallback? clear = onClear;
    if (clear != null && state == SelectFieldState.idle) {
      return Semantics(
        button: true,
        child: GestureDetector(
          key: const Key('select-field-clear'),
          behavior: HitTestBehavior.opaque,
          onTap: clear,
          child: const SizedBox(
            width: 28,
            height: 28,
            child: Icon(
              Icons.close_rounded,
              size: 18,
              color: BrandColors.muted,
            ),
          ),
        ),
      );
    }
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
// can be escaped. Returns the chosen value via the overlay-dismiss helper
// (`dismissOverlay(context, value)`).
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
    required this.optionMaxLines,
    required this.source,
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
  final int optionMaxLines;
  final SearchableSelectSource<T>? source;

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
    // Anything the BODY reads off the widget invalidates the body cache
    // (see [_cachedBody]). The modal route re-creates this widget on every
    // keyboard frame with the SAME values, so on those frames nothing here
    // differs and the cache survives.
    if (!identical(oldWidget.options, widget.options) ||
        oldWidget.state != widget.state ||
        !identical(oldWidget.source, widget.source) ||
        oldWidget.optionMaxLines != widget.optionMaxLines ||
        oldWidget.emptyLabel != widget.emptyLabel ||
        oldWidget.errorLabel != widget.errorLabel ||
        oldWidget.retryLabel != widget.retryLabel ||
        oldWidget.onRetry != widget.onRetry) {
      _cachedBody = null;
    }
  }

  /// The body subtree (loading / error / empty / rows), reused as the SAME
  /// widget instance across rebuilds that cannot change it (perf N2).
  ///
  /// `showModalBottomSheet`'s page builder wraps this sheet in
  /// `MediaQuery.removePadding`, which depends on the WHOLE ambient
  /// MediaQuery, so the sheet itself is rebuilt on every frame of the
  /// keyboard animation no matter which MediaQuery aspect it reads. Handing
  /// Flutter the identical body instance on those frames makes it
  /// short-circuit the whole subtree — the Consumer, the option mapping, the
  /// rows. Cleared by every `setState` that changes what the body shows
  /// ([_commit], the cooldown's end) and by [didUpdateWidget]; the remote
  /// Consumer still rebuilds itself when its provider emits.
  Widget? _cachedBody;

  @override
  void dispose() {
    _debounce?.cancel();
    _cooldown?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  int? get _maxQueryLength => widget.source?.maxQueryLength;

  // ---- remote-path state (unused when `widget.source == null`) ------------

  /// The last option list a remote query RESOLVED to. Shown under a thin
  /// progress bar while the next query loads, so the content-sized sheet does
  /// not collapse to the spinner and grow back on every debounced query
  /// (perf M1). `null` until the first resolve — only then is the full
  /// [_SheetLoading] shown.
  List<SelectOption<T>>? _lastRemoteOptions;

  /// Running while a server rate limit is being sat out. See
  /// [SearchableSelectSource.throttleCooldownOf].
  Timer? _cooldown;

  /// The throttle error the running/finished cooldown belongs to, so a rebuild
  /// showing the SAME error never restarts the clock.
  Object? _cooldownError;

  bool get _coolingDown => _cooldown?.isActive ?? false;

  void _onSearchChanged(String raw) {
    _debounce?.cancel();
    final SearchableSelectSource<T>? source = widget.source;
    _debounce = Timer(source?.debounce ?? _kSearchDebounce, () {
      if (!mounted) return;
      // A throttled remote sheet holds the keystroke; the cooldown's end
      // commits whatever the box then holds (one request, not a burst).
      if (source != null && _coolingDown) return;
      _commit(raw);
    });
  }

  void _commit(String raw) {
    // The in-memory path matches on a FOLDED label, so it commits a folded
    // query. The remote path sends the term to a server that does its own
    // normalisation (and whose 3-gram index is built on the stored form), so
    // it commits the term trimmed but otherwise verbatim — folding it here
    // would strip the very diacritics «Кам’янка» is indexed under. With a
    // [SearchableSelectSource.maxQueryLength] it is also bounded by the same
    // function the repository applies, so key == wire text.
    final SearchableSelectSource<T>? source = widget.source;
    final int? max = _maxQueryLength;
    final String committed = source == null
        ? _fold(raw)
        : (max == null ? raw.trim() : boundSearchQuery(raw, max));
    if (committed == _query) return;
    setState(() {
      _query = committed;
      _cachedBody = null;
    });
  }

  /// Starts sitting out a rate limit. Called from the remote body's error
  /// branch during build, so it only mutates fields and arms a timer — the
  /// widget being built already renders the throttled state.
  void _startCooldown(Object error, Duration cooldown) {
    if (identical(error, _cooldownError)) return;
    _cooldownError = error;
    _cooldown?.cancel();
    _cooldown = Timer(cooldown, () {
      if (!mounted) return;
      // Re-render (the Retry affordance returns) and apply what the user
      // typed meanwhile. If that is the throttled query itself, nothing is
      // re-issued — the user decides via Retry.
      setState(() => _cachedBody = null);
      _commit(_searchController.text);
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
    // Aspect-specific reads (`sizeOf` / `viewInsetsOf`) rather than
    // `MediaQuery.of`. That alone does NOT stop the per-keyboard-frame
    // rebuild — the modal route rebuilds this sheet on every inset frame
    // regardless (see [_cachedBody]) — it only drops the dependencies this
    // build never needed. What keeps those frames cheap is the body cache.
    final maxHeight = MediaQuery.sizeOf(context).height * 0.8;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
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
                        onPressed: () => dismissOverlay(context),
                      ),
                    ],
                  ),
                ),
                // Search field — hidden while loading/error since there is no
                // list to filter; this keeps the focus on the state affordance.
                // On the REMOTE path it is always present: the query is what
                // produces the load, so hiding the input during one would trap
                // the user on a spinner they cannot steer out of.
                if (widget.source != null ||
                    widget.state == SelectFieldState.idle)
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
                      inputFormatters: _maxQueryLength == null
                          ? null
                          : <TextInputFormatter>[
                              LengthLimitingTextInputFormatter(_maxQueryLength),
                            ],
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
                Flexible(child: _cachedBody ??= _body(context)),
                if (widget.menuFooter != null) widget.menuFooter!(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final SearchableSelectSource<T>? source = widget.source;
    if (source != null) return _remoteBody(source);
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
            dismissOverlay(context);
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
        return _list(filtered);
    }
  }

  /// The three remote states, all rendered UNDER the always-present search
  /// input (see the `widget.source != null` guard on it).
  ///
  /// A non-blank query the server cannot serve short-circuits BEFORE the
  /// `Consumer`, so no provider is watched and no request is issued for a 1-2
  /// character term — the "type at least three characters" hint IS the body.
  ///
  /// Below-minimum deliberately does NOT hold the last servable query
  /// (mobile-backlog 2026-07-29, `search_filters_controller.dart:402-413`): on
  /// discovery, holding lets the applied term and the visible text diverge
  /// indefinitely — the box reads «аб» while the results are still «манікюр».
  /// Here the body always reflects the box: three-plus characters show their
  /// own matches, one or two show the hint, an empty box shows the major list.
  /// Nothing stale ever survives underneath.
  Widget _remoteBody(SearchableSelectSource<T> source) {
    if (_query.isNotEmpty && !source.isSearchable(_query)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(VelvetSpacing.xl),
          child: Text(
            source.belowMinimumLabel,
            key: const Key('select-menu-minimum'),
            textAlign: TextAlign.center,
            style: _emptyStyle,
          ),
        ),
      );
    }
    return Consumer(
      builder: (BuildContext context, WidgetRef ref, _) {
        return source
            .resolve(ref, _query)
            .when(
              loading: () {
                final List<SelectOption<T>>? previous = _lastRemoteOptions;
                if (previous == null) return const _SheetLoading();
                // Stale-while-loading (perf M1): the previous rows keep the
                // sheet's height, and a 2 dp camel bar laid OVER their top
                // edge (no layout shift) says a new answer is on its way.
                // Rows stay at full strength and tappable — dimming would
                // read as "disabled".
                return _remoteData(previous, refreshing: true);
              },
              error: (Object error, StackTrace stackTrace) {
                final Duration? cooldown = source.throttleCooldownOf?.call(
                  error,
                );
                if (cooldown != null) {
                  _startCooldown(error, cooldown);
                  return _SheetError(
                    message: error is Failure
                        ? error.userMessage(context)
                        : widget.errorLabel,
                    retryLabel: widget.retryLabel,
                    // No Retry while the limiter is closed: an action whose
                    // promise is "this will work now" is false until then.
                    onRetry: _coolingDown
                        ? null
                        : () => source.onRetry(ref, _query),
                  );
                }
                return _SheetError(
                  message: widget.errorLabel,
                  retryLabel: widget.retryLabel,
                  // Unlike the in-memory path this retry does NOT close the
                  // sheet: the query the user typed lives in the sheet's own
                  // controller, so dismissing would discard it and make them
                  // type it again to see whether the retry worked.
                  onRetry: () => source.onRetry(ref, _query),
                );
              },
              data: (List<SelectOption<T>> options) {
                _lastRemoteOptions = options;
                return _remoteData(options);
              },
            );
      },
    );
  }

  /// ONE shape for both "rows" and "rows + refreshing" (perf N4): always a
  /// `Stack` whose first child is the content, with the bar appended only
  /// while refreshing. Loading -> data therefore keeps the content's element
  /// (and the list's scroll state) instead of tearing the list down and
  /// rebuilding it on every query.
  Widget _remoteData(List<SelectOption<T>> options, {bool refreshing = false}) {
    return Stack(
      children: <Widget>[
        if (options.isNotEmpty)
          _list(options)
        else
          Center(
            child: Padding(
              padding: const EdgeInsets.all(VelvetSpacing.xl),
              child: Text(
                widget.emptyLabel,
                key: const Key('select-menu-empty'),
                style: _emptyStyle,
              ),
            ),
          ),
        if (refreshing)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            // Its own layer: the indeterminate animation repaints every
            // frame and must not drag the rows' layer along with it.
            child: RepaintBoundary(
              child: LinearProgressIndicator(
                key: Key('select-menu-refreshing'),
                minHeight: 2,
                color: BrandColors.accent,
                backgroundColor: Colors.transparent,
              ),
            ),
          ),
      ],
    );
  }

  Widget _list(List<SelectOption<T>> options) {
    return RepaintBoundary(
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: VelvetSpacing.sm),
        itemCount: options.length,
        itemBuilder: (BuildContext context, int index) {
          final SelectOption<T> option = options[index];
          return _SelectOptionTile<T>(
            key: option.rowKey,
            label: option.label,
            maxLines: widget.optionMaxLines,
            onTap: () => dismissOverlay(context, option.value),
          );
        },
      ),
    );
  }
}

/// A single selectable option row inside the dropdown menu.
class _SelectOptionTile<T> extends StatelessWidget {
  const _SelectOptionTile({
    super.key,
    required this.label,
    required this.onTap,
    this.maxLines = 1,
  });

  final String label;
  final VoidCallback onTap;

  /// Lines one row may occupy before ellipsising — see
  /// `SearchableSelectField.optionMaxLines`.
  final int maxLines;

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
                    maxLines: maxLines,
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

  /// `null` hides the Retry button (a rate-limit cooldown is running).
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final VoidCallback? retry = onRetry;
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
          if (retry != null) ...<Widget>[
            const SizedBox(height: VelvetSpacing.md),
            TextButton(
              key: const Key('select-menu-retry'),
              onPressed: retry,
              style: TextButton.styleFrom(
                foregroundColor: BrandColors.accentDeep,
              ),
              child: Text(retryLabel),
            ),
          ],
        ],
      ),
    );
  }
}

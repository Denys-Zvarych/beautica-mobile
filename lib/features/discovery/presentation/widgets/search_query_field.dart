// Phase 13.x — the shared free-text search field («Пошук майстра або послуги»).
//
// Extracted from `search_filters_screen.dart`'s private `_SearchField` (the
// pill-shaped recessed inset with a leading magnifier). Chrome —
// [NeumorphicInset] at radius 28, [VelvetSizes.field] height,
// `VelvetText.input()`, camel cursor, placeholder styling — is unchanged from
// the approved VelvetTouch treatment.
//
// SOLE HOST: the FILTERS screen. The results screen briefly hosted a second
// copy for live search; that field was removed, so free-text entry happens in
// exactly one place and `SearchFilters.query` can only ever be re-keyed from
// there.
//
// The one addition is the MIN-LENGTH ERROR: while the trimmed text sits at 1 …
// [kSearchMinQueryLength] - 1 characters the field goes into a real, blocking
// ERROR state — not a hint. It shipped as a hint (11 sp `discCaptionMuted`) and
// read as decoration: it explained nothing was happening while the keystroke was
// silently swallowed upstream, blocked nothing, and left stale results and a
// stale applied-query chip on screen.
//
// The treatment is lifted VERBATIM from the canonical in-app min-length error,
// `features/support/presentation/widgets/message_area.dart` — no new visual
// language:
//   • `NeumorphicInset(focused:, hasError:)` — the 2 dp ring flips to
//     [BrandColors.error] (#B0452F) while the term is below the minimum, and to
//     [BrandColors.accent] on focus otherwise (message_area.dart:108-110);
//   • a `Semantics(liveRegion: true)` row with a 15 sp `Icons.error_outline` and
//     the error copy in `VelvetText.feedback(BrandColors.error)`
//     (message_area.dart:150-167);
//   • BOTH an error and a muted helper style are kept and switched between
//     (message_area.dart:60-61) — the switch is exactly what this field lacked.
//
// An EMPTY box is NOT an error: searching on the locality / category / price
// facets alone is legitimate, so the error window is strictly 1 … 2 characters.
//
// INPUT IS ALSO CAPPED AT THE OTHER END (sec LOW-1): [kSearchMaxQueryLength]
// characters, control characters filtered out, counter chrome suppressed — the
// backend rejects anything longer or with an interior newline/tab with a hard
// 400 that the results screen's Retry button could only reproduce forever.
//
// The widget listens to the [TextEditingController] rather than taking the text
// as a parameter, so the helper tracks BOTH typing and programmatic changes
// («Скинути фільтри» clearing the box, the results screen's chip clearing the
// applied query through the shared draft).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/brand_colors.dart';
import '../../../../core/theme/velvet_geometry.dart';
import '../../../../core/theme/velvet_text.dart';
import '../../../../core/widgets/neumorphic.dart';
import '../../domain/search_filters.dart';

/// Pill search field (recessed inset, leading magnifier) plus the below-minimum
/// error line.
class SearchQueryField extends StatefulWidget {
  const SearchQueryField({
    super.key,
    this.fieldKey = const Key('search_query_field'),
    required this.controller,
    required this.hintText,
    required this.minLengthError,
    required this.onChanged,
  });

  /// Key placed on the inner [TextField] so widget tests can target it.
  /// Defaults to the filters screen's key, which is the only production host.
  final Key fieldKey;

  final TextEditingController controller;

  /// Placeholder copy («Пошук майстра або послуги»).
  final String hintText;

  /// Localised «Введіть щонайменше 3 символи для пошуку» ERROR copy, shown —
  /// together with the red inset ring — only while the trimmed text is 1 …
  /// [kSearchMinQueryLength] - 1 characters long.
  final String minLengthError;

  final ValueChanged<String> onChanged;

  @override
  State<SearchQueryField> createState() => _SearchQueryFieldState();
}

class _SearchQueryFieldState extends State<SearchQueryField> {
  static final TextStyle _hintStyle = VelvetText.input().copyWith(
    color: BrandColors.placeholder,
    fontWeight: FontWeight.w600,
  );

  /// Error voice for the below-minimum line — the same
  /// `VelvetText.feedback(BrandColors.error)` `MessageArea` uses
  /// (message_area.dart:60). This REPLACES the muted
  /// `VelvetText.discCaptionMuted` the line used to render in: that style is the
  /// field's helper voice (the locality rows still use it for genuinely
  /// non-blocking hints), and a hard rejection rendered in it is precisely why
  /// the state read as decoration.
  static final TextStyle _errorStyle = VelvetText.feedback(BrandColors.error);

  /// Strips every character the backend's `^[^\p{Cntrl}]*$` guard rejects.
  ///
  /// The range is Java's `\p{Cntrl}` verbatim (ASCII C0 plus DEL), so this is a
  /// strict superset of [FilteringTextInputFormatter.singleLineFormatter] — it
  /// catches a pasted interior tab as well as a newline. Built once at
  /// class-load; a `FilteringTextInputFormatter` is not const.
  static final List<TextInputFormatter> _formatters = <TextInputFormatter>[
    FilteringTextInputFormatter.deny(RegExp(r'[\x00-\x1F\x7F]')),
  ];

  /// `buildCounter` hook that renders nothing — the Material character counter
  /// would add a second line inside the fixed-height VelvetTouch pill.
  static Widget? _noCounter(
    BuildContext context, {
    required int currentLength,
    required int? maxLength,
    required bool isFocused,
  }) => null;

  /// Whether the current text is a non-empty term that is still too short for
  /// the backend to honour — i.e. the field is in its ERROR state.
  ///
  /// Derived with the shared [isBelowSearchMinimum] predicate so the ring, the
  /// error line, the controller's `setQuery` outcome and the results screen's
  /// blocking gate can never disagree about where the threshold sits.
  late bool _belowMinimum;

  final FocusNode _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _belowMinimum = isBelowSearchMinimum(widget.controller.text);
    widget.controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(SearchQueryField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
      _belowMinimum = isBelowSearchMinimum(widget.controller.text);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final bool next = isBelowSearchMinimum(widget.controller.text);
    // Rebuild only when the error state actually flips — a keystroke that does
    // not cross the threshold costs nothing.
    if (next == _belowMinimum) return;
    if (!mounted) return;
    setState(() => _belowMinimum = next);
  }

  void _onFocusChanged() {
    if (!mounted) return;
    final bool next = _focusNode.hasFocus;
    if (next == _focused) return;
    setState(() => _focused = next);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        NeumorphicInset(
          radius: 28,
          focused: _focused,
          // Red 2 dp ring while the term is below the backend minimum — the
          // canonical error affordance (message_area.dart:108-110). `hasError`
          // wins over `focused` inside NeumorphicInset, so the ring stays red
          // while the user keeps typing in the offending field.
          hasError: _belowMinimum,
          child: SizedBox(
            height: VelvetSizes.field,
            child: Row(
              children: <Widget>[
                const SizedBox(width: VelvetSpacing.md + 2),
                const Icon(
                  Icons.search_rounded,
                  color: BrandColors.muted,
                  size: 21,
                ),
                const SizedBox(width: VelvetSpacing.sm),
                Expanded(
                  child: TextField(
                    key: widget.fieldKey,
                    controller: widget.controller,
                    focusNode: _focusNode,
                    onChanged: widget.onChanged,
                    textInputAction: TextInputAction.search,
                    // Keep the term inside what the backend will accept
                    // (sec LOW-1): `@Size(max = 100)` + `^[^\p{Cntrl}]*$` on
                    // both search DTOs. A pasted 300-character string, or one
                    // carrying an interior newline/tab, otherwise reaches the
                    // wire and 400s into a ResultsError whose Retry button
                    // re-issues the identical doomed request forever. Trimming
                    // in the repository cannot save it — trim strips only the
                    // ENDS.
                    maxLength: kSearchMaxQueryLength,
                    maxLengthEnforcement: MaxLengthEnforcement.enforced,
                    // Suppress the Material character counter: it would add a
                    // second line of chrome inside the VelvetTouch pill and
                    // break its fixed [VelvetSizes.field] height.
                    buildCounter: _noCounter,
                    inputFormatters: _formatters,
                    style: VelvetText.input(),
                    cursorColor: BrandColors.accent,
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: widget.hintText,
                      hintStyle: _hintStyle,
                    ),
                  ),
                ),
                const SizedBox(width: VelvetSpacing.md),
              ],
            ),
          ),
        ),
        // Error line — icon + copy, announced to screen readers the moment it
        // appears. Structure lifted from message_area.dart:150-167; the widget
        // key is unchanged so existing targeting keeps working.
        if (_belowMinimum) ...<Widget>[
          const SizedBox(height: VelvetSpacing.sm),
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Semantics(
              liveRegion: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(
                    Icons.error_outline,
                    size: 15,
                    color: BrandColors.error,
                  ),
                  const SizedBox(width: VelvetSpacing.xs + 2),
                  Expanded(
                    child: Text(
                      widget.minLengthError,
                      key: const Key('search_query_min_length_hint'),
                      style: _errorStyle,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// Phase 13.x — the shared free-text search field («Пошук майстра або послуги»).
//
// Extracted VERBATIM from `search_filters_screen.dart`'s private `_SearchField`
// (the pill-shaped recessed inset with a leading magnifier) so the results
// screen can host the very same control for live search instead of inventing a
// second one. Chrome — [NeumorphicInset] at radius 28, [VelvetSizes.field]
// height, `VelvetText.input()`, camel cursor, placeholder styling — is unchanged
// from the approved VelvetTouch treatment.
//
// The one addition is the MIN-LENGTH HELPER: while the trimmed text sits at 1 …
// [kSearchMinQueryLength] - 1 characters the field renders a quiet line beneath
// itself explaining that the backend needs at least three. It reuses the exact
// helper treatment the locality rows already use (`VelvetText.discCaptionMuted`,
// 6 dp left inset, [VelvetSpacing.xs] gap) — no new component.
//
// INPUT IS ALSO CAPPED AT THE OTHER END (sec LOW-1): [kSearchMaxQueryLength]
// characters, control characters filtered out, counter chrome suppressed — the
// backend rejects anything longer or with an interior newline/tab with a hard
// 400 that the results screen's Retry button could only reproduce forever.
//
// The widget listens to the [TextEditingController] rather than taking the text
// as a parameter, so the helper tracks BOTH typing and programmatic changes
// («Скинути фільтри» clearing the box, a query applied from the results screen).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/brand_colors.dart';
import '../../../../core/theme/velvet_geometry.dart';
import '../../../../core/theme/velvet_text.dart';
import '../../../../core/widgets/neumorphic.dart';
import '../../domain/search_filters.dart';

/// Pill search field (recessed inset, leading magnifier) plus the below-minimum
/// helper line.
class SearchQueryField extends StatefulWidget {
  const SearchQueryField({
    super.key,
    this.fieldKey = const Key('search_query_field'),
    required this.controller,
    required this.hintText,
    required this.minLengthHint,
    required this.onChanged,
  });

  /// Key placed on the inner [TextField] — distinct per host screen so widget
  /// tests can target the right one. Defaults to the filters screen's key.
  final Key fieldKey;

  final TextEditingController controller;

  /// Placeholder copy («Пошук майстра або послуги»).
  final String hintText;

  /// Localised «Введіть щонайменше 3 символи» helper, shown only while the
  /// trimmed text is 1 … [kSearchMinQueryLength] - 1 characters long.
  final String minLengthHint;

  final ValueChanged<String> onChanged;

  @override
  State<SearchQueryField> createState() => _SearchQueryFieldState();
}

class _SearchQueryFieldState extends State<SearchQueryField> {
  static final TextStyle _hintStyle = VelvetText.input().copyWith(
    color: BrandColors.placeholder,
    fontWeight: FontWeight.w600,
  );
  static final TextStyle _helperStyle = VelvetText.discCaptionMuted;

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
  /// the backend to honour.
  late bool _belowMinimum;

  static bool _isBelowMinimum(String raw) {
    final int length = raw.trim().length;
    return length > 0 && length < kSearchMinQueryLength;
  }

  @override
  void initState() {
    super.initState();
    _belowMinimum = _isBelowMinimum(widget.controller.text);
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(SearchQueryField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
      _belowMinimum = _isBelowMinimum(widget.controller.text);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final bool next = _isBelowMinimum(widget.controller.text);
    // Rebuild only when the helper's visibility actually flips — a keystroke
    // that does not cross the threshold costs nothing.
    if (next == _belowMinimum) return;
    if (!mounted) return;
    setState(() => _belowMinimum = next);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        NeumorphicInset(
          radius: 28,
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
        if (_belowMinimum) ...<Widget>[
          const SizedBox(height: VelvetSpacing.xs),
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Text(
              widget.minLengthHint,
              key: const Key('search_query_min_length_hint'),
              style: _helperStyle,
            ),
          ),
        ],
      ],
    );
  }
}

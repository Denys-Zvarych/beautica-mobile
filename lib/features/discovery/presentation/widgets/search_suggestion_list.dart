// Phase 352 D6/D8 — the suggestion list rendered inline under `SearchQueryField`,
// above «Локація» (`search_filters_screen.dart`). No overlay: there is nothing
// in `lib/` to reuse for one, and an overlay would fight the screen's staggered
// `ListView` + keyboard insets (D6).
//
// Rows reuse the SHARED [SelectOptionTile] (promoted, Phase 352 D8) — the same
// tile the category/service-type sheets render. CATEGORY and SERVICE rows look
// identical (no leading glyph): a SERVICE label is self-describing
// («Нарощення нігтів»).

import 'package:flutter/material.dart';

import '../../../../core/theme/velvet_geometry.dart';
import '../../../../core/widgets/neumorphic.dart';
import '../../../services/presentation/widgets/select_option_tile.dart';
import '../../domain/search_suggestion.dart';

/// The «Пошук» suggestion list. Renders nothing when [suggestions] is empty
/// (Phase 352 D7 — hidden, never an empty-state message: free text still
/// matches master/service names the suggestion catalogue doesn't cover, so
/// "nothing found" here would be false).
class SearchSuggestionList extends StatelessWidget {
  const SearchSuggestionList({
    super.key,
    required this.suggestions,
    required this.onPick,
  });

  /// Rows to render, already ranked and capped by the caller.
  final List<SearchSuggestion> suggestions;

  /// Invoked with the tapped suggestion.
  final ValueChanged<SearchSuggestion> onPick;

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) return const SizedBox.shrink();
    return NeumorphicCard(
      key: const Key('search_suggestion_list'),
      padding: EdgeInsets.zero,
      radius: VelvetRadii.field,
      clipContent: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final SearchSuggestion suggestion in suggestions)
            SelectOptionTile(
              key: Key('search_suggestion_${_rowId(suggestion)}'),
              label: suggestion.label,
              onTap: () => onPick(suggestion),
            ),
        ],
      ),
    );
  }

  /// A stable, content-derived row key: `category_<key>` or
  /// `service_<slug>` — unique within one suggestion list (the backend/local
  /// matcher never emit the same category or slug twice, D4's "duplicate-label
  /// SERVICE dropped" rule).
  static String _rowId(SearchSuggestion s) => switch (s.type) {
    SearchSuggestionType.category => 'category_${s.categoryKey}',
    SearchSuggestionType.service => 'service_${s.serviceTypeSlug}',
  };
}

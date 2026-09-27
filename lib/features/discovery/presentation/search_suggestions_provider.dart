// Phase 352 D2/D3/D9 — the debounced, place-keyed suggestion pipeline behind
// the «Пошук» suggestion list.
//
// Every keystroke re-runs [SearchSuggestions.build] (it watches the query
// DRAFT — `searchQueryDraftControllerProvider`, written on every keystroke
// with no debounce — and the filters' `cityId`/`districtId`). What is shown
// depends on whether a place is chosen (D2):
//
//   - NATIONAL (no place): instant CATEGORY rows from `approvedCategoriesProvider`
//     via the local matcher [matchSearchSuggestions], replaced by the
//     server's answer [kSearchSuggestionDebounce] after the LAST keystroke of
//     a settled term. A network error / 429 leaves the local rows in place —
//     no error UI, the list is a convenience.
//   - PLACE CHOSEN: no local rows at all — showing a category with no master
//     in this place, then retracting it, is exactly the false-hope flicker
//     Open Q2 exists to remove. The list is empty until the server answers;
//     an error clears it to empty too.
//
// A response is applied only when its request key — [SuggestionCacheKey],
// `(foldedTerm, cityId, districtId)` — still equals the CURRENT key: a late
// answer for an old term or an old place is silently discarded (the stale
// guard). Changing the place while the list is open re-keys and re-fetches;
// switching BACK to an already-answered place is an [LruCache] hit — instant,
// zero requests.
//
// Riverpod plumbing note: this is a synchronous `Notifier<List<SearchSuggestion>>`,
// not an `AsyncNotifier` — there is deliberately no loading/error state to
// surface (D7); `state` only ever holds "what to render right now", including
// mid-flight instant/provisional rows.

import 'dart:async';

import 'package:dio/dio.dart' show CancelToken, DioException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/cache/lru_cache.dart';
import '../../../shared/util/search_fold.dart';
import '../../services/data/service_repository.dart'
    show approvedCategoriesProvider;
import '../../services/domain/service_category_option.dart';
import '../data/search_suggestion_cache_provider.dart';
import '../data/search_suggestion_repository.dart';
import '../domain/search_filters.dart';
import '../domain/search_suggestion.dart';
import '../domain/search_suggestions.dart';
import 'state/search_filters_controller.dart';

part 'search_suggestions_provider.g.dart';

/// Debounce between the last keystroke (or place change) and the
/// request/refetch (Phase 352 D9) — the same value as Phase 347's
/// `kSettlementSearchDebounce`; a separate constant because it is a separate
/// concern.
const Duration kSearchSuggestionDebounce = Duration(milliseconds: 200);

/// The suggestion rows to render under the search field right now. Empty
/// means "render nothing" (D7) — see the file header for the national vs.
/// place-chosen behaviour.
@Riverpod(keepAlive: true)
class SearchSuggestions extends _$SearchSuggestions {
  Timer? _debounce;

  /// Cancels whatever server fetch is currently pending (Timer-delayed or
  /// already in flight) — mobile-perf LOW cycle-1 fix. Superseded on every
  /// new [_scheduleFetch] call and on dispose, so an outdated request never
  /// runs to completion after its answer can no longer be applied; the stale
  /// guard in [_scheduleFetch]'s callback still stays (a response that lands
  /// in the tiny window before cancellation is observed must still be
  /// discarded by key, not just by cancellation).
  CancelToken? _cancelToken;

  /// The key [build] last resolved — `null` only before the first non-empty
  /// term. Used both to detect "nothing suggestion-relevant changed" (a
  /// rebuild triggered by, say, `approvedCategoriesProvider` resolving) and
  /// as the stale-response guard inside [_scheduleFetch].
  SuggestionCacheKey? _currentKey;

  /// What [build] last returned — read back instead of the notifier's own
  /// `state` getter so `_resolve`'s "nothing changed" branch never depends on
  /// `state` having been assigned yet.
  List<SearchSuggestion> _rows = const <SearchSuggestion>[];

  /// Folded display-name labels for [_memoCategories], recomputed only when
  /// the categories list's IDENTITY changes across `build()` reruns
  /// (mobile-perf LOW cycle-1 fix) — `approvedCategoriesProvider` hands back
  /// the SAME list instance until the catalogue itself changes, so this is a
  /// true per-build memo, not a per-key one: it survives every keystroke, not
  /// just a repeated key.
  List<ServiceCategoryOption>? _memoCategories;
  List<String> _memoFoldedLabels = const <String>[];

  /// Returns [_memoFoldedLabels] for [categories], recomputing (once) only
  /// when [categories] is a different list instance than last time — the ONE
  /// place either the exact-match check below or [matchSearchSuggestions]
  /// folds a category label, instead of each folding it separately every
  /// build.
  List<String> _foldedLabelsFor(List<ServiceCategoryOption> categories) {
    if (identical(categories, _memoCategories)) return _memoFoldedLabels;
    _memoCategories = categories;
    _memoFoldedLabels = <String>[
      for (final ServiceCategoryOption c in categories)
        foldSearchLabel(c.displayName),
    ];
    return _memoFoldedLabels;
  }

  @override
  List<SearchSuggestion> build() {
    ref.onDispose(() {
      _debounce?.cancel();
      _cancelToken?.cancel();
    });

    final String draft = ref.watch(searchQueryDraftControllerProvider);
    final ({String? cityId, String? districtId}) place = ref.watch(
      searchFiltersControllerProvider.select(
        (SearchFilters f) => (cityId: f.cityId, districtId: f.districtId),
      ),
    );
    final List<ServiceCategoryOption> categories =
        ref.watch(approvedCategoriesProvider).value ??
        const <ServiceCategoryOption>[];

    _rows = _resolve(draft, place.cityId, place.districtId, categories);
    return _rows;
  }

  List<SearchSuggestion> _resolve(
    String draft,
    String? cityId,
    String? districtId,
    List<ServiceCategoryOption> categories,
  ) {
    final String folded = foldSearchLabel(draft);

    // D7 — an empty box shows nothing; no request, no debounce armed.
    if (folded.isEmpty) {
      _debounce?.cancel();
      _cancelToken?.cancel();
      _currentKey = null;
      return const <SearchSuggestion>[];
    }

    // D7 — the folded text equals a CATEGORY suggestion exactly (typically
    // right after a CATEGORY tap, which writes the label verbatim into the
    // field) → hidden, no request. Checked before the key/cache path so a
    // tap never flashes a one-frame list of its own suggestion.
    final List<String> foldedLabels = _foldedLabelsFor(categories);
    for (int i = 0; i < categories.length; i++) {
      if (foldedLabels[i] == folded) {
        _debounce?.cancel();
        _cancelToken?.cancel();
        _currentKey = null;
        return const <SearchSuggestion>[];
      }
    }

    final SuggestionCacheKey key = (folded, cityId, districtId);
    if (key == _currentKey) {
      // Rebuilt for a reason unrelated to the suggestion key itself (e.g.
      // `approvedCategoriesProvider` resolving after the request was already
      // scheduled) — the in-flight/settled rows for this key are unaffected.
      return _rows;
    }
    _debounce?.cancel();
    _currentKey = key;

    final LruCache<SuggestionCacheKey, List<SearchSuggestion>> cache = ref.read(
      searchSuggestionCacheProvider,
    );
    final List<SearchSuggestion>? cached = cache.get(key);
    if (cached != null) return cached;

    final bool national = cityId == null && districtId == null;
    // D2 — instant local CATEGORY rows only when no place is chosen; a place
    // is scoped server-side only, so nothing local can be trusted for it.
    // Reuses the same [foldedLabels] the exact-match check above already
    // computed — see [_foldedLabelsFor]'s doc.
    final List<SearchSuggestion> instant = national
        ? matchSearchSuggestions(draft, categories, foldedLabels: foldedLabels)
        : const <SearchSuggestion>[];

    _scheduleFetch(key, draft, cityId, districtId, national: national);
    return instant;
  }

  void _scheduleFetch(
    SuggestionCacheKey key,
    String term,
    String? cityId,
    String? districtId, {
    required bool national,
  }) {
    // Supersede (mobile-perf LOW cycle-1 fix): a new key always outdates
    // whatever fetch belonged to the previous one — Timer-delayed OR already
    // in flight. Cancelling here (not just the Timer below) stops a
    // superseded HTTP request from running to completion after its answer
    // can no longer be applied.
    _cancelToken?.cancel();
    final CancelToken cancelToken = CancelToken();
    _cancelToken = cancelToken;

    _debounce = Timer(kSearchSuggestionDebounce, () async {
      if (!ref.mounted) return;
      try {
        final List<SearchSuggestion> rows = await ref
            .read(searchSuggestionRepositoryProvider)
            .fetch(
              term: term,
              cityId: cityId,
              districtId: districtId,
              cancelToken: cancelToken,
            );
        // Stale guard: a late answer for an old term or an old place is
        // discarded — the CURRENT key has already moved on.
        if (!ref.mounted || key != _currentKey) return;
        ref.read(searchSuggestionCacheProvider).put(key, rows);
        _rows = rows;
        state = rows;
      } on DioException catch (e) {
        // A cancellation is never an error — it means a NEWER fetch already
        // took over (see above). Nothing to apply, nothing to clear: the
        // newer fetch owns rendering the list from here.
        if (CancelToken.isCancel(e)) return;
        if (!ref.mounted || key != _currentKey) return;
        if (!national) {
          _rows = const <SearchSuggestion>[];
          state = const <SearchSuggestion>[];
        }
      } catch (_) {
        if (!ref.mounted || key != _currentKey) return;
        // D2 fallback — national: keep the local rows already on screen
        // (nothing to do here); place chosen: no verified rows exist, so
        // show nothing. Neither case surfaces an error — the list is a
        // convenience and «Показати майстрів» still works regardless.
        if (!national) {
          _rows = const <SearchSuggestion>[];
          state = const <SearchSuggestion>[];
        }
      }
    });
  }
}

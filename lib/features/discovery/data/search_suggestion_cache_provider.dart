// Phase 352 D3 — the «Пошук» suggestion list's session-lifetime LRU, split
// into its OWN file (mobile-security MEDIUM + mobile-perf HIGH, cycle-1 fix,
// 2026-09-26) so `auth_notifier.dart`'s [logout] can `clear()` it directly —
// the same way it already clears `settlementSearchCacheProvider`
// (`location_providers.dart`) — WITHOUT importing
// `search_suggestions_provider.dart`, which pulls in
// `search_filters_controller.dart`, which itself imports `auth_notifier.dart`
// (a genuine import cycle the split avoids). This file and its dependencies
// (`core/cache/lru_cache.dart`, the domain `SearchSuggestion`) touch nothing
// auth-shaped, mirroring why `settlementSearchCacheProvider`'s own file is
// safe for `auth_notifier.dart` to import.
//
// Was previously declared inline in `search_suggestions_provider.dart`
// (Phase 352 D2/D3/D9); moved here verbatim — the type, the provider, and its
// doc comments are unchanged, so every existing caller/import of
// `searchSuggestionCacheProvider` (re-exported by
// `search_suggestions_provider.dart`) keeps working.
//
// Pure Dart + Riverpod only: no Flutter imports in this file.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/cache/lru_cache.dart';
import '../domain/search_suggestion.dart';

part 'search_suggestion_cache_provider.g.dart';

/// The suggestion request key: the folded typed term plus the chosen place.
/// Both the [LruCache] key AND the "is this response still current"
/// comparison (Phase 352 D2/D3). Records compare by value, so two keys built
/// from equal fields are the same map entry / the same "still current" check.
typedef SuggestionCacheKey = (
  String foldedTerm,
  String? cityId,
  String? districtId,
);

/// Session-lifetime LRU of settled suggestion answers (Phase 352 D3). 64
/// entries is enough for a session that typically uses one or two places —
/// the key carries the place, so switching back to an earlier one is a hit
/// and switching to a new one never serves a different place's rows.
///
/// Cleared on [AuthNotifier.logout] (mobile-security, 2026-09-26) — like
/// `settlementSearchCacheProvider`, this is a `keepAlive` cache keyed by what
/// the user TYPED (plus the chosen place) and watches nothing, so nothing in
/// the auth cascade reaches it on its own.
@Riverpod(keepAlive: true)
LruCache<SuggestionCacheKey, List<SearchSuggestion>> searchSuggestionCache(
  Ref ref,
) => LruCache<SuggestionCacheKey, List<SearchSuggestion>>(64);

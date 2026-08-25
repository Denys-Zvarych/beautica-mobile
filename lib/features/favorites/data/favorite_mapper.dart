// Phase 111 — `FavoriteMasterResponse` / `FavoriteSalonResponse` → [FavoriteItem].
//
// ── THE `?? ''` DEFECT THIS FILE EXISTS TO NOT REPEAT ───────────────────────
//
// `booking_mapper.dart:119` maps a nullable wire id with `masterId: dto.masterId
// ?? ''`. That is lenient in the worst possible way: it does not fail, it
// SUCCEEDS into a card that looks entirely normal and navigates to
// `/masters/` — a path go_router resolves to its "page not found" page. The
// backlog row filed against `favorite_masters_card.dart:113` names this file
// by anticipation: "whoever writes the favourites mapper MUST drop-or-throw on
// an empty masterId rather than repeating `?? ''`".
//
// **This mapper DROPS.** Both options satisfy the rule; drop is the right one
// for a LIST surface. Throwing turns one malformed row into an error screen
// that hides the fifteen good favourites beside it, and there is no user action
// that fixes it — the client cannot repair a server projection. Dropping loses
// exactly the row that was already unusable (an id-less card cannot navigate,
// and cannot be unfavourited either — `DELETE /favorites` is keyed on
// targetId), keeps every actionable row, and logs the discrepancy in debug so
// the cause is visible to us rather than to the client. The count difference is
// never surfaced as a number anywhere, so a dropped row cannot make the screen
// contradict itself.
//
// ── WHO SANITIZES WHAT ──────────────────────────────────────────────────────
//
// Everything provider-authored — name, salon name, city and district labels,
// the category LABEL AND the location note — is run through
// `sanitizeDisplayText` HERE.
//
// `street`, `buildingNo` and each category's `code` are the exceptions, and
// the reason is narrow in each case. `street`/`buildingNo` are never rendered
// on their own: both are composed by `buildStreetLine`
// (`shared/formatters/address_lines.dart:92`), which sanitizes them itself, so
// repeating it here would duplicate an invariant the composer already owns.
// A category's `code` is never rendered at all — `FavoriteChoice.from`
// (`favorites_filter.dart`) uses it only for equality and chip selection — so
// it is only trimmed (`_idOrNull`), the same treatment as `masterId`/
// `salonId`, not sanitized for display. See `_categoriesFromDto` for the
// both-or-neither rule each pair follows, and the defensive dedupe-by-id.
//
// `locationNote` is NOT in that group, and an earlier revision of this header
// claimed it was. It is wrong: `buildStreetLine(street, buildingNo)` never
// receives the note. The favourites cards compose the street line and then
// pass the note SEPARATELY to `ResultAddressBlock.note`
// (`favorite_cards.dart:530`, `:657`), which renders it with a bare
// `Text(note)` (`result_address_block.dart:164`) and reads it into the card's
// TTS label (`favorite_cards.dart:632`). Every OTHER surface in the app puts a
// provider note through `ExpandableNote`, which sanitizes internally
// (`expandable_note.dart:106`); `ResultAddressBlock` never had to, because
// until Phase 111 it never received prose. The backend validates the note with
// `@Size(max = 1000)` and nothing else — no character class — so a lone U+202E
// would reorder rendered address text on a list every client scrolls.
//
// So: **this mapper owns `locationNote` sanitization, because no composer
// downstream does.** `_visibleOrNull` also drops a whitespace-only note, which
// would otherwise claim a rendered row plus its 3dp gap and show nothing.

import 'dart:developer';

import 'package:beautica_api/beautica_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:flutter/foundation.dart';

import 'package:beautica_mobile/shared/util/sanitize_display_text.dart';

import '../domain/favorite_item.dart';

/// Maps the generated favourites DTOs onto the domain [FavoriteItem].
abstract final class FavoriteMapper {
  static const String _tag = 'feature.favorites.mapper';

  /// Maps a page of favourited masters, dropping any row with no usable id.
  static List<FavoriteItem> mastersFromDtoList(
    BuiltList<FavoriteMasterResponse> rows,
  ) {
    final List<FavoriteItem> out = <FavoriteItem>[];
    for (final FavoriteMasterResponse dto in rows) {
      final FavoriteItem? item = _masterFromDto(dto);
      if (item != null) out.add(item);
    }
    return out;
  }

  /// Maps a page of favourited salons, dropping any row with no usable id.
  static List<FavoriteItem> salonsFromDtoList(
    BuiltList<FavoriteSalonResponse> rows,
  ) {
    final List<FavoriteItem> out = <FavoriteItem>[];
    for (final FavoriteSalonResponse dto in rows) {
      final FavoriteItem? item = _salonFromDto(dto);
      if (item != null) out.add(item);
    }
    return out;
  }

  /// Returns null — and logs — when [dto] carries no usable `masterId`.
  static FavoriteItem? _masterFromDto(FavoriteMasterResponse dto) {
    final String? id = _idOrNull(dto.masterId);
    if (id == null) {
      _logDroppedRow('master');
      return null;
    }
    final String name = _joinName(dto.firstName, dto.lastName);
    return FavoriteItem(
      id: id,
      kind: FavoriteKind.master,
      name: name,
      initials: initialsOf(name),
      rating: _ratingOrNull(dto.avgRating),
      // Provider-authored — sanitized, matching every other display string in
      // this method. `salonName` is what draws `_AffiliationLine`; it is NOT
      // used to derive `salonId`/navigation (out of scope for this render).
      salonName: _visibleOrNull(dto.salonName),
      categories: _categoriesFromDto(dto.categories),
      cityLabel: _visibleOrNull(dto.cityLabel),
      districtLabel: _visibleOrNull(dto.districtLabel),
      // For a salon-affiliated master (since backend `ca2c98a`), these are the
      // EMPLOYING SALON's street/buildingNo/locationNote, not the person's
      // own — the client renders them as-is; see `FavoriteMasterCard`.
      street: dto.street,
      buildingNo: dto.buildingNo,
      locationNote: _visibleOrNull(dto.locationNote),
    );
  }

  /// Returns null — and logs — when [dto] carries no usable `salonId`.
  static FavoriteItem? _salonFromDto(FavoriteSalonResponse dto) {
    final String? id = _idOrNull(dto.salonId);
    if (id == null) {
      _logDroppedRow('salon');
      return null;
    }
    final String name = _visibleOrNull(dto.name) ?? '';
    return FavoriteItem(
      id: id,
      kind: FavoriteKind.salon,
      name: name,
      initials: initialsOf(name),
      rating: _ratingOrNull(dto.avgRating),
      categories: _categoriesFromDto(dto.categories),
      cityLabel: _visibleOrNull(dto.cityLabel),
      districtLabel: _visibleOrNull(dto.districtLabel),
      street: dto.street,
      buildingNo: dto.buildingNo,
      locationNote: _visibleOrNull(dto.locationNote),
    );
  }

  /// The id, or null when absent / blank / whitespace-only.
  ///
  /// Trimmed BEFORE the emptiness test: a `'   '` id is exactly as unusable in
  /// a route as `''` is, and would otherwise sail through an `isNotEmpty`
  /// check and produce the same dead card.
  static String? _idOrNull(String? raw) {
    if (raw == null) return null;
    final String trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Every distinct, both-or-neither `(code, label)` pair in [raw], deduped
  /// by id and kept in first-seen (wire) order.
  ///
  /// `code` is a server enum-ish token (`MANICURE`) used only for
  /// equality/selection — trimmed like an id via [_idOrNull], never sanitized
  /// for display since it is never displayed. `label` is provider/admin-
  /// authored Ukrainian text that IS rendered on the filter chip, so it goes
  /// through [_visibleOrNull].
  ///
  /// `FavoriteChoice.from` (`favorites_filter.dart`) requires both a non-null
  /// id AND a non-empty label to produce a chip a client can both select and
  /// read. An element carrying one without the other — code with no label, or
  /// a label with no code — cannot satisfy that, so it is dropped rather than
  /// leaking a half-formed entry that would be either unselectable or
  /// unreadable. Deduped defensively in case the server ever repeats a code:
  /// the chip set (and this list) are keyed by id, so a repeat would otherwise
  /// build two identical chips racing for the same `Key`.
  static List<FavoriteCategory> _categoriesFromDto(
    BuiltList<FavoriteCategoryView>? raw,
  ) {
    if (raw == null || raw.isEmpty) return const <FavoriteCategory>[];
    final Map<String, FavoriteCategory> byId = <String, FavoriteCategory>{};
    for (final FavoriteCategoryView view in raw) {
      final String? id = _idOrNull(view.code);
      final String? label = _visibleOrNull(view.label);
      if (id == null || label == null) continue;
      byId.putIfAbsent(id, () => FavoriteCategory(id: id, label: label));
    }
    return List<FavoriteCategory>.unmodifiable(byId.values);
  }

  /// A provider-authored display string, sanitized and trimmed, or null when it
  /// reduces to nothing.
  ///
  /// Sanitize-then-test, matching `address_lines.dart`'s `_visibleOrNull`: a
  /// field made entirely of characters `sanitizeDisplayText` strips (a lone
  /// U+200B, say) is `isNotEmpty` before sanitization and empty after it, so
  /// testing first would let it claim a rendered line that shows nothing.
  static String? _visibleOrNull(String? raw) {
    if (raw == null) return null;
    final String clean = sanitizeDisplayText(raw).trim();
    return clean.isEmpty ? null : clean;
  }

  /// «Марта Гончар» from the two name halves, either of which may be absent.
  static String _joinName(String? first, String? last) =>
      <String>[?_visibleOrNull(first), ?_visibleOrNull(last)].join(' ');

  /// A backend `0.00` means "no reviews yet", never "rated zero" — folded to
  /// null so the card draws `★ –` rather than libelling the provider with a
  /// `0.0` beside a star.
  static double? _ratingOrNull(double? raw) {
    if (raw == null || raw <= 0) return null;
    return raw;
  }

  /// Up to two initials for the portrait disc — the first letter of the first
  /// two whitespace-separated words. Empty when [name] yields none, which the
  /// disc renders as a bare camel circle rather than a placeholder glyph.
  ///
  /// Visible for testing: the mark is the master card's only identity cue when
  /// no avatar is loaded, so its degenerate cases (one word, empty, punctuation
  /// only) are worth pinning directly.
  @visibleForTesting
  static String initialsOf(String name) {
    final List<String> words = name
        .split(' ')
        .where((String w) => w.isNotEmpty)
        .toList(growable: false);
    if (words.isEmpty) return '';
    if (words.length == 1) return _firstGrapheme(words.first);
    return '${_firstGrapheme(words[0])}${_firstGrapheme(words[1])}';
  }

  /// The first code POINT of [word].
  ///
  /// `runes.first`, not `substring(0, 1)`: the latter slices UTF-16 code units
  /// and would hand back half a surrogate pair as an unrenderable replacement
  /// glyph. Ukrainian is BMP so the two agree on every seed row — which is
  /// exactly why the wrong one would never have been caught here.
  ///
  /// Not full grapheme-cluster segmentation (that would need
  /// `package:characters`, which this package does not depend on): a base
  /// letter followed by a combining mark still yields the base alone. For a
  /// two-letter monogram that is the right answer anyway — a stray diacritic
  /// floating over an initial would be worse than its absence.
  static String _firstGrapheme(String word) =>
      word.isEmpty ? '' : String.fromCharCode(word.runes.first);

  static void _logDroppedRow(String kind) {
    if (kDebugMode) {
      log(
        'dropped a favourite $kind row with a blank id — it would have built a '
        'card navigating to go_router "page not found"',
        name: _tag,
        level: 900,
      );
    }
  }
}

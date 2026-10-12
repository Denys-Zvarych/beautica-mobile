// Phase 403 (9.8, D1) — the ONE portfolio photo mapper.
//
// PROMOTED from `features/salon/data/salon_mapper.dart`
// (`SalonPortfolioMapper`) — moved and renamed, never copied. Every portfolio
// read (salon or master) and every upload answer goes through it.
//
// Logs never carry the id or URL — only that an entry was dropped.

import 'dart:developer';

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/media/portfolio/portfolio_photo.dart';

/// Maps backend `MediaFileResponse` portfolio entries to [PortfolioPhoto].
abstract final class PortfolioPhotoMapper {
  static const String _tag = 'core.media.portfolio';

  /// Entries with a null/empty `id` or `url` are dropped (logged) rather than
  /// thrown — one broken photo must not blank the whole portfolio rail.
  static List<PortfolioPhoto> fromDtoList(Iterable<MediaFileResponse> dtos) {
    final List<PortfolioPhoto> out = <PortfolioPhoto>[];
    for (final MediaFileResponse dto in dtos) {
      final PortfolioPhoto? photo = _photo(dto.id, dto.url);
      if (photo == null) {
        _logDropped();
        continue;
      }
      out.add(photo);
    }
    return out;
  }

  /// Maps the raw `data` object of an upload answer
  /// (`ApiResponse<MediaFileResponse>`, read by the hand-written multipart
  /// path). `null` when [data] is not a map or lacks a usable `id`/`url`.
  static PortfolioPhoto? fromJson(Object? data) {
    if (data is! Map) return null;
    final Object? id = data['id'];
    final Object? url = data['url'];
    return _photo(id is String ? id : null, url is String ? url : null);
  }

  static PortfolioPhoto? _photo(String? id, String? url) {
    if (id == null || id.isEmpty || url == null || url.isEmpty) return null;
    return PortfolioPhoto(id: id, url: url);
  }

  static void _logDropped() => log(
    'MediaFileResponse missing id/url — dropping portfolio entry',
    name: _tag,
    level: 900,
  );
}

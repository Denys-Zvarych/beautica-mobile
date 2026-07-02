// Phase 13.6 follow-up — Salon portfolio photo domain model.
//
// Backing the "Про салон" tab's real photo rail. Loaded from
// `GET /salons/{salonId}/portfolio` (public, unauthenticated, `permitAll` —
// `MediaController.java`, `MediaService.getPortfolio`, Phase 7.7 backend).
// Deliberately NOT the full generated `MediaFileResponse` (entityType/
// mediaType/createdAt are backend bookkeeping the rail never renders) — only
// the two fields the tile actually needs.
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'salon_portfolio_photo.freezed.dart';

/// One photo in a salon's public portfolio gallery.
@freezed
abstract class SalonPortfolioPhoto with _$SalonPortfolioPhoto {
  const factory SalonPortfolioPhoto({required String id, required String url}) =
      _SalonPortfolioPhoto;
}

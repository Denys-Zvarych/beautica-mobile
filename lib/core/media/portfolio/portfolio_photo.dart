// Phase 403 (9.8, D1) — the ONE portfolio photo domain model.
//
// PROMOTED from `features/salon/domain/salon_portfolio_photo.dart`
// (`SalonPortfolioPhoto`, Phase 13.6 follow-up) — moved and renamed, never
// copied: the salon «Про салон» rail and the independent master's portfolio
// share this type.
//
// Loaded from `GET /salons/{salonId}/portfolio` or
// `GET /masters/{masterId}/portfolio` (public, `permitAll`), and returned by
// the portfolio upload endpoints. Deliberately NOT the full generated
// `MediaFileResponse` (entityType/mediaType/createdAt are backend bookkeeping
// the rail never renders) — only the two fields a tile actually needs.
//
// `toString()` is hand-redacted (`toStringOverride: false`): the object URL
// carries the R2 key, and an instance in an error message or a log line must
// never print it.
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'portfolio_photo.freezed.dart';

/// One photo in a salon's or an independent master's portfolio.
@Freezed(toStringOverride: false)
abstract class PortfolioPhoto with _$PortfolioPhoto {
  const factory PortfolioPhoto({required String id, required String url}) =
      _PortfolioPhoto;

  const PortfolioPhoto._();

  @override
  String toString() => 'PortfolioPhoto(<redacted>)';
}

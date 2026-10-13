// Phase 403 (9.8, D2) — whose portfolio a read / upload / delete targets.
//
// LOCKED PRODUCT RULE (user, 2026-10-12): "salon photos only related to the
// salon, not owner or admin or masters".
//   • [PortfolioOwner.salon] — the SALON's photos. Built ONLY on salon screens
//     (salon management «Про салон», the public salon profile). Any salon
//     manager (owner, or the admin bound to that salon) may add or delete any
//     of them, whoever uploaded it.
//   • [PortfolioOwner.masterSelf] — an INDEPENDENT_MASTER's own portfolio.
//     Built ONLY where the master is `MasterType.independentMaster`; owners
//     and admins have NO personal portfolio (O4). Writes are self-only — the
//     backend resolves the master from the JWT — so [masterId] is used for the
//     read path and as the cache key only.
//
// D9: both constructors' call sites are pinned by
// `test/core/media/portfolio/portfolio_owner_call_sites_test.dart`, so a
// salon photo can never leak onto a master profile (or vice versa) without a
// red test. Construct a variant only through the named factories.
//
// `toString()` is hand-redacted (`toStringOverride: false`, like
// `PortfolioPhoto`): Riverpod copies a family argument's `toString()` into
// provider names and error messages, and the id must never reach either.
// Equality / hashCode stay generated and VALUE-based — family keys depend on
// them.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'portfolio_owner.freezed.dart';

/// The owner of a portfolio. Value-equal, so it keys provider families.
@Freezed(toStringOverride: false)
sealed class PortfolioOwner with _$PortfolioOwner {
  /// An INDEPENDENT_MASTER's portfolio. Written only by that master (self,
  /// JWT-resolved) from their own profile; read by [masterId] both there and
  /// on their public profile (phase 404 D2 — one family entry, one cache).
  /// Never built for a salon owner or salon master.
  ///
  /// Does NOT authorise writes for a VIEWED master: the public profile builds
  /// it with another master's id purely to read (and share the cache entry).
  /// Every write is resolved server-side from the caller's JWT, so a write
  /// wired there would hit the VIEWER's own portfolio while the cache showed
  /// the viewed master's list. Writes belong only on the master's own
  /// profile; pinned by `portfolio_owner_call_sites_test.dart` (R4).
  const factory PortfolioOwner.masterSelf(String masterId) =
      PortfolioOwnerMasterSelf;

  /// Salon [salonId]'s portfolio.
  const factory PortfolioOwner.salon(String salonId) = PortfolioOwnerSalon;

  const PortfolioOwner._();

  @override
  String toString() => switch (this) {
    PortfolioOwnerSalon() => 'PortfolioOwner.salon(<redacted>)',
    PortfolioOwnerMasterSelf() => 'PortfolioOwner.masterSelf(<redacted>)',
  };
}

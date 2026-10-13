// Phase 403 (9.8, D3) — the ONE portfolio read provider, for a salon and for
// an independent master alike.
//
// `portfolioProvider(PortfolioOwner)`: autoDispose family, held by
// [Ref.keepAlive] for a 5-minute TTL (the exact pattern the salon «Про салон»
// rail used before the promotion), so an away-and-back tab switch serves the
// cached gallery. `salonPortfolioProvider(salonId)` is now a thin delegate to
// `portfolioProvider(PortfolioOwner.salon(salonId))`.
//
// Reads:
//   • salon  → `SalonRepository.getSalonPortfolio` — UNCHANGED transport, so
//     every existing salon fake / golden / integration fixture keeps feeding
//     the rail exactly as before;
//   • master → `MediaUploadRepository.getMasterPortfolio`.
//
// The master branch rebuilds when the signed-in user changes (sign-out /
// account switch): a master's own cached gallery never outlives its session.
// Identity-only `select` — never a bare `authProvider` watch.
//
// Writes go through `PortfolioEditController`, which PATCHES this provider's
// cached list after a successful upload (prepend the returned photo) or
// delete (drop the id — also on a 404, already gone) and falls back to an
// invalidate only when there is no settled cached value. The salon delegate
// watches `.future`, so it sees the same patched list.

import 'dart:async';

import 'package:beautica_mobile/core/media/portfolio/portfolio_owner.dart';
import 'package:beautica_mobile/core/media/portfolio/portfolio_photo.dart';
import 'package:beautica_mobile/core/media/upload/media_upload_repository.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show ProviderListenableSelect;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'portfolio_notifier.g.dart';

/// How long a loaded portfolio stays cached without a listener.
const Duration kPortfolioCacheTtl = Duration(minutes: 5);

/// The cache TTL [PortfolioNotifier.build] (and the `salonPortfolioProvider`
/// delegate) arms. Production uses [kPortfolioCacheTtl]; `makeTestContainer`
/// defaults it to [Duration.zero] — no keepAlive, no timer outliving
/// flutter_test's pending-timer check — unless a test overrides it itself.
/// Mirrors `salonManagementProfileCacheWindowProvider` (phase 384).
@riverpod
Duration portfolioCacheTtl(Ref ref) => kPortfolioCacheTtl;

/// [owner]'s portfolio, newest first (at most 50 — above the 30-photo cap).
///
/// A class notifier (not a plain future provider) only so the write
/// controller can PATCH the cached list after a write ([prependLocal] /
/// [removeLocal]) instead of refetching up to 50 rows; the read itself is
/// unchanged. Generated name: `portfolioProvider`.
@riverpod
class PortfolioNotifier extends _$PortfolioNotifier {
  @override
  Future<List<PortfolioPhoto>> build(PortfolioOwner owner) async {
    // Keep the link alive across an away-and-back tab switch, then close it
    // so a stale gallery eventually refetches. The timer is cancelled on
    // dispose so it can never fire after the provider is gone. A zero TTL
    // (the shared test container's default) arms neither link nor timer.
    keepAliveFor(ref, ref.read(portfolioCacheTtlProvider));

    return switch (owner) {
      final PortfolioOwnerSalon o =>
        ref.watch(salonRepositoryProvider).getSalonPortfolio(o.salonId),
      final PortfolioOwnerMasterSelf o => _masterPortfolio(o.masterId),
    };
  }

  Future<List<PortfolioPhoto>> _masterPortfolio(String masterId) {
    ref.watch(authProvider.select(authUserIdOrNull));
    return ref
        .watch(mediaUploadRepositoryProvider)
        .getMasterPortfolio(masterId);
  }

  /// Puts the just-uploaded [photo] at the head of the LOADED list (the list
  /// is newest first). Returns `false` — nothing patched — when there is no
  /// settled value to patch (loading / error / refetching); the caller then
  /// invalidates instead. Idempotent on [PortfolioPhoto.id].
  bool prependLocal(PortfolioPhoto photo) {
    final AsyncValue<List<PortfolioPhoto>> s = state;
    if (s is! AsyncData<List<PortfolioPhoto>>) return false;
    final List<PortfolioPhoto> current = s.value;
    if (current.any((PortfolioPhoto p) => p.id == photo.id)) return true;
    state = AsyncData<List<PortfolioPhoto>>(
      List<PortfolioPhoto>.unmodifiable(<PortfolioPhoto>[photo, ...current]),
    );
    return true;
  }

  /// Drops [mediaId] from the LOADED list. Returns `false` when there is no
  /// settled value to patch (see [prependLocal]).
  bool removeLocal(String mediaId) {
    final AsyncValue<List<PortfolioPhoto>> s = state;
    if (s is! AsyncData<List<PortfolioPhoto>>) return false;
    final List<PortfolioPhoto> current = s.value;
    if (!current.any((PortfolioPhoto p) => p.id == mediaId)) return true;
    state = AsyncData<List<PortfolioPhoto>>(
      List<PortfolioPhoto>.unmodifiable(
        current.where((PortfolioPhoto p) => p.id != mediaId),
      ),
    );
    return true;
  }
}

/// Holds [ref] alive for [ttl], then releases it; the timer is cancelled on
/// dispose. A non-positive [ttl] is a no-op (plain autoDispose).
void keepAliveFor(Ref ref, Duration ttl) {
  if (ttl <= Duration.zero) return;
  final link = ref.keepAlive();
  final Timer timer = Timer(ttl, link.close);
  ref.onDispose(timer.cancel);
}

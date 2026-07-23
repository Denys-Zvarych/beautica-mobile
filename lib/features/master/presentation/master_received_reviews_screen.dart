// Phase 4.6 — Independent-master received-reviews screen ("Мої відгуки").
//
// The salon "Відгуки" tab (Phase 13.6) lifted onto a standalone, pushed master
// screen: a rating-summary card (avg ★ + count + 5★→1★ distribution) over a
// sortable list of review cards, with a ⇅ sort control. Renders
// [MasterReviewsBody] — extracted so `PublicMasterReviewsScreen` (a CLIENT
// viewing another master's reviews) can share the exact same UI.
//
// Master deltas vs salon (documented, not bugs):
//   • Standalone screen with a back affordance (pushed route), titled
//     «Мої відгуки» — not a tab inside another profile.
//
// masterId source (CORRECTNESS — HIGH): the review endpoints
// `GET /masters/{masterId}/reviews[/summary]` MUST be keyed on the Master-row
// id, which is an independently generated UUID DISTINCT from the session user
// id (`master.id != user.id`). That id is read from the loaded profile
// ([masterProfileProvider] → `GET /masters/me` → `MasterDetailResponse.masterId`,
// surfaced as [Master.id] by [MasterMapper.fromDto]). Querying by
// `session.user.id` (the old bug) lands every real independent master on the
// backend's non-master routes: summary 404 + an empty list. The screen therefore
// resolves the id from [masterProfileProvider], handling its own loading/error
// states, while keeping the unauthenticated fail-closed short-circuit.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';

import 'master_profile_notifier.dart';
import 'widgets/master_reviews_body.dart';
import 'widgets/profile_scaffold.dart';

/// The master's own received-reviews screen.
///
/// Resolves the masterId from the loaded [masterProfileProvider] (the
/// Master-row id — see the file header) and threads it into
/// [masterReviewSummaryProvider] / [masterReviewsProvider]. Acquires the
/// ref-counted [ScreenProtectionManager] for the lifetime of this PII surface
/// (mirrors [MasterProfileScreen]).
class MasterReceivedReviewsScreen extends ConsumerStatefulWidget {
  const MasterReceivedReviewsScreen({super.key});

  @override
  ConsumerState<MasterReceivedReviewsScreen> createState() =>
      _MasterReceivedReviewsScreenState();
}

class _MasterReceivedReviewsScreenState
    extends ConsumerState<MasterReceivedReviewsScreen> {
  // Captured in initState so dispose() never touches `ref` — under Riverpod 3.x
  // reading `ref` in dispose() throws. Hold the keepAlive manager reference.
  late final ScreenProtectionManager _screenProtection;

  @override
  void initState() {
    super.initState();
    // SEC LOW: ref-counted screenshot guard + iOS app-switcher-snapshot blur
    // for this PII-bearing `/master/*` surface (client names + comments). The
    // manager is idempotent and `!kDebugMode`-guarded internally.
    _screenProtection = ref.read(screenProtectionProvider)..acquire();
  }

  @override
  void dispose() {
    // SEC LOW: release the ref-counted guard; protection only lifts once the
    // last PII route unmounts.
    _screenProtection.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final session = ref.watch(authProvider).value;

    if (session is! Authenticated) {
      // No authenticated session — the redirect guard normally prevents this,
      // but fail closed with a retryable error rather than a crash. Short-
      // circuits BEFORE watching the profile or the review providers.
      return ProfileScaffold(
        title: l10n.masterReviewsTitle,
        child: ErrorState(
          failure: const UnauthorizedFailure(),
          onRetry: () => ref.invalidate(authProvider),
        ),
      );
    }

    // Resolve the Master-row id from the loaded profile — NOT session.user.id
    // (see the file header). The profile's own loading / error states are
    // rendered here so the review providers are only keyed once a real id
    // exists.
    final masterAsync = ref.watch(masterProfileProvider);

    return ProfileScaffold(
      title: l10n.masterReviewsTitle,
      child: masterAsync.when(
        data: (Master master) => MasterReviewsBody(masterId: master.id),
        loading: () => const MasterReviewsBodySkeleton(),
        error: (Object e, _) => ErrorState(
          failure: e is Failure ? e : UnknownFailure(cause: e),
          onRetry: () => ref.invalidate(masterProfileProvider),
        ),
      ),
    );
  }
}

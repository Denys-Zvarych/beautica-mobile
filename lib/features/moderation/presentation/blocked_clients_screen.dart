// Phase 426 — «Заблоковані клієнти» (independent master, salon owner, salon
// admin; owner/admin see the salon's list).
//
// Ported from the approved preview
// `docs/signup-designs/UgcSafety/lib/screens/blocked_users_screen.dart`:
// SectionScaffold (as «Акаунт») + intro line + one [BlockedEntryCard] per
// block, newest first (the server's order); empty → [SalonNoticeCard], copy
// verbatim. Unblock → the 425 confirm → `DELETE /blocks/{id}` → the card
// folds away (AnimatedSize, the preview's only motion: it shows what changed)
// → success snack; the list then refetches.
//
// Production swaps from the preview: the hard-coded list → [blockedClientsProvider]
// (loading skeleton + error-with-retry states added), the inline snack →
// `showSuccessSnack` / `showErrorSnack`, Navigator → go_router, copy → ARB.
// Rows go through the scaffold's lazy `slivers` path: the list may hold up to
// 500 blocks (397), which must not all be built eagerly.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/role_home.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/salon_notice_card.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';

import '../../auth/domain/user_role.dart';
import '../../auth/presentation/auth_notifier.dart';
import '../../master/presentation/widgets/section_scaffold.dart';
import '../application/block_notifier.dart';
import '../application/blocked_list_notifier.dart';
import '../domain/client_block.dart';
import 'widgets/block_confirm_dialog.dart';
import 'widgets/blocked_entry_card.dart';

/// The provider's (or salon's) blocked clients.
class BlockedClientsScreen extends ConsumerStatefulWidget {
  const BlockedClientsScreen({super.key});

  static const Key emptyKey = Key('blocked-clients-empty');
  static const Key loadingKey = Key('blocked-clients-loading');
  static const Key errorKey = Key('blocked-clients-error');

  @override
  ConsumerState<BlockedClientsScreen> createState() =>
      _BlockedClientsScreenState();
}

class _BlockedClientsScreenState extends ConsumerState<BlockedClientsScreen> {
  /// Rows unblocked on this visit, folding away until the refetch drops them.
  final Set<String> _leaving = <String>{};

  /// One unblock at a time (the confirm dialog is single-flight already;
  /// this covers the DELETE that follows it).
  bool _busy = false;

  static const Duration _fold = Duration(milliseconds: 260);

  void _onBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      final UserRole? role = ref.read(authProvider.select(authUserRoleOrNull));
      context.go(role == null ? RouteNames.login : roleHomePath(role));
    }
  }

  Future<void> _unblock(ClientBlock block) async {
    if (_busy) return;
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (!await showUnblockClientDialog(context, block.displayName)) return;
    if (!mounted) return;
    setState(() => _busy = true);
    final BlockWriteResult result = await ref
        .read(clientBlockControllerProvider.notifier)
        .unblockById(block.id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result is BlockWriteDone) _leaving.add(block.id);
    });
    switch (result) {
      case BlockWriteDone():
        showSuccessSnack(context, l10n.clientUnblockedSnack);
      case BlockWriteFailed(:final Failure failure):
        showErrorSnack(context, failure.userMessage(context));
      case BlockWriteInProgress():
        // Another block write was in flight — this call did nothing.
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<ClientBlock>> async = ref.watch(
      blockedClientsProvider,
    );
    final DateTime todayKyiv = kyivToday(ref.watch(clockProvider));

    final List<ClientBlock>? blocks = async.value;
    final List<Widget> content;
    if (blocks != null && !async.hasError) {
      final bool empty = blocks.every(
        (ClientBlock b) => _leaving.contains(b.id),
      );
      content = <Widget>[
        if (empty)
          const SliverToBoxAdapter(child: _EmptyNotice())
        else
          SliverList.builder(
            itemCount: blocks.length,
            itemBuilder: (BuildContext context, int index) {
              final ClientBlock block = blocks[index];
              return AnimatedSize(
                key: ValueKey<String>('blocked-row-${block.id}'),
                duration: _fold,
                curve: Curves.easeInOut,
                child: _leaving.contains(block.id)
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(
                          bottom: VelvetSpacing.md,
                        ),
                        child: BlockedEntryCard(
                          key: ValueKey<String>('blocked-card-${block.id}'),
                          block: block,
                          todayKyiv: todayKyiv,
                          onUnblock: () => _unblock(block),
                        ),
                      ),
              );
            },
          ),
      ];
    } else if (async.hasError && !async.isLoading) {
      final Object error = async.error ?? const UnknownFailure();
      content = <Widget>[
        SliverToBoxAdapter(
          child: Padding(
            key: BlockedClientsScreen.errorKey,
            padding: const EdgeInsets.only(top: VelvetSpacing.xl),
            child: ErrorState(
              failure: error is Failure ? error : UnknownFailure(cause: error),
              onRetry: () => ref.invalidate(blockedClientsProvider),
            ),
          ),
        ),
      ];
    } else {
      content = const <Widget>[SliverToBoxAdapter(child: _LoadingBody())];
    }

    return SectionScaffold(
      title: l10n.blockedClientsTitle,
      backSemanticLabel: l10n.blockedClientsBackSemanticLabel,
      backKey: const Key('btn-back-blocked-clients'),
      onBack: _onBack,
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(left: 4, bottom: VelvetSpacing.lg),
            child: Text(l10n.blockedClientsIntro, style: VelvetText.body()),
          ),
        ),
        ...content,
      ],
    );
  }
}

/// D3 — the preview's empty notice, copy verbatim.
class _EmptyNotice extends StatelessWidget {
  const _EmptyNotice();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return SalonNoticeCard(
      key: BlockedClientsScreen.emptyKey,
      icon: Icons.block_rounded,
      title: l10n.blockedClientsEmptyTitle,
      body: l10n.blockedClientsEmptyBody,
    );
  }
}

/// Loading — shimmer blocks in the card's own geometry so nothing jumps
/// when data lands.
class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    return const SkeletonShimmerScope(
      child: Column(
        key: BlockedClientsScreen.loadingKey,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _LoadingCard(),
          SizedBox(height: VelvetSpacing.md),
          _LoadingCard(),
          SizedBox(height: VelvetSpacing.md),
          _LoadingCard(),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return const NeumorphicCard(
      child: Row(
        children: <Widget>[
          SkeletonBlock(width: 48, height: 48, circle: true),
          SizedBox(width: VelvetSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SkeletonBlock(width: 140, height: 14),
                SizedBox(height: VelvetSpacing.sm),
                SkeletonBlock(width: 100, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

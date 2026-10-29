// Phase 425 — the provider's block list (backend 397 `GET /blocks`).
//
// Declared here so phase 425's block / unblock can refresh it (D6); the
// «Заблоковані клієнти» screen that renders it is phase 426.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/features/moderation/data/block_repository.dart';
import 'package:beautica_mobile/features/moderation/domain/client_block.dart';

part 'blocked_list_notifier.g.dart';

/// The caller's blocked clients, newest first.
@riverpod
Future<List<ClientBlock>> blockedClients(Ref ref) =>
    ref.watch(clientBlockRepositoryProvider).list();

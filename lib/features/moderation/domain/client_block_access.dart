// Phase 426 D1 — who may block clients and manage the «Заблоковані клієнти»
// list: independent master, salon owner, salon admin (owner/admin share the
// salon's list). Salon master and client never — the row is hidden and the
// route bounces them. A null role fails closed.
//
// Pure Dart: no Flutter imports.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';

/// `true` only for the three provider roles that own a block list.
bool clientBlocksAllowedFor(UserRole? role) => switch (role) {
  UserRole.independentMaster ||
  UserRole.salonOwner ||
  UserRole.salonAdmin => true,
  UserRole.salonMaster || UserRole.client || null => false,
};

// Phase 426 — pixel lock for «Заблоковані клієнти».
//
// NEW baselines (no existing image moved):
//   • blocked_clients_list_360_{1x,1_3x} — a registered client (no phone) +
//     a guest with a masked phone + a last-year guest (year on the day line)
//   • blocked_clients_empty_360_1x       — D3 empty notice
//   • blocked_clients_error_360_1x       — ErrorState with retry
//
// The promoted shell / disc (RaisedCardShell, MasterMark) keep their ORIGINAL
// screens locked by the unchanged `favorite_cards_golden_test.dart`
// baselines, re-run green after the promotion.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/moderation/data/block_repository.dart';
import 'package:beautica_mobile/features/moderation/domain/client_block.dart';
import 'package:beautica_mobile/features/moderation/presentation/blocked_clients_screen.dart';

import '../features/moderation/support/fake_client_block_repository.dart';
import '../helpers/fakes/fake_notification_repository.dart' show FixedRoleAuth;
import 'helpers/golden_pump.dart';

DateTime _now() => DateTime.utc(2026, 10, 28, 12);

final List<ClientBlock> _blocks = <ClientBlock>[
  ClientBlock(
    id: 'blk-1',
    kind: ClientBlockKind.client,
    displayName: 'Олег М.',
    createdAt: DateTime.utc(2026, 10, 12, 9),
  ),
  ClientBlock(
    id: 'blk-2',
    kind: ClientBlockKind.guest,
    displayName: 'Ірина С.',
    maskedPhone: '+380 •• ••• 12 34',
    createdAt: DateTime.utc(2026, 10, 3, 9),
  ),
  ClientBlock(
    id: 'blk-3',
    kind: ClientBlockKind.guest,
    displayName: 'Клієнт',
    maskedPhone: '+380 •• ••• 98 76',
    createdAt: DateTime.utc(2025, 9, 28, 9),
  ),
];

List<Object> _overrides(ClientBlockRepository repo) => <Object>[
  authProvider.overrideWith(() => FixedRoleAuth(UserRole.independentMaster)),
  clientBlockRepositoryProvider.overrideWithValue(repo),
  clockProvider.overrideWithValue(_now),
];

void main() {
  const double width = 360;
  const Size screen = Size(width, 900);

  for (final double scale in <double>[1.0, 1.3]) {
    final String s = scale == 1.0 ? '1x' : '1_3x';
    goldenTest(
      'blocked clients — list ($s)',
      fileName: 'blocked_clients_list_360_$s',
      constraints: BoxConstraints.tight(screen),
      textScaleFactor: scale,
      pumpWidget: goldenPumpWidget(
        width: width,
        overrides: _overrides(FakeClientBlockRepository(seeded: _blocks)),
      ),
      builder: () => const BlockedClientsScreen(),
    );
  }

  goldenTest(
    'blocked clients — empty',
    fileName: 'blocked_clients_empty_360_1x',
    constraints: BoxConstraints.tight(screen),
    textScaleFactor: 1.0,
    pumpWidget: goldenPumpWidget(
      width: width,
      overrides: _overrides(FakeClientBlockRepository()),
    ),
    builder: () => const BlockedClientsScreen(),
  );

  goldenTest(
    'blocked clients — error',
    fileName: 'blocked_clients_error_360_1x',
    constraints: BoxConstraints.tight(screen),
    textScaleFactor: 1.0,
    pumpWidget: goldenPumpWidget(
      width: width,
      overrides: _overrides(
        FakeClientBlockRepository()..nextFailure = const UnknownFailure(),
      ),
    ),
    builder: () => const BlockedClientsScreen(),
  );
}

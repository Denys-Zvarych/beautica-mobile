// M509 — pixel lock for the «Клієнти» list.
//
// NEW baselines (no existing image moved by this file):
//   • clients_screen_list_360_{1x,1_3x} — rows on the master bar: a rated
//     registered client with both dates, a blocked one, an unrated one («—»),
//     a nameless guest («Гість», no kind label) and a name that wraps
//   • clients_screen_empty_360_1x       — empty roster (search hidden)
//   • clients_screen_error_360_1x       — ErrorState with retry
//
// Preview parity: `docs/signup-designs/ClientsTab/` (list at 360 px, master
// bar host). Dates are fixed instants; Kyiv wall-clock formatting is exercised
// (`Ост.: 7 лис`, `Наст.: пт, 20 лис, 14:00`).

import 'package:dio/dio.dart' show CancelToken;
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/clients/data/client_repository.dart';
import 'package:beautica_mobile/features/clients/domain/client_summary.dart';
import 'package:beautica_mobile/features/clients/presentation/clients_screen.dart';
import 'package:beautica_mobile/shared/widgets/velvet_bottom_nav_bar.dart';
import 'package:flutter/material.dart';

import '../helpers/fakes/fake_notification_repository.dart' show FixedRoleAuth;
import 'helpers/golden_pump.dart';

DateTime _now() => DateTime.utc(2026, 11, 16, 10);

class _Repo implements ClientRepository {
  // M510 — the card reads are not exercised here.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  _Repo(this.rows, {this.failure});

  final List<ClientSummary> rows;
  final Failure? failure;

  @override
  Future<PageResponse<ClientSummary>> list(
    ClientListScope scope, {
    String? q,
    int page = 0,
    int size = kClientPageSize,
    CancelToken? cancelToken,
  }) async {
    final Failure? f = failure;
    if (f != null) throw f;
    return PageResponse<ClientSummary>(
      items: rows,
      page: 0,
      totalPages: 1,
      totalElements: rows.length,
    );
  }
}

final List<ClientSummary> _rows = <ClientSummary>[
  ClientSummary(
    ref: const ClientRef.registered('u1'),
    displayName: 'Оксана Мельник',
    lastVisitAt: DateTime.utc(2026, 11, 7, 10),
    nextVisitAt: DateTime.utc(2026, 11, 20, 12),
    ratingAvg: 4.9,
    ratingCount: 12,
    completedVisits: 9,
  ),
  ClientSummary(
    ref: const ClientRef.registered('u2'),
    displayName: 'Тетяна Гончаренко-Шевченко',
    lastVisitAt: DateTime.utc(2026, 10, 2, 10),
    ratingAvg: 4.5,
    ratingCount: 3,
    blocked: true,
  ),
  ClientSummary(
    ref: const ClientRef.registered('u3'),
    displayName: 'Наталія Бойко',
    lastVisitAt: DateTime.utc(2026, 9, 14, 10),
  ),
  ClientSummary(
    ref: const ClientRef.guest('g1'),
    nextVisitAt: DateTime.utc(2026, 11, 18, 8, 30),
  ),
  ClientSummary(
    ref: const ClientRef.guest('g2'),
    displayName: 'Ірина Коваль',
    lastVisitAt: DateTime.utc(2026, 8, 1, 10),
  ),
];

List<Object> _overrides(ClientRepository repo) => <Object>[
  authProvider.overrideWith(() => FixedRoleAuth(UserRole.independentMaster)),
  clientRepositoryProvider.overrideWithValue(repo),
  clockProvider.overrideWithValue(_now),
];

Widget _screen() => const ClientsScreen(
  scope: ClientListScope.me(),
  cardBase: '/master/clients',
  bottomNavBar: VelvetBottomNavBar(activeIndex: kMasterClientsNavTab),
);

void main() {
  const double width = 360;
  const Size screen = Size(width, 900);

  for (final double scale in <double>[1.0, 1.3]) {
    final String s = scale == 1.0 ? '1x' : '1_3x';
    goldenTest(
      'clients screen — list ($s)',
      fileName: 'clients_screen_list_360_$s',
      constraints: BoxConstraints.tight(screen),
      textScaleFactor: scale,
      pumpWidget: goldenPumpWidget(
        width: width,
        overrides: _overrides(_Repo(_rows)),
      ),
      builder: _screen,
    );
  }

  goldenTest(
    'clients screen — empty',
    fileName: 'clients_screen_empty_360_1x',
    constraints: BoxConstraints.tight(screen),
    textScaleFactor: 1.0,
    pumpWidget: goldenPumpWidget(
      width: width,
      overrides: _overrides(_Repo(const <ClientSummary>[])),
    ),
    builder: _screen,
  );

  goldenTest(
    'clients screen — error',
    fileName: 'clients_screen_error_360_1x',
    constraints: BoxConstraints.tight(screen),
    textScaleFactor: 1.0,
    pumpWidget: goldenPumpWidget(
      width: width,
      overrides: _overrides(
        _Repo(const <ClientSummary>[], failure: const UnknownFailure()),
      ),
    ),
    builder: _screen,
  );
}

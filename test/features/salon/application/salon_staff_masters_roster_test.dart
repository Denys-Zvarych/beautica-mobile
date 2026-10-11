// `salonStaffMastersRosterProvider` / `staffMastersOf` — the STAFF-side master
// roster the «Записи» board, its «Майстер» filter and the walk-in wizard read
// (2026-10-05), projected from the management `GET /salons/{id}/staff` roster
// instead of the public, bookable-only `GET /salons/{id}/masters` rail.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/core/media/upload/media_upload_repository.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/salon/application/salon_management_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_staff_masters_roster.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_master_summary.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';

import '../../../helpers/fakes/fake_salon_repository.dart';

const SalonStaffMember _master = SalonStaffMember(
  userId: 'user-m1',
  masterId: 'm1',
  role: SalonStaffRole.master,
  masterType: MasterType.salonMaster,
  firstName: 'Оля',
  lastName: 'Коваль',
  professionalTitle: 'Стиліст',
  avatarUrl: 'https://media.test/m1.png',
  avgRating: 4.8,
  reviewCount: 12,
);

const SalonStaffMember _ownerMaster = SalonStaffMember(
  userId: 'user-owner',
  masterId: 'm-owner',
  role: SalonStaffRole.master,
  masterType: MasterType.salonOwner,
  firstName: 'Ірина',
  lastName: 'Власник',
);

const SalonStaffMember _admin = SalonStaffMember(
  userId: 'user-admin',
  role: SalonStaffRole.admin,
  firstName: 'Адмін',
  lastName: 'Салону',
);

class _SignedOutAuth extends AuthNotifier {
  @override
  Future<AuthSession> build() =>
      Future<AuthSession>.value(const AuthSession.unauthenticated());
}

void main() {
  group('staffMastersOf', () {
    test('keeps every master WITH a master row, owner-masters included, in '
        'backend order; drops admins', () {
      final List<SalonMasterSummary> out = staffMastersOf(
        const <SalonStaffMember>[_admin, _ownerMaster, _master],
      );
      expect(out.map((SalonMasterSummary m) => m.masterId), <String>[
        'm-owner',
        'm1',
      ]);
      expect(out.first.type, MasterType.salonOwner);
    });

    test('maps every field the board header and the wizard tile render', () {
      final SalonMasterSummary m = staffMastersOf(const <SalonStaffMember>[
        _master,
      ]).single;
      expect(
        m,
        const SalonMasterSummary(
          masterId: 'm1',
          firstName: 'Оля',
          lastName: 'Коваль',
          professionalTitle: 'Стиліст',
          avatarUrl: 'https://media.test/m1.png',
          avgRating: 4.8,
          reviewCount: 12,
          type: MasterType.salonMaster,
        ),
      );
    });

    test('a master entry with no master row or no masterType never crashes: '
        'no row -> dropped, unknown type -> salonMaster', () {
      final List<SalonMasterSummary> out =
          staffMastersOf(const <SalonStaffMember>[
            SalonStaffMember(
              userId: 'u-norow',
              role: SalonStaffRole.master,
              firstName: 'А',
              lastName: 'Б',
            ),
            SalonStaffMember(
              userId: 'u-x',
              masterId: 'm-x',
              role: SalonStaffRole.master,
              firstName: 'В',
              lastName: 'Г',
            ),
          ]);
      expect(out.single.masterId, 'm-x');
      expect(out.single.type, MasterType.salonMaster);
    });
  });

  test('salonStaffMastersRosterProvider reads /staff, never the public '
      '/masters rail', () async {
    final FakeSalonRepository repo = FakeSalonRepository(
      salon: const Salon(id: 's1', name: 'Салон'),
      // The public rail lists NOBODY — a board still reading it would be
      // empty.
      staff: const <SalonStaffMember>[_master, _ownerMaster, _admin],
    );
    final ProviderContainer container = ProviderContainer(
      overrides: [
        salonRepositoryProvider.overrideWithValue(repo),
        authProvider.overrideWith(_SignedOutAuth.new),
      ],
    );
    addTearDown(container.dispose);

    final List<SalonMasterSummary> roster = await container.read(
      salonStaffMastersRosterProvider('s1').future,
    );

    expect(roster.map((SalonMasterSummary m) => m.masterId), <String>[
      'm1',
      'm-owner',
    ]);
    expect(repo.getSalonStaffCalls, 1);
  });

  group('stable identity across parent patches (2026-10-05 audit P2)', () {
    // The board's `_columnsFor` / `_masterFilterOptions` and the wizard's
    // `_coveringMasterIds` / `_resolveDerived` memo on `identical(roster)`.
    // A parent patch the roster does not show must hand back the SAME list.

    late ProviderContainer container;
    late List<AsyncValue<List<SalonMasterSummary>>> emitted;

    Future<List<SalonMasterSummary>> settle() =>
        container.read(salonStaffMastersRosterProvider('s1').future);

    SalonManagementProfile parent() =>
        container.read(salonManagementProfileProvider('s1').notifier);

    setUp(() async {
      container = ProviderContainer(
        overrides: [
          salonRepositoryProvider.overrideWithValue(
            FakeSalonRepository(
              salon: const Salon(id: 's1', name: 'Салон'),
              staff: const <SalonStaffMember>[_master, _ownerMaster, _admin],
            ),
          ),
          authProvider.overrideWith(_SignedOutAuth.new),
        ],
      );
      emitted = <AsyncValue<List<SalonMasterSummary>>>[];
      // Keeps the family member alive AND records every state a consumer
      // `ref.watch` would observe.
      container.listen<AsyncValue<List<SalonMasterSummary>>>(
        salonStaffMastersRosterProvider('s1'),
        (_, AsyncValue<List<SalonMasterSummary>> next) => emitted.add(next),
      );
      await settle();
      emitted.clear();
    });

    tearDown(() => container.dispose());

    test('an ADMIN avatar patch (patchStaffAvatar) keeps the roster '
        'identical, and no consumer sees it lose its value', () async {
      final List<SalonMasterSummary> before = await settle();

      expect(
        parent().patchStaffAvatar('user-admin', 'https://media.test/a.png'),
        isTrue,
      );
      final List<SalonMasterSummary> after = await settle();

      expect(identical(after, before), isTrue);
      // Non-vacuous: the patch DID rebuild the roster.
      expect(emitted, isNotEmpty);
      expect(
        emitted.every(
          (AsyncValue<List<SalonMasterSummary>> s) => s.value != null,
        ),
        isTrue,
        reason: 'a parent patch must never surface a value-less loading',
      );
    });

    test(
      'a salon image patch (patchImage) keeps the roster identical',
      () async {
        final List<SalonMasterSummary> before = await settle();

        expect(
          parent().patchImage(SalonImageSlot.cover, 'https://media.test/c.png'),
          isTrue,
        );
        final List<SalonMasterSummary> after = await settle();

        expect(identical(after, before), isTrue);
      },
    );

    test('positive control: a MASTER avatar patch yields a NEW list carrying '
        'the new photo', () async {
      final List<SalonMasterSummary> before = await settle();

      expect(
        parent().patchStaffAvatar('user-m1', 'https://media.test/new.png'),
        isTrue,
      );
      final List<SalonMasterSummary> after = await settle();

      expect(identical(after, before), isFalse);
      expect(
        after
            .singleWhere((SalonMasterSummary m) => m.masterId == 'm1')
            .avatarUrl,
        'https://media.test/new.png',
      );
    });
  });
}

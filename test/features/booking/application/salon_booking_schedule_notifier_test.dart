// Phase 14.16/14.17 — Unit tests for [SalonBookingSchedule] (the per-master
// {date, time} state notifier backing `SalonTimeScreen`) and the
// [salonMasterDaySlotsProvider] family it exposes for the time phase.
//
// Strategy: fresh `ProviderContainer` per test (disposed via tearDown),
// mirroring `working_days_notifier_test.dart`'s shape for the family
// provider, plus direct notifier-method assertions for the plain
// (non-family) `SalonBookingSchedule` class.

import 'dart:async';

import 'package:beautica_mobile/features/booking/application/salon_booking_schedule_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/slot_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot.dart';
import 'package:beautica_mobile/features/booking/domain/salon_master_day_slots_query.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockSlotRepository extends Mock implements SlotRepository {}

void main() {
  group('SalonBookingScheduleState', () {
    test('entryFor returns an empty entry for an unknown masterId', () {
      const state = SalonBookingScheduleState();
      final entry = state.entryFor('m1');
      expect(entry.date, isNull);
      expect(entry.slot, isNull);
      expect(entry.isScheduled, isFalse);
    });

    test('isScheduled is true only once BOTH date and slot are set', () {
      final slot = BookingSlot(
        startAt: DateTime(2026, 7, 14, 14),
        endAt: DateTime(2026, 7, 14, 15),
        available: true,
      );
      const dateOnlyEntry = SalonScheduleEntry();
      final withDate = dateOnlyEntry.copyWith(date: DateTime(2026, 7, 14));
      expect(withDate.isScheduled, isFalse);
      final withBoth = withDate.copyWith(slot: slot);
      expect(withBoth.isScheduled, isTrue);
    });

    test('scheduledCount / allScheduled reflect the subset of masterIds '
        'that are fully scheduled', () {
      final slot = BookingSlot(
        startAt: DateTime(2026, 7, 14, 14),
        endAt: DateTime(2026, 7, 14, 15),
        available: true,
      );
      final state = SalonBookingScheduleState(
        entries: <String, SalonScheduleEntry>{
          'm1': SalonScheduleEntry(date: DateTime(2026, 7, 14), slot: slot),
          'm2': SalonScheduleEntry(date: DateTime(2026, 7, 15)),
        },
      );
      expect(state.scheduledCount(<String>['m1', 'm2', 'm3']), 1);
      expect(state.allScheduled(<String>['m1', 'm2']), isFalse);
      expect(state.allScheduled(<String>['m1']), isTrue);
      // Nothing to schedule is never "done".
      expect(state.allScheduled(<String>[]), isFalse);
    });

    test('nextUnscheduledIndex wraps once and returns null once every '
        'master is scheduled', () {
      final slot = BookingSlot(
        startAt: DateTime(2026, 7, 14, 14),
        endAt: DateTime(2026, 7, 14, 15),
        available: true,
      );
      final scheduled = SalonScheduleEntry(
        date: DateTime(2026, 7, 14),
        slot: slot,
      );
      final masterIds = <String>['m1', 'm2', 'm3'];

      final onlyM1Scheduled = SalonBookingScheduleState(
        entries: <String, SalonScheduleEntry>{'m1': scheduled},
      );
      // From index 0 (m1, already scheduled), the next unscheduled is m2 (1).
      expect(onlyM1Scheduled.nextUnscheduledIndex(masterIds, 0), 1);
      // From index 2 (m3), wraps to m1 first (scheduled) then lands on m2.
      expect(onlyM1Scheduled.nextUnscheduledIndex(masterIds, 2), 1);

      final allScheduled = SalonBookingScheduleState(
        entries: <String, SalonScheduleEntry>{
          'm1': scheduled,
          'm2': scheduled,
          'm3': scheduled,
        },
      );
      expect(allScheduled.nextUnscheduledIndex(masterIds, 0), isNull);
      expect(
        const SalonBookingScheduleState().nextUnscheduledIndex(<String>[], 0),
        isNull,
      );
    });
  });

  group('SalonBookingSchedule notifier', () {
    ProviderContainer makeContainer() {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      return container;
    }

    test('build() starts with no scheduled masters', () {
      final container = makeContainer();
      final state = container.read(salonBookingScheduleProvider);
      expect(state.entries, isEmpty);
    });

    test('selectDate sets the date (date-only) and leaves any slot unset', () {
      final container = makeContainer();
      final notifier = container.read(salonBookingScheduleProvider.notifier);

      notifier.selectDate('m1', DateTime(2026, 7, 14, 9, 30));

      final entry = container.read(salonBookingScheduleProvider).entryFor('m1');
      expect(entry.date, DateTime(2026, 7, 14));
      expect(entry.slot, isNull);
    });

    test('selecting a NEW date clears a previously-chosen slot for that '
        'master — picking a new date re-opens the time choice', () {
      final container = makeContainer();
      final notifier = container.read(salonBookingScheduleProvider.notifier);
      final slot = BookingSlot(
        startAt: DateTime(2026, 7, 14, 14),
        endAt: DateTime(2026, 7, 14, 15),
        available: true,
      );

      notifier.selectDate('m1', DateTime(2026, 7, 14));
      notifier.selectSlot('m1', slot);
      expect(
        container.read(salonBookingScheduleProvider).isScheduled('m1'),
        isTrue,
      );

      notifier.selectDate('m1', DateTime(2026, 7, 15));
      final entry = container.read(salonBookingScheduleProvider).entryFor('m1');
      expect(entry.date, DateTime(2026, 7, 15));
      expect(entry.slot, isNull);
    });

    test('clearDate resets a master back to fully unscheduled', () {
      final container = makeContainer();
      final notifier = container.read(salonBookingScheduleProvider.notifier);
      final slot = BookingSlot(
        startAt: DateTime(2026, 7, 14, 14),
        endAt: DateTime(2026, 7, 14, 15),
        available: true,
      );
      notifier.selectDate('m1', DateTime(2026, 7, 14));
      notifier.selectSlot('m1', slot);

      notifier.clearDate('m1');

      final entry = container.read(salonBookingScheduleProvider).entryFor('m1');
      expect(entry.date, isNull);
      expect(entry.slot, isNull);
    });

    test('picks for one master never clobber another master\'s entry', () {
      final container = makeContainer();
      final notifier = container.read(salonBookingScheduleProvider.notifier);

      notifier.selectDate('m1', DateTime(2026, 7, 14));
      notifier.selectDate('m2', DateTime(2026, 7, 20));

      final state = container.read(salonBookingScheduleProvider);
      expect(state.entryFor('m1').date, DateTime(2026, 7, 14));
      expect(state.entryFor('m2').date, DateTime(2026, 7, 20));
    });
  });

  group('salonMasterDaySlotsProvider', () {
    late _MockSlotRepository repo;

    setUp(() {
      repo = _MockSlotRepository();
    });

    ProviderContainer makeContainer() {
      final container = ProviderContainer(
        overrides: [slotRepositoryProvider.overrideWithValue(repo)],
        retry: (int _, Object _) => null,
      );
      addTearDown(container.dispose);
      return container;
    }

    test('delegates to SlotRepository.getMasterSlots with the query\'s '
        'masterId/serviceId/date and resolves to its result', () async {
      final query = SalonMasterDaySlotsQuery(
        masterId: 'm1',
        serviceId: 'svc-1',
        date: DateTime(2026, 7, 14, 13),
      );
      final fixture = <BookingSlot>[
        BookingSlot(
          startAt: DateTime(2026, 7, 14, 9),
          endAt: DateTime(2026, 7, 14, 9, 30),
          available: true,
        ),
      ];
      when(
        () => repo.getMasterSlots(
          masterId: any(named: 'masterId'),
          serviceId: any(named: 'serviceId'),
          date: any(named: 'date'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((_) async => fixture);

      final container = makeContainer();
      final result = await container.read(
        salonMasterDaySlotsProvider(query).future,
      );

      expect(result, fixture);
      final captured = verify(
        () => repo.getMasterSlots(
          masterId: captureAny(named: 'masterId'),
          serviceId: captureAny(named: 'serviceId'),
          date: captureAny(named: 'date'),
          cancelToken: captureAny(named: 'cancelToken'),
        ),
      ).captured;
      expect(captured[0], 'm1');
      expect(captured[1], 'svc-1');
      expect(captured[2], DateTime(2026, 7, 14));
    });

    test('cancels the in-flight request\'s CancelToken when the family '
        'instance is superseded, mirroring workingDaysProvider\'s '
        'cancel-on-supersede behaviour', () async {
      final Completer<List<BookingSlot>> pending =
          Completer<List<BookingSlot>>();
      when(
        () => repo.getMasterSlots(
          masterId: any(named: 'masterId'),
          serviceId: any(named: 'serviceId'),
          date: any(named: 'date'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((_) => pending.future);

      final container = makeContainer();
      final query = SalonMasterDaySlotsQuery(
        masterId: 'm1',
        serviceId: 'svc-1',
        date: DateTime(2026, 7, 14),
      );

      final sub = container.listen(
        salonMasterDaySlotsProvider(query),
        (_, _) {},
      );
      await Future<void>.delayed(Duration.zero);

      final captured = verify(
        () => repo.getMasterSlots(
          masterId: any(named: 'masterId'),
          serviceId: any(named: 'serviceId'),
          date: any(named: 'date'),
          cancelToken: captureAny(named: 'cancelToken'),
        ),
      ).captured;
      final CancelToken token = captured.single as CancelToken;
      expect(token.isCancelled, isFalse);

      sub.close();
      container.invalidate(salonMasterDaySlotsProvider(query));

      expect(token.isCancelled, isTrue);
      pending.complete(const <BookingSlot>[]);
    });
  });
}

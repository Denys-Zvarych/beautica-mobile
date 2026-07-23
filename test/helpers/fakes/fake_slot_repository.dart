// Fake [SlotRepository] for widget tests.
//
// Returns settled (empty by default) read results so any screen reached
// through `slotRepositoryProvider` — `workingDaysProvider`'s dependency
// (SlotDateScreen's calendar gate) and `SlotPickerNotifier`'s
// `getMasterSlots` fetch — resolves on the first microtask without touching
// the real Dio stack or leaking a connection-timeout `Timer` past widget-test
// teardown. Default behaviour mirrors [FakeServiceRepository]: read paths
// return settled data immediately.

import 'package:beautica_mobile/features/booking/data/slot_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot.dart';
import 'package:beautica_mobile/features/booking/domain/working_day.dart';
import 'package:dio/dio.dart';

/// In-memory [SlotRepository] implementation for tests.
///
/// Assign [slots] / [workingDays] to control the read responses.
final class FakeSlotRepository implements SlotRepository {
  FakeSlotRepository({List<BookingSlot>? slots, List<WorkingDay>? workingDays})
    : _slots = slots ?? const <BookingSlot>[],
      _workingDays = workingDays ?? const <WorkingDay>[];

  final List<BookingSlot> _slots;
  final List<WorkingDay> _workingDays;

  @override
  Future<List<BookingSlot>> getMasterSlots({
    required String masterId,
    required String serviceId,
    required DateTime date,
    CancelToken? cancelToken,
  }) async => _slots;

  @override
  Future<List<WorkingDay>> getWorkingDays({
    required String masterId,
    required DateTime from,
    required DateTime to,
    String? serviceId,
    CancelToken? cancelToken,
  }) async => _workingDays;
}

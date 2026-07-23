// Phase 14.1 — SlotPickerNotifier: shared state for the two-screen slot
// picker (`SlotDateScreen` + `SlotTimeScreen`).
//
// A single, non-family `@riverpod` [AsyncNotifier]-style provider (autoDispose
// by default) watched by BOTH screens of the date→time flow. Because
// `context.push` keeps the pushed-FROM screen mounted (just obscured) rather
// than disposing it, [SlotDateScreen]'s `ref.watch(slotPickerProvider)` keeps
// this provider alive for the whole flow without `keepAlive: true` — it
// disposes cleanly once both screens are popped, so a later booking attempt
// (possibly for a different master/service) always starts from a fresh
// `build()`.
//
// [masterId] / [serviceId] are NOT baked into a family key (unlike e.g.
// `serviceById`): [loadSlots] takes them as explicit parameters instead. This
// keeps the provider's shape simple (no family-of-class-notifier codegen risk)
// and matches the phase doc's literal description of the state shape
// (`{selectedDate, selectedSlot, AsyncValue<List<BookingSlot>> slots}`).

import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/booking_providers.dart';
import '../data/slot_repository.dart';
import '../domain/booking_slot.dart';

part 'slot_picker_notifier.g.dart';

/// Immutable state for the slot picker: the currently selected date/slot and
/// the [AsyncValue] of that date's fetched slots.
class SlotPickerState {
  const SlotPickerState({
    this.selectedDate,
    this.selectedSlot,
    this.slots = const AsyncData<List<BookingSlot>>(<BookingSlot>[]),
  });

  /// The date chosen on the date screen, or `null` before any pick.
  final DateTime? selectedDate;

  /// The slot chosen on the time screen, or `null` before any pick.
  final BookingSlot? selectedSlot;

  /// The fetched slots for [selectedDate].
  final AsyncValue<List<BookingSlot>> slots;

  SlotPickerState copyWith({
    DateTime? selectedDate,
    bool clearSelectedSlot = false,
    BookingSlot? selectedSlot,
    AsyncValue<List<BookingSlot>>? slots,
  }) {
    return SlotPickerState(
      selectedDate: selectedDate ?? this.selectedDate,
      selectedSlot: clearSelectedSlot
          ? null
          : (selectedSlot ?? this.selectedSlot),
      slots: slots ?? this.slots,
    );
  }
}

/// Drives the shared date/time selection state for the slot picker.
@riverpod
class SlotPicker extends _$SlotPicker {
  /// The [CancelToken] for the currently in-flight (or most recently issued)
  /// `getMasterSlots` request, if any. Cancelled at the START of every new
  /// [loadSlots] call so rapid day-switching never stacks N concurrent
  /// requests — only response-side staleness ([state.selectedDate] mismatch)
  /// used to be guarded against; the REQUEST itself now gets cancelled too.
  CancelToken? _activeCancelToken;

  @override
  SlotPickerState build() {
    ref.onDispose(() => _activeCancelToken?.cancel());
    return const SlotPickerState();
  }

  /// Selects [date], resets any previously-chosen slot, and fetches that
  /// day's slots for [masterId] + the ordered [serviceIds] visit selection
  /// (non-empty; one element in the single-service path — MO-3/MO-4 wire the
  /// multi-service summed block).
  Future<void> loadSlots({
    required String masterId,
    required List<String> serviceIds,
    required DateTime date,
  }) async {
    _activeCancelToken?.cancel();
    final CancelToken cancelToken = CancelToken();
    _activeCancelToken = cancelToken;

    state = state.copyWith(
      selectedDate: date,
      clearSelectedSlot: true,
      slots: const AsyncLoading<List<BookingSlot>>(),
    );
    final SlotRepository repo = ref.read(slotRepositoryProvider);
    final AsyncValue<List<BookingSlot>> result = await AsyncValue.guard(
      () => repo.getMasterSlots(
        masterId: masterId,
        serviceIds: serviceIds,
        date: date,
        cancelToken: cancelToken,
      ),
    );
    // This request was superseded by a newer loadSlots call (which already
    // cancelled `cancelToken` above) — discard its (cancellation-error)
    // result rather than letting it clobber the newer in-flight state.
    if (cancelToken.isCancelled) return;
    // Guard against a stale response overwriting a NEWER date selection made
    // while this fetch was in flight (rapid re-tapping different days).
    if (state.selectedDate != date) return;
    state = state.copyWith(slots: result);
  }

  /// Selects [slot] as the client's chosen appointment time.
  void selectSlot(BookingSlot slot) {
    state = state.copyWith(selectedSlot: slot);
  }
}

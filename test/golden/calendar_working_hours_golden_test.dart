// Phase 17.4 — Visual regression goldens for WorkingHoursScreen.
//
// WorkingHoursScreen is a weekly grid editor — one neumorphic row per ISO day
// (Mon–Sun) with time-picker fields. It is date-bearing: the notifier reads the
// working hours stored in the backend, but the SCREEN itself does not render a
// date — it just shows the weekly template. No clock override is needed.
//
// Two states goldened per matrix cell:
//   • LOADED — full 7-day week with Mon–Fri active 09:00–18:00, Sat–Sun closed.
//   • LOADING — AsyncLoading state (shows skeleton/spinner).
//
// Matrix: {320, 360, 414} dp × {textScale 1.0, 1.3} = 12 golden PNGs.
//
// Strategy:
//   • Override [workingHoursRepositoryProvider] with a [_StubWorkingHoursRepo]
//     that returns the seed week synchronously.
//   • [masterProfileProvider] and [clockProvider] are not needed because
//     [workingHoursRepositoryProvider] is overridden directly — the provider
//     factory never runs.
//   • No router: WorkingHoursScreen calls context.go() only on CTA tap or
//     navigation events, not during initial render.

import 'dart:async';

import 'package:beautica_mobile/features/calendar/data/working_hours_repository.dart';
import 'package:beautica_mobile/features/calendar/data/working_hours_repository_provider.dart';
import 'package:beautica_mobile/features/calendar/domain/working_hours.dart';
import 'package:beautica_mobile/features/calendar/presentation/working_hours_screen.dart';

import 'helpers/golden_pump.dart';

// ---------------------------------------------------------------------------
// Stub repository — returns a fixed 7-day week without network I/O.
// ---------------------------------------------------------------------------

final class _StubWorkingHoursRepo implements WorkingHoursRepository {
  _StubWorkingHoursRepo(this._hours);
  final List<WorkingHours> _hours;

  @override
  Future<List<WorkingHours>> list() async => _hours;

  @override
  Future<List<WorkingHours>> replaceAll(List<WorkingHours> hours) async =>
      _hours;
}

// ---------------------------------------------------------------------------
// Loading stub — [list] never completes, so the screen stays in AsyncLoading
// and renders its CircularProgressIndicator for the LOADING golden.
// ---------------------------------------------------------------------------

final class _LoadingWorkingHoursRepo implements WorkingHoursRepository {
  @override
  Future<List<WorkingHours>> list() => Completer<List<WorkingHours>>().future;

  @override
  Future<List<WorkingHours>> replaceAll(List<WorkingHours> hours) async =>
      hours;
}

// ---------------------------------------------------------------------------
// Seed data — Mon–Fri 09:00–18:00, Sat 10:00–14:00, Sun closed.
// ---------------------------------------------------------------------------

List<WorkingHours> _seedWeek() => const <WorkingHours>[
  WorkingHours(
    dayOfWeek: 1,
    startTime: '09:00:00',
    endTime: '18:00:00',
    isActive: true,
  ),
  WorkingHours(
    dayOfWeek: 2,
    startTime: '09:00:00',
    endTime: '18:00:00',
    isActive: true,
  ),
  WorkingHours(
    dayOfWeek: 3,
    startTime: '09:00:00',
    endTime: '18:00:00',
    isActive: true,
  ),
  WorkingHours(
    dayOfWeek: 4,
    startTime: '09:00:00',
    endTime: '18:00:00',
    isActive: true,
  ),
  WorkingHours(
    dayOfWeek: 5,
    startTime: '09:00:00',
    endTime: '18:00:00',
    isActive: true,
  ),
  WorkingHours(
    dayOfWeek: 6,
    startTime: '10:00:00',
    endTime: '14:00:00',
    isActive: true,
  ),
  WorkingHours(
    dayOfWeek: 7,
    startTime: '09:00:00',
    endTime: '18:00:00',
    isActive: false,
  ),
];

// ---------------------------------------------------------------------------
// Override factory
// ---------------------------------------------------------------------------

List<Object> _loadedOverrides() => <Object>[
  workingHoursRepositoryProvider.overrideWithValue(
    _StubWorkingHoursRepo(_seedWeek()),
  ),
];

List<Object> _loadingOverrides() => <Object>[
  workingHoursRepositoryProvider.overrideWithValue(_LoadingWorkingHoursRepo()),
];

// ---------------------------------------------------------------------------
// Goldens
// ---------------------------------------------------------------------------

void main() {
  for (final width in kGoldenWidths) {
    for (final scale in kGoldenTextScales) {
      final suffix = widthScaleSuffix(width, scale);

      // LOADED state
      goldenTest(
        'working_hours LOADED ${width.toInt()}dp text-${scale}x',
        fileName: 'working_hours_loaded_$suffix',
        constraints: BoxConstraints.tight(Size(width, kGoldenHeight)),
        textScaleFactor: scale,
        pumpWidget: goldenPumpWidget(
          overrides: _loadedOverrides(),
          width: width,
        ),
        builder: () => const WorkingHoursScreen(),
      );

      // LOADING state — AsyncLoading; the repository's list() never resolves so
      // the screen renders its CircularProgressIndicator. settle:false because
      // the spinner animates forever and pumpAndSettle would time out.
      goldenTest(
        'working_hours LOADING ${width.toInt()}dp text-${scale}x',
        fileName: 'working_hours_loading_$suffix',
        constraints: BoxConstraints.tight(Size(width, kGoldenHeight)),
        textScaleFactor: scale,
        // pumpBeforeTest: pumpOnce — overrides alchemist's default
        // onlyPumpAndSettle, which would otherwise time out on the perpetual
        // CircularProgressIndicator. Combined with settle:false on the pump
        // override, the spinner is captured at a deterministic single frame.
        pumpBeforeTest: pumpOnce,
        pumpWidget: goldenPumpWidget(
          overrides: _loadingOverrides(),
          width: width,
          settle: false,
        ),
        builder: () => const WorkingHoursScreen(),
      );
    }
  }
}

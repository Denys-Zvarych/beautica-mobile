// BookingTimeScreen: the independent-master booking flow's time step — a
// horizontal `PageView` slider, one slide per service the client selected in
// Step 1 (`ServiceSelectorSheet`).
//
// The independent analogue of `salon_time_screen.dart`, keyed by SERVICE
// instead of MASTER. Each slide (`ServiceSchedulePage`) picks ONE date + time
// PER SERVICE — the confirmed salon-parity UX (a separate time per selected
// service). Completing a service's date+time auto-advances the slider to the
// next unscheduled service; «Підтвердити» enables only once EVERY slide has a
// date and a time.
//
// NO `POST /bookings` CALL IN THIS SCREEN: «Підтвердити» is PURE FORWARD
// NAVIGATION — it snapshots every service's picked date/time into concrete
// `BookingAppointment`s (each with a STABLE idempotency key generated ONCE
// here, never on retry) and pushes `RouteNames.bookingConfirm`, where the
// actual N-booking submit runs (`BookingConfirmScreen` →
// `IndependentBookingSubmit`, one `POST /bookings` per service). Before
// navigating it runs a client-side self-overlap guard (mirrors the backend's
// CLIENT_BOOKING_CONFLICT 409): two services scheduled at overlapping times
// are rejected with a clear Ukrainian message rather than sent to fail.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';

import '../application/independent_booking_schedule_notifier.dart';
import '../domain/booking_appointment.dart';
import '../domain/booking_confirm_args.dart';
import '../domain/booking_slot.dart';
import '../domain/booking_slot_picker_args.dart';
import 'widgets/independent_schedule_confirm_bar.dart';
import 'widgets/service_schedule_page.dart';

const Uuid _kUuid = Uuid();

/// Independent-master booking flow — per-service date/time picker, opened by
/// `ServiceSelectorSheet`'s «Далі» CTA.
class BookingTimeScreen extends ConsumerStatefulWidget {
  const BookingTimeScreen({super.key, required this.args});

  final BookingSlotPickerArgs args;

  @override
  ConsumerState<BookingTimeScreen> createState() => _BookingTimeScreenState();
}

class _BookingTimeScreenState extends ConsumerState<BookingTimeScreen> {
  PageController? _pager;
  int _current = 0;
  bool _poppedForMissingServices = false;

  /// The resolved serviceIds from the most recent successful `build()`, kept
  /// as a field so the back handlers can resolve the ACTIVE slide's service
  /// (mirrors `salon_time_screen.dart`'s `_masterIds`).
  List<String> _serviceIds = const <String>[];

  late final ScreenProtectionManager _screenProtection;

  @override
  void initState() {
    super.initState();
    // SEC: this screen renders the client's selected service names + the
    // master's address context (via `ServiceSchedulePage`'s `MasterStrip`) —
    // guard against screenshots / app-switcher snapshots while mounted.
    // Mirrors the salon time screen. Do not remove in a future audit pass.
    _screenProtection = ref.read(screenProtectionProvider)..acquire();
  }

  @override
  void dispose() {
    _screenProtection.release();
    _pager?.dispose();
    super.dispose();
  }

  void _goTo(int index, int count) {
    if (index < 0 || index >= count) return;
    final PageController? pager = _pager;
    if (pager == null || !pager.hasClients) return;
    pager.animateToPage(
      index,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  void _handleCompleted(int index, List<String> serviceIds) {
    final int? next = ref
        .read(independentBookingScheduleProvider)
        .nextUnscheduledIndex(serviceIds, index);
    if (next != null) _goTo(next, serviceIds.length);
  }

  /// Snapshots every service's picked date/time into concrete
  /// [BookingAppointment]s and pushes the confirmation screen. The CTA is only
  /// enabled once every service is scheduled, so each entry here has a
  /// non-null slot — any without one is defensively skipped. Each appointment
  /// gets a STABLE idempotency key generated here (once, not on retry).
  ///
  /// Runs the client-side self-overlap guard first: if any two chosen windows
  /// overlap, it shows a clear message and does NOT navigate (pre-empting the
  /// backend's per-appointment CLIENT_BOOKING_CONFLICT 409).
  void _confirm(List<MasterService> services) {
    final IndependentBookingScheduleState schedule = ref.read(
      independentBookingScheduleProvider,
    );
    final List<BookingAppointment> appointments = <BookingAppointment>[
      for (final MasterService s in services)
        if (schedule.entryFor(s.id).slot case final BookingSlot slot?)
          BookingAppointment(
            serviceId: s.id,
            startAt: slot.startAt,
            idempotencyKey: _kUuid.v4(),
          ),
    ];
    if (appointments.isEmpty) return;

    if (_hasOverlap(appointments, services)) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.bookingServiceOverlapError),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    context.push(
      RouteNames.bookingConfirm,
      extra: BookingConfirmArgs(
        masterId: widget.args.masterId,
        appointments: appointments,
        master: widget.args.master,
        rescheduleBookingId: widget.args.rescheduleBookingId,
      ),
    );
  }

  /// `true` if any two appointments' [start, start + duration) windows overlap.
  /// Consecutive (touching but non-overlapping) windows are fine — that is
  /// exactly what the backend permits.
  bool _hasOverlap(
    List<BookingAppointment> appointments,
    List<MasterService> services,
  ) {
    final Map<String, int> durationById = <String, int>{
      for (final MasterService s in services) s.id: s.durationMinutes,
    };
    final List<BookingAppointment> sorted =
        <BookingAppointment>[...appointments]..sort(
          (BookingAppointment a, BookingAppointment b) =>
              a.startAt.compareTo(b.startAt),
        );
    for (int i = 1; i < sorted.length; i++) {
      final BookingAppointment prev = sorted[i - 1];
      final BookingAppointment cur = sorted[i];
      final DateTime prevEnd = prev.startAt.add(
        Duration(minutes: durationById[prev.serviceId] ?? 0),
      );
      if (cur.startAt.isBefore(prevEnd)) return true;
    }
    return false;
  }

  bool _activeServiceIsInTimePhase() {
    if (_current < 0 || _current >= _serviceIds.length) return false;
    return ref
            .read(independentBookingScheduleProvider)
            .entryFor(_serviceIds[_current])
            .date !=
        null;
  }

  void _exitActiveServiceTimePhase() {
    if (_current < 0 || _current >= _serviceIds.length) return;
    ref
        .read(independentBookingScheduleProvider.notifier)
        .clearDate(_serviceIds[_current]);
  }

  void _handleTopBarBack() {
    if (_activeServiceIsInTimePhase()) {
      _exitActiveServiceTimePhase();
      return;
    }
    context.pop();
  }

  static bool _activeSlideInTimePhase(
    IndependentBookingScheduleState s,
    int current,
    List<String> serviceIds,
  ) {
    if (current < 0 || current >= serviceIds.length) return false;
    return s.entryFor(serviceIds[current]).date != null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final List<MasterService> services = widget.args.services;

    if (services.isEmpty) {
      // Defensive: this route is only reachable via `ServiceSelectorSheet`'s
      // «Далі», which requires at least one service — reaching it empty is a
      // broken-flow edge case (e.g. a stale deep link).
      if (!_poppedForMissingServices) {
        _poppedForMissingServices = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) context.pop();
        });
      }
      return const Scaffold(body: SizedBox.shrink());
    }

    final List<String> serviceIds = <String>[
      for (final MasterService s in services) s.id,
    ];
    _serviceIds = serviceIds;

    // Per-service occupancy (duration + post-booking buffer), threaded into
    // every slide so each `ServiceSchedulePage` can pre-disable the slots that
    // would overlap a sibling service already scheduled on the same day. This
    // is client-side only — the slots endpoint reflects CONFIRMED bookings, not
    // these in-session picks (the backend CLIENT_BOOKING_CONFLICT 409 remains
    // the authoritative backstop, still pre-empted by `_hasOverlap` below).
    final Map<String, int> occupancyMinutesByServiceId = <String, int>{
      for (final MasterService s in services)
        s.id: s.durationMinutes + s.bufferMinutesAfter,
    };

    if (_pager == null) {
      final int initialPage =
          ref
              .read(independentBookingScheduleProvider)
              .nextUnscheduledIndex(serviceIds, -1) ??
          0;
      _pager = PageController(initialPage: initialPage);
      _current = initialPage;
    }
    if (_current >= serviceIds.length) _current = serviceIds.length - 1;

    final Widget body = Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            VelvetSpacing.lg,
            0,
            VelvetSpacing.lg,
            VelvetSpacing.xs,
          ),
          child: Consumer(
            builder: (BuildContext context, WidgetRef ref, Widget? child) {
              final int scheduledMask = ref.watch(
                independentBookingScheduleProvider.select((
                  IndependentBookingScheduleState s,
                ) {
                  int mask = 0;
                  for (int i = 0; i < serviceIds.length; i++) {
                    if (s.isScheduled(serviceIds[i])) mask |= 1 << i;
                  }
                  return mask;
                }),
              );
              return _ServicePager(
                count: serviceIds.length,
                current: _current,
                isScheduled: (int i) => (scheduledMask & (1 << i)) != 0,
                onPrev: _current > 0
                    ? () => _goTo(_current - 1, serviceIds.length)
                    : null,
                onNext: _current < serviceIds.length - 1
                    ? () => _goTo(_current + 1, serviceIds.length)
                    : null,
                onJump: (int i) => _goTo(i, serviceIds.length),
              );
            },
          ),
        ),
        Expanded(
          child: PageView.builder(
            controller: _pager,
            physics: const BouncingScrollPhysics(),
            onPageChanged: (int i) => setState(() => _current = i),
            itemCount: services.length,
            itemBuilder: (BuildContext context, int i) {
              final MasterService service = services[i];
              return ServiceSchedulePage(
                key: ValueKey<String>('service-schedule-page-${service.id}'),
                master: widget.args.master,
                service: service,
                occupancyMinutesByServiceId: occupancyMinutesByServiceId,
                onCompleted: () => _handleCompleted(i, serviceIds),
                keepAlive: (i - _current).abs() <= 1,
              );
            },
          ),
        ),
      ],
    );

    final Widget bottomBar = Consumer(
      builder: (BuildContext context, WidgetRef ref, Widget? child) {
        // The whole schedule state drives this bar: `allScheduled` gates the
        // CTA, and every scheduled service's slot feeds its chosen-window
        // label into the shelf. Watching the state (not a narrow `.select`) is
        // deliberate — a slot pick on any slide must both re-evaluate the CTA
        // and refresh that service's shelf row. This is an isolated `Consumer`,
        // so only this small bar rebuilds, never the calendar/time grid above.
        final IndependentBookingScheduleState schedule = ref.watch(
          independentBookingScheduleProvider,
        );
        final Map<String, String> chosenWindows = <String, String>{
          for (final MasterService s in services)
            if (schedule.entryFor(s.id).slot case final BookingSlot slot?)
              s.id: formatBookingWindow(
                slot.startAt,
                slot.startAt.add(Duration(minutes: s.durationMinutes)),
              ),
        };
        return IndependentScheduleConfirmBar(
          key: const Key('booking-time-cta-footer'),
          ctaKey: const Key('booking-time-confirm-cta'),
          services: services,
          chosenWindowByServiceId: chosenWindows,
          enabled: schedule.allScheduled(serviceIds),
          onConfirm: () => _confirm(services),
        );
      },
    );

    return Consumer(
      builder: (BuildContext context, WidgetRef ref, Widget? child) {
        final int current = _current;
        final List<String> ids = _serviceIds;
        final bool inTimePhase = ref.watch(
          independentBookingScheduleProvider.select(
            (IndependentBookingScheduleState s) =>
                _activeSlideInTimePhase(s, current, ids),
          ),
        );
        return PopScope(
          canPop: !inTimePhase,
          onPopInvokedWithResult: (bool didPop, Object? result) {
            if (!didPop) _exitActiveServiceTimePhase();
          },
          child: child!,
        );
      },
      child: Scaffold(
        backgroundColor: BrandColors.base,
        bottomNavigationBar: bottomBar,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              Consumer(
                builder: (BuildContext context, WidgetRef ref, Widget? child) {
                  final int current = _current;
                  final List<String> ids = _serviceIds;
                  final bool inTimePhase = ref.watch(
                    independentBookingScheduleProvider.select(
                      (IndependentBookingScheduleState s) =>
                          _activeSlideInTimePhase(s, current, ids),
                    ),
                  );
                  return _TopBar(
                    title: l10n.bookingServiceTimeTitle,
                    backSemantics: inTimePhase
                        ? l10n.bookingTimeScreenBackSemantics
                        : l10n.bookingServiceTimeBackSemantics,
                    onBack: _handleTopBarBack,
                  );
                },
              ),
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top bar + step indicator (mirrors SalonTimeScreen's copy)
// ---------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.backSemantics,
    required this.onBack,
  });

  final String title;
  final String backSemantics;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.lg,
        VelvetSpacing.md,
        VelvetSpacing.lg,
        VelvetSpacing.sm,
      ),
      child: SizedBox(
        height: 56,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Align(
              alignment: Alignment.centerLeft,
              child: NeumorphicIconButton(
                key: const Key('booking-time-back'),
                icon: Icons.arrow_back_ios_new_rounded,
                semanticLabel: backSemantics,
                onTap: onBack,
              ),
            ),
            Text(
              title,
              style: VelvetText.subheading(),
              textAlign: TextAlign.center,
            ),
            const Align(
              alignment: Alignment.centerRight,
              child: _StepIndicator(current: 2, total: 3),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      label: l10n.salonBookingStepLabel(current, total),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: VelvetSpacing.sm + 2,
              vertical: 3,
            ),
            decoration: BoxDecoration(
              color: BrandColors.base,
              borderRadius: BorderRadius.circular(VelvetRadii.pill),
              boxShadow: VelvetShadows.extrudedSmall,
            ),
            child: Text(
              l10n.salonBookingStepLabel(current, total),
              style: VelvetText.stepPillLabel,
            ),
          ),
          const SizedBox(height: VelvetSpacing.sm),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (int i = 1; i <= total; i++) ...<Widget>[
                Container(
                  height: 4,
                  width: i == current ? 20 : 12,
                  decoration: BoxDecoration(
                    color: i <= current
                        ? BrandColors.accent
                        : BrandColors.faint.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(VelvetRadii.pill),
                  ),
                ),
                if (i < total) const SizedBox(width: 4),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Slider position indicator — ‹ › arrows + per-service dots + counter.
// ---------------------------------------------------------------------------

class _ServicePager extends StatelessWidget {
  const _ServicePager({
    required this.count,
    required this.current,
    required this.isScheduled,
    required this.onPrev,
    required this.onNext,
    required this.onJump,
  });

  final int count;
  final int current;
  final bool Function(int) isScheduled;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final ValueChanged<int> onJump;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final int doneCount = List<int>.generate(
      count,
      (int i) => i,
    ).where(isScheduled).length;
    return Semantics(
      label: l10n.bookingServicePagerSemantics(current + 1, count, doneCount),
      child: Row(
        children: <Widget>[
          _PagerArrow(
            icon: Icons.chevron_left_rounded,
            semanticLabel: l10n.bookingServicePagerPrevSemantics,
            onTap: onPrev,
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    for (int i = 0; i < count; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: _PagerDot(
                          key: Key('booking-time-pager-dot-$i'),
                          current: i == current,
                          done: isScheduled(i),
                          semanticLabel: isScheduled(i)
                              ? l10n.bookingServicePagerDotDoneLabel(i + 1)
                              : l10n.bookingServicePagerDotLabel(i + 1),
                          onTap: () => onJump(i),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: VelvetSpacing.xs),
                Text(
                  l10n.bookingServicePagerCounterLabel(current + 1, count),
                  style: VelvetText.schedulePagerCounter,
                ),
              ],
            ),
          ),
          _PagerArrow(
            icon: Icons.chevron_right_rounded,
            semanticLabel: l10n.bookingServicePagerNextSemantics,
            onTap: onNext,
          ),
        ],
      ),
    );
  }
}

class _PagerDot extends StatelessWidget {
  const _PagerDot({
    super.key,
    required this.current,
    required this.done,
    required this.semanticLabel,
    required this.onTap,
  });

  final bool current;
  final bool done;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Widget dot = AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      height: 10,
      width: current ? 26 : 10,
      decoration: BoxDecoration(
        gradient: done
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  BrandColors.accentLatte,
                  BrandColors.accentDeep,
                ],
              )
            : null,
        color: done
            ? null
            : current
            ? BrandColors.accent
            : BrandColors.faint.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
      ),
      alignment: Alignment.center,
      child: done && !current
          ? const Icon(Icons.check_rounded, size: 8, color: BrandColors.white)
          : null,
    );
    return Semantics(
      button: true,
      selected: current,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: VelvetSpacing.xs),
          child: dot,
        ),
      ),
    );
  }
}

class _PagerArrow extends StatefulWidget {
  const _PagerArrow({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  State<_PagerArrow> createState() => _PagerArrowState();
}

class _PagerArrowState extends State<_PagerArrow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onTap != null;
    final Color glyph = enabled ? BrandColors.accentDeep : BrandColors.faint;

    final Widget face = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: 40,
      width: 40,
      decoration: BoxDecoration(
        color: BrandColors.base,
        borderRadius: BorderRadius.circular(VelvetRadii.field),
        boxShadow: (!enabled || _pressed) ? null : VelvetShadows.extrudedSmall,
      ),
      child: Icon(widget.icon, color: glyph, size: 24),
    );

    if (!enabled) {
      return Semantics(
        button: true,
        enabled: false,
        label: widget.semanticLabel,
        child: Opacity(opacity: 0.55, child: face),
      );
    }
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap!();
        },
        child: face,
      ),
    );
  }
}

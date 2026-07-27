// Phase 15.1 — Unit tests for [ScheduleMapper] (generated DTO ⇄ domain).
//
// Covers: WorkIntervalDto ⇄ WorkInterval time format; weekly response gap-fill
// to 7 ordered ISO days + request→response round-trip; override CUSTOM_HOURS ⇄
// intervals and DAY_OFF ⇄ empty intervals (reason/note dropped from the
// contract); effective-day source mapping for every wire value; leap-day date
// parse/serialise.
//
// Pure Dart: builds generated built_value DTOs directly, no network.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_mapper.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:built_collection/built_collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

WorkIntervalDto _dto(String start, String end) => WorkIntervalDto(
  (b) => b
    ..startTime = start
    ..endTime = end,
);

void main() {
  group('WorkInterval ⇄ WorkIntervalDto', () {
    test('parses "09:00:00" dropping seconds', () {
      final wi = ScheduleMapper.intervalFromDto(_dto('09:00:00', '18:30:00'));
      expect(wi.start, const TimeOfDay(hour: 9, minute: 0));
      expect(wi.end, const TimeOfDay(hour: 18, minute: 30));
    });

    test('serialises TimeOfDay → "HH:mm:00" (seconds zeroed)', () {
      final dto = ScheduleMapper.intervalToDto(
        WorkInterval(
          start: const TimeOfDay(hour: 9, minute: 5),
          end: const TimeOfDay(hour: 17, minute: 0),
        ),
      );
      expect(dto.startTime, '09:05:00');
      expect(dto.endTime, '17:00:00');
    });

    test('parseTime tolerates malformed / null → midnight', () {
      expect(
        ScheduleMapper.parseTime(null),
        const TimeOfDay(hour: 0, minute: 0),
      );
      expect(ScheduleMapper.parseTime(''), const TimeOfDay(hour: 0, minute: 0));
    });
  });

  group('weeklyScheduleFromResponse — gap-fill to 7 ISO days', () {
    test(
      'sparse 5-day response → 7 TemplateDays ordered 1..7, gaps day-off',
      () {
        // Backend sends only Mon–Fri (1..5), each 09:00–18:00.
        final response = WeeklyScheduleResponse(
          (b) => b
            ..validFrom = Date(2026, 6, 1)
            ..validTo = null
            ..days = ListBuilder<WeeklyScheduleDayResponse>(
              <WeeklyScheduleDayResponse>[
                for (var dow = 1; dow <= 5; dow++)
                  WeeklyScheduleDayResponse(
                    (db) => db
                      ..dayOfWeek = dow
                      ..intervals = ListBuilder<WorkIntervalDto>(
                        <WorkIntervalDto>[_dto('09:00:00', '18:00:00')],
                      ),
                  ),
              ],
            ),
        );

        final schedule = ScheduleMapper.weeklyScheduleFromResponse(response);

        expect(schedule.days, hasLength(7));
        expect(schedule.days.map((d) => d.dayOfWeek), [1, 2, 3, 4, 5, 6, 7]);
        // Mon–Fri working, Sat/Sun gap-filled to day-off (empty intervals).
        expect(
          schedule.days.take(5).every((d) => d.intervals.isNotEmpty),
          isTrue,
        );
        expect(schedule.days[5].isDayOff, isTrue);
        expect(schedule.days[6].isDayOff, isTrue);
        expect(schedule.validFrom, DateTime(2026, 6, 1));
        expect(schedule.validTo, isNull);
      },
    );

    test('out-of-range / null dayOfWeek rows are skipped', () {
      final response = WeeklyScheduleResponse(
        (b) => b
          ..validFrom = Date(2026, 1, 1)
          ..days = ListBuilder<WeeklyScheduleDayResponse>(
            <WeeklyScheduleDayResponse>[
              WeeklyScheduleDayResponse(
                (db) => db
                  ..dayOfWeek =
                      0 // out of range
                  ..intervals = ListBuilder<WorkIntervalDto>(<WorkIntervalDto>[
                    _dto('09:00:00', '18:00:00'),
                  ]),
              ),
            ],
          ),
      );

      final schedule = ScheduleMapper.weeklyScheduleFromResponse(response);

      expect(schedule.days, hasLength(7));
      expect(schedule.days.every((d) => d.isDayOff), isTrue);
    });

    test('id attaches when supplied', () {
      final response = WeeklyScheduleResponse(
        (b) => b..validFrom = Date(2026, 6, 1),
      );
      final schedule = ScheduleMapper.weeklyScheduleFromResponse(
        response,
        id: 'sched-1',
      );
      expect(schedule.id, 'sched-1');
    });

    // ── Regression: the dropped-id bug ───────────────────────────────────────
    //
    // The weekly-template editor's create-vs-update diffing keys off
    // `existing.id`. The list path (`listWeeklySchedules`) maps each row via
    // `weeklyScheduleFromResponse` with NO explicit `id:` override, so the id
    // MUST come from the wire (`dto.id`). The original bug: the mapper ignored
    // `dto.id`, so every listed template loaded with `id == null` → the editor's
    // second save POSTed a duplicate window → backend overlap rejection
    // ("Schedule window overlaps an existing window starting ..."). These tests
    // pin `dto.id` flowing through — the exact assertion that would have caught
    // it.
    test('id flows from the wire (dto.id) when no override is given', () {
      final response = WeeklyScheduleResponse(
        (b) => b
          ..id = 'wire-sched-7'
          ..validFrom = Date(2026, 6, 1),
      );

      final schedule = ScheduleMapper.weeklyScheduleFromResponse(response);

      expect(
        schedule.id,
        'wire-sched-7',
        reason:
            'a reloaded list template must be self-identifying from dto.id so '
            'the editor PUTs (updates) instead of POSTing a duplicate window',
      );
    });

    test('explicit id override wins over dto.id (the re-attach path)', () {
      final response = WeeklyScheduleResponse(
        (b) => b
          ..id = 'wire-sched-7'
          ..validFrom = Date(2026, 6, 1),
      );

      final schedule = ScheduleMapper.weeklyScheduleFromResponse(
        response,
        id: 'targeted-id',
      );

      expect(
        schedule.id,
        'targeted-id',
        reason:
            'the create/update re-attach path pins the id the caller targeted, '
            'overriding any server echo',
      );
    });

    test('id is null when neither the wire nor an override supplies one', () {
      final response = WeeklyScheduleResponse(
        (b) => b..validFrom = Date(2026, 6, 1),
      );

      final schedule = ScheduleMapper.weeklyScheduleFromResponse(response);

      expect(schedule.id, isNull);
    });
  });

  group('weeklyScheduleToRequest — round-trips through fromResponse', () {
    test('request days survive a request→response→domain cycle unchanged', () {
      final domain = WeeklySchedule(
        validFrom: DateTime(2026, 6, 1),
        validTo: DateTime(2026, 12, 31),
        days: <TemplateDay>[
          for (var dow = 1; dow <= 7; dow++)
            TemplateDay(
              dayOfWeek: dow,
              label: 'd$dow',
              intervals: dow <= 5
                  ? <WorkInterval>[
                      WorkInterval(
                        start: const TimeOfDay(hour: 9, minute: 0),
                        end: const TimeOfDay(hour: 18, minute: 0),
                      ),
                    ]
                  : <WorkInterval>[],
            ),
        ],
      );

      final request = ScheduleMapper.weeklyScheduleToRequest(domain);

      expect(request.days, hasLength(7));
      expect(request.days!.map((d) => d.dayOfWeek), [1, 2, 3, 4, 5, 6, 7]);
      // Day-off weekdays sent as an explicit EMPTY list (not omitted).
      expect(request.days![5].intervals, isEmpty);
      expect(request.days![6].intervals, isEmpty);
      // Working days carry the single 09:00–18:00 interval.
      expect(request.days![0].intervals, hasLength(1));
      expect(request.days![0].intervals!.first.startTime, '09:00:00');
      expect(request.days![0].intervals!.first.endTime, '18:00:00');
      expect(request.validFrom, Date(2026, 6, 1));
      expect(request.validTo, Date(2026, 12, 31));

      // Rebuild a response from the request shape → fromResponse must yield the
      // same logical week (empty intervals = day off both directions).
      final response = WeeklyScheduleResponse(
        (b) => b
          ..validFrom = request.validFrom
          ..validTo = request.validTo
          ..days = ListBuilder<WeeklyScheduleDayResponse>(
            request.days!.map(
              (d) => WeeklyScheduleDayResponse(
                (db) => db
                  ..dayOfWeek = d.dayOfWeek
                  ..intervals = d.intervals!.toBuilder(),
              ),
            ),
          ),
      );

      final back = ScheduleMapper.weeklyScheduleFromResponse(response);
      expect(back.days.map((d) => d.dayOfWeek), [1, 2, 3, 4, 5, 6, 7]);
      expect(back.days.take(5).every((d) => !d.isDayOff), isTrue);
      expect(back.days[5].isDayOff, isTrue);
      expect(back.days[6].isDayOff, isTrue);
      expect(back.validFrom, DateTime(2026, 6, 1));
      expect(back.validTo, DateTime(2026, 12, 31));
    });
  });

  group('overrideFromResponse — 1 row = 1 date', () {
    test('CUSTOM_HOURS ↔ intervals (single day, start == end)', () {
      final dto = ScheduleOverrideResponse(
        (b) => b
          ..date = Date(2026, 6, 10)
          ..kind = ScheduleOverrideResponseKindEnum.CUSTOM_HOURS
          ..intervals = ListBuilder<WorkIntervalDto>(<WorkIntervalDto>[
            _dto('10:00:00', '14:00:00'),
          ]),
      );

      final override = ScheduleMapper.overrideFromResponse(dto);

      expect(override.kind, OverrideKind.custom);
      expect(override.isSingleDay, isTrue);
      expect(override.start, DateTime(2026, 6, 10));
      expect(override.end, DateTime(2026, 6, 10));
      expect(override.intervals, hasLength(1));
      expect(
        override.intervals.single.start,
        const TimeOfDay(hour: 10, minute: 0),
      );
      expect(
        override.intervals.single.end,
        const TimeOfDay(hour: 14, minute: 0),
      );
    });

    test('DAY_OFF ↔ a plain full day-off (empty intervals)', () {
      // The backend dropped reason/note from schedule overrides — those fields
      // are now structurally absent from the generated ScheduleOverrideResponse,
      // so a DAY_OFF maps to a plain closed day, nothing more.
      final dto = ScheduleOverrideResponse(
        (b) => b
          ..date = Date(2026, 7, 1)
          ..kind = ScheduleOverrideResponseKindEnum.DAY_OFF,
      );

      final override = ScheduleMapper.overrideFromResponse(dto);

      expect(override.kind, OverrideKind.dayOff);
      expect(override.intervals, isEmpty);
      expect(override.start, DateTime(2026, 7, 1));
      expect(override.end, DateTime(2026, 7, 1));
    });
  });

  group('overrideToRequestForDate', () {
    // REGRESSION (Phase 15.4 wire-contract change): a DAY_OFF override request
    // sets ONLY `date` + `kind`. The backend dropped reason/note, so those
    // fields are now structurally absent from the generated request type —
    // their omission is type-enforced, not something the mapper must assert.
    //
    // This is also the stale-code/regen-drift guard for the reason/note
    // removal: if a future regen re-introduced `reason`/`note` on
    // ScheduleOverrideRequest (contract drift), the mapper that was cleaned of
    // those members would still build a request with ONLY date + kind set, and
    // this test would keep passing — while the build would no longer fail. The
    // type-level omission is therefore the primary guard; this test pins the
    // intended request SHAPE (date + kind, no intervals) so any behavioural
    // regression that started populating intervals on a day-off is caught here.
    test('day-off request sets ONLY date + kind — no intervals', () {
      final override = ScheduleOverride.dayOff(
        start: DateTime(2026, 7, 1),
        end: DateTime(2026, 7, 1),
      );

      final req = ScheduleMapper.overrideToRequestForDate(
        override,
        DateTime(2026, 7, 1),
      );

      // Only the two fields the new contract allows are set …
      expect(req.kind, ScheduleOverrideRequestKindEnum.DAY_OFF);
      expect(req.date, Date(2026, 7, 1));
      // … and a day-off never carries working intervals.
      expect(req.intervals ?? const <WorkIntervalDto>[], isEmpty);
    });

    test('custom-hours serialises intervals as HH:mm:00', () {
      final override = ScheduleOverride.custom(
        start: DateTime(2026, 7, 2),
        end: DateTime(2026, 7, 2),
        intervals: <WorkInterval>[
          WorkInterval(
            start: const TimeOfDay(hour: 11, minute: 0),
            end: const TimeOfDay(hour: 15, minute: 30),
          ),
        ],
      );

      final req = ScheduleMapper.overrideToRequestForDate(
        override,
        DateTime(2026, 7, 2),
      );

      expect(req.kind, ScheduleOverrideRequestKindEnum.CUSTOM_HOURS);
      expect(req.intervals, hasLength(1));
      expect(req.intervals!.single.startTime, '11:00:00');
      expect(req.intervals!.single.endTime, '15:30:00');
      expect(req.date, Date(2026, 7, 2));
    });
  });

  group('effectiveDayFromResponse — source mapping', () {
    final cases = <EffectiveDayResponseSource_Enum, EffectiveSource>{
      EffectiveDayResponseSource_Enum.TEMPLATE: EffectiveSource.template,
      EffectiveDayResponseSource_Enum.OVERRIDE_CUSTOM:
          EffectiveSource.overrideCustom,
      EffectiveDayResponseSource_Enum.OVERRIDE_DAY_OFF:
          EffectiveSource.overrideDayOff,
      EffectiveDayResponseSource_Enum.NO_SCHEDULE: EffectiveSource.noSchedule,
    };

    cases.forEach((wire, domain) {
      test('$wire → $domain', () {
        final dto = EffectiveDayResponse(
          (b) => b
            ..date = Date(2026, 6, 5)
            ..source_ = wire,
        );
        final eff = ScheduleMapper.effectiveDayFromResponse(dto);
        expect(eff.source, domain);
        expect(eff.date, DateTime(2026, 6, 5));
      });
    });

    test('null source collapses to noSchedule', () {
      final dto = EffectiveDayResponse((b) => b..date = Date(2026, 6, 5));
      expect(
        ScheduleMapper.effectiveDayFromResponse(dto).source,
        EffectiveSource.noSchedule,
      );
    });

    test(
      'OVERRIDE_DAY_OFF maps to the neutral closed source (no reason field on '
      'EffectiveDay)',
      () {
        // The backend dropped reason/note — those fields are now structurally
        // absent from the generated EffectiveDayResponse. The mapper resolves a
        // day-off purely as overrideDayOff with empty intervals — the neutral
        // «Вихідний» state, no reason label.
        final dto = EffectiveDayResponse(
          (b) => b
            ..date = Date(2026, 6, 5)
            ..source_ = EffectiveDayResponseSource_Enum.OVERRIDE_DAY_OFF,
        );
        final eff = ScheduleMapper.effectiveDayFromResponse(dto);
        expect(eff.source, EffectiveSource.overrideDayOff);
        expect(eff.intervals, isEmpty);
      },
    );
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Phase 15.7 — EXPLICIT_TIMES (discrete working-times) wire mapping.
  // ───────────────────────────────────────────────────────────────────────────

  group('weekly EXPLICIT_TIMES day — round-trips sorted + deduped', () {
    test('unsorted + duplicate + HH:mm:ss times → request EXPLICIT_TIMES, no '
        'intervals → response → domain, sorted + deduped', () {
      // Domain working EXPLICIT_TIMES day: Monday with three discrete starts
      // supplied UNSORTED, with a DUPLICATE (10:00 twice — one as HH:mm:ss),
      // and an HH:mm:ss-form entry. The rest of the week is a day-off.
      final domain = WeeklySchedule(
        validFrom: DateTime(2026, 6, 1),
        validTo: null,
        days: <TemplateDay>[
          TemplateDay(
            dayOfWeek: 1,
            label: 'd1',
            mode: WeekdayMode.explicitTimes,
            intervals: const <WorkInterval>[],
            times: const <TimeOfDay>[
              TimeOfDay(hour: 14, minute: 0),
              TimeOfDay(hour: 10, minute: 0),
              TimeOfDay(hour: 10, minute: 0), // duplicate (wall-clock)
              TimeOfDay(hour: 9, minute: 30),
            ],
          ),
          for (var dow = 2; dow <= 7; dow++)
            TemplateDay(
              dayOfWeek: dow,
              label: 'd$dow',
              intervals: const <WorkInterval>[],
            ),
        ],
      );

      final request = ScheduleMapper.weeklyScheduleToRequest(domain);

      // The EXPLICIT_TIMES day serialises as mode=EXPLICIT_TIMES + a sorted,
      // de-duped HH:mm:00 times list — and carries NO intervals.
      final monReq = request.days!.firstWhere((d) => d.dayOfWeek == 1);
      expect(monReq.mode, WeeklyScheduleDayRequestModeEnum.EXPLICIT_TIMES);
      expect(monReq.times!.toList(), <String>[
        '09:30:00',
        '10:00:00',
        '14:00:00',
      ]);
      expect(monReq.intervals ?? const <WorkIntervalDto>[], isEmpty);

      // Rebuild a response that echoes the request shape, then read it back.
      final response = WeeklyScheduleResponse(
        (b) => b
          ..validFrom = request.validFrom
          ..days = ListBuilder<WeeklyScheduleDayResponse>(
            request.days!.map(
              (d) => WeeklyScheduleDayResponse(
                (db) => db
                  ..dayOfWeek = d.dayOfWeek
                  ..mode =
                      d.mode == WeeklyScheduleDayRequestModeEnum.EXPLICIT_TIMES
                      ? WeeklyScheduleDayResponseModeEnum.EXPLICIT_TIMES
                      : WeeklyScheduleDayResponseModeEnum.INTERVAL
                  ..times = d.times?.toBuilder()
                  ..intervals = d.intervals?.toBuilder(),
              ),
            ),
          ),
      );

      final back = ScheduleMapper.weeklyScheduleFromResponse(response);
      final mon = back.days.firstWhere((d) => d.dayOfWeek == 1);
      expect(mon.mode, WeekdayMode.explicitTimes);
      expect(mon.intervals, isEmpty);
      expect(mon.times, <TimeOfDay>[
        const TimeOfDay(hour: 9, minute: 30),
        const TimeOfDay(hour: 10, minute: 0),
        const TimeOfDay(hour: 14, minute: 0),
      ]);
      expect(mon.isDayOff, isFalse);
    });

    test('INTERVAL day round-trips unchanged (regression)', () {
      // A plain INTERVAL working day must keep mode=INTERVAL, carry its
      // intervals, and surface NO discrete times after a full round trip.
      final domain = WeeklySchedule(
        validFrom: DateTime(2026, 6, 1),
        validTo: null,
        days: <TemplateDay>[
          TemplateDay(
            dayOfWeek: 1,
            label: 'd1',
            intervals: <WorkInterval>[
              WorkInterval(
                start: const TimeOfDay(hour: 9, minute: 0),
                end: const TimeOfDay(hour: 18, minute: 0),
              ),
            ],
          ),
          for (var dow = 2; dow <= 7; dow++)
            TemplateDay(
              dayOfWeek: dow,
              label: 'd$dow',
              intervals: const <WorkInterval>[],
            ),
        ],
      );

      final request = ScheduleMapper.weeklyScheduleToRequest(domain);
      final monReq = request.days!.firstWhere((d) => d.dayOfWeek == 1);
      expect(monReq.mode, WeeklyScheduleDayRequestModeEnum.INTERVAL);
      expect(monReq.intervals, hasLength(1));
      expect(monReq.times ?? const <String>[], isEmpty);

      final response = WeeklyScheduleResponse(
        (b) => b
          ..validFrom = request.validFrom
          ..days = ListBuilder<WeeklyScheduleDayResponse>(
            request.days!.map(
              (d) => WeeklyScheduleDayResponse(
                (db) => db
                  ..dayOfWeek = d.dayOfWeek
                  ..mode =
                      d.mode == WeeklyScheduleDayRequestModeEnum.EXPLICIT_TIMES
                      ? WeeklyScheduleDayResponseModeEnum.EXPLICIT_TIMES
                      : WeeklyScheduleDayResponseModeEnum.INTERVAL
                  ..times = d.times?.toBuilder()
                  ..intervals = d.intervals?.toBuilder(),
              ),
            ),
          ),
      );

      final back = ScheduleMapper.weeklyScheduleFromResponse(response);
      final mon = back.days.firstWhere((d) => d.dayOfWeek == 1);
      expect(mon.mode, WeekdayMode.interval);
      expect(mon.times, isEmpty);
      expect(mon.intervals, hasLength(1));
      expect(mon.intervals.single.start, const TimeOfDay(hour: 9, minute: 0));
      expect(mon.intervals.single.end, const TimeOfDay(hour: 18, minute: 0));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Phase 15.8 REGRESSION — empty-discrete day == day-off (the contract-
  // conformance bug). A `TemplateDay` left in `explicitTimes` mode but carrying
  // ZERO discrete times is NOT a valid EXPLICIT_TIMES day: the backend
  // `WeeklyScheduleDayRequest.isModeConsistent` rejects an EXPLICIT_TIMES day
  // with an empty `times` list (400 on `days[i].modeConsistent`). It means "this
  // weekday off", which is the canonical INTERVAL-empty day-off encoding.
  //
  // BUG: a fresh master profile saving a weekly schedule that left a day off
  // WHILE that day's row was in `explicitTimes` mode previously serialised as
  // `mode=EXPLICIT_TIMES, times:[]` → backend 400
  // (`MethodArgumentNotValidException` on `days[0].modeConsistent`).
  //
  // FIX (schedule_mapper.weeklyScheduleToRequest): the guard is
  // `if (d.mode == explicitTimes && d.times.isNotEmpty)` — an empty-times
  // explicit day falls through to the INTERVAL-empty (day-off) branch. These
  // tests pin the EXACT wire shape that previously 400'd.
  // ───────────────────────────────────────────────────────────────────────────

  group('weeklyScheduleToRequest — empty-discrete day == day-off (15.8 '
      'modeConsistent regression)', () {
    test('an explicitTimes day with EMPTY times serialises as INTERVAL + empty '
        'intervals + NO times (the exact shape that 400d before the fix)', () {
      // Monday is explicitTimes but the master added no slots (left it off while
      // in discrete mode). The other six days are plain INTERVAL day-offs.
      final domain = WeeklySchedule(
        validFrom: DateTime(2026, 6, 1),
        validTo: null,
        days: <TemplateDay>[
          TemplateDay(
            dayOfWeek: 1,
            label: 'd1',
            mode: WeekdayMode.explicitTimes,
            intervals: const <WorkInterval>[],
            times: const <TimeOfDay>[], // EMPTY discrete list == day-off
          ),
          for (var dow = 2; dow <= 7; dow++)
            TemplateDay(
              dayOfWeek: dow,
              label: 'd$dow',
              intervals: const <WorkInterval>[],
            ),
        ],
      );

      final request = ScheduleMapper.weeklyScheduleToRequest(domain);

      final monReq = request.days!.firstWhere((d) => d.dayOfWeek == 1);
      // The day-off MUST be INTERVAL (the canonical empty-intervals day-off),
      // NEVER EXPLICIT_TIMES with an empty times list.
      expect(
        monReq.mode,
        WeeklyScheduleDayRequestModeEnum.INTERVAL,
        reason:
            'an empty-times explicitTimes day is a day-off — it must serialise '
            'as INTERVAL, not EXPLICIT_TIMES (which would 400 on modeConsistent)',
      );
      expect(monReq.intervals ?? const <WorkIntervalDto>[], isEmpty);
      // No discrete times ride on a day-off.
      expect(monReq.times ?? const <String>[], isEmpty);
    });

    test('NO day in the request carries EXPLICIT_TIMES with an empty times list '
        '(whole-payload modeConsistent invariant)', () {
      // A realistic fresh-profile mix: one real discrete working day (Mon), one
      // empty-discrete day left off in explicit mode (Tue), and five plain
      // INTERVAL day-offs. The backend contract: EXPLICIT_TIMES ⇒ times
      // non-empty. The whole payload must satisfy it.
      final domain = WeeklySchedule(
        validFrom: DateTime(2026, 6, 1),
        validTo: null,
        days: <TemplateDay>[
          TemplateDay(
            dayOfWeek: 1,
            label: 'd1',
            mode: WeekdayMode.explicitTimes,
            intervals: const <WorkInterval>[],
            times: const <TimeOfDay>[
              TimeOfDay(hour: 9, minute: 0),
              TimeOfDay(hour: 13, minute: 0),
            ],
          ),
          TemplateDay(
            dayOfWeek: 2,
            label: 'd2',
            mode: WeekdayMode.explicitTimes,
            intervals: const <WorkInterval>[],
            times: const <TimeOfDay>[], // empty discrete == day-off
          ),
          for (var dow = 3; dow <= 7; dow++)
            TemplateDay(
              dayOfWeek: dow,
              label: 'd$dow',
              intervals: const <WorkInterval>[],
            ),
        ],
      );

      final request = ScheduleMapper.weeklyScheduleToRequest(domain);

      for (final day in request.days!) {
        if (day.mode == WeeklyScheduleDayRequestModeEnum.EXPLICIT_TIMES) {
          expect(
            day.times ?? const <String>[],
            isNotEmpty,
            reason:
                'EXPLICIT_TIMES day ${day.dayOfWeek} must carry ≥1 time — an '
                'empty-times EXPLICIT_TIMES day 400s on backend modeConsistent',
          );
        }
      }

      // And specifically: the real working day stays EXPLICIT_TIMES with its
      // times; the empty-discrete day collapses to INTERVAL.
      final mon = request.days!.firstWhere((d) => d.dayOfWeek == 1);
      expect(mon.mode, WeeklyScheduleDayRequestModeEnum.EXPLICIT_TIMES);
      expect(mon.times!.toList(), <String>['09:00:00', '13:00:00']);
      final tue = request.days!.firstWhere((d) => d.dayOfWeek == 2);
      expect(tue.mode, WeeklyScheduleDayRequestModeEnum.INTERVAL);
      expect(tue.intervals ?? const <WorkIntervalDto>[], isEmpty);
      expect(tue.times ?? const <String>[], isEmpty);
    });

    test('a discrete day WITH times still serialises as EXPLICIT_TIMES + those '
        'times, no intervals (no regression)', () {
      final domain = WeeklySchedule(
        validFrom: DateTime(2026, 6, 1),
        validTo: null,
        days: <TemplateDay>[
          TemplateDay(
            dayOfWeek: 1,
            label: 'd1',
            mode: WeekdayMode.explicitTimes,
            intervals: const <WorkInterval>[],
            times: const <TimeOfDay>[
              TimeOfDay(hour: 9, minute: 0),
              TimeOfDay(hour: 13, minute: 0),
            ],
          ),
          for (var dow = 2; dow <= 7; dow++)
            TemplateDay(
              dayOfWeek: dow,
              label: 'd$dow',
              intervals: const <WorkInterval>[],
            ),
        ],
      );

      final monReq = ScheduleMapper.weeklyScheduleToRequest(
        domain,
      ).days!.firstWhere((d) => d.dayOfWeek == 1);

      expect(monReq.mode, WeeklyScheduleDayRequestModeEnum.EXPLICIT_TIMES);
      expect(monReq.times!.toList(), <String>['09:00:00', '13:00:00']);
      expect(monReq.intervals ?? const <WorkIntervalDto>[], isEmpty);
    });

    test('an INTERVAL working day still serialises as INTERVAL + its intervals '
        '(no regression)', () {
      final domain = WeeklySchedule(
        validFrom: DateTime(2026, 6, 1),
        validTo: null,
        days: <TemplateDay>[
          TemplateDay(
            dayOfWeek: 1,
            label: 'd1',
            intervals: <WorkInterval>[
              WorkInterval(
                start: const TimeOfDay(hour: 9, minute: 0),
                end: const TimeOfDay(hour: 18, minute: 0),
              ),
            ],
          ),
          for (var dow = 2; dow <= 7; dow++)
            TemplateDay(
              dayOfWeek: dow,
              label: 'd$dow',
              intervals: const <WorkInterval>[],
            ),
        ],
      );

      final monReq = ScheduleMapper.weeklyScheduleToRequest(
        domain,
      ).days!.firstWhere((d) => d.dayOfWeek == 1);

      expect(monReq.mode, WeeklyScheduleDayRequestModeEnum.INTERVAL);
      expect(monReq.intervals, hasLength(1));
      expect(monReq.intervals!.single.startTime, '09:00:00');
      expect(monReq.intervals!.single.endTime, '18:00:00');
      expect(monReq.times ?? const <String>[], isEmpty);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Phase 15.9 REGRESSION — a no-work CUSTOM_HOURS override collapses to
  // DAY_OFF. A CUSTOM_HOURS override that resolves to zero working slots (empty
  // times in EXPLICIT_TIMES mode, or empty intervals in INTERVAL mode) is NOT a
  // valid CUSTOM_HOURS payload — the backend `kindConsistent` check would 400.
  // It means "no hours that date", which is DAY_OFF (carries neither intervals
  // nor times). See overrideToRequestForDate.
  // ───────────────────────────────────────────────────────────────────────────

  group('overrideToRequestForDate — no-work CUSTOM_HOURS collapses to DAY_OFF '
      '(15.9 kindConsistent regression)', () {
    test('a CUSTOM_HOURS override in explicit mode with EMPTY times serialises '
        'as DAY_OFF (no intervals, no times)', () {
      // ScheduleOverride.explicitTimes with an empty times list: mode=explicit,
      // kind=custom, but no working slots → resolves to a day-off.
      final override = ScheduleOverride.explicitTimes(
        start: DateTime(2026, 7, 3),
        end: DateTime(2026, 7, 3),
        times: const <TimeOfDay>[], // empty discrete → no work
      );
      // Sanity: this IS a custom-kind, explicit-mode override with no slots.
      expect(override.kind, OverrideKind.custom);
      expect(override.mode, WeekdayMode.explicitTimes);
      expect(override.times, isEmpty);

      final req = ScheduleMapper.overrideToRequestForDate(
        override,
        DateTime(2026, 7, 3),
      );

      expect(
        req.kind,
        ScheduleOverrideRequestKindEnum.DAY_OFF,
        reason:
            'a CUSTOM_HOURS override with zero working slots is a day-off — '
            'serialising it as empty CUSTOM_HOURS would 400 on kindConsistent',
      );
      expect(req.times ?? const <String>[], isEmpty);
      expect(req.intervals ?? const <WorkIntervalDto>[], isEmpty);
      expect(req.date, Date(2026, 7, 3));
    });

    test('a CUSTOM_HOURS override in interval mode with EMPTY intervals '
        'serialises as DAY_OFF (no intervals, no times)', () {
      final override = ScheduleOverride.custom(
        start: DateTime(2026, 7, 4),
        end: DateTime(2026, 7, 4),
        intervals: const <WorkInterval>[], // empty intervals → no work
      );
      expect(override.kind, OverrideKind.custom);
      expect(override.mode, WeekdayMode.interval);
      expect(override.intervals, isEmpty);

      final req = ScheduleMapper.overrideToRequestForDate(
        override,
        DateTime(2026, 7, 4),
      );

      expect(req.kind, ScheduleOverrideRequestKindEnum.DAY_OFF);
      expect(req.intervals ?? const <WorkIntervalDto>[], isEmpty);
      expect(req.times ?? const <String>[], isEmpty);
    });

    test('a real discrete override (WITH times) still serialises as '
        'CUSTOM_HOURS + EXPLICIT_TIMES + its times (no regression)', () {
      final override = ScheduleOverride.explicitTimes(
        start: DateTime(2026, 7, 5),
        end: DateTime(2026, 7, 5),
        times: const <TimeOfDay>[
          TimeOfDay(hour: 9, minute: 0),
          TimeOfDay(hour: 11, minute: 0),
        ],
      );

      final req = ScheduleMapper.overrideToRequestForDate(
        override,
        DateTime(2026, 7, 5),
      );

      expect(req.kind, ScheduleOverrideRequestKindEnum.CUSTOM_HOURS);
      expect(req.mode, ScheduleOverrideRequestModeEnum.EXPLICIT_TIMES);
      expect(req.times!.toList(), <String>['09:00:00', '11:00:00']);
      expect(req.intervals ?? const <WorkIntervalDto>[], isEmpty);
    });
  });

  group('override EXPLICIT_TIMES — round-trips sorted + deduped', () {
    test('explicitTimes override → request EXPLICIT_TIMES + sorted times, no '
        'intervals → response → domain', () {
      final override = ScheduleOverride.explicitTimes(
        start: DateTime(2026, 7, 5),
        end: DateTime(2026, 7, 5),
        times: const <TimeOfDay>[
          TimeOfDay(hour: 16, minute: 0),
          TimeOfDay(hour: 9, minute: 0),
          TimeOfDay(hour: 9, minute: 0), // duplicate
          TimeOfDay(hour: 12, minute: 30),
        ],
      );
      // The ctor already sort+dedupes the domain side.
      expect(override.mode, WeekdayMode.explicitTimes);
      expect(override.intervals, isEmpty);
      expect(override.times, <TimeOfDay>[
        const TimeOfDay(hour: 9, minute: 0),
        const TimeOfDay(hour: 12, minute: 30),
        const TimeOfDay(hour: 16, minute: 0),
      ]);

      final req = ScheduleMapper.overrideToRequestForDate(
        override,
        DateTime(2026, 7, 5),
      );
      expect(req.kind, ScheduleOverrideRequestKindEnum.CUSTOM_HOURS);
      expect(req.mode, ScheduleOverrideRequestModeEnum.EXPLICIT_TIMES);
      expect(req.times!.toList(), <String>['09:00:00', '12:30:00', '16:00:00']);
      expect(req.intervals ?? const <WorkIntervalDto>[], isEmpty);

      final response = ScheduleOverrideResponse(
        (b) => b
          ..date = req.date
          ..kind = ScheduleOverrideResponseKindEnum.CUSTOM_HOURS
          ..mode = ScheduleOverrideResponseModeEnum.EXPLICIT_TIMES
          ..times = req.times?.toBuilder(),
      );

      final back = ScheduleMapper.overrideFromResponse(response);
      expect(back.kind, OverrideKind.custom);
      expect(back.mode, WeekdayMode.explicitTimes);
      expect(back.intervals, isEmpty);
      expect(back.times, <TimeOfDay>[
        const TimeOfDay(hour: 9, minute: 0),
        const TimeOfDay(hour: 12, minute: 30),
        const TimeOfDay(hour: 16, minute: 0),
      ]);
      expect(back.start, DateTime(2026, 7, 5));
      expect(back.end, DateTime(2026, 7, 5));
    });

    test('DAY_OFF override regresses unchanged (no mode/times)', () {
      final override = ScheduleOverride.dayOff(
        start: DateTime(2026, 7, 6),
        end: DateTime(2026, 7, 6),
      );

      final req = ScheduleMapper.overrideToRequestForDate(
        override,
        DateTime(2026, 7, 6),
      );
      expect(req.kind, ScheduleOverrideRequestKindEnum.DAY_OFF);
      expect(req.times ?? const <String>[], isEmpty);
      expect(req.intervals ?? const <WorkIntervalDto>[], isEmpty);

      final response = ScheduleOverrideResponse(
        (b) => b
          ..date = req.date
          ..kind = ScheduleOverrideResponseKindEnum.DAY_OFF,
      );
      final back = ScheduleMapper.overrideFromResponse(response);
      expect(back.kind, OverrideKind.dayOff);
      expect(back.mode, WeekdayMode.interval);
      expect(back.times, isEmpty);
      expect(back.intervals, isEmpty);
    });

    test('INTERVAL custom override regresses unchanged', () {
      final override = ScheduleOverride.custom(
        start: DateTime(2026, 7, 7),
        end: DateTime(2026, 7, 7),
        intervals: <WorkInterval>[
          WorkInterval(
            start: const TimeOfDay(hour: 11, minute: 0),
            end: const TimeOfDay(hour: 15, minute: 0),
          ),
        ],
      );

      final req = ScheduleMapper.overrideToRequestForDate(
        override,
        DateTime(2026, 7, 7),
      );
      expect(req.kind, ScheduleOverrideRequestKindEnum.CUSTOM_HOURS);
      expect(req.mode, ScheduleOverrideRequestModeEnum.INTERVAL);
      expect(req.intervals, hasLength(1));
      expect(req.times ?? const <String>[], isEmpty);

      final response = ScheduleOverrideResponse(
        (b) => b
          ..date = req.date
          ..kind = ScheduleOverrideResponseKindEnum.CUSTOM_HOURS
          ..mode = ScheduleOverrideResponseModeEnum.INTERVAL
          ..intervals = req.intervals?.toBuilder(),
      );
      final back = ScheduleMapper.overrideFromResponse(response);
      expect(back.mode, WeekdayMode.interval);
      expect(back.times, isEmpty);
      expect(back.intervals, hasLength(1));
      expect(back.intervals.single.start, const TimeOfDay(hour: 11, minute: 0));
      expect(back.intervals.single.end, const TimeOfDay(hour: 15, minute: 0));
    });
  });

  group('effectiveDayFromResponse — discrete times signal', () {
    test('response WITH times → times populated + isExplicitTimes==true', () {
      final dto = EffectiveDayResponse(
        (b) => b
          ..date = Date(2026, 6, 8)
          ..source_ = EffectiveDayResponseSource_Enum.TEMPLATE
          ..times = ListBuilder<String>(<String>[
            '13:00:00',
            '09:00:00',
            '09:00:00', // duplicate — collapsed
          ]),
      );

      final eff = ScheduleMapper.effectiveDayFromResponse(dto);

      expect(eff.isExplicitTimes, isTrue);
      expect(eff.times, <TimeOfDay>[
        const TimeOfDay(hour: 9, minute: 0),
        const TimeOfDay(hour: 13, minute: 0),
      ]);
      // EXPLICIT_TIMES days carry no intervals.
      expect(eff.intervals, isEmpty);
    });

    test('response WITHOUT times → empty times + isExplicitTimes==false', () {
      final dto = EffectiveDayResponse(
        (b) => b
          ..date = Date(2026, 6, 8)
          ..source_ = EffectiveDayResponseSource_Enum.TEMPLATE
          ..intervals = ListBuilder<WorkIntervalDto>(<WorkIntervalDto>[
            _dto('09:00:00', '18:00:00'),
          ]),
      );

      final eff = ScheduleMapper.effectiveDayFromResponse(dto);

      expect(eff.isExplicitTimes, isFalse);
      expect(eff.times, isEmpty);
      expect(eff.intervals, hasLength(1));
    });
  });

  group('discrete-times robustness — malformed wire degrades gracefully', () {
    test('a garbage time string never throws (crash-safe parse)', () {
      // A mix of valid, garbage, and seconds-bearing strings. The crash-safe
      // parse degrades each unparseable edge to midnight rather than throwing,
      // so one broken row can never crash a whole schedule load.
      final dto = EffectiveDayResponse(
        (b) => b
          ..date = Date(2026, 6, 9)
          ..source_ = EffectiveDayResponseSource_Enum.OVERRIDE_CUSTOM
          ..times = ListBuilder<String>(<String>[
            'not-a-time',
            '10:00:00',
            '', // empty → midnight
            '99:99', // out of range → clamped
          ]),
      );

      late final EffectiveDay eff;
      expect(
        () => eff = ScheduleMapper.effectiveDayFromResponse(dto),
        returnsNormally,
      );
      // It produced SOME times list without throwing; the valid 10:00 survives.
      expect(eff.times, contains(const TimeOfDay(hour: 10, minute: 0)));
      expect(eff.isExplicitTimes, isTrue);
    });

    test('overrideFromResponse with malformed discrete times never throws', () {
      final dto = ScheduleOverrideResponse(
        (b) => b
          ..date = Date(2026, 6, 9)
          ..kind = ScheduleOverrideResponseKindEnum.CUSTOM_HOURS
          ..mode = ScheduleOverrideResponseModeEnum.EXPLICIT_TIMES
          ..times = ListBuilder<String>(<String>['garbage', '08:30:00']),
      );

      late final ScheduleOverride back;
      expect(
        () => back = ScheduleMapper.overrideFromResponse(dto),
        returnsNormally,
      );
      expect(back.mode, WeekdayMode.explicitTimes);
      expect(back.times, contains(const TimeOfDay(hour: 8, minute: 30)));
    });
  });

  group('Date ⇄ DateTime — leap day', () {
    test('2024-02-29 parses to a date-only DateTime and serialises back', () {
      final dto = EffectiveDayResponse(
        (b) => b
          ..date = Date(2024, 2, 29)
          ..source_ = EffectiveDayResponseSource_Enum.TEMPLATE,
      );

      final eff = ScheduleMapper.effectiveDayFromResponse(dto);
      expect(eff.date, DateTime(2024, 2, 29));
      expect(eff.date.hour, 0);
      expect(eff.date.minute, 0);

      final wire = ScheduleMapper.dateToWire(eff.date);
      expect(wire, Date(2024, 2, 29));
    });
  });

  // ── 2026-07-26 booking-conflict design — POST /overrides/conflicts wire ───
  //
  // Zero coverage existed for this mapper surface before this audit
  // (mobile-qa, 2026-07-26): `conflictQueryRequestForSpan` builds the request
  // body every save now sends BEFORE any write; `overrideConflictFromResponse`
  // / `overrideConflictCheckFromResponse` decode the response the day-off-
  // conflict dialog renders. A silent field-name drift here would go
  // undetected by every existing widget test (they all construct the domain
  // types directly, never round-trip the wire).
  group('conflictQueryRequestForSpan', () {
    test('DAY_OFF span carries kind=DAY_OFF, no mode/intervals/times', () {
      final span = ScheduleOverride.dayOff(
        start: DateTime(2026, 7, 27),
        end: DateTime(2026, 7, 29),
      );
      final req = ScheduleMapper.conflictQueryRequestForSpan(span);

      expect(req.from, Date(2026, 7, 27));
      expect(req.to, Date(2026, 7, 29));
      expect(req.kind, OverrideConflictQueryRequestKindEnum.DAY_OFF);
      expect(req.mode, isNull);
      expect(req.intervals, isNull);
      expect(req.times, isNull);
    });

    test('CUSTOM_HOURS/INTERVAL span carries kind=CUSTOM_HOURS, mode=INTERVAL, '
        'the serialised intervals — never times', () {
      final span = ScheduleOverride.custom(
        start: DateTime(2026, 7, 27),
        end: DateTime(2026, 7, 27),
        intervals: <WorkInterval>[
          WorkInterval(
            start: const TimeOfDay(hour: 9, minute: 0),
            end: const TimeOfDay(hour: 18, minute: 0),
          ),
        ],
      );
      final req = ScheduleMapper.conflictQueryRequestForSpan(span);

      expect(req.kind, OverrideConflictQueryRequestKindEnum.CUSTOM_HOURS);
      expect(req.mode, OverrideConflictQueryRequestModeEnum.INTERVAL);
      expect(req.intervals, hasLength(1));
      expect(req.intervals!.first.startTime, '09:00:00');
      expect(req.times, isNull);
    });

    test('CUSTOM_HOURS/EXPLICIT_TIMES span carries mode=EXPLICIT_TIMES, the '
        'serialised times — never intervals', () {
      final span = ScheduleOverride.explicitTimes(
        start: DateTime(2026, 7, 27),
        end: DateTime(2026, 7, 27),
        times: <TimeOfDay>[
          const TimeOfDay(hour: 9, minute: 0),
          const TimeOfDay(hour: 15, minute: 0),
        ],
      );
      final req = ScheduleMapper.conflictQueryRequestForSpan(span);

      expect(req.mode, OverrideConflictQueryRequestModeEnum.EXPLICIT_TIMES);
      expect(req.times, <String>['09:00:00', '15:00:00']);
      expect(req.intervals, isNull);
    });

    test(
      'a CUSTOM_HOURS override with zero working slots collapses to '
      'DAY_OFF on the wire — mirrors overrideToRequestForDate\'s '
      'kindConsistent contract so the two request builders never disagree',
      () {
        final span = ScheduleOverride.custom(
          start: DateTime(2026, 7, 27),
          end: DateTime(2026, 7, 27),
          intervals: const <WorkInterval>[],
        );
        final req = ScheduleMapper.conflictQueryRequestForSpan(span);
        expect(req.kind, OverrideConflictQueryRequestKindEnum.DAY_OFF);
      },
    );
  });

  group('overrideConflictFromResponse', () {
    test('maps every field 1:1, UTC instants kept canonical (no .toLocal)', () {
      final dto = OverrideConflictResponse(
        (b) => b
          ..bookingId = 'booking-42'
          ..appointmentId = 'appt-7'
          ..date = Date(2026, 7, 27)
          ..startsAt = DateTime.utc(2026, 7, 27, 10)
          ..endsAt = DateTime.utc(2026, 7, 27, 11)
          ..clientDisplayName = 'Олена Гриценко'
          ..serviceName = 'Манікюр з покриттям',
      );

      final c = ScheduleMapper.overrideConflictFromResponse(dto);

      expect(c.bookingId, 'booking-42');
      expect(c.appointmentId, 'appt-7');
      expect(c.date, DateTime(2026, 7, 27));
      expect(c.startsAt, DateTime.utc(2026, 7, 27, 10));
      expect(c.endsAt, DateTime.utc(2026, 7, 27, 11));
      expect(c.clientDisplayName, 'Олена Гриценко');
      expect(c.serviceName, 'Манікюр з покриттям');
      expect(c.durationMinutes, 60);
    });

    test(
      'a null appointmentId (standalone booking, not a visit child) survives '
      'as null — never coerced to empty string',
      () {
        final dto = OverrideConflictResponse(
          (b) => b
            ..bookingId = 'booking-1'
            ..date = Date(2026, 7, 27)
            ..startsAt = DateTime.utc(2026, 7, 27, 10)
            ..endsAt = DateTime.utc(2026, 7, 27, 11)
            ..clientDisplayName = 'Клієнт'
            ..serviceName = 'Послуга',
        );
        final c = ScheduleMapper.overrideConflictFromResponse(dto);
        expect(c.appointmentId, isNull);
      },
    );

    test(
      'a malformed row (every optional field absent) never throws — '
      'defensive fallbacks keep one bad row from crashing the whole preview',
      () {
        final dto = OverrideConflictResponse(
          (b) => b..date = Date(2026, 7, 27),
        );
        expect(
          () => ScheduleMapper.overrideConflictFromResponse(dto),
          returnsNormally,
        );
        final c = ScheduleMapper.overrideConflictFromResponse(dto);
        expect(c.bookingId, '');
        expect(c.clientDisplayName, '');
        expect(c.serviceName, '');
        expect(c.startsAt, DateTime.fromMillisecondsSinceEpoch(0));
      },
    );
  });

  group('overrideConflictCheckFromResponse', () {
    test('maps conflicts + totalCount + truncated + scanTruncated 1:1', () {
      final row = OverrideConflictResponse(
        (b) => b
          ..bookingId = 'b1'
          ..date = Date(2026, 7, 27)
          ..startsAt = DateTime.utc(2026, 7, 27, 10)
          ..endsAt = DateTime.utc(2026, 7, 27, 11)
          ..clientDisplayName = 'Клієнт'
          ..serviceName = 'Послуга',
      );
      final dto = OverrideConflictPreviewResponse(
        (b) => b
          ..conflicts.replace(<OverrideConflictResponse>[row])
          ..totalCount = 8
          ..truncated = true
          ..scanTruncated = false,
      );

      final check = ScheduleMapper.overrideConflictCheckFromResponse(dto);

      expect(check.conflicts, hasLength(1));
      expect(
        check.totalCount,
        8,
        reason:
            'the AUTHORITATIVE count must come from the wire totalCount, '
            'never re-derived from conflicts.length',
      );
      expect(check.truncated, isTrue);
      expect(check.scanTruncated, isFalse);
      expect(check.isCountExact, isTrue);
    });

    test('a null totalCount falls back to conflicts.length (defensive — the '
        'backend always sends it for a real response)', () {
      final dto = OverrideConflictPreviewResponse(
        (b) => b..conflicts.replace(const <OverrideConflictResponse>[]),
      );
      final check = ScheduleMapper.overrideConflictCheckFromResponse(dto);
      expect(check.totalCount, 0);
      expect(check.truncated, isFalse);
      expect(check.scanTruncated, isFalse);
    });

    test('an absent conflicts list maps to an empty list, not a crash', () {
      final dto = OverrideConflictPreviewResponse((b) => b..totalCount = 0);
      final check = ScheduleMapper.overrideConflictCheckFromResponse(dto);
      expect(check.conflicts, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 2026-07-27 — STORED WORKING WINDOW (`windowStart` / `windowEnd`).
  //
  // The backend now persists the outer working window on the weekly-template
  // day, the per-date override and the effective day as DISPLAY-ONLY metadata,
  // so `DayHours.fromIntervals` can re-render a break flush against a window
  // edge instead of normalising it into a shortened working day. Intervals
  // remain the sole canonical availability.
  //
  // Two contracts this mapper must honour, both asserted here against the
  // GENERATED request/response models (never a hand-rolled map — a wire-NAME
  // mismatch is exactly the drift these tests exist to catch):
  //
  //   READ  — BOTH-OR-NEITHER. One edge alone, an empty string, or a
  //           degenerate pair (`end <= start`) all yield `null`, i.e. "no
  //           stored window" → the legacy gap-reconstruction regime. The window
  //           is NEVER synthesised from `min(start)..max(end)`; a missing
  //           window must stay missing, because synthesising one would silently
  //           promote every legacy row into the new regime and change what
  //           already-shipped schedules display.
  //   WRITE — sent on INTERVAL branches only: `null` for a day-off and for
  //           EXPLICIT_TIMES (the backend ignores it there; the mapper does not
  //           rely on that leniency).
  // ═══════════════════════════════════════════════════════════════════════════

  /// One weekly-day response row with an optional stored window.
  WeeklyScheduleDayResponse weeklyDayDto({
    int dayOfWeek = 1,
    List<WorkIntervalDto> intervals = const <WorkIntervalDto>[],
    String? windowStart,
    String? windowEnd,
  }) => WeeklyScheduleDayResponse(
    (b) => b
      ..dayOfWeek = dayOfWeek
      ..intervals = ListBuilder<WorkIntervalDto>(intervals)
      ..windowStart = windowStart
      ..windowEnd = windowEnd,
  );

  /// A one-day weekly response wrapping [day], mapped to its TemplateDay.
  TemplateDay mapWeeklyDay(WeeklyScheduleDayResponse day) =>
      ScheduleMapper.weeklyScheduleFromResponse(
        WeeklyScheduleResponse(
          (b) => b
            ..validFrom = Date(2026, 6, 1)
            ..days = ListBuilder<WeeklyScheduleDayResponse>(
              <WeeklyScheduleDayResponse>[day],
            ),
        ),
      ).days.firstWhere((TemplateDay d) => d.dayOfWeek == day.dayOfWeek);

  group('windowStart/windowEnd — READ (both-or-neither, never synthesised)', () {
    test('BOTH present on a weekly day → the window is carried verbatim', () {
      // The user\'s bug shape: intervals start at 10:00 but the stored window
      // starts at 09:00, because a 09:00–10:00 break was carved off the edge.
      final TemplateDay day = mapWeeklyDay(
        weeklyDayDto(
          intervals: <WorkIntervalDto>[_dto('10:00:00', '18:00:00')],
          windowStart: '09:00:00',
          windowEnd: '18:00:00',
        ),
      );

      expect(day.window, isNotNull);
      expect(day.window!.start, const TimeOfDay(hour: 9, minute: 0));
      expect(day.window!.end, const TimeOfDay(hour: 18, minute: 0));
      // The intervals are untouched — the window rides alongside, it does not
      // replace or widen availability.
      expect(day.intervals, hasLength(1));
      expect(day.intervals.single.start, const TimeOfDay(hour: 10, minute: 0));
    });

    test('BOTH ABSENT → null, and the window is NOT synthesised from '
        'min(start)..max(end)', () {
      // THE ANTI-SYNTHESIS GUARD. A legacy row carries intervals only. If the
      // mapper invented a window here, every pre-window template would jump to
      // the new regime and `[09:00–13:00, 14:00–18:00]` would suddenly render
      // its lunch break differently — a silent behaviour change on shipped
      // data.
      final TemplateDay day = mapWeeklyDay(
        weeklyDayDto(
          intervals: <WorkIntervalDto>[
            _dto('09:00:00', '13:00:00'),
            _dto('14:00:00', '18:00:00'),
          ],
        ),
      );

      expect(
        day.window,
        isNull,
        reason:
            'an absent window is a real, meaningful null — the legacy '
            'gap-reconstruction regime — never a value derived from the '
            'intervals',
      );
    });

    test('ONLY windowStart present → null (both-or-neither)', () {
      final TemplateDay day = mapWeeklyDay(
        weeklyDayDto(
          intervals: <WorkIntervalDto>[_dto('10:00:00', '18:00:00')],
          windowStart: '09:00:00',
        ),
      );

      expect(
        day.window,
        isNull,
        reason:
            'half a window is not a window — a lone edge must not be paired '
            'with a fabricated counterpart',
      );
    });

    test('ONLY windowEnd present → null (both-or-neither)', () {
      final TemplateDay day = mapWeeklyDay(
        weeklyDayDto(
          intervals: <WorkIntervalDto>[_dto('10:00:00', '18:00:00')],
          windowEnd: '18:00:00',
        ),
      );

      expect(day.window, isNull);
    });

    test('an EMPTY-STRING edge is treated as absent, not as midnight', () {
      // `parseTime('')` degrades to 00:00; without the empty-string guard an
      // empty windowStart would become a 00:00 window start and manufacture a
      // nine-hour phantom break.
      final TemplateDay day = mapWeeklyDay(
        weeklyDayDto(
          intervals: <WorkIntervalDto>[_dto('10:00:00', '18:00:00')],
          windowStart: '',
          windowEnd: '18:00:00',
        ),
      );

      expect(day.window, isNull);
    });

    test('a degenerate window (end <= start) → null', () {
      final TemplateDay inverted = mapWeeklyDay(
        weeklyDayDto(
          intervals: <WorkIntervalDto>[_dto('10:00:00', '18:00:00')],
          windowStart: '18:00:00',
          windowEnd: '09:00:00',
        ),
      );
      expect(inverted.window, isNull, reason: 'end before start');

      final TemplateDay zeroLength = mapWeeklyDay(
        weeklyDayDto(
          intervals: <WorkIntervalDto>[_dto('10:00:00', '18:00:00')],
          windowStart: '09:00:00',
          windowEnd: '09:00:00',
        ),
      );
      expect(zeroLength.window, isNull, reason: 'end equal to start');
    });

    // ── CONTAINMENT (2026-07-27 audit) ──────────────────────────────────────
    //
    // The window must CONTAIN every interval of its own row, else it is
    // rejected and the row falls back to the legacy gap regime. The backend
    // enforces containment on write, but the client must not RELY on that: a
    // backend regression or tampered row could ship a window narrower than its
    // intervals, and `DayHours._breaksFromWindowMinusIntervals` CLAMPS
    // intervals into the window rather than rejecting them.
    //
    // The damage is not cosmetic. `intervals=[08:00–18:00]` with
    // `window=09:00–10:00` would render a one-hour day with no warning, and the
    // master's very next save collapses `toIntervals()` to `[09:00–10:00]` —
    // writing away 8 hours of genuinely bookable time, with the backend
    // blessing the now self-consistent result. Falling back to `null` keeps the
    // intervals authoritative.
    test('a window NARROWER than its own intervals is REJECTED → null, so the '
        'intervals stay authoritative (availability data-loss guard)', () {
      final TemplateDay day = mapWeeklyDay(
        weeklyDayDto(
          intervals: <WorkIntervalDto>[_dto('08:00:00', '18:00:00')],
          windowStart: '09:00:00',
          windowEnd: '10:00:00',
        ),
      );

      expect(
        day.window,
        isNull,
        reason:
            'a non-containing window must not be honoured — clamping to it '
            'would render a 09:00–10:00 day and the next save would discard 8 '
            'bookable hours',
      );
      // The intervals are untouched, and the legacy regime derives the window
      // from THEM — the day still reads 08:00–18:00.
      final DayHours redrawn = DayHours.fromIntervals(
        day.intervals,
        window: day.window,
      );
      expect(redrawn.window.start, const TimeOfDay(hour: 8, minute: 0));
      expect(redrawn.window.end, const TimeOfDay(hour: 18, minute: 0));
    });

    test(
      'a window that misses containment by ONE EDGE only is also rejected',
      () {
        // Late start: the window begins after the first interval does.
        expect(
          mapWeeklyDay(
            weeklyDayDto(
              intervals: <WorkIntervalDto>[_dto('08:00:00', '18:00:00')],
              windowStart: '09:00:00',
              windowEnd: '18:00:00',
            ),
          ).window,
          isNull,
          reason: 'the interval starts before the window',
        );

        // Early end: the window closes before the last interval does.
        expect(
          mapWeeklyDay(
            weeklyDayDto(
              intervals: <WorkIntervalDto>[_dto('09:00:00', '19:00:00')],
              windowStart: '09:00:00',
              windowEnd: '18:00:00',
            ),
          ).window,
          isNull,
          reason: 'the interval ends after the window',
        );
      },
    );

    test('containment is checked across ALL intervals, not just the first', () {
      // The first block fits; the SECOND pokes past the window end.
      expect(
        mapWeeklyDay(
          weeklyDayDto(
            intervals: <WorkIntervalDto>[
              _dto('10:00:00', '13:00:00'),
              _dto('14:00:00', '19:00:00'),
            ],
            windowStart: '09:00:00',
            windowEnd: '18:00:00',
          ),
        ).window,
        isNull,
      );
    });

    test('an EXACTLY-flush window (edges touching the intervals) is ACCEPTED — '
        'containment is inclusive, not strict', () {
      // The commonest real shape: window == the outer bounds of the intervals.
      // A strict (>/<) check here would reject every ordinary day.
      final TemplateDay day = mapWeeklyDay(
        weeklyDayDto(
          intervals: <WorkIntervalDto>[
            _dto('09:00:00', '13:00:00'),
            _dto('14:00:00', '18:00:00'),
          ],
          windowStart: '09:00:00',
          windowEnd: '18:00:00',
        ),
      );

      expect(day.window, isNotNull);
      expect(day.window!.start, const TimeOfDay(hour: 9, minute: 0));
      expect(day.window!.end, const TimeOfDay(hour: 18, minute: 0));
    });

    test('containment applies to overrides and effective days too', () {
      final ScheduleOverride override = ScheduleMapper.overrideFromResponse(
        ScheduleOverrideResponse(
          (b) => b
            ..date = Date(2026, 6, 10)
            ..kind = ScheduleOverrideResponseKindEnum.CUSTOM_HOURS
            ..intervals = ListBuilder<WorkIntervalDto>(<WorkIntervalDto>[
              _dto('08:00:00', '18:00:00'),
            ])
            ..windowStart = '09:00:00'
            ..windowEnd = '10:00:00',
        ),
      );
      expect(override.window, isNull);

      final EffectiveDay effective = ScheduleMapper.effectiveDayFromResponse(
        EffectiveDayResponse(
          (b) => b
            ..date = Date(2026, 6, 5)
            ..source_ = EffectiveDayResponseSource_Enum.TEMPLATE
            ..intervals = ListBuilder<WorkIntervalDto>(<WorkIntervalDto>[
              _dto('08:00:00', '18:00:00'),
            ])
            ..windowStart = '09:00:00'
            ..windowEnd = '10:00:00',
        ),
      );
      expect(effective.window, isNull);
    });

    test(
      'an EMPTY intervals list satisfies containment vacuously (day-off)',
      () {
        // A day-off row: no interval can violate containment. Every reader
        // ignores the window there anyway, so the mapper need not special-case
        // it — this pins that the containment loop does not accidentally reject
        // the empty case.
        final ScheduleOverride override = ScheduleMapper.overrideFromResponse(
          ScheduleOverrideResponse(
            (b) => b
              ..date = Date(2026, 6, 10)
              ..kind = ScheduleOverrideResponseKindEnum.CUSTOM_HOURS
              ..windowStart = '09:00:00'
              ..windowEnd = '18:00:00',
          ),
        );

        expect(override.intervals, isEmpty);
        expect(override.window, isNotNull);
      },
    );

    test('an EXPLICIT_TIMES weekly day never carries a window, even if the '
        'wire sent one', () {
      final TemplateDay day = mapWeeklyDay(
        WeeklyScheduleDayResponse(
          (b) => b
            ..dayOfWeek = 1
            ..mode = WeeklyScheduleDayResponseModeEnum.EXPLICIT_TIMES
            ..times = ListBuilder<String>(<String>['09:00:00', '11:00:00'])
            ..windowStart = '09:00:00'
            ..windowEnd = '18:00:00',
        ),
      );

      expect(day.mode, WeekdayMode.explicitTimes);
      expect(day.window, isNull);
    });

    test('a gap-filled (absent) weekly day is a day-off with no window', () {
      final WeeklySchedule schedule = ScheduleMapper.weeklyScheduleFromResponse(
        WeeklyScheduleResponse((b) => b..validFrom = Date(2026, 6, 1)),
      );

      expect(schedule.days, hasLength(7));
      expect(schedule.days.every((TemplateDay d) => d.window == null), isTrue);
    });

    test('overrideFromResponse — BOTH present → window; one alone → null', () {
      ScheduleOverride mapOverride({String? start, String? end}) =>
          ScheduleMapper.overrideFromResponse(
            ScheduleOverrideResponse(
              (b) => b
                ..date = Date(2026, 6, 10)
                ..kind = ScheduleOverrideResponseKindEnum.CUSTOM_HOURS
                ..intervals = ListBuilder<WorkIntervalDto>(<WorkIntervalDto>[
                  _dto('10:00:00', '18:00:00'),
                ])
                ..windowStart = start
                ..windowEnd = end,
            ),
          );

      final ScheduleOverride both = mapOverride(
        start: '09:00:00',
        end: '18:00:00',
      );
      expect(both.window, isNotNull);
      expect(both.window!.start, const TimeOfDay(hour: 9, minute: 0));
      expect(both.window!.end, const TimeOfDay(hour: 18, minute: 0));

      expect(mapOverride(start: '09:00:00').window, isNull);
      expect(mapOverride(end: '18:00:00').window, isNull);
      expect(mapOverride().window, isNull);
      expect(
        mapOverride(start: '18:00:00', end: '09:00:00').window,
        isNull,
        reason: 'degenerate pair',
      );
    });

    test(
      'effectiveDayFromResponse — BOTH present → window; one alone → null',
      () {
        EffectiveDay mapEffective({String? start, String? end}) =>
            ScheduleMapper.effectiveDayFromResponse(
              EffectiveDayResponse(
                (b) => b
                  ..date = Date(2026, 6, 5)
                  ..source_ = EffectiveDayResponseSource_Enum.TEMPLATE
                  ..intervals = ListBuilder<WorkIntervalDto>(<WorkIntervalDto>[
                    _dto('10:00:00', '18:00:00'),
                  ])
                  ..windowStart = start
                  ..windowEnd = end,
              ),
            );

        final EffectiveDay both = mapEffective(
          start: '09:00:00',
          end: '18:00:00',
        );
        expect(both.window, isNotNull);
        expect(both.window!.start, const TimeOfDay(hour: 9, minute: 0));
        expect(both.window!.end, const TimeOfDay(hour: 18, minute: 0));

        expect(mapEffective(start: '09:00:00').window, isNull);
        expect(mapEffective(end: '18:00:00').window, isNull);
        expect(
          mapEffective().window,
          isNull,
          reason: 'a legacy / day-off / no-schedule day carries no window',
        );
      },
    );
  });

  group('windowStart/windowEnd — WRITE (INTERVAL branches only)', () {
    WeeklySchedule weekly(List<TemplateDay> days) => WeeklySchedule(
      validFrom: DateTime(2026, 6, 1),
      validTo: null,
      days: days,
    );

    WorkInterval wi(int sh, int sm, int eh, int em) => WorkInterval(
      start: TimeOfDay(hour: sh, minute: sm),
      end: TimeOfDay(hour: eh, minute: em),
    );

    test('an INTERVAL day with a window sends BOTH keys, serialised '
        'HH:mm:00', () {
      final WeeklyScheduleRequest req = ScheduleMapper.weeklyScheduleToRequest(
        weekly(<TemplateDay>[
          TemplateDay(
            dayOfWeek: 1,
            label: 'd1',
            intervals: <WorkInterval>[wi(10, 0, 18, 0)],
            window: wi(9, 0, 18, 0),
          ),
        ]),
      );

      // Asserted on the GENERATED request model's own fields — if a regen
      // renamed the wire field this would not compile, which is the point.
      final WeeklyScheduleDayRequest day1 = req.days!.firstWhere(
        (WeeklyScheduleDayRequest d) => d.dayOfWeek == 1,
      );
      expect(day1.mode, WeeklyScheduleDayRequestModeEnum.INTERVAL);
      expect(day1.windowStart, '09:00:00');
      expect(day1.windowEnd, '18:00:00');
      // The window rides ALONGSIDE the intervals; it does not replace them.
      expect(day1.intervals, hasLength(1));
      expect(day1.intervals!.single.startTime, '10:00:00');
    });

    test('an INTERVAL day WITHOUT a window sends neither key (a legacy row '
        'stays legacy on the way back out)', () {
      final WeeklyScheduleRequest req = ScheduleMapper.weeklyScheduleToRequest(
        weekly(<TemplateDay>[
          TemplateDay(
            dayOfWeek: 1,
            label: 'd1',
            intervals: <WorkInterval>[wi(9, 0, 18, 0)],
          ),
        ]),
      );

      final WeeklyScheduleDayRequest day1 = req.days!.firstWhere(
        (WeeklyScheduleDayRequest d) => d.dayOfWeek == 1,
      );
      expect(day1.windowStart, isNull);
      expect(day1.windowEnd, isNull);
    });

    test('a DAY-OFF day sends NO window even when the domain row still holds '
        'one', () {
      // A day toggled off keeps its stashed window in memory; the wire must not
      // carry a window with nothing to contain.
      final WeeklyScheduleRequest req = ScheduleMapper.weeklyScheduleToRequest(
        weekly(<TemplateDay>[
          TemplateDay(
            dayOfWeek: 1,
            label: 'd1',
            intervals: <WorkInterval>[],
            window: wi(9, 0, 18, 0),
          ),
        ]),
      );

      final WeeklyScheduleDayRequest day1 = req.days!.firstWhere(
        (WeeklyScheduleDayRequest d) => d.dayOfWeek == 1,
      );
      expect(day1.intervals, isEmpty);
      expect(day1.windowStart, isNull);
      expect(day1.windowEnd, isNull);
    });

    test('an EXPLICIT_TIMES day sends NO window', () {
      final TemplateDay day = TemplateDay(
        dayOfWeek: 1,
        label: 'd1',
        intervals: <WorkInterval>[wi(10, 0, 18, 0)],
        window: wi(9, 0, 18, 0),
      );
      // The real flip path: setMode clears the window (pinned in
      // schedule_model_test.dart) — but assert the mapper independently by
      // forcing a window back on after the flip.
      day.setMode(WeekdayMode.explicitTimes);
      day.times = <TimeOfDay>[const TimeOfDay(hour: 9, minute: 0)];
      day.window = wi(9, 0, 18, 0);

      final WeeklyScheduleRequest req = ScheduleMapper.weeklyScheduleToRequest(
        weekly(<TemplateDay>[day]),
      );

      final WeeklyScheduleDayRequest day1 = req.days!.firstWhere(
        (WeeklyScheduleDayRequest d) => d.dayOfWeek == 1,
      );
      expect(day1.mode, WeeklyScheduleDayRequestModeEnum.EXPLICIT_TIMES);
      expect(
        day1.windowStart,
        isNull,
        reason:
            'the backend rejects a window on an EXPLICIT_TIMES day; the mapper '
            'must not rely on it being ignored',
      );
      expect(day1.windowEnd, isNull);
    });

    test(
      'overrideToRequestForDate — CUSTOM_HOURS INTERVAL sends both keys',
      () {
        final ScheduleOverrideRequest req =
            ScheduleMapper.overrideToRequestForDate(
              ScheduleOverride.custom(
                start: DateTime(2026, 7, 2),
                end: DateTime(2026, 7, 2),
                intervals: <WorkInterval>[wi(10, 0, 18, 0)],
                window: wi(9, 0, 18, 0),
              ),
              DateTime(2026, 7, 2),
            );

        expect(req.kind, ScheduleOverrideRequestKindEnum.CUSTOM_HOURS);
        expect(req.mode, ScheduleOverrideRequestModeEnum.INTERVAL);
        expect(req.windowStart, '09:00:00');
        expect(req.windowEnd, '18:00:00');
      },
    );

    test('overrideToRequestForDate — a DAY_OFF override sends no window', () {
      final ScheduleOverrideRequest req =
          ScheduleMapper.overrideToRequestForDate(
            ScheduleOverride.dayOff(
              start: DateTime(2026, 7, 1),
              end: DateTime(2026, 7, 1),
            ),
            DateTime(2026, 7, 1),
          );

      expect(req.kind, ScheduleOverrideRequestKindEnum.DAY_OFF);
      expect(req.windowStart, isNull);
      expect(req.windowEnd, isNull);
    });

    test('overrideToRequestForDate — an EMPTY-intervals CUSTOM override '
        'collapses to DAY_OFF and sends no window', () {
      // `_wireShapeOf` collapses a no-work custom override to DAY_OFF before
      // the INTERVAL branch is reached, so the window is unreachable there.
      final ScheduleOverrideRequest req =
          ScheduleMapper.overrideToRequestForDate(
            ScheduleOverride.custom(
              start: DateTime(2026, 7, 2),
              end: DateTime(2026, 7, 2),
              intervals: <WorkInterval>[],
              window: wi(9, 0, 18, 0),
            ),
            DateTime(2026, 7, 2),
          );

      expect(req.kind, ScheduleOverrideRequestKindEnum.DAY_OFF);
      expect(req.windowStart, isNull);
      expect(req.windowEnd, isNull);
    });

    test('overrideToRequestForDate — an EXPLICIT_TIMES override sends no '
        'window', () {
      final ScheduleOverrideRequest req =
          ScheduleMapper.overrideToRequestForDate(
            ScheduleOverride.explicitTimes(
              start: DateTime(2026, 7, 2),
              end: DateTime(2026, 7, 2),
              times: <TimeOfDay>[const TimeOfDay(hour: 9, minute: 0)],
            ),
            DateTime(2026, 7, 2),
          );

      expect(req.mode, ScheduleOverrideRequestModeEnum.EXPLICIT_TIMES);
      expect(req.windowStart, isNull);
      expect(req.windowEnd, isNull);
    });
  });

  group('windowStart/windowEnd — request→response→domain round-trip', () {
    test('the user\'s bug shape survives a full wire cycle and re-renders as a '
        'BREAK, not a shortened window', () {
      // Editor state: window 09:00–18:00 with a 09:00–10:00 break.
      final DayHours edited = DayHours(
        window: WorkInterval(
          start: const TimeOfDay(hour: 9, minute: 0),
          end: const TimeOfDay(hour: 18, minute: 0),
        ),
        breaks: <BreakRange>[
          BreakRange(
            start: const TimeOfDay(hour: 9, minute: 0),
            end: const TimeOfDay(hour: 10, minute: 0),
          ),
        ],
      );

      // SAVE — through the real request mapper.
      final WeeklyScheduleRequest req = ScheduleMapper.weeklyScheduleToRequest(
        WeeklySchedule(
          validFrom: DateTime(2026, 6, 1),
          validTo: null,
          days: <TemplateDay>[
            TemplateDay(
              dayOfWeek: 1,
              label: 'd1',
              intervals: edited.toIntervals(),
              window: edited.window.clone(),
            ),
          ],
        ),
      );

      final WeeklyScheduleDayRequest sent = req.days!.firstWhere(
        (WeeklyScheduleDayRequest d) => d.dayOfWeek == 1,
      );
      expect(sent.intervals!.single.startTime, '10:00:00');
      expect(sent.windowStart, '09:00:00');

      // LOAD — echo the request shape back as a response and map it home.
      final TemplateDay reloaded = mapWeeklyDay(
        weeklyDayDto(
          intervals: sent.intervals!.toList(),
          windowStart: sent.windowStart,
          windowEnd: sent.windowEnd,
        ),
      );

      final DayHours redrawn = DayHours.fromIntervals(
        reloaded.intervals,
        window: reloaded.window,
      );

      expect(
        ScheduleMapper.formatTimeWire(redrawn.window.start),
        '09:00:00',
        reason:
            'THE BUG: a 10:00 window start means the break was normalised into '
            'a shortened working day and vanished from the editor',
      );
      expect(redrawn.breaks, hasLength(1));
      expect(redrawn.breaks.single.start, const TimeOfDay(hour: 9, minute: 0));
      expect(redrawn.breaks.single.end, const TimeOfDay(hour: 10, minute: 0));
    });
  });
}

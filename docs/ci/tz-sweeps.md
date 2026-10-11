
# CI: timezone sweeps (`tz-sweeps` job)

The `tz-sweeps` job runs one matrix leg per zone: `kyiv-dst`, `tokyo`, `honolulu`. The unit shards
stay on the runner's UTC. Every zone is set by a STEP-level `env: TZ:`, never job-level, which
`test/ci/dst_rail_ci_coverage_test.dart` pins. The step `run:` bodies are pinned to the pre-400
text by `tool/ci/affected_tests/test/pipeline_e2e_test.dart`.

Moved verbatim from `pr-validate.yml` comments, in file order.

<a id="job-tz-sweeps"></a>

### tz-sweeps (phase 402 D1)

tz-sweeps (D1): one leg per zone. The three zone steps below keep their
names, their STEP-level `env: TZ:` (never job-level, see the DST step) and
their commands; a matrix leg only selects which one runs. Zones are
independent processes, so they no longer queue behind each other.

<a id="dst-rail"></a>

### DST rail guards (market zone)

The day rail's two RENDERED DST guards can only observe the bug they
exist to catch on a host whose UTC offset actually changes across the
transition. A UTC runner SKIPS them in the unit shards; this leg re-runs
that one file under the market zone so they genuinely execute on CI.

Deliberately scoped to a single file rather than set as a job-level
`env: TZ`. The booking formatters are pinned to Europe/Kyiv in code and
`slot_time_tz_regression_test.dart` proves it by asserting Kyiv
wall-clocks on a NON-Kyiv runner — under `TZ=Europe/Kyiv` a regression
to `.toLocal()` passes that suite silently (verified by mutation). The
unit shards must therefore stay UTC.

Pinned by test/ci/dst_rail_ci_coverage_test.dart — renaming or dropping
this step fails that test.

<a id="tokyo"></a>

### Third-timezone sweep: Asia/Tokyo (2026-08-02)

2026-08-02 — a third CI zone, distinct from BOTH the main suite (UTC)
and the DST-rail step above (Europe/Kyiv). The main suite's UTC run
lets slot_time_tz_regression_test.dart PROVE Kyiv-pinning by asserting
Kyiv wall-clocks on a non-Kyiv host — under Kyiv itself a regression to
`.toLocal()` passes that suite silently (mutation-verified). But UTC
and Europe/Kyiv are BOTH zones this codebase's own market anchor cares
about, so a bug that reads the raw device/host clock instead of
converting through toBeauticaTime can still coincidentally agree with
the correct Kyiv-derived value on either of them. A zone with NO
relationship to Kyiv at all closes that gap: any host-clock leak fails
loudly here regardless of which of the other two zones it happened to
slip past.

Asia/Tokyo specifically: UTC+9, and — unlike Europe/Kyiv — it observes
NO DST, so its offset is constant year-round. That makes the verdict a
property of the CODE under test, never of the CALENDAR DATE the runner
happens to execute on. A larger-skew zone that also carried DST would
make day-boundary divergence fire depending on the HOUR CI happens to
run — flaky-by-clock, exactly the failure mode this whole track exists
to eliminate.

DIRECTION (2026-08-04, measured — see the Pacific/Honolulu step that
follows this one). Asia/Tokyo is EAST of Kyiv, so it only ever pushes a
host-local fixture BACKWARD across the Kyiv day boundary, and only for
a bounded band of fixture hours. For a bare `DateTime(Y,M,D,H)` on a
host at UTC+O, the Kyiv hour is `H - O + 3`; the Kyiv calendar day
differs from D only when that falls outside [0,24). At O=+9 that means
H < 6 — Tokyo can ONLY catch a host-local anchor whose named hour is
00:00-05:59. It is structurally blind to every afternoon/evening
fixture, which is most of them in a booking app. That blindness is why
the Honolulu step below was ADDED rather than swapped in: the two zones
catch DISJOINT hour bands and neither subsumes the other. Both
directions were proven by executed mutation, not derived — see the
Honolulu step's own comment for the two probes and their verdicts.

Scoped to the same date/time-sensitive directories as the rest of this
workflow's zone-specific coverage, not the whole suite — running
obviously zone-independent tests (widget layout, form validation, …)
under a third zone would add CI time without adding any signal.

MEASURED, not estimated (2026-08-02) — a prior version of this comment
asserted "measured GREEN … (2,343 tests)" for a scope that included
test/shared/widgets/, but that number was never actually run: an
independent static grep of this exact directory list counted ~2,093
top-level test( / testWidgets( calls, and a separate cited run logged
1,824 tests. Three numbers, none agreeing, because none of them came
from executing the committed scope. This directory list was then
ACTUALLY RUN, twice, against the exact `flutter test` invocation below:
  - with test/shared/widgets/ included: 2,404 passed, 5 skipped,
    0 failed, real 3m56.138s (TZ=Asia/Tokyo).
  - with test/shared/widgets/ dropped (the scope actually committed
    below): 2,311 passed, 5 skipped, 0 failed, real 3m44.128s
    (TZ=Asia/Tokyo). The 5 skips are the DST-rail guards in
    bookings_day_rail_test.dart, which only fire on a host whose UTC
    offset changes across the transition — Asia/Tokyo observes no DST,
    same reason they skip on the main UTC step.
Both runs were 0 failures, so no latent host-clock leak was found by
running this — this scope is a GATE against a future regression, not
a speculative ratchet against a hypothetical one. ~3m44s is well
inside the ~5 minute budget this step was designed around.

SCOPE DECISION (2026-08-02, on the measurement above): test/shared/
widgets/ is DROPPED, every other directory KEPT. 0 of its 12 files
match scripts/forbid_host_local_instant_anchor.sh's own zone-critical
classifier (toBeauticaTime|clockProvider|TZDateTime|beauticaZone|
kBeauticaTimeZoneName), and 9 of 12 contain no time-related symbol at
all. The remaining 3 (period_range_picker_*_test.dart,
velvet_bottom_nav_bar_mount_parity_test.dart) touch DateTime only for
a "today" ring / a booked-day set fixture, and period_range_picker_
span_cap_test.dart's own header already documents its cases as
identical under TZ=UTC and TZ=Europe/Kyiv (calendar-only DateTime(y,
m, d) literals, not host-clock reads) — not the host-local-instant-
anchor bug class this sweep exists to catch.

The OTHER directories in this list do NOT all score higher on that
same classifier — measured per directory (zone-critical files /
total files), 2026-08-02:
  test/features/booking/    8/91   test/shared/formatters/   1/8
  test/features/schedule/   0/19   test/shared/time/         1/1
  test/features/home/       1/18   test/shared/calendar/     1/1
  test/routing/             0/17   test/core/time/           1/1
test/features/schedule/ (0/19) and test/routing/ (0/17) score
IDENTICALLY to the dropped test/shared/widgets/ on the classifier
metric alone. They stay in scope anyway, on DOMAIN RELEVANCE rather
than classifier score: the classifier only sees what a TEST FIXTURE
references, not what the production widget/screen under test calls
internally. test/features/schedule/ renders calendar/weekly-template
UI, and test/routing/ contains auth_redirect_test.dart /
booking_route_guard_test.dart — both plausible homes for a screen or
guard calling DateTime.now() directly without the test file ever
naming toBeauticaTime. test/shared/widgets/ was dropped instead
because it is generic UI atoms (rating stars, error states,
swipe-back gestures) and was MANUALLY confirmed non-time-domain file
by file — the per-file check two paragraphs up, a stronger signal
than the classifier score alone. Do not re-derive a "0/N ⇒ safe to
drop" rule from the table above; test/features/schedule/ and
test/routing/ are the standing counterexample.

REJECTED ALTERNATIVE: trimming to a curated file list (e.g. just the
~106 files that touch a time-related symbol, or the 13 that are
zone-critical). Rejected because a hardcoded file list silently stops
covering a file added LATER — exactly the "guard that stops guarding"
failure class scripts/forbid_host_local_instant_anchor.sh's own header
was written to eliminate, and it would need manual upkeep forever.
Directory-level scope auto-covers new files the day they're added, at
a measured cost (~3m44s) this step's budget already accepts. Do not
re-litigate this without a fresh measurement of the CURRENT committed
list — see the numbers above and re-run:
  time TZ=Asia/Tokyo flutter test <the directories below> --reporter=expanded

Step-level `env:` — see the DST rail guards step above for why this
must never become a job-level override; test/ci/dst_rail_ci_coverage_test.dart
asserts there is no job-level `env:` anywhere in this file.
2026-08-02 — test/features/calendar/ ADDED to the sweep. It was not
previously in this list even though `working_hours_repository.dart`
(`_todayKyiv()`) became genuinely zone-critical in the same change
that added `scripts/forbid_raw_clock_read.sh` — the working-hours
repository's window-selection logic now derives "today" through the
Kyiv-anchored clock seam, exactly the class of code this sweep exists
to catch a host-clock-leak regression in. See
`test/features/calendar/data/working_hours_repository_test.dart`'s
own "Kyiv-anchored" test group for the Tokyo-pinned regression case.

<a id="honolulu"></a>

### Fourth-timezone sweep: Pacific/Honolulu (2026-08-04)

2026-08-04 — a FOURTH CI zone, WEST of Kyiv. Added, not swapped in for
Asia/Tokyo, because measurement showed the two are complementary rather
than redundant.

WHAT THIS CATCHES THAT NO GREP CAN
scripts/forbid_host_local_instant_anchor.sh's six rules are all
single-file text rules. The bug class they structurally cannot see is
CROSS-FILE DATAFLOW: a test file names a host-local instant, hands it to
a widget, and the widget converts it through Europe/Kyiv somewhere the
test file never references. On 2026-08-04 an attempt to widen that
script's Rule 1 to reach this class was MEASURED AND REFUSED — with its
stage-1 classifier disabled the matcher returned 74 hits / 1 genuine
defect / 73 inert, 1.4% precision, i.e. 73 rubber-stamped annotations
(commit 030ddb18, and the refusal is recorded in that script's header).
The single defect was found instead by EXECUTING the suite under
TZ=Pacific/Honolulu, at precision 1/1 with zero annotations. This step
is that execution, wired. It cannot be rubber-stamped: there is no
marker to add, only a passing or failing test.

WHY HONOLULU IN ADDITION TO TOKYO — MEASURED IN BOTH DIRECTIONS
For a bare `DateTime(Y,M,D,H)` on a host at UTC+O, the Kyiv wall-clock
hour is `H - O + 3`, so the Kyiv calendar day differs from D only when
that leaves [0,24). Per zone that is a band of FIXTURE HOURS:
  Europe/Kyiv (+3)      none      — the dev VM; blind by construction
  UTC          (0)      H >= 21   — the main suite
  Asia/Tokyo   (+9)     H <  6    — the step above
  Pacific/Honolulu (-10) H >= 11  — this step
Tokyo's band and Honolulu's band are DISJOINT, so neither subsumes the
other and a swap would lose real coverage. Honolulu's band strictly
contains the main UTC suite's.

Proven by executed mutation on booking_confirm_test.dart, not derived
(2026-08-04). Its `_kStartAt`/`_kEndAt` were reverted to the pre-
030ddb18 host-local spelling and the file run under all four zones:
  PROBE A  DateTime(2026,7,20,14)  Kyiv PASS  UTC PASS  Tokyo PASS
                                   Honolulu FAIL
    — the real defect 030ddb18 fixed. booking_confirm_screen.dart:248
      keys its bookingsDayProvider invalidation off
      `dateOnly(toBeauticaTime(startAt))`; under Honolulu that instant
      is 03:00 the NEXT Kyiv day, so the invalidation targeted a family
      member the test never subscribed to. Failure was
      `Expected: <2> Actual: <1>` on the "REGRESSION GUARD — ...
      invalidates bookingsDayProvider" test. Tokyo does NOT see it.
  PROBE B  DateTime(2026,7,20,2)   Kyiv PASS  UTC PASS  Honolulu PASS
                                   Tokyo FAIL
    — the mirror direction, same defect shape at an early-morning
      fixture hour. This is what earns Asia/Tokyo its slot: Honolulu
      does NOT see it. Do not "consolidate" the two sweeps into one.
A THIRD probe records the residual gap honestly rather than claiming
full coverage:
  PROBE C  DateTime(2026,7,20,8)   Tokyo PASS  Honolulu PASS
Fixture hours 06:00-10:59 are caught by NO zone in this workflow. Only
a maximal pair (Pacific/Kiritimati UTC+14 with Pacific/Niue UTC-11)
would close it — verified: probe C is RED under Pacific/Kiritimati.
Deliberately NOT adopted: it would mean retiring Asia/Tokyo as the CI
host zone while a dozen test files still use `tz.getLocation('Asia/
Tokyo')` as this codebase's canonical "other zone" idiom, for five
fixture hours. Revisit only WITH a fresh full-sweep measurement under
both replacement zones — neither has ever been run at this scope.

Pacific/Honolulu specifically: UTC-10 and — like Asia/Tokyo, unlike
Europe/Kyiv — it observes NO DST, so its offset is constant year-round
and the verdict stays a property of the CODE, never of the calendar
date the runner happens to execute on.

COST, MEASURED (2026-08-04, dev VM, this exact scope, current tree):
  TZ=Asia/Tokyo        2413 passed, 5 skipped, 0 failed, real 6m01.457s
  TZ=Pacific/Honolulu  2413 passed, 5 skipped, 0 failed, real 5m56.630s
The two zones cost the same, so this step adds ~1x the Tokyo step.

It does NOT "double test wall time" — a claim made when this step was
first proposed, and measured to be wrong. The denominator was measured
too, same machine, same tree: the main `Test` step above
(`flutter test --coverage --exclude-tags golden`, the whole suite) is
5493 passed, 3 skipped, real 22m47.850s. So the zone-sensitive part of
this job goes from ~29m (main + Kyiv rail file + Tokyo) to ~35m — about
+20%, not +100%. Re-measure both numbers before re-litigating the cost;
the earlier 3m44s Tokyo figure in the step above is from the 2026-08-02
tree and no longer comparable (2311 tests then, 2413 now).

The 5 skips are bookings_day_rail_test.dart's DST-transition guards, which
need a host whose offset changes — same reason they skip under Tokyo
and under the main UTC suite. It is GREEN on the current tree: the
defect it originally found is already fixed in 030ddb18, so this is a
gate against regression, not a live bug hunt. Scope is deliberately the
SAME directory list as the Tokyo step — see that step's SCOPE DECISION
and REJECTED ALTERNATIVE notes; both apply verbatim here, and the two
lists must be kept identical so a directory added to one is not
silently uncovered in the other direction.

Step-level `env:` — never job-level, for the reason spelled out on the
DST rail guards step. Pinned by test/ci/dst_rail_ci_coverage_test.dart;
deleting this step fails that test.

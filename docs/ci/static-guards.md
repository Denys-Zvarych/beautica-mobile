
# CI: static guards (`gates-fast`, `gates`)

Each `scripts/forbid_*.sh` keeps its regex-level rationale in its own header. This file keeps the
CI-side narratives, including the incident notes from 2026-06-24, 2026-08-02, 2026-08-18 and
2026-09-17 (mobile-security S-L2). `scripts/verify_guards.sh --self-test` (in `gates`) runs every
guard's self-test. `test/ci/forbid_scripts_wired_test.dart` checks that every guard is wired.

Moved verbatim from `pr-validate.yml` comments, in file order.

<a id="magic-padding"></a>

### Forbid magic padding numbers (phase 1.2)

Phase 1.2 spacing scale gate — every padding literal must reference
`AppSpacing.*` from `lib/core/theme/app_spacing.dart`. The check
itself lives in `scripts/forbid_magic_padding.sh` so regex churn
stays out of CI YAML. The script exits 0 when no offenders are
found, 1 the moment a raw numeric `EdgeInsets(...)` shows up
under `lib/`. Documented in `analysis_options.yaml`.

<a id="provider-self-invalidation"></a>

### Forbid un-annotated provider self-invalidation (2026-06-18)

2026-06-18 cycle-safeguard — forbid un-annotated cross-provider
self-invalidation inside notifiers. A `ref.invalidate(otherProvider)` /
`ref.refresh(otherProvider)` from inside a Notifier can close a watch
cycle (CircularDependencyError, debug-only / stripped in release). The
check lives in scripts/forbid_provider_self_invalidation.sh (regex +
rationale documented there, not in this YAML). Each legitimate call is
unblocked by a `// cycle-safe: <reason>` annotation, never by weakening
the gate. Exits 0 when clean, 1 on the first un-annotated offender.

<a id="cycle-stub-in-tests"></a>

### Forbid cycle-closing-provider stubs (2026-06-18)

2026-06-18 cycle-safeguard — forbid stubbing the cycle-closing providers
in notifier/integration tests. The 2026-06-18 logout regression shipped
because those tests stubbed masterProfile/servicesList/serviceRepository,
breaking the real watch edge so the debug cycle assert had nothing to
fire on. The check lives in scripts/forbid_cycle_stub_in_tests.sh; each
legitimate stub is unblocked by a `// cycle-stub-ok: <reason>` annotation.

<a id="cycle-gates-self-test"></a>

### Self-test cycle-guard gates (2026-06-18)

2026-06-18 — self-test the two cycle-guard gates above. Their awk
comment/multiline detection is load-bearing; this pins it against
fixture snippets (plain offender → flagged, annotated → pass, plus each
former known false-negative from findings 1/2/4 → now flagged). Pure
bash + awk, no extra dependency. See scripts/test/test_cycle_gates.sh.

<a id="client-branch-appbar"></a>

### Forbid AppBar in CLIENT branch-root screens (2026-06-24)

2026-06-24 drift-prevention gate — CLIENT branch-root screens must reuse
the shared ClientTopBar; a per-screen Scaffold(appBar:)/AppBar() re-lays
out the wordmark and makes it jump on tab hop. The check lives in
scripts/forbid_client_branch_appbar.sh (enumerated branch roots +
rationale documented there). Each legitimate bar is unblocked by a
`// client-chrome-ok: <reason>` annotation. Exits 0 clean, 1 on offense.

<a id="cyrillic-finder"></a>

### Forbid Cyrillic find.text finders (2026-06-24)

2026-06-24 drift-prevention gate — forbid Cyrillic find.text('…') finders
in tests; they become findsNothing failures the day EN ships. Locate by
Key / semantics / AppLocalizations instead. Legacy files predating the
gate are grandfathered in scripts/.cyrillic_finder_allow (ratchet — the
baseline only shrinks); new exceptions use `// i18n-finder-ok: <reason>`.

<a id="fixed-wait"></a>

### Forbid fixed-duration pump waits (2026-06-24)

2026-06-24 drift-prevention gate — forbid fixed pump/pumpAndSettle(const
Duration(...)) sleeps in tests; they are flaky (too short → red on slow
CI, too long → slow suite). Prefer pump-until-condition. Legacy files are
grandfathered in scripts/.fixed_wait_allow (ratchet — baseline only
shrinks); new exceptions use `// fixed-wait-ok: <reason>`.

<a id="raw-container-with-header"></a>

### Forbid raw ProviderContainer in header-importing tests (phase 361)

Phase 361 audit (perf P2) — a test that imports a header/shell widget
(which mounts the live notification bell) must build its container with
`makeTestContainer` (test/helpers/test_container.dart), never a raw
`ProviderContainer(`: the real notifier's 60 s poll timer would leak
past the pending-timer check. Exceptions: FILE:LINE in
scripts/.raw_container_with_header_allow.

<a id="unmocked-approved-categories"></a>

### Forbid unmocked approvedCategoriesProvider (2026-06-24)

2026-06-24 fixture-footgun gate — a test that mounts ServiceForm( must
also override approvedCategoriesProvider. That provider sources from the
REAL Dio (not serviceRepositoryProvider); an un-overridden mount leaks a
15s connect-timeout Timer AND paints the category field's error ring at
rest (silently-wrong golden). Bit 3 fixtures already. Exceptions use
`// approved-categories-ok: <reason>`.

<a id="inline-fontsize"></a>

### Forbid inline fontSize under lib/features (2026-07-10)

2026-07-10 refactor-ratchet — the VelvetText font-size consolidation
moved 212 inline fontSize: sites under lib/features/** onto 116 cached
tokens (lib/core/theme/velvet_text.dart). This gate forbids a new inline
TextStyle(fontSize:) / .copyWith(fontSize:) from silently re-fragmenting
the scale. The only permitted inline sites (runtime-computed values +
HubAvatar/HubPhoto ctor params) are listed in scripts/.inline_fontsize_allow.

<a id="naive-router-location"></a>

### Forbid naive currentConfiguration reads (2026-07-19)

2026-07-19 push-location safeguard — forbid a direct
currentConfiguration.uri/.fullPath read in tests; go_router excludes
ImperativeRouteMatch (the match kind context.push produces) from both,
so a direct read after a push keeps reporting the pre-push location
forever. Shipped twice for real (nav-bar-hide `ab34c0a`; the
"btn-menu-master not navigating" backlog MEDIUM, which was never a
real nav regression). Route through AppHarness.location/
expectLocation (integration_test/support/app_harness.dart) instead.
Legacy files are grandfathered in
scripts/.naive_router_location_allow (ratchet — baseline only
shrinks); new exceptions use `// router-location-ok: <reason>`.

<a id="raw-bookings-query"></a>

### Forbid BookingsDayQuery.masterOwn (phase 7.1 P4 / 7.9)

Phase 7.1 perf P4, retargeted Phase 7.9 — BookingsDayQuery.masterOwn()
containment (the retired `MasterBookingsQuery.raw` this gate originally
guarded is gone). `.of()` is the only normalising path: it sorts
statuses/serviceIds canonically and truncates `day` to date-only, so a
rail wired straight to `.masterOwn(` mints a new bookingsDayProvider
family member per tap. Has to be a structural gate: nothing about the
leak is visible to a test or a lint (the screen behaves correctly, it
just refetches per tap).

<a id="stale-future-date"></a>

### Forbid stale absolute future-date fixtures (2026-07-20/21)

2026-07-20 incident — an absolute DateTime.utc(2026, 7, 20, 15) anchor
hand-rolled into four booking-detail specs quietly expired against the
real wall clock (BookingDisplayX.isPast), turning 16 "upcoming booking"
assertions into false negatives on a date, not a code change. Legacy
files predating this gate are grandfathered in
scripts/.stale_future_date_allow (ratchet — baseline only shrinks);
new exceptions use `// future-date-ok: <reason>`.

2026-07-21 — scan widened to `integration_test/` as well. The gate was
green through the recurrence because it only ever walked
`test/features/booking/`, while a SECOND copy of the same expired
instant sat in `integration_test/support/fake_backend.dart`
(`bookingStartsAt`) and silently flipped every E2E CONFIRMED-affordance
assertion. A guard that cannot see a tier does not protect it.

<a id="host-local-instant-anchor"></a>

### Forbid host-local instant anchors (2026-08-02)

2026-08-02 (Phase 225 audit cycles 4 and 5, and again same day) — the
dev VM this project is built on runs TZ=Europe/Kyiv, which is ALSO the
business timezone (kBeauticaTimeZoneName). A bare local
DateTime(2026, 6, 14, 12) resolves its underlying instant through the
HOST PROCESS's own TZ, so on the dev VM it is indistinguishable from a
correctly-pinned Kyiv instant and silently stops discriminating
anything, while CI (TZ=UTC) or any other machine resolves it to a
DIFFERENT instant — the fixture then either never fails locally no
matter what the zone-conversion code does, or fails only on CI and
reads as unrelated flake. This has shipped three times, most recently
in `lib/core/time/clock_provider.dart`'s own doc comment, which taught
the bad pattern as the canonical override example (fixed alongside
this gate). Every zone-critical test file (one that touches
toBeauticaTime/clockProvider/TZDateTime/beauticaZone/
kBeauticaTimeZoneName) must instead pin `DateTime.utc(...)` or a
`TZDateTime(...)` anchored to a named device zone. No allow-list — see
the script header. Escape hatch: `// host-tz-ok: <reason>`.

<a id="raw-clock-read"></a>

### Forbid un-annotated raw clock reads (2026-08-02)

2026-08-02 — companion PRODUCTION-code gate to the test-only one
above. The locked principle (ARCHITECTURE-mobile.md § 0.9): the
device clock supplies the current INSTANT, Europe/Kyiv decides which
calendar DAY it falls on. A classifying gate that only flags the
BUGGY `DateTime.now()` reads is impossible by grep alone —
`endAt.isBefore(DateTime.now())` (a correct absolute-instant
comparison) and `dateOnly(DateTime.now())` (the bug) are
syntactically identical at the call site; they differ only in what
the RESULT flows into. So this is a DECLARATION gate instead: it
flags every live-code `DateTime.now` reference under `lib/` — call
form and bare tear-off alike — unless it is annotated
`// instant-ok: <reason>` or is the ONE hard-coded exemption
(`clock_provider.dart`'s own seam definition). See the script header
for the full rationale and for why a `dateOnly(` gate was rejected
(real false positives: `days.map(dateOnly)`,
`bookings_day_query.dart`).

<a id="missing-test-text-input"></a>

### Forbid missing testTextInput.register() (2026-07-22)

2026-07-22 — `tester.enterText` is a SILENT NO-OP in profile/release
unless the harness registers the test text-input mock: the editing
state is posted with client id -1 (both
IntegrationTestWidgetsFlutterBinding and PatrolBinding override
`registerTestTextInput => false`), and the -1 escape hatch in
TextInput._handleTextInputInvocation lives inside an
`assert(() {...}())` block that non-debug builds strip. Every field
then stays empty and the flow fails downstream with a misleading tap
error. 16 integration flows call enterText and ALL boot through
AppHarness.boot, so one deleted line silently guts the
`integration-profile` job. Invisible to analyze, to lints, and to the
debug suite (debug keeps the assert) — hence a structural gate.

<a id="expectlocation-home"></a>

### Forbid vacuous expectLocation(home) (2026-07-22)

2026-07-22 vacuous-assertion audit — `RouteNames.home` is '/', and
AppHarness.expectLocation matched with `startsWith`, so
`expectLocation(router, RouteNames.home)` reduced to `startsWith('/')`:
satisfied by every one of the ~59 routes in the app. TWO login flows
shipped it as their closing assertion (auth_login_patrol_test.dart,
auth_login_flow_test.dart) — one of them with a comment recording the
vacuity and the assertion left in place. The helper now matches
segment-aware AND rejects '/' at runtime; this gate is the static half,
and also catches a freshly hand-rolled local copy of the helper that
would not inherit the runtime guard.

Distinct from forbid_naive_router_location.sh, the near-miss above:
that gate governs WHERE the location is read from and says nothing
about WHAT it is compared against. Zero baseline — no allow-list.

<a id="slash-in-patrol-test-name"></a>

### Forbid slashes in patrol test names (2026-07-22)

2026-07-22 — forbid '/' inside a patrolTest description.
AndroidTestOrchestrator names a per-test output file after the
description and Context.openFileOutput rejects path separators, so one
slash kills the orchestrator PROCESS. It surfaces only as
"Instrumentation run failed due to Process crashed" with zero failed
assertions — indistinguishable at a glance from the unrelated emulator
device-loss issue, and completely invisible to analyze/format/test,
since nothing host-side touches the orchestrator. Static gate is the
only place this can be caught cheaply. Zero baseline, no allow-list.

<a id="results-bare-pump-and-settle"></a>

### Forbid bare pumpAndSettle after a results tap (2026-07-31)

2026-07-31 — forbid a bare pumpAndSettle() straight after a
results-screen tap. SearchResultsScreen keeps an INDETERMINATE
_LoadMoreSpinner mounted while data.hasMore (FakeBackend seeds
totalPages: 2), so quiescence never arrives and the settle times out
MID-PUMP — tripping !_expectingFrame in postTest, which kills every
LATER test in the file with '!inTest' before they execute a line. That
is how 7 tests in client_search_flow_test.dart had never once been
observed running. The hazard was documented in comments six times in
that one file and still recurred on the seventh flow; prose does not
gate. Deliberately NARROW (local tap→settle adjacency only) — the true
condition is runtime `hasMore`, which no grep can see; see the script
header's KNOWN BLIND SPOTS. Zero baseline, no allow-list.

<a id="raw-query-param-cast"></a>

### Forbid raw queryParameters casts (2026-07-31)

2026-07-31 — forbid a direct cast on a queryParameters read inside
integration_test/support. The generated OpenAPI client sends repeatable
params as a Dio ListParam, and WHICH params are repeatable is decided by
the backend spec — so a param that is scalar today flips under any
./scripts/regenerate_api.sh with no mobile code change. The cast then
throws INSIDE the DioAdapter route callback, which never reads as "the
fake is broken": the request fails, the provider goes AsyncError, and
the screen paints an error body, so the failure surfaces as unrelated
downstream assertions in other files. This exact bug has shipped THREE
times in one file (status, then serviceId on working-days, then
serviceId on slots — the last reddened 4 tests across 2 flows). Reads
must route through _multiQueryParam / _scalarQueryParam, which tolerate
ListParam / List / scalar / absent alike. Zero baseline, same-line
`// query-param-cast-ok:` escape hatch.

<a id="blind-calendar-tap"></a>

### Forbid blind calendar day taps (2026-07-31)

2026-07-31 — forbid a blind tester.tap on a booking-calendar-day-* cell.
MonthCalendar sits in a SingleChildScrollView; on the 800x600 test
surface the scroll fold is at y~419 while the last two grid rows centre
at y~440/490. A blind tap on a below-the-fold cell does NOT throw — the
finder resolves, tap() computes a centre, and the tap lands on the
summary bar and is silently swallowed, failing later on an unrelated
assertion. Crucially it is DATE-DEPENDENT (tests tap DateTime.now().day),
so the suite is green ~18 days a month and red the last ~12 — it reads
as flake and gets re-run rather than fixed. Enabled-cell taps must go
through tester.tapCalendarDay (ensureVisible first). Tests proving a
cell is INERT keep tapping directly and declare it with
`warnIfMissed: false` — that is the exemption token. Zero baseline.

<a id="client-branch-key"></a>

### Forbid a client branch screen missing its Key (2026-07-31)

2026-07-31 — every CLIENT shell branch screen must carry the stable
`client-branch-<slug>` Key its placeholder exposed. Shell E2Es target
those keys to assert which branch is showing (text would couple them to
UA copy). The Phase 13.7 placeholder->HomeHubScreen migration dropped
`client-branch-home` while every sibling carried theirs over, leaving
two shell flows quietly red for a reason that looked like a navigation
bug. The widget tier is structurally blind to this: its branch-key
assertions pump the PLACEHOLDER, not the replacement. The branch->screen
mapping is derived from app_router.dart, so placeholder-served branches
are skipped automatically and a graduating branch is covered the day it
graduates - no allow-list to maintain.

<a id="page-title-token-fork"></a>

### Forbid a page-title token fork (2026-08-22)

2026-08-22 — the page-title typography unification (mobile-qa)
consolidated the four INDEPENDENT_MASTER tab-root titles (which had
silently diverged onto three different sizes — heading() 21sp, the
deleted one-off masterBookingsTitle 22sp, subheading() 14sp) onto ONE
token, VelvetText.pageTitle. Nothing stopped a future edit from
repointing one screen at a different token, or reintroducing a new
one-off title token, so this gate makes both mechanical. Rule A: no
new *Title-shaped VelvetText token outside the baselined allow-list
(scripts/.page_title_token_allow). Rule B: each of the four known
title call sites stays on VelvetText.pageTitle.

<a id="forked-calendar-grid"></a>

### Forbid a forked calendar grid (2026-08-14)

2026-08-14 — the calendar-consolidation change (mobile-backlog D5)
collapsed every month/week calendar surface onto ONE shared file
(`lib/shared/widgets/calendar_grid.dart`) precisely so a future D1–D4-
style fix lands everywhere at once — before it, `period_range_picker
.dart` had silently forked ~250 lines of `month_calendar.dart`'s
weekday-bar/week-row/day-cell logic, which is why those fixes had to
be re-applied there by hand once discovered. This gate makes the
single-implementation property mechanical: no second definition of
the shared primitives, no hardcoded copy of the weekendMuted hex, and
no raw Color hex literal in any of the three known calendar-grid
consumers. Zero baseline.

<a id="salon-booking-submit-notifier"></a>

### Forbid the deleted salon submit notifier (phase 271 D5)

2026-08-22 (Phase 271 D5) — the per-master salon booking submit
notifier was deleted after being harvested for its pinned test
behaviour (Phase 277's *Test cases*). It had already been deleted
once (MO-4) and come back once via a `git checkout` of an ancestor
commit (Phase 268's restore) — this gate makes a repeat of that same
move fail CI instead of shipping. Zero occurrences under lib/ of the
notifier's filename, its class, or its per-appointment status enum.

<a id="undeclared-scoped-service-dep"></a>

### Forbid an undeclared scoped-services dependency (2026-09-10)

2026-09-10 — phase 317 points the three services screens at a salon
master through ONE `ProviderScope` overriding `serviceTargetProvider`.
Riverpod 3 does not inherit scope transitively, so the whole watcher
chain carries an explicit `dependencies:` declaration. A provider
added to that chain later WITHOUT one does not crash — riverpod's
"may be scoped" assert is kDebugMode-only and `riverpod_lint` was
removed on 2026-08-18 — it silently resolves to ROOT, rendering the
operator's own catalogue under the salon master's heading and
dispatching `DELETE /services/{id}` against the SHARED salon service
definition on a delete. This gate makes the missing declaration fail
CI instead.

<a id="unencoded-path-interpolation"></a>

### Forbid unencoded API path interpolation (2026-09-17, S-L2)

2026-09-17 (mobile-security S-L2) — enforce the path-encoding
invariant `lib/core/network/path_segment.dart` had only ASSERTED.
That file's promotion comment claimed the encoder moved to core "so a
fix reaches every raw path in the app at once"; it had not — four
sites kept a bare `Uri.encodeComponent` (which does not escape `.`, so
`..` survives into Dio's `normalizePath()` and retargets the request
on the bearer-token-carrying Dio) and two more interpolated an id with
no encoding at all. All six were fixed in the same commit that added
this gate, AFTER watching it catch every one of them on the unfixed
tree. It checks hand-built `/api/v1/…` literals only — the provenance
half of the invariant stays a code-review obligation, and the guard's
header says so.

2026-09-17, same day: the first revision scanned ONE LINE AT A TIME
and was therefore blind to a path `dart format` had wrapped into
ADJACENT STRING LITERALS — which is how two of the six fixed sites
(`location_repository.dart:96`, `:107`) are spelled, so the gate could
not re-detect a regression at them. The scan is now group-aware and
both directions are sentinelled in `--self-test`; see the guard's
header, section "MULTI-LINE, and why that is not a detail".

<a id="api-enum-fallback"></a>

### Forbid reading the generated-enum fallback (phase 348)

2026-09-24 (Phase 348 re-audit INFO-1) — every generated beautica_api
enum now decodes an unknown wire value to `unknownDefaultOpenApi`
(`enumUnknownDefaultCase=true`). The ONE reading of that fallback is
`lib/core/network/api_enum_names.dart`; a `<GeneratedEnum>.valueOf(`
or a stray `unknownDefaultOpenApi` literal in lib/ is a second, drifting
reading of it. Enum names derived from api/lib on every run.

<a id="unclassified-layer-dim"></a>

### Forbid unclassified layer-opacity dims (phase 300)

2026-10-02 (Phase 300) — CI goldens discard layer opacity (Phase 299),
so a dim under an `Opacity`/`AnimatedOpacity` can look golden-covered
while never observed. Every layer-opacity site under lib/ must carry
`// dim-gated: <test>` or `// dim-decorative: <why>`; there is no
allow-list (Phase 301 burned it down) — any unclassified site fails.

<a id="layer-dim-harness"></a>

### Self-test layer-dim guard (phase 300)

Phase 300 — end-to-end harness for the guard above (runs the shipped
script as a subprocess in temp trees: injection, path confinement,
CRLF, comment handling, no-allow-list). Modelled on
test_cycle_gates.sh.

<a id="direct-navigator"></a>

### Forbid direct Navigator usage (phase 1.4)

Phase 1.4 — enforce go_router-only navigation in feature code.
Direct Navigator calls bypass the route table and are a mobile-qa HIGH
finding. lib/features/ is fully populated now — this gate is live.
Comment-only lines are excluded: ported-screen file headers routinely
document the design-preview's imperative `Navigator.push`/`maybePop`
→ go_router swap as part of the REUSE-FIRST port record (see
move_admin_salon_screen.dart, staff_settings_screen.dart), and failing
CI for documenting compliance with the rule is backwards. A line is
skipped only when its FIRST non-whitespace characters are a comment
marker (`//`, `///`, `/*`, or a `*` block-comment continuation) — real
code with a trailing comment (`Navigator.push(ctx); // TODO`) is still
flagged.

<a id="shared-preferences"></a>

### Forbid SharedPreferences in features (MS1)

MS1 — SharedPreferences must never be used for tokens or PII in feature
code. flutter_secure_storage is the only approved secure store.
lib/features/ is currently empty so this always passes; the gate becomes
live as soon as Phase 2.2 creates the auth feature directory.
`2>/dev/null` suppresses "no such file" noise when the dir doesn't exist.

<a id="openapi-drift"></a>

### OpenAPI client drift gate (phase 3.1)

Phase 3.1 — OpenAPI client drift gate.
Regenerates the Dart client from the COMMITTED spec snapshot
(tool/openapi/api-spec.json) into a temp dir, then diffs against the
committed api/.  Fails if they diverge — no live backend needed.
Tool setup: openapi_generator_cli is activated on the first run and
its JAR is cached in .dart_tool/openapi_generator_cache/.

<a id="builtvalue-codegen"></a>

### Verify built_value codegen (incident 2026-07-02)

Named, dependency-free guard for a live incident (2026-07-02): a
build_runner incremental-cache staleness bug let two generated
.g.dart files silently fall behind their .dart sources (a missing
Builder setter broke the compile; a missing @SerializersFor
registration would have caused a silent runtime "Serializer not
found" failure). Runs before the slower JAR-based check below so a
codegen-consistency break fails fast. See scripts/verify_builtvalue_codegen.sh
--self-test and the struck-through row in docs/mobile-phases/mobile-backlog.md.

<a id="openapi-check-timeout"></a>

### Verify OpenAPI client is up to date (Fix 3, PR #73)

Contract-drift gate (Fix 3, 2026-06-02): regenerates the Dart client
from the committed spec and fails on any diff vs api/. The companion
static guard test/core/config/app_config_path_test.dart (run by the
Test step below) pins the other half of the contract — that
AppConfig.baseUrl never carries an /api/v1 prefix and the generated
client paths resolve to a SINGLE /api/v1/ segment (no double-prefix).
Run locally with:  ./scripts/regenerate_api.sh --check

timeout-minutes (2026-09-27, PR #73): the `validate` job carries no
job-level timeout (GitHub default 6h), and this step's first-run
openapi_generator_cli JAR download can stall — job 108694409797's
PR-event run sat here >27min while the push run on the SAME commit
finished it in 63s. Fail fast instead of burning the 6h default.

<a id="custom-lint-removed"></a>

### custom_lint step removed (2026-08-18)

2026-08-18 — a `dart run custom_lint` step used to sit here. It was
deleted, along with the custom_lint / custom_lint_builder /
riverpod_lint dependencies, because it gated NOTHING: `custom_lint`
was archived upstream 2026-03-24 and riverpod_lint had already left
it in 3.1.0, so the host loaded ZERO plugins and still exited 0.
Falsified with a probe violating three riverpod_lint rules at once —
`No issues found!`, exit 0, `--format=json` -> `{"diagnostics":[]}`.

Re-homing riverpod_lint on Dart's native analyzer-plugin path was
attempted in the same pass and abandoned: the rules fire, but their
diagnostics are unsuppressable on this toolchain, so 33 pre-existing
findings would make the `Analyze` step permanently red with no way
to annotate a deliberate exception. See pubspec.yaml's lints block
for the evidence and the revisit condition. No lint plugin is
configured today; `analysis_options.yaml` declares none.

<a id="raw-ui-strings"></a>

### Forbid raw UI strings (2026-08-18)

2026-08-18 — the REAL `no_raw_ui_strings` gate. AST-based (the
Phase 1.3 checker, unchanged and covered by 19 unit tests), driven by
`tool/lints/no_raw_ui_strings.dart` behind the house-pattern shell
guard. Escape comment: `// raw-ui-string-ok: <reason>`
(`// ignore: no_raw_ui_strings` also honoured). Legacy offenders are
grandfathered in `scripts/.raw_ui_strings_allow` — shrink-only ratchet.

<a id="keepalive-family-invalidation"></a>

### Forbid bare keepalive-family cross-invalidation (2026-08-21)

2026-08-21 — this track closed a `ProviderSubscription`-closed crash
class: a keepAlive family member drops to ZERO listeners not because
its screen was popped, but because the SAME still-mounted screen
swapped which family key it watches via local state (a rail tap, a
sort toggle, a week page). `invalidateSelf()` then severs the
keepAlive link and queues disposal on a zero-duration Timer, racing
the next frame's re-subscribe to the SAME key. The proven remedy —
gate on "was this key pinned?", invalidate, THEN eagerly re-read so
the keepAlive link is re-touched before the queued disposal fires —
is applied at four sites (bookingsDay, master/salon reviews,
effectiveSchedule). This gate makes a bare cross-file family
invalidation fail CI instead of silently reintroducing the race.
Allow-list: scripts/.keepalive_family_invalidation_allow.

<a id="verify-guards-self-test"></a>

### Self-test drift-prevention gates (2026-06-24, 2026-08-18)

2026-06-24 — self-test the drift gates above. Each gate's
comment/annotation detection is load-bearing; --self-test pins it against
fixture snippets (plain offender → flagged, annotated/commented → pass).

2026-08-18 — this used to be 22 hand-written `--self-test` lines, one
per guard. That list was itself an un-gated gap: a guard added
without someone remembering to append its line here would have a
--self-test that never ran anywhere, looking covered while being
verified by nothing — the same silent-green class as the two bugs
found today (`no_raw_ui_strings` shipped as a never-loaded
`custom_lint` plugin; `riverpod_lint` silently stopped loading when
`custom_lint` was archived).

`verify_guards.sh --self-test` derives the list from the SAME
discovery glob normal mode uses (`scripts/forbid_*.sh`), so adding a
guard enrols it automatically — there is no second place to forget.
It requires every discovered guard to BOTH exit 0 AND print
`SELF-TEST OK: <basename>` (exit 0 alone is exactly the failure mode
being retired), asserts sentinel count == discovered count, and
names any guard that produced no sentinel.

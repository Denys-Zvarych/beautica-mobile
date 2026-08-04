#!/usr/bin/env bash
# Host-local-instant-anchor gate (dev-VM-zone-equals-business-zone trap).
#
# THE FRAGILITY THIS GUARDS
# --------------------------
# The dev VM this project is built on runs `TZ=Europe/Kyiv` — and
# `Europe/Kyiv` (`lib/shared/time/time_zones.dart`'s `kBeauticaTimeZoneName`)
# is ALSO the business timezone. A bare local constructor,
# `DateTime(2026, 6, 14, 12)`, resolves its underlying instant through the
# HOST PROCESS's own `TZ` — so on the dev VM that instant IS already Kyiv
# wall-clock, on CI (`TZ=UTC`) it is a DIFFERENT instant three hours earlier,
# and on any other machine it is whatever that machine's `TZ` happens to be.
# A test anchored this way is therefore either:
#   (a) accidentally correct on the dev VM and silently non-discriminating —
#       it can never fail there no matter what the zone-conversion code does,
#       because "device local" and "Kyiv local" are the same value by
#       construction, or
#   (b) correct on CI and wrong on the dev VM (or vice versa), which reads as
#       unrelated flake and gets re-run rather than fixed.
# Either way the fixture stops being a test of the zone-conversion logic it
# was written to pin. This has shipped THREE times: Phase 225 audit cycles 4
# and 5, and again on 2026-08-02. The root cause the architect traced it to:
# `lib/core/time/clock_provider.dart`'s own doc comment taught the bad pattern
# as the canonical override example — fixed alongside this gate.
#
# THIS SCRIPT NOW ENFORCES THREE RULES
# -------------------------------------
# RULE 1 (original, below) is scoped to "zone-critical" files — ones whose
# raw text already touches the Kyiv-anchored clock seam by name. RULE 2 (added
# 2026-08-02, see "RULE 2" section further down) is scoped to EVERY file under
# the same scan roots, with no Stage-1 filter at all. The scopes are DIFFERENT
# ON PURPOSE — that difference is part of what let 28 failures through on
# 2026-08-02: three schedule-widget test files fed a host-local `DateTime`
# instant through a `clock:` named parameter. `clock:` hands a widget an
# INSTANT; the widget (via `lib/shared/time/kyiv_day.dart`'s `kyivDayOf`)
# converts that instant through the Kyiv zone to derive "today". None of
# those three files mention `toBeauticaTime`, `clockProvider`, `TZDateTime`,
# `beauticaZone`, or `kBeauticaTimeZoneName` anywhere in their text — the zone
# conversion happens entirely INSIDE the widget under test, not in the test
# file — so Rule 1's Stage-1 classifier never even looked at them. Rule 2
# exists because "does this file mention the zone seam by name" is the wrong
# question for a `clock:` argument: ANY file, zone-aware-looking or not, can
# hand a widget an instant that then gets zone-converted somewhere downstream
# the test file never references. Do not fold Rule 2's scan back behind the
# zone-critical filter — that regression is the exact bug this rule was added
# to close.
#
# CORRECTION (post-mortem on THIS gate itself, same day): Rule 2 as first
# built only matched a LITERAL `DateTime(` inline at the `clock:` call site.
# But the actual 2026-08-02 fixtures did not do that — all three files used
# VARIABLE INDIRECTION instead (`clock: () => _today`, `clock: _testToday`,
# `clock: () => now`, sometimes through a two-hop chain like
# `DateTime _testToday() => _date;`). A literal-only Rule 2 would NOT have
# caught the incident it cites as its own motivation — an assertion this
# comment used to make and that was FALSE. Rule 2 was extended the same day
# to also resolve a `clock:`-fed IDENTIFIER to its own same-file declaration
# (see "RULE 2 IDENTIFIER RESOLUTION" below); the scratch-copy proof against
# the genuine pre-fix content of all three files is what closed this gap. Do
# not let this class of error recur: a script's own header claiming it covers
# an incident it was never actually run against is exactly the kind of
# unverified assertion this whole gate exists to replace with code.
#
# RULE 1
# ------
# Under EITHER scan root — `test/` or `integration_test/` — inside a file
# whose RAW text (including comments — deliberately over-inclusive) matches
#     toBeauticaTime|clockProvider|TZDateTime|beauticaZone|kBeauticaTimeZoneName
# (i.e. the file is "zone-critical": it exercises the Kyiv-anchored clock seam
# in some way), flag every `DateTime(` call where ALL of the following hold:
#
#   1. NOT A QUALIFIED CONSTRUCTOR. The character immediately before the
#      literal substring `DateTime(` is neither `.` nor a word character
#      (`[A-Za-z0-9_]`). This is what the literal-substring search alone does
#      NOT already exclude: `DateTime.utc(`, `.now(`, `.parse(`, and
#      `.fromMillisecondsSinceEpoch(` never produce the substring `DateTime(`
#      at all (the character right after `DateTime` is `.`, not `(`), but
#      `TZDateTime(` / `tz.TZDateTime(` DO contain `DateTime(` as a substring
#      — preceded by `Z`, a word character — so rule 1 is what excludes those.
#   2. LITERAL-YEAR FIRST ARG. Skipping whitespace after the opening `(`, the
#      first character is a digit. Excludes derived forms like
#      `DateTime(day.year, day.month, day.day, hour, minute)`, which read a
#      real calendar day rather than pinning an arbitrary host-resolved one.
#   3. ARITY >= 4 (i.e. at least 3 top-level commas between `DateTime(` and
#      its matching `)`). A 3-arg call (`DateTime(y, m, d)`, no time-of-day
#      component) can never disagree with its UTC twin on which SIDE of a
#      day-boundary it falls, so it isn't the bug class this gate exists for.
#      Depth is tracked forward (`(`/`[`/`{` increment, `)`/`]`/`}` decrement,
#      commas counted only at depth 1, stop the instant depth returns to 0) —
#      NOT a `[^)]*` regex, which would silently truncate at the first `)` of
#      any NESTED call and either over- or under-count the arg list.
#   4. LIVE CODE. Survives `strip_strings($0)` (not inside a string literal);
#      the line's first non-space token is not `//` (not a whole-comment
#      line); the match sits before any `//` that starts a real trailing
#      comment (found via `comment_start`, run over the already
#      string-stripped buffer — with no quotes left in that buffer, any `//`
#      remaining in it is, by construction, a real comment marker rather than
#      one hiding inside a string, so this composition needs no separate
#      raw-vs-stripped position mapping).
#   5. NOT ANNOTATED. Neither the matching line nor the line directly above
#      matches `// host-tz-ok: <reason>` (case-sensitive marker, any leading
#      whitespace, same convention as `future-date-ok` / `fixed-wait-ok`).
#      GOTCHA (same one those two gates already document): "the line directly
#      above" means the LAST comment line before the code. A marker sitting on
#      the FIRST line of a multi-line rationale block does NOT unblock the
#      code below it — the marker has to be the closing line of the block.
#
# ACCEPTED FIXES (RULE 1)
# ------------------------
#     DateTime.utc(2026, 8, 1, 23, 30)                               // a fixed instant
#     tz.TZDateTime(tz.getLocation('Asia/Tokyo'), 2026, 8, 2, 5, 0)  // a specific DEVICE zone
# Both fix the underlying instant independently of whichever `TZ` the process
# happens to run under. Worked reference:
# test/features/home/application/next_appointment_provider_test.dart:596-717
# (the "Kyiv-day boundary" group — one case anchored `.utc`, the other to an
# explicit `Asia/Tokyo` TZDateTime, precisely so the divergence each test
# exercises is a property of the FIXTURE, not of the host running it).
#
# RULE 2
# ------
# Under EITHER scan root — `test/` or `integration_test/` — in ANY `*.dart`
# file (no Stage-1 zone-critical filter; see "THIS SCRIPT NOW ENFORCES TWO
# RULES" above for why), flag a `clock:` NAMED ARGUMENT whose value pins a
# host-local instant. This happens in TWO ways, both covered:
#
#   (a) LITERAL AT THE CALL SITE — a bare local `DateTime(` call, of ANY
#       arity, inlined directly:
#           clock: () => DateTime(2026, 6, 13),   // closure form
#           clock: DateTime(2026, 6, 13),         // direct form
#
#   (b) IDENTIFIER INDIRECTION — a `clock:` argument that names an
#       identifier instead, whose SAME-FILE declaration is itself a bare
#       local `DateTime(` (see "RULE 2 IDENTIFIER RESOLUTION" below). This is
#       the shape the real 2026-08-02 incident actually used —
#       `clock: () => _today`, `clock: _testToday`, `clock: () => now` — NOT
#       form (a); a Rule 2 that only matched form (a) would not have caught
#       it (see the "CORRECTION" note above).
#
# Detection of form (a), precisely:
#   1. Find `clock:` as a word-bounded token (the character before `clock`,
#      if any, is not `[A-Za-z0-9_]` — excludes `myclock:`-style false hits)
#      that survives the same live-code checks as Rule 1: not inside a string
#      (`strip_strings`), not on a whole-comment line, and not at/after a
#      trailing `//` comment on its own line (`comment_start`).
#   2. Skip whitespace after the `:`. Optionally skip a `() =>` closure prefix
#      (flexible inner whitespace) if present.
#   3. What remains must start, LITERALLY, with the 9 characters `DateTime(`.
#      This is a prefix match on the trimmed remainder, not a substring
#      search — which is what excludes `DateTime.utc(` (10th char is `.`, not
#      `(`) and `tz.TZDateTime(` / `TZDateTime(` (the remainder starts with
#      `t`/`T`, not `D`) without needing Rule 1's separate preceding-char
#      check.
#   4. Skipping whitespace after that `(`, the first character must be a
#      digit (same rationale as Rule 1's rule 2: excludes derived forms like
#      `DateTime(day.year, day.month, day.day)`).
#   5. NOT ANNOTATED — same `// host-tz-ok: <reason>` convention, same
#      same-line-or-directly-above rule, as Rule 1's rule 5.
# NO ARITY FLOOR. Unlike Rule 1, arity is irrelevant here: a `clock:` value
# supplies an INSTANT that `kyivDayOf` converts through a DIFFERENT zone than
# whatever the host happens to run under, so even `DateTime(2026, 6, 13)`
# (arity 3, no time-of-day component) can land on the wrong side of the Kyiv
# day boundary depending on the host's own `TZ` — that's exactly the bug: on
# `TZ=Asia/Tokyo`, local midnight June 13 is 18:00 June 12 in Kyiv.
#
# RULE 2 IDENTIFIER RESOLUTION (form (b), added 2026-08-02 alongside the
# correction above)
# -----------------------------------------------------------------------
# When the trimmed remainder after `clock:` (optionally after a `() =>`
# closure prefix) does NOT start with `DateTime(`, check whether it is
# instead a BARE identifier reference — `clock: _x`, `clock: () => _x`, or
# `clock: () => _x()` (a zero-argument call) — immediately followed by a
# terminator (`,`, `)`, `;`, or end of string). A call carrying an ARGUMENT
# (`clock: () => _asClockInstant(_today)`) does NOT match this shape and is
# never chased — resolving what a helper does with its OWN parameter is
# genuine dataflow analysis, deliberately out of scope.
#
# When it does match, resolve that identifier against a table of same-file
# `DateTime`-typed declarations collected in a BEGIN pre-pass (one `getline`
# sweep of the file before the main scan), recognising exactly three forms:
#     final DateTime <name> = <initializer>;
#     DateTime <name> = <initializer>;
#     DateTime <name>() => <initializer>;
# If the resolved initializer is ITSELF just a bare name that is also
# declared in the file (e.g. `DateTime _testToday() => _date;`), chase again
# — bounded to 8 hops, far more than any real fixture needs — until landing
# on a genuine expression. Flag when that terminal expression contains a bare
# local `DateTime(` ANYWHERE in it (not only at its start — wrapping is
# common, e.g. `final DateTime _today = _dateOnly(DateTime(2026, 6, 13));`),
# using the same qualified-constructor exclusion and digit-first-arg check as
# Rule 1 / form (a) above. `// host-tz-ok:` on the `clock:` site itself
# suppresses exactly like it does for form (a). When flagged, this also
# prints the RESOLVED DECLARATION's own line (deduplicated per file) — that
# is literally where the fix belongs, and the author should not have to go
# hunting for it.
#
# HONEST LIMITS OF IDENTIFIER RESOLUTION — STATED PLAINLY, NOT SILENTLY
# ACCEPTED
#   - SAME-FILE ONLY. A declaration in a different file is never looked up;
#     `resolve_decl` returns "" and the reference is silently not flagged.
#   - NO REASSIGNMENT TRACKING. Only the DECLARATION is resolved. A later
#     plain reassignment (`name = DateTime(...);`, no `DateTime` type prefix
#     — so never mistaken for a new declaration) between the declaration and
#     the `clock:` use is invisible to this gate.
#   - SINGLE-LINE DECLARATIONS ONLY. A declaration whose initializer spans
#     multiple lines is not recognised at all (nothing to chase from).
#   - NOT RUNTIME-COMPUTED. An initializer that calls a non-trivial function
#     is scanned as TEXT for a bare `DateTime(` substring — it is not
#     evaluated, so a helper that returns a bare instant via some indirect
#     path this text scan can't see (e.g. behind a conditional, or built from
#     `.add(...)` on an already-resolved instant) is not analysed further
#     than the literal text of its own initializer.
#   - FIRST DECLARATION WINS ON NAME COLLISION. If the same name is declared
#     more than once in the file (e.g. reused in two different test bodies),
#     only the first occurrence populates the lookup table — no scope
#     awareness.
#   - A CALL CARRYING AN ARGUMENT IS NEVER CHASED (see above) — this is
#     BY DESIGN (chasing into a parameter is genuine dataflow analysis), not
#     an oversight, and is exactly what lets the already-fixed sites' own
#     `asClockInstant(dayToken)`-style helper (test/helpers/clock_instant.dart)
#     stay unflagged when called with an IDENTIFIER argument: the SAFETY
#     lives in the helper's body (`DateTime.utc(...)`), which reviewers still
#     need to eyeball once per helper, not once per call site.
#   - A SAFE HELPER CALLED WITH AN INLINE LITERAL STILL LOOKS LIKE THE BUG,
#     TEXTUALLY. `has_bare_datetime_call` scans a resolved declaration's
#     initializer for a bare `DateTime(` ANYWHERE in it (needed to catch
#     `_dateOnly(DateTime(2026, 6, 13))`-style wrapping — see above) — so
#     `DateTime now = asClockInstant(DateTime(2026, 6, 9));` DOES get flagged
#     even though `asClockInstant` makes it safe (it only reads
#     `.year`/`.month`/`.day`, which a local `DateTime(...)` constructor
#     always reports exactly as written regardless of host `TZ` — only the
#     INSTANT such a value maps to is host-dependent, and `asClockInstant`
#     never reads that). This gate cannot know a given call is that kind of
#     helper without hardcoding its name, which would make Rule 2 depend on
#     a naming convention rather than on syntax — worse than the false
#     positive. THE FIX IS AT THE CALL SITE, NOT IN THIS GATE: pass a
#     date-token IDENTIFIER (`asClockInstant(_today)`) rather than an inline
#     literal (`asClockInstant(DateTime(2026, 6, 9))`) — which is also just
#     better style (reuse the named token instead of repeating the date).
#     `test/features/schedule/presentation/day_hours_sheet_test.dart`'s
#     `asClockInstant(_date)` is the worked example.
# Reviewers still need to eyeball what a `clock:`-fed identifier resolves to
# when this gate's same-file, single-hop-chain, text-only resolution cannot
# reach it — these limits are real, not a return to "trust the reviewer for
# everything" that the literal-only version effectively was.
#
# ACCEPTED FIXES (RULE 2)
# ------------------------
#     clock: () => DateTime.utc(2026, 6, 13, 12),   // noon UTC — round-trips
#                                                    // to the intended day
#                                                    // from any realistic
#                                                    // host zone
#     clock: () => tz.TZDateTime(tz.getLocation('Asia/Tokyo'), 2026, 6, 13, 12),
#                                                    // when the test needs a
#                                                    // SPECIFIC device zone
# Incident: 2026-08-02, 28 deterministic test failures — three schedule-widget
# test files pinned "today" with a HOST-LOCAL `DateTime` instant fed through a
# `clock:` param, via variable indirection in every case (`clock: () =>
# _today`, `clock: _testToday`, `clock: () => now` — never an inline literal;
# see the "CORRECTION" note above). Under `TZ=Asia/Tokyo` that instant
# converts, via `kyivDayOf`, to June 12 in Kyiv rather than the intended
# June 13. Fixed by mobile-qa by re-anchoring every such fixture to
# `DateTime.utc(y, m, d, 12)` (directly, or via a small `_asClockInstant`
# helper). Verified against the genuine pre-fix content of all three files
# (`git show HEAD:<path>` at the point this correction was made, before
# mobile-qa's fix was committed) — Rule 2's identifier resolution flags all
# three.
#
# RULE 3 (added 2026-08-04 — the `DateTime.now()` hole Rules 1 and 2 could
# not reach)
# ------------------------------------------------------------------------
# WHY NEITHER EXISTING RULE CAUGHT THIS. On 2026-08-04 an E2E test read the
# HOST clock (`DateTime.now()`) to decide which calendar cell to tap, while
# the app under test ran on the INJECTED clock pinned to
# `integration_test/support/fake_backend.dart`'s
# `kFixedNow = DateTime.utc(2026, 6, 14, 12, 0, 0)`. It therefore tapped a
# cell for a date the app considers PAST. A past cell gets `onTap: null`
# (`lib/features/booking/presentation/widgets/month_calendar.dart`) and
# renders with NO `GestureDetector` at all, so the tap landed on the
# `SingleChildScrollView` behind it, silently no-opped, and no slots fetch
# fired. The test was green only when the real-world day-of-month happened to
# be >= 14 — invisible roughly 17 days out of every 30, which is the same
# "passes by accident on this machine, on this date" failure mode Rules 1 and
# 2 exist for. Neither reached it:
#   - RULE 1 requires a `DateTime(` with a LITERAL DIGIT first argument and
#     arity >= 4. `DateTime.now()` has no arguments at all, and does not even
#     produce the substring `DateTime(`.
#   - RULE 2 only inspects values that reach a `clock:` NAMED PARAMETER. The
#     failing read was assigned to a plain local that was used to build a
#     widget `Key` — it never went near a `clock:` argument.
#   - `scripts/forbid_raw_clock_read.sh` DOES flag every `DateTime.now`, but
#     its scan root is `lib/` ONLY (that split is documented in its own
#     header: "that one polices TEST anchors, this one polices PRODUCTION
#     reads"). The E2E tier was therefore covered by neither.
#
# THE RULE — A DECLARATION GATE, DELIBERATELY NOT A CLASSIFYING ONE. Under
# the `integration_test/` scan root ONLY, in ANY `*.dart` file (no Stage-1
# zone-critical filter, same as Rule 2), flag EVERY live-code reference to
# `DateTime.now` — both the call form (`DateTime.now()`) and the bare tear-off
# (`DateTime Function() clock = DateTime.now;`, which never calls it and which
# every ad-hoc `DateTime\.now\(\)` grep therefore misses). No attempt is made
# to tell a "good" read from a "bad" one, for exactly the reason
# `forbid_raw_clock_read.sh`'s header already states and which this incident
# proves out: `DateTime.now().isAfter(deadline)` (a genuine elapsed-wall-time
# measurement) and `DateTime.now().day` (the bug) are syntactically
# indistinguishable at the point of the read — they differ only in what the
# result flows into, which is dataflow analysis, not something a grep-shaped
# gate can decide. The 2026-08-04 read in particular had NO distinguishing
# syntax whatsoever: it was a bare `DateTime.now()` assigned to a local. Any
# rule narrow enough to spare the harness's polling deadlines would have
# spared the bug too.
#
# Detection, precisely (mirrors `forbid_raw_clock_read.sh` row for row so the
# two gates stay behaviourally identical where they overlap conceptually):
#   1. The literal substring `DateTime.now`, found in the string-stripped
#      buffer (`strip_strings`) — never inside a string literal.
#   2. NOT A LONGER IDENTIFIER. The character immediately before the match is
#      not a word character (`[A-Za-z0-9_]`) — this is what excludes
#      `tz.TZDateTime.now(loc)` / `TZDateTime.now(...)`, which contain
#      `DateTime.now` as a substring.
#   3. LIVE CODE. Line's first non-space token is not `//`; the match sits
#      before any real trailing `//` comment (`comment_start` over the
#      already string-stripped buffer).
#   4. NOT ANNOTATED. Neither the matching line nor the line directly above
#      carries `// instant-ok: <reason>`.
#
# WHY `instant-ok:` AND NOT `host-tz-ok:`. Rules 1 and 2 ask "why is this
# HOST-LOCAL literal's zone resolution correct here" — that is the
# `host-tz-ok:` question. Rule 3 asks a different one: "why is reading the
# DEVICE clock at all correct in a tier whose app under test runs on an
# INJECTED clock" — which is exactly the question
# `scripts/forbid_raw_clock_read.sh` already poses in `lib/`, under
# `// instant-ok: <reason>`. Reusing that marker keeps ONE vocabulary for
# "this raw clock read is genuinely an absolute-instant use" across both
# gates and both scan roots. A `host-tz-ok:` marker therefore does NOT
# suppress a Rule 3 hit (pinned by a self-test probe row) — the two markers
# answer different questions and are not interchangeable.
#
# SCAN ROOT — `integration_test/` ONLY, AND WHY. The E2E tier boots the REAL
# app with `clockProvider` overridden to a SINGLE pinned instant
# (`e2e_boot_policy.dart`'s `clockProvider.overrideWithValue(clock ?? () =>
# kFixedNow)`), so in that tier every host-clock read is, by construction,
# reading a clock the app under test does not share. `test/` has no such
# tier-wide pinned clock — each widget test decides its own override or none
# at all — so a blanket declaration gate there would be noise rather than
# signal. STATED PLAINLY AS A LIMIT, NOT SOLD AS COMPLETE: a `test/` widget
# test that overrides `clockProvider` and then reads `DateTime.now()` to
# build a fixture has the same defect and is NOT caught by any gate today.
# Rules 1 and 2 already scan `test/` for the literal-anchor shapes; this is
# the residue.
#
# ACCEPTED FIXES (RULE 3)
# ------------------------
#     final DateTime today = kyivToday(() => kFixedNow);  // the app's own injected clock
#     final DateTime start = fb.serverNow.add(...);       // FakeBackend's server clock (defaults to kFixedNow)
#     if (DateTime.now().isAfter(deadline)) { … }         // instant-ok: elapsed-wall-time poll, not a calendar-day derivation
# Incident: 2026-08-04 — `integration_test/public_master_profile_flow_test.dart`
# (Flows A, C, D) and `integration_test/independent_multi_service_booking_flow_test.dart`
# both picked a calendar day from `DateTime.now()` while the app ran on
# `kFixedNow`; fixed by routing both through `kyivToday(() => kFixedNow)`.
#
# NO LEGACY BASELINE — AND NONE SHOULD EVER BE ADDED
# ---------------------------------------------------
# Unlike `forbid_stale_future_date_fixture.sh`'s `.stale_future_date_allow`
# ratchet, this gate carries NO allow-list. At the moment it was introduced
# the two known offenders were `test/core/time/clock_provider_test.dart`'s
# three bare `DateTime(...)` fixtures, converted to `DateTime.utc(...)` in the
# same change that added this gate — so the baseline is empty from line one.
# Do NOT add a `.host_local_instant_allow` file to make a future offender
# "pass": every legitimate case is expressible either as `DateTime.utc(...)`
# or a `TZDateTime(...)` pinned to a named device zone, so there is never a
# reason to grandfather one in. If this ever feels necessary, the fix belongs
# in the flagged test, not in this script.
#
# CI hard-gate (run from `.github/workflows/pr-validate.yml`); also runnable
# locally before pushing.
# Self-test:  ./scripts/forbid_host_local_instant_anchor.sh --self-test

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"

# Repo-relative directories scanned — the WHOLE widget/unit tier and the WHOLE
# E2E tier, not a narrower subset. Unlike the stale-future-date gate (whose
# blind spot was a missing ROOT), this gate's risk is a missing FILE within an
# already-scanned root, so there is no narrower defensible scope: any test
# file anywhere under either tier can hand-roll a zone-critical fixture.
scan_dirs=(
  "test"
  "integration_test"
)

# Stage 1 classification — RULE 1 ONLY. A file only enters RULE 1's Stage 2
# scanning when its RAW text (comments included — deliberately
# over-inclusive, see header) touches the Kyiv-anchored clock seam in some
# way. This keeps Rule 1 silent on the ~overwhelming majority of the suite
# that never reads a clock at all, while still catching every file that
# does — including one whose ONLY reference is in a comment, since a comment
# can just as easily reference the wrong pattern as code can.
#
# RULE 2 DELIBERATELY DOES NOT USE THIS FILTER — see "THIS SCRIPT NOW
# ENFORCES TWO RULES" in the header for why a `clock:` argument needs
# whole-tree scanning regardless of whether the file "looks" zone-critical.
zone_critical_pattern='toBeauticaTime|clockProvider|TZDateTime|beauticaZone|kBeauticaTimeZoneName'

# `// host-tz-ok:` (any leading whitespace before the `//`) — same convention
# as `future-date-ok` / `fixed-wait-ok`. Shared by RULES 1 and 2.
annotation='[/][/][[:space:]]*host-tz-ok:'

# RULE 3's marker — `// instant-ok:`, the SAME vocabulary
# `scripts/forbid_raw_clock_read.sh` uses in `lib/`, deliberately NOT
# `host-tz-ok:` (see header "WHY `instant-ok:` AND NOT `host-tz-ok:`").
now_annotation='[/][/][[:space:]]*instant-ok:'

# RULE 3's scan root — a single entry of ${scan_dirs[@]}, not all of them.
# See header "SCAN ROOT — `integration_test/` ONLY, AND WHY".
now_scan_dir='integration_test'

# ---------------------------------------------------------------------------
# scan_file <path> <do_rule1: 0|1> <do_rule3: 0|1>
#   Emits "R1:<path>:<line>:<text>" for each un-annotated, live-code, bare
#   `DateTime(<digit>, ...)` call of arity >= 4 in <path> — ONLY when
#   <do_rule1> is "1" (run_scan's job: <path> already passed Stage 1
#   zone-critical classification; this function does not re-check it).
#   ALWAYS (regardless of <do_rule1>) also emits "R2:<path>:<line>:<text>"
#   for each un-annotated, live-code `clock:` named argument that pins a
#   host-local instant, of ANY arity — either a bare local `DateTime(...)`
#   inlined directly (closure form `clock: () => DateTime(...)` or direct
#   form `clock: DateTime(...)`), OR an identifier resolved to a same-file
#   declaration whose own initializer is a bare local `DateTime(...)` (see
#   "RULE 2 IDENTIFIER RESOLUTION" in the header) — in which case a second
#   "R2:" line for the resolved declaration is also emitted. See header
#   "RULE 2" for the full spec.
#   Emits "R3:<path>:<line>:<text>" for each un-annotated, live-code
#   `DateTime.now` reference (call form OR bare tear-off) — ONLY when
#   <do_rule3> is "1" (run_scan sets it for the `integration_test` scan dir
#   and nothing else; this function does not re-derive it from <path>). See
#   header "RULE 3".
# ---------------------------------------------------------------------------
scan_file() {
  local do_rule1="${2:-0}"
  local do_rule3="${3:-0}"
  awk -v file="$1" -v ann="$annotation" -v do_rule1="$do_rule1" \
      -v now_ann="$now_annotation" -v do_rule3="$do_rule3" '
    # Reused verbatim from scripts/forbid_stale_future_date_fixture.sh.
    # Erases quoted content entirely (does not preserve length/position) —
    # every match this script makes is found and positioned INSIDE this
    # stripped buffer, so internal positions stay self-consistent even though
    # they no longer line up with the raw line.
    function strip_strings(s,   out, c, i, q, esc) {
      out = ""; q = ""; esc = 0
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (q != "") {
          if (esc) { esc = 0; continue }
          if (c == "\\") { esc = 1; continue }
          if (c == q) { q = "" }
          continue
        }
        if (c == "\"" || c == "'"'"'") { q = c; continue }
        out = out c
      }
      return out
    }
    # Reused verbatim from scripts/forbid_stale_future_date_fixture.sh.
    # Index of the `//` that starts a line comment, ignoring `//` inside a
    # string literal; 0 if none. Run here over the ALREADY string-stripped
    # buffer (see rule 4 above), where it degenerates to "index of the first
    # literal `//`" — its quote-tracking never engages because no quotes
    # survive stripping, which is exactly what makes this composition sound
    # without a raw-to-stripped position map.
    function comment_start(s,   i, c, q, esc) {
      q = ""; esc = 0
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (q != "") {
          if (esc) { esc = 0; continue }
          if (c == "\\") { esc = 1; continue }
          if (c == q) { q = "" }
          continue
        }
        if (c == "\"" || c == "'"'"'") { q = c; continue }
        if (c == "/" && substr(s, i + 1, 1) == "/") { return i }
      }
      return 0
    }
    # Counts top-level commas between s[start] (the "(" of a DateTime( call)
    # and its matching ")", tracking bracket depth forward. Stops the INSTANT
    # depth returns to 0 — i.e. at DateTime'"'"'s OWN closing paren, never a
    # later one belonging to an enclosing call. Deliberately not a `[^)]*`
    # regex (see header, rule 3).
    function count_top_commas(s, start,   i, c, depth, commas, n) {
      n = length(s)
      depth = 0
      commas = 0
      for (i = start; i <= n; i++) {
        c = substr(s, i, 1)
        if (c == "(" || c == "[" || c == "{") {
          depth++
        } else if (c == ")" || c == "]" || c == "}") {
          depth--
          if (depth == 0) { return commas }
        } else if (c == "," && depth == 1) {
          commas++
        }
      }
      return commas
    }

    # =========================================================================
    # RULE 2 IDENTIFIER RESOLUTION (one-hop-or-chained same-file lookup — see
    # header "RULE 2" for the full spec and its honest limits). A `clock:`
    # argument that names an identifier instead of inlining a literal is
    # resolved to that identifier'"'"'s OWN declaration in THIS SAME FILE, then
    # the resulting initializer expression is scanned for a bare local
    # `DateTime(` the same way Rule 1 scans a whole line for one.
    # =========================================================================

    # True (1) iff `s` contains a bare local `DateTime(` call anywhere in it —
    # not preceded by `.` or a word character (excludes `TZDateTime(` /
    # `tz.TZDateTime(`; `DateTime.utc(` never contains the literal substring
    # `DateTime(` at all — see header rule 1) — AND whose first argument,
    # skipping whitespace, opens on a digit (excludes derived forms like
    # `DateTime(day.year, day.month, day.day)`, same rationale as Rule 1'"'"'s
    # rule 2). Used to inspect a RESOLVED declaration'"'"'s initializer, not a
    # call-site argument directly (that is what the existing literal-form scan
    # already does).
    function has_bare_datetime_call(s,   pos, idx, abs, parenidx, prevc, rest2, firstc3) {
      pos = 1
      while (1) {
        idx = index(substr(s, pos), "DateTime(")
        if (idx == 0) { return 0 }
        abs = pos + idx - 1
        parenidx = abs + 8
        if (abs > 1) {
          prevc = substr(s, abs - 1, 1)
          if (prevc == "." || prevc ~ /[A-Za-z0-9_]/) { pos = abs + 1; continue }
        }
        rest2 = substr(s, parenidx + 1)
        sub(/^[[:space:]]*/, "", rest2)
        firstc3 = substr(rest2, 1, 1)
        if (firstc3 ~ /[0-9]/) { return 1 }
        pos = abs + 1
      }
    }

    # Chases `decl_init` (populated by the BEGIN pre-pass below) from `nm`
    # through a BOUNDED chain of "initializer is ITSELF just a bare name"
    # declarations — e.g. `DateTime _testToday() => _date;` where `_date` is
    # in turn `final DateTime _date = DateTime(2026, 6, 21);` — and returns the
    # NAME of the terminal declaration: the one whose initializer is an actual
    # expression, not just another name. Returns "" if `nm` has no local
    # declaration at all (the honest cross-file-declaration limit: nothing to
    # chase, so silently not flagged — see header). MAX_CHASE_HOPS bounds a
    # pathological/self-referential chain; no real fixture in this codebase
    # needs anywhere near this many hops.
    function resolve_decl(nm,   cur, hops, val, MAX_CHASE_HOPS) {
      MAX_CHASE_HOPS = 8
      if (!(nm in decl_init)) { return "" }
      cur = nm
      hops = 0
      while (hops < MAX_CHASE_HOPS) {
        val = decl_init[cur]
        if (val ~ /^[A-Za-z_][A-Za-z0-9_]*$/ && (val in decl_init) && val != cur) {
          cur = val
          hops++
          continue
        }
        return cur
      }
      return cur
    }

    # -------------------------------------------------------------------------
    # BEGIN pre-pass — collects every same-file `DateTime`-typed declaration
    # BEFORE the main per-record scan runs, so a `clock:` site can resolve an
    # identifier regardless of whether its declaration appears earlier or
    # LATER in the file. Reads `file` (the same path awk is about to scan as
    # its main input) through an independent `getline < file` stream — this
    # does not touch NR/FNR/$0 of the main record loop below.
    #
    # Recognises exactly the three forms named in the header:
    #     final DateTime <name> = <initializer>;
    #     DateTime <name> = <initializer>;
    #     DateTime <name>() => <initializer>;
    # A declaration must be a SINGLE LINE (after string-stripping and
    # trailing-comment removal) — a multi-line initializer is not chased
    # (documented limit). `DateTime Function() <name>` (a function-TYPED
    # variable, e.g. a clock threaded through as a parameter) is explicitly
    # excluded, not misread as a plain `DateTime` declaration named
    # "Function". A later PLAIN REASSIGNMENT (`name = ...;`, no `DateTime`
    # type prefix) is never mistaken for a new declaration, so `decl_init`
    # always reflects the value at DECLARATION time, never a later mutation
    # (the "reassigned between declaration and use" limit). If the same name
    # is declared more than once in the file (e.g. the same local name reused
    # in two different test bodies), only the FIRST declaration seen is kept
    # — a shadow-aware second pass is out of scope (documented limit).
    # -------------------------------------------------------------------------
    BEGIN {
      dline_no = 0
      while ((getline draw < file) > 0) {
        dline_no++
        dcode = strip_strings(draw)
        dcs = comment_start(dcode)
        if (dcs > 0) { dcode = substr(dcode, 1, dcs - 1) }
        dtrim = dcode
        sub(/^[[:space:]]+/, "", dtrim)
        if (dtrim ~ /^final[[:space:]]+DateTime[[:space:]]+/) {
          sub(/^final[[:space:]]+DateTime[[:space:]]+/, "", dtrim)
        } else if (dtrim ~ /^DateTime[[:space:]]+/) {
          sub(/^DateTime[[:space:]]+/, "", dtrim)
        } else {
          continue
        }
        # Exclude `DateTime Function() <name> = ...` (function-typed
        # variable) — not a plain DateTime declaration.
        if (dtrim ~ /^Function[[:space:]]*\(/) { continue }
        if (!match(dtrim, /^[A-Za-z_][A-Za-z0-9_]*/) || RSTART != 1) { continue }
        dname = substr(dtrim, 1, RLENGTH)
        dafter = substr(dtrim, RLENGTH + 1)
        sub(/^[[:space:]]*/, "", dafter)
        dinit = ""
        if (substr(dafter, 1, 2) == "()") {
          dafter = substr(dafter, 3)
          sub(/^[[:space:]]*/, "", dafter)
          if (substr(dafter, 1, 2) == "=>") {
            dinit = substr(dafter, 3)
          }
        } else if (substr(dafter, 1, 1) == "=" && substr(dafter, 2, 1) != "=") {
          # `substr(dafter,2,1) != "="` excludes `==` (equality) being
          # misread as an assignment.
          dinit = substr(dafter, 2)
        }
        if (dinit == "") { continue }
        sub(/^[[:space:]]*/, "", dinit)
        sub(/;[[:space:]]*$/, "", dinit)
        sub(/[[:space:]]+$/, "", dinit)
        if (dinit == "") { continue }
        if (!(dname in decl_init)) {
          decl_init[dname] = dinit
          decl_line[dname] = dline_no
          decl_text[dname] = draw
        }
      }
      close(file)
    }
    {
      # (4a) Genuine whole-comment line? First non-space token is `//`.
      firsttok = $0
      sub(/^[[:space:]]+/, "", firsttok)
      if (firsttok ~ /^[/][/]/) { prev = $0; next }

      codeonly = strip_strings($0)
      cs = comment_start(codeonly)

      # ===================== RULE 1 (zone-critical files only) =====================
      is_offender1 = 0
      if (do_rule1 == "1") {
        pos = 1
        while (1) {
          idx = index(substr(codeonly, pos), "DateTime(")
          if (idx == 0) { break }
          abs = pos + idx - 1
          parenidx = abs + 8   # index, in codeonly, of the "(" itself

          # (4c) Match sits at/after a trailing comment in the stripped buffer.
          if (cs > 0 && abs >= cs) { pos = abs + 1; continue }

          # (1) Qualified-constructor exclusion (TZDateTime(, tz.TZDateTime(, …).
          if (abs > 1) {
            prevc = substr(codeonly, abs - 1, 1)
            if (prevc == "." || prevc ~ /[A-Za-z0-9_]/) { pos = abs + 1; continue }
          }

          # (2) First arg, skipping whitespace, must open on a digit.
          rest = substr(codeonly, parenidx + 1)
          sub(/^[[:space:]]*/, "", rest)
          firstc = substr(rest, 1, 1)
          if (firstc !~ /[0-9]/) { pos = abs + 1; continue }

          # (3) Arity >= 4, i.e. >= 3 top-level commas, depth-tracked.
          if (count_top_commas(codeonly, parenidx) >= 3) {
            is_offender1 = 1
          }
          pos = abs + 1
        }
      }

      # ===================== RULE 2 (ALL files, `clock:` argument) ==================
      # No zone-critical gate — see header. Any arity; only the two
      # literal-at-the-call-site shapes (closure / direct); see header rule 2.
      is_offender2 = 0
      dt2_idname = ""
      dt2_target = ""
      pos = 1
      while (1) {
        idx = index(substr(codeonly, pos), "clock:")
        if (idx == 0) { break }
        abs = pos + idx - 1

        # Word-boundary before "clock" (excludes e.g. "myclock:").
        if (abs > 1) {
          prevc = substr(codeonly, abs - 1, 1)
          if (prevc ~ /[A-Za-z0-9_]/) { pos = abs + 1; continue }
        }

        # Match sits at/after a trailing comment in the stripped buffer.
        if (cs > 0 && abs >= cs) { pos = abs + 1; continue }

        # Skip whitespace after "clock:", then an optional "() =>" closure
        # prefix (flexible inner whitespace), then require the remainder to
        # start LITERALLY with "DateTime(" — a prefix match, not a substring
        # search, which is what excludes DateTime.utc(, tz.TZDateTime(/
        # TZDateTime(, and any bare identifier/closure indirection without a
        # separate preceding-char check (see header rule 3).
        rest = substr(codeonly, abs + 6)
        sub(/^[[:space:]]*/, "", rest)
        sub(/^\(\)[[:space:]]*=>[[:space:]]*/, "", rest)
        if (substr(rest, 1, 9) == "DateTime(") {
          # First arg, skipping whitespace, must open on a digit (same
          # rationale as Rule 1: excludes derived forms like
          # DateTime(day.year, day.month, day.day)).
          after = substr(rest, 10)
          sub(/^[[:space:]]*/, "", after)
          firstc = substr(after, 1, 1)
          if (firstc ~ /[0-9]/) {
            is_offender2 = 1
          }
        } else {
          # RULE 2 IDENTIFIER RESOLUTION — the remainder is not a literal
          # `DateTime(` call; check whether it is a BARE identifier reference,
          # optionally called with ZERO arguments (`_x`, `_x()`), immediately
          # followed by a terminator (`,`, `)`, `;`, or end of string) — i.e.
          # exactly the three shapes named in the header: `clock: _x`,
          # `clock: () => _x`, `clock: () => _x()`. A call carrying an
          # ARGUMENT (e.g. `_asClockInstant(_today)`) does NOT match this —
          # chasing into a helper'"'"'s own parameter is genuine dataflow
          # analysis, deliberately out of scope (see header).
          if (match(rest, /^[A-Za-z_][A-Za-z0-9_]*/) && RSTART == 1) {
            idname = substr(rest, 1, RLENGTH)
            tail = substr(rest, RLENGTH + 1)
            sub(/^[[:space:]]*/, "", tail)
            if (substr(tail, 1, 2) == "()") { tail = substr(tail, 3) }
            sub(/^[[:space:]]*/, "", tail)
            tailc = substr(tail, 1, 1)
            if (tailc == "" || tailc == "," || tailc == ")" || tailc == ";") {
              target = resolve_decl(idname)
              if (target != "" && has_bare_datetime_call(decl_init[target])) {
                is_offender2 = 1
                dt2_idname = idname
                dt2_target = target
              }
            }
          }
        }
        pos = abs + 1
      }

      # ============ RULE 3 (integration_test/ only, raw device-clock read) ==========
      # A DECLARATION gate: every live-code `DateTime.now` reference, call
      # form or bare tear-off, with no attempt to classify good from bad (see
      # header "RULE 3" for why classifying is not possible here). Mirrors
      # scripts/forbid_raw_clock_read.sh row for row.
      is_offender3 = 0
      if (do_rule3 == "1") {
        pos = 1
        while (1) {
          idx = index(substr(codeonly, pos), "DateTime.now")
          if (idx == 0) { break }
          abs = pos + idx - 1

          # Match sits at/after a trailing comment in the stripped buffer.
          if (cs > 0 && abs >= cs) { pos = abs + 1; continue }

          # Exclude a longer identifier merely ENDING in "DateTime.now"
          # (tz.TZDateTime.now(loc) / TZDateTime.now(...)): the character
          # immediately before the match must not be a word character.
          if (abs > 1) {
            prevc = substr(codeonly, abs - 1, 1)
            if (prevc ~ /[A-Za-z0-9_]/) { pos = abs + 1; continue }
          }

          is_offender3 = 1
          pos = abs + 12   # length("DateTime.now")
        }
      }

      # Annotation suppression. RULES 1 and 2 share `host-tz-ok:`; RULE 3
      # uses `instant-ok:` and is NOT suppressed by `host-tz-ok:` — the two
      # markers answer different questions (see header). Both honour the same
      # same-line-or-directly-above placement rule, with the same documented
      # gotcha: on a multi-line rationale block the marker must be the LAST
      # comment line before the code.
      if (is_offender1 || is_offender2) {
        if ($0 ~ ann || prev ~ ann) { is_offender1 = 0; is_offender2 = 0 }
      }
      if (is_offender3) {
        if ($0 ~ now_ann || prev ~ now_ann) { is_offender3 = 0 }
      }

      if (is_offender1 || is_offender2 || is_offender3) {
        if (is_offender1) { printf "R1:%s:%d:%s\n", file, NR, $0 }
        if (is_offender3) { printf "R3:%s:%d:%s\n", file, NR, $0 }
        if (is_offender2) {
          printf "R2:%s:%d:%s\n", file, NR, $0
          # Also report the RESOLVED declaration once per unique target per
          # file — "so the author knows what to change" (this is literally
          # the line to fix). Deduped via reported_decl so a name referenced
          # by several clock: sites in the same file is only printed once.
          if (dt2_target != "" && !(dt2_target in reported_decl)) {
            reported_decl[dt2_target] = 1
            if (dt2_idname == dt2_target) {
              printf "R2:%s:%d:%s    [declaration of `%s`, referenced directly by the clock: site above]\n", file, decl_line[dt2_target], decl_text[dt2_target], dt2_target
            } else {
              printf "R2:%s:%d:%s    [declaration of `%s`, resolved from `%s` referenced by the clock: site above]\n", file, decl_line[dt2_target], decl_text[dt2_target], dt2_target, dt2_idname
            }
          }
        }
      }
      prev = $0
    }
  ' "$1"
}

# ---------------------------------------------------------------------------
# run_scan <tree_root>
#   Emits "R1:..." / "R2:..." offenders across every *.dart file under each
#   of ${scan_dirs[@]}, resolved relative to <tree_root>. RULE 1 is restricted
#   to files that pass Stage 1 zone-critical classification (unchanged from
#   before Rule 2 existed); RULE 2 runs against EVERY file, unconditionally —
#   `scan_file` is called for every file found, and only the do_rule1 flag
#   varies. A scan dir that does not exist under <tree_root> contributes
#   nothing (lets the self-test synthesize one root at a time).
#
#   RULE 3 runs against every file under `$now_scan_dir` (`integration_test`)
#   and no other scan dir — the flag is derived from the DIRECTORY being
#   walked, never from the file's own text, so there is no per-file filter to
#   regress (see header "SCAN ROOT — `integration_test/` ONLY, AND WHY").
# ---------------------------------------------------------------------------
run_scan() {
  local tree_root="$1"
  local d f do_rule1 do_rule3
  for d in "${scan_dirs[@]}"; do
    do_rule3=0
    if [ "$d" = "$now_scan_dir" ]; then
      do_rule3=1
    fi
    while IFS= read -r -d '' f; do
      [ -z "$f" ] && continue
      do_rule1=0
      if grep -qE "$zone_critical_pattern" "$f" 2>/dev/null; then
        do_rule1=1
      fi
      scan_file "$f" "$do_rule1" "$do_rule3"
    done < <(find "$tree_root/$d" -type f -name '*.dart' -print0 2>/dev/null | sort -z)
  done
}

# ---------------------------------------------------------------------------
# Self-test mode. RULE 1 probes: synthesize ONE zone-critical probe PER SCAN
# ROOT (proves `integration_test/` is genuinely walked, not merely listed in
# `scan_dirs` — the same lesson `forbid_stale_future_date_fixture.sh` learned
# the hard way on 2026-07-21) plus ONE non-zone-critical probe carrying the
# exact flagged shape, to pin Stage 1 classification independently of Stage 2
# matching. RULE 2 probes: a SEPARATE pair of files, ONE PER SCAN ROOT, each
# deliberately carrying NO zone-critical marker at all — this is the exact
# shape of the 2026-08-02 incident, and pins that Rule 2 bypasses Stage 1
# entirely rather than merely "also happening to pass" it.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  probe_paths=(
    "test/core/time/host_local_instant_probe_test.dart"
    "integration_test/support/host_local_instant_probe.dart"
  )
  noncritical_path="test/core/time/host_local_instant_probe_control_test.dart"

  # Lines Rule 1 must flag, and the total per zone-critical probe file.
  offender_lines=(16 19 44 60)
  offenders_per_probe=${#offender_lines[@]}

  # RULE 2 probes: one per scan root, neither containing any zone-critical
  # marker (see block comment above).
  clock_probe_paths=(
    "test/features/schedule/presentation/clock_param_probe_test.dart"
    "integration_test/support/clock_param_probe.dart"
  )
  # Lines Rule 2 must flag in each clock-probe file (closure form arity 3,
  # closure form arity 4, direct form) — see the probe content below.
  clock_offender_lines=(13 16 19)
  clock_offenders_per_probe=${#clock_offender_lines[@]}

  for probe in "${probe_paths[@]}"; do
    mkdir -p "$tmp/$(dirname "$probe")"
    cat > "$tmp/$probe" <<'EOF'
// Zone-critical marker for the self-test probe (mentions toBeauticaTime,
// clockProvider, TZDateTime, beauticaZone, kBeauticaTimeZoneName so Stage 1
// classification picks this file up under EITHER scan root).
// Exercises scripts/forbid_host_local_instant_anchor.sh row-by-row.

// (1) arity 3 — not flagged.
final DateTime a = DateTime(2026, 8, 1);

// (2) DateTime.utc — qualified constructor, not flagged.
final DateTime b = DateTime.utc(2026, 8, 1, 23, 30);

// (3) TZDateTime — qualified constructor (device-zone form), not flagged.
final DateTime c = tz.TZDateTime(loc, 2026, 8, 2, 5, 0);

// (4) bare DateTime(, arity 4 — MUST be flagged.
final DateTime d = DateTime(2026, 8, 1, 23, 30);

// (5) bare DateTime(, arity 7 — MUST be flagged.
final DateTime e = DateTime(2026, 8, 1, 23, 30, 0, 0);

// (6) derived first arg (day.year, ...) — not flagged, rule 2.
final DateTime f = DateTime(day.year, day.month, day.day, 9, 0);

// (7) whole-line comment — not flagged.
// final DateTime g = DateTime(2026, 8, 1, 23, 30);

// (8) trailing comment hides the call — not flagged.
final DateTime h = x; // DateTime(2026, 8, 1, 23, 30)

// (9) inside a string literal — not flagged (strip_strings).
const String s = "DateTime(2026, 8, 1, 23, 30)";

// (10) same-line host-tz-ok marker — not flagged.
final DateTime i = DateTime(2026, 8, 1, 23, 30); // host-tz-ok: pinned instant, see group header

// (11) marker on the line directly above — not flagged.
// host-tz-ok: pinned instant, see group header
final DateTime j = DateTime(2026, 8, 1, 23, 30);

// (12) nested, arity 3 — not flagged; pins the depth counter.
final k = f(DateTime(2026, 8, 1), 3);

// (13) nested, arity 4 — MUST be flagged; same pin, other direction.
final l = f(DateTime(2026, 8, 1, 9), 3);

// (14) arity 3 with a nested-bracket comma INSIDE DateTime's own arg list —
// not flagged; pins the depth-RESTRICTED comma count (only depth==1 commas
// count) distinctly from (12)/(13), which pin only where counting STOPS. A
// counter that summed every comma regardless of depth would misread this as
// arity 4 (2 top-level + 1 nested) and flag it — a real false positive a
// naive `[^)]*`-style or depth-blind counter would produce.
final DateTime m = DateTime(2026, 8, sumOf(1, 2));

// (15) host-tz-ok marker at the TOP of a multi-line rationale block (not the
// line directly above the code) — MUST still be flagged. Per the documented
// gotcha (header rule 5, shared with future-date-ok / fixed-wait-ok), the
// marker only unblocks when it is the LAST comment line before the code.
// host-tz-ok: reason stated first, on the TOP line of a 2-line block
// second line of rationale — THIS line, not the one above, is "directly
final DateTime n = DateTime(2026, 8, 1, 23, 30);
EOF
  done

  mkdir -p "$tmp/$(dirname "$noncritical_path")"
  cat > "$tmp/$noncritical_path" <<'EOF'
// A file with NO zone-critical marker — Stage 1 classification must skip it
// even though it carries the exact flagged shape below (pins Stage 1
// independently of Stage 2's own matching logic).
final DateTime d = DateTime(2026, 8, 1, 23, 30);
EOF

  for probe in "${clock_probe_paths[@]}"; do
    mkdir -p "$tmp/$(dirname "$probe")"
    # NOTE: this file's own comments must not spell out any of Stage 1's
    # marker identifiers (not even in prose) — doing so would make Stage 1
    # classify THIS file as zone-critical and defeat the point of the probe.
    # The device-zone qualified-constructor exclusion is exercised in a
    # SEPARATE, deliberately zone-critical probe below instead, precisely
    # because writing that identifier out requires spelling the marker.
    cat > "$tmp/$probe" <<'EOF'
// Non-zone-critical probe (deliberately carries NONE of the identifiers
// Stage 1 classification looks for) — pins that RULE 2 does not gate
// through Stage 1 at all. This is the exact shape that let 28 failures
// through on 2026-08-02: three schedule widget tests anchored `clock:` with
// a bare local DateTime(...) in files Stage 1 never looked at, because the
// zone conversion happens entirely inside the widget under test, not in
// the test file itself. (The qualified device-zone-constructor exclusion
// is covered separately, in clock_param_tzdatetime_probe_test.dart, since
// spelling that identifier here would itself trip Stage 1 and defeat this
// file's whole point.)

// (r2-1) closure form, arity 3 — MUST be flagged.
final w1 = Widget(clock: () => DateTime(2026, 6, 13));

// (r2-2) closure form, arity 4 — MUST be flagged.
final w2 = Widget(clock: () => DateTime(2026, 6, 13, 12));

// (r2-3) direct form (no closure) — MUST be flagged.
final w3 = Widget(clock: DateTime(2026, 6, 13));

// (r2-4) DateTime.utc — not flagged (correct fix form).
final w4 = Widget(clock: () => DateTime.utc(2026, 6, 13, 12));

// (r2-5) indirection through an UNDECLARED-IN-THIS-FILE identifier — not
// flagged; `_today` has no local declaration anywhere in this probe file
// (deliberately), so identifier resolution (see
// clock_param_identifier_probe_test.dart for the full positive/negative
// matrix) has nothing to chase and silently no-ops — the honest
// cross-file/undeclared limit, not a general "indirection slips by" gap.
final w5 = Widget(clock: () => _today);

// (r2-6) same-line host-tz-ok marker — not flagged.
final w6 = Widget(clock: () => DateTime(2026, 6, 13)); // host-tz-ok: reason

// (r2-7) whole-line comment — not flagged.
// final w7 = Widget(clock: () => DateTime(2026, 6, 13));

// (r2-8) derived first arg — not flagged, same rule-2-arg-digit exclusion
// as rule 1.
final w8 = Widget(clock: () => DateTime(day.year, day.month, day.day));
EOF
  done

  # Deliberately ZONE-CRITICAL (mentions the device-zone constructor by
  # name) — exists solely to confirm RULE 2 also excludes the real
  # tz.TZDateTime(...) form used by actual fixtures, independent of RULE 1's
  # own handling of the same literal (already pinned by the zone-critical
  # probes above). Must contribute ZERO offenders to EITHER rule.
  tzdatetime_probe="test/features/schedule/presentation/clock_param_tzdatetime_probe_test.dart"
  mkdir -p "$tmp/$(dirname "$tzdatetime_probe")"
  cat > "$tmp/$tzdatetime_probe" <<'EOF'
// Deliberately zone-critical — exists only to confirm RULE 2's
// qualified-constructor exclusion also handles tz.TZDateTime(...), the form
// real fixtures use for a specific device zone. Must contribute ZERO
// offenders to either rule.
final w = Widget(clock: () => tz.TZDateTime(loc, 2026, 6, 13, 12));
EOF

  # RULE 2 IDENTIFIER RESOLUTION probe — pins the extension that resolves a
  # `clock:` identifier to its own same-file declaration. This is the
  # mechanism that closes the false-claim gap: the real 2026-08-02 incident
  # files used variable indirection (`clock: () => _today`,
  # `clock: _testToday`), not an inline literal, and the ORIGINAL Rule 2
  # (literal-at-call-site only) would NOT have caught them. See header "RULE
  # 2" for the full spec of what gets chased and what deliberately does not.
  identifier_probe="test/features/schedule/presentation/clock_param_identifier_probe_test.dart"
  mkdir -p "$tmp/$(dirname "$identifier_probe")"
  cat > "$tmp/$identifier_probe" <<'EOF'
// Non-zone-critical probe — RULE 2 IDENTIFIER RESOLUTION. Deliberately
// carries NONE of Stage 1's marker identifiers.

// ---- Declarations chased by clock: sites below ----

// (decl-1) bare DateTime(, referenced DIRECTLY by a clock: site — MUST be
// flagged (0-hop: the identifier IS the terminal declaration).
final DateTime idA = DateTime(2026, 5, 1);

// (decl-2) a genuine instant — NOT flagged when resolved.
final DateTime idB = DateTime.utc(2026, 5, 2, 12);

// (decl-3) wraps a bare DateTime( inside another call — MUST be flagged when
// resolved (pins "look for DateTime( anywhere in the initializer, not only
// at its start").
final DateTime idC = _dateOnly(DateTime(2026, 5, 3));

// (decl-4) function form, chased to idA — MUST be flagged (the 2-hop shape
// day_hours_sheet_test.dart's real `_testToday() => _date;` actually used).
DateTime idD() => idA;

// (decl-5) a helper that takes an ARGUMENT — never chased (chasing into a
// parameter is genuine dataflow analysis, deliberately out of scope).
DateTime idE(DateTime dayToken) =>
    DateTime.utc(dayToken.year, dayToken.month, dayToken.day, 12);

// (decl-6) declared safely, then REASSIGNED (not re-declared) to a bare
// DateTime( before use — resolution must use the DECLARATION, never the
// reassignment (documented limit).
DateTime idF = DateTime.utc(2026, 5, 6, 12);

// ---- clock: sites ----

// (r2id-1) direct form, 0-hop — MUST be flagged.
final s1 = Widget(clock: idA);

// (r2id-2) closure form, 0-hop — MUST be flagged.
final s2 = Widget(clock: () => idA);

// (r2id-3) resolves to a qualified instant — not flagged.
final s3 = Widget(clock: () => idB);

// (r2id-4) resolves to a wrapped bare DateTime( — MUST be flagged.
final s4 = Widget(clock: () => idC);

// (r2id-5) chained through a zero-arg function-form declaration to idA —
// MUST be flagged.
final s5 = Widget(clock: () => idD());

// (r2id-6) a call carrying an ARGUMENT — not resolved, not flagged (out of
// scope by design; see decl-5).
final s6 = Widget(clock: () => idE(idA));

// (r2id-7) resolves to the DECLARATION (a safe instant), never a later
// reassignment (a bare local DateTime) — not flagged.
final s7 = Widget(clock: () => idF);

// (r2id-8) an identifier with NO local declaration anywhere in this file —
// resolve_decl returns "" — not flagged (the cross-file/undeclared honest
// limit).
final s8 = Widget(clock: () => _externallyDeclared);

// (r2id-9) host-tz-ok on the clock: site itself suppresses an
// identifier-resolved offender exactly like a literal one.
final s9 = Widget(clock: idA); // host-tz-ok: reason
EOF
  # Clock-site lines that MUST be flagged, and the (deduped) declaration
  # lines that must accompany them.
  identifier_offender_clock_lines=(35 38 44 48)
  identifier_offender_decl_lines=(8 16)
  identifier_offenders_total=$(( ${#identifier_offender_clock_lines[@]} + ${#identifier_offender_decl_lines[@]} ))
  # Clock-site lines that must NOT be flagged (qualified instant / call with
  # an argument / declaration-not-reassignment / no local declaration /
  # host-tz-ok annotated).
  identifier_clean_lines=(41 52 56 61 65)

  # RULE 3 probe — raw device-clock reads in the E2E tier. Lives under
  # `integration_test/` because that is RULE 3's ONLY scan root; the
  # `test/`-side control below carries the identical shape and must stay
  # clean, which is what pins the root restriction independently of the
  # matching logic.
  now_probe="integration_test/support/host_now_probe.dart"
  mkdir -p "$tmp/$(dirname "$now_probe")"
  cat > "$tmp/$now_probe" <<'EOF'
// Probe for RULE 3 (raw device-clock read in the E2E tier) — exercises the
// rule row by row. Carries no `clock:` named argument, so RULE 2 must
// contribute nothing here; row (r3-8) does mention the device-zone
// constructor by name (which makes Stage 1 classify this file as
// zone-critical and therefore ENABLES Rule 1 on it), but the file contains
// no bare DateTime(<digit>, …) call at all, so Rule 1 must still find
// nothing.

// (r3-1) call form, live code — MUST be flagged.
final DateTime a = DateTime.now();

// (r3-2) bare tear-off — never calls now(), only tears it off, which is
// exactly what a `DateTime\.now\(\)` grep misses — MUST be flagged.
final DateTime Function() b = DateTime.now;

// (r3-3) same-line instant-ok marker — not flagged.
final DateTime c = DateTime.now(); // instant-ok: elapsed-wall-time poll

// (r3-4) marker on the line directly above — not flagged.
// instant-ok: elapsed-wall-time poll
final DateTime d = DateTime.now();

// (r3-5) whole-line comment — not flagged.
// final DateTime e = DateTime.now();

// (r3-6) inside a string literal — not flagged (strip_strings).
const String s = "DateTime.now()";

// (r3-7) trailing comment hides the call — not flagged.
final DateTime f = g; // DateTime.now()

// (r3-8) a longer identifier merely ENDING in DateTime.now — not flagged.
final DateTime h = tz.TZDateTime.now(loc);

// (r3-9) host-tz-ok is RULE 1/2's marker, NOT RULE 3's — MUST still be
// flagged. The question RULE 3 asks ("why is reading the DEVICE clock
// correct in a tier whose app runs on an injected one") is the instant-ok
// question, not the host-tz-ok one, and the two are not interchangeable.
// host-tz-ok: wrong marker for a raw device-clock read
final DateTime i = DateTime.now();
EOF
  now_offender_lines=(10 14 40)
  now_clean_lines=(17 21 24 27 30 33)

  # RULE 3 scan-root control — the SAME flagged shape, under `test/` instead
  # of `integration_test/`. Must contribute ZERO offenders: RULE 3's root
  # restriction is derived from the directory being walked, and this is what
  # proves that derivation is real rather than incidental.
  now_control_path="test/core/time/host_now_scope_control_test.dart"
  mkdir -p "$tmp/$(dirname "$now_control_path")"
  cat > "$tmp/$now_control_path" <<'EOF'
// Control for RULE 3's scan-root restriction: this file sits under test/,
// NOT integration_test/, and carries the exact flagged shape below. RULE 3
// must contribute ZERO offenders from it — the widget/unit tier has no
// single app-wide injected clock the way the E2E tier does (see the
// script header's "SCAN ROOT" section, which states that residual gap
// plainly rather than pretending it is covered).
final DateTime a = DateTime.now();
DateTime Function() b = DateTime.now;
EOF

  out="$(run_scan "$tmp")"
  flagged="$(printf '%s\n' "$out" | grep -c . || true)"
  expected=$(( ${#probe_paths[@]} * offenders_per_probe + ${#clock_probe_paths[@]} * clock_offenders_per_probe + identifier_offenders_total + ${#now_offender_lines[@]} ))
  if [ "$flagged" -ne "$expected" ]; then
    echo "SELF-TEST FAIL: expected exactly $expected offenders"
    echo "                ($offenders_per_probe Rule-1 hits × ${#probe_paths[@]}"
    echo "                zone-critical probes, plus $clock_offenders_per_probe"
    echo "                Rule-2 hits × ${#clock_probe_paths[@]} clock probes,"
    echo "                plus $identifier_offenders_total Rule-2 identifier-"
    echo "                resolution hits, plus ${#now_offender_lines[@]} Rule-3"
    echo "                raw-device-clock-read hits; the non-zone-critical"
    echo "                Rule-1 control and the test/-side Rule-3 scan-root"
    echo "                control must each contribute zero), got $flagged:"
    printf '%s\n' "$out"
    exit 1
  fi
  for ln in "${identifier_offender_clock_lines[@]}" "${identifier_offender_decl_lines[@]}"; do
    if ! printf '%s\n' "$out" | grep -q "^R2:$tmp/$identifier_probe:$ln:"; then
      echo "SELF-TEST FAIL: expected a Rule-2 identifier-resolution offender"
      echo "                at $identifier_probe:$ln, none found."
      printf '%s\n' "$out"
      exit 1
    fi
  done
  for ln in "${identifier_clean_lines[@]}"; do
    if printf '%s\n' "$out" | grep -q "^R2:$tmp/$identifier_probe:$ln:"; then
      echo "SELF-TEST FAIL: line $ln of $identifier_probe should NOT be"
      echo "                flagged (qualified instant / call-with-argument /"
      echo "                reassignment-not-redeclaration / no local"
      echo "                declaration / host-tz-ok), but was:"
      printf '%s\n' "$out"
      exit 1
    fi
  done
  if printf '%s\n' "$out" | grep -q "^R1:$tmp/$identifier_probe:"; then
    echo "SELF-TEST FAIL: $identifier_probe was flagged by Rule 1 — this probe"
    echo "                carries no zone-critical marker, so Stage 1 must"
    echo "                exclude it from Rule 1 entirely:"
    printf '%s\n' "$out"
    exit 1
  fi
  for probe in "${probe_paths[@]}"; do
    for ln in "${offender_lines[@]}"; do
      if ! printf '%s\n' "$out" | grep -q "^R1:$tmp/$probe:$ln:"; then
        echo "SELF-TEST FAIL: expected a Rule-1 offender at $probe:$ln, none found."
        echo "                Is '$(dirname "$(dirname "$probe")")' listed in"
        echo "                scan_dirs AND actually walked by run_scan?"
        printf '%s\n' "$out"
        exit 1
      fi
    done
  done
  if printf '%s\n' "$out" | grep -q "$noncritical_path"; then
    echo "SELF-TEST FAIL: the non-zone-critical Rule-1 probe was flagged —"
    echo "                Stage 1 classification is not gating Rule 1 at all:"
    printf '%s\n' "$out"
    exit 1
  fi

  for probe in "${clock_probe_paths[@]}"; do
    for ln in "${clock_offender_lines[@]}"; do
      if ! printf '%s\n' "$out" | grep -q "^R2:$tmp/$probe:$ln:"; then
        echo "SELF-TEST FAIL: expected a Rule-2 offender at $probe:$ln, none found."
        echo "                This probe carries NO zone-critical marker — if"
        echo "                Rule 2 is (re-)gated behind Stage 1 classification,"
        echo "                this is exactly the regression that let 28"
        echo "                failures through on 2026-08-02."
        printf '%s\n' "$out"
        exit 1
      fi
    done
    # Lines that must NOT be flagged by Rule 2 in the clock probe: 22 (.utc),
    # 30 (indirection through an identifier undeclared in THIS file — the
    # cross-file/undeclared honest limit), 33 (host-tz-ok annotated), 36
    # (whole-line comment, can't match anyway — asserted for documentation),
    # 40 (derived first arg).
    for ln in 22 30 33 36 40; do
      if printf '%s\n' "$out" | grep -q "^R2:$tmp/$probe:$ln:"; then
        echo "SELF-TEST FAIL: line $ln of $probe should NOT be flagged by Rule 2"
        echo "                (qualified constructor / undeclared indirection /"
        echo "                annotated / whole-line comment / derived first arg), but was:"
        printf '%s\n' "$out"
        exit 1
      fi
    done
    # This probe must ALSO never be flagged by Rule 1 — it carries no
    # zone-critical marker, so Rule 1's Stage 1 filter must exclude it
    # entirely regardless of what Rule 2 finds.
    if printf '%s\n' "$out" | grep -q "^R1:$tmp/$probe:"; then
      echo "SELF-TEST FAIL: $probe was flagged by Rule 1 — this probe carries"
      echo "                no zone-critical marker, so Stage 1 must exclude"
      echo "                it from Rule 1 entirely:"
      printf '%s\n' "$out"
      exit 1
    fi
  done

  # The dedicated device-zone-constructor probe (deliberately zone-critical)
  # must contribute ZERO offenders to either rule.
  if printf '%s\n' "$out" | grep -q "$tzdatetime_probe"; then
    echo "SELF-TEST FAIL: $tzdatetime_probe was flagged — RULE 2's"
    echo "                qualified-constructor exclusion does not handle the"
    echo "                real tz.TZDateTime(...) form:"
    printf '%s\n' "$out"
    exit 1
  fi

  # ---- RULE 3 assertions -----------------------------------------------
  for ln in "${now_offender_lines[@]}"; do
    if ! printf '%s\n' "$out" | grep -q "^R3:$tmp/$now_probe:$ln:"; then
      echo "SELF-TEST FAIL: expected a Rule-3 offender at $now_probe:$ln,"
      echo "                none found. Is '$now_scan_dir' still walked with"
      echo "                do_rule3=1 by run_scan? (line 40 in particular"
      echo "                pins that // host-tz-ok: does NOT suppress Rule 3.)"
      printf '%s\n' "$out"
      exit 1
    fi
  done
  for ln in "${now_clean_lines[@]}"; do
    if printf '%s\n' "$out" | grep -q "^R3:$tmp/$now_probe:$ln:"; then
      echo "SELF-TEST FAIL: line $ln of $now_probe should NOT be flagged by"
      echo "                Rule 3 (instant-ok annotated same-line or above /"
      echo "                whole-line comment / string literal / trailing"
      echo "                comment / longer identifier ending in"
      echo "                DateTime.now), but was:"
      printf '%s\n' "$out"
      exit 1
    fi
  done
  if printf '%s\n' "$out" | grep -q "^R1:$tmp/$now_probe:"; then
    echo "SELF-TEST FAIL: $now_probe was flagged by Rule 1 — it contains no"
    echo "                bare DateTime(<digit>, ...) call at all:"
    printf '%s\n' "$out"
    exit 1
  fi
  if printf '%s\n' "$out" | grep -q "$now_control_path"; then
    echo "SELF-TEST FAIL: the test/-side Rule-3 scan-root control was flagged"
    echo "                — Rule 3 is not restricted to $now_scan_dir/ at all:"
    printf '%s\n' "$out"
    exit 1
  fi

  echo "SELF-TEST PASS: RULE 1 — qualified constructors (DateTime.utc,"
  echo "                TZDateTime), derived first args, comments (whole-line"
  echo "                and trailing), string-literal contents, and both"
  echo "                host-tz-ok annotation placements all stay clean;"
  echo "                bare arity>=4 DateTime(<digit>, ...) is flagged in"
  echo "                BOTH scan roots (${scan_dirs[*]}), including nested"
  echo "                inside another call (pinning the depth counter in"
  echo "                both directions) and nested INSIDE DateTime's own arg"
  echo "                list (pinning depth-RESTRICTED comma counting, not"
  echo "                merely where counting stops); a file with no"
  echo "                zone-critical marker is skipped entirely even"
  echo "                carrying the same shape; and a host-tz-ok marker"
  echo "                sitting on the TOP line of a multi-line block (not"
  echo "                directly above the code) does NOT unblock."
  echo "                RULE 2 — a bare local DateTime(...) fed through a"
  echo "                clock: named argument (closure or direct form, any"
  echo "                arity) is flagged in a file carrying NO zone-critical"
  echo "                marker at all, in BOTH scan roots — proving Rule 2"
  echo "                bypasses Stage 1 classification, which is the exact"
  echo "                gap that let 28 failures through on 2026-08-02; while"
  echo "                DateTime.utc(...), tz.TZDateTime(...), a host-tz-ok"
  echo "                annotation, a whole-line comment, and a derived first"
  echo "                arg all stay clean. RULE 2 IDENTIFIER RESOLUTION — a"
  echo "                clock: argument that names an identifier (direct,"
  echo "                closure, or zero-arg-call form) is resolved to its own"
  echo "                same-file declaration, chased through a bounded chain"
  echo "                of bare-name-only declarations, and flagged when the"
  echo "                terminal initializer contains a bare DateTime( even"
  echo "                when wrapped in another call — this is the exact"
  echo "                variable-indirection shape the real 2026-08-02"
  echo "                incident files used and literal-only Rule 2 would NOT"
  echo "                have caught; a qualified initializer, a call carrying"
  echo "                an ARGUMENT (not chased — genuine dataflow analysis,"
  echo "                out of scope), a later reassignment (only the"
  echo "                DECLARATION is resolved), an identifier with no local"
  echo "                declaration (cross-file — nothing to chase), and a"
  echo "                host-tz-ok annotation all stay clean."
  echo "                RULE 3 — every live-code DateTime.now reference under"
  echo "                $now_scan_dir/ is flagged, in BOTH the call form and"
  echo "                the bare tear-off (which no DateTime\\.now\\(\\) grep"
  echo "                ever caught); an instant-ok annotation (same-line or"
  echo "                directly above), a whole-line comment, a string"
  echo "                literal, a trailing comment, and a longer identifier"
  echo "                merely ENDING in DateTime.now (tz.TZDateTime.now) all"
  echo "                stay clean; a host-tz-ok marker does NOT suppress it"
  echo "                (different question, different marker); and the same"
  echo "                shape under test/ contributes nothing, pinning that"
  echo "                Rule 3's scan root really is $now_scan_dir/ only."
  exit 0
fi

# ---------------------------------------------------------------------------
# Real run over the working tree. No allow-list — see header.
# ---------------------------------------------------------------------------
offenders="$(run_scan "$root")"
rule1_offenders="$(printf '%s\n' "$offenders" | grep '^R1:' | sed 's/^R1://' || true)"
rule2_offenders="$(printf '%s\n' "$offenders" | grep '^R2:' | sed 's/^R2://' || true)"
rule3_offenders="$(printf '%s\n' "$offenders" | grep '^R3:' | sed 's/^R3://' || true)"

failed=0

if [ -n "$rule1_offenders" ]; then
  failed=1
  echo "Host-local DateTime(...) instant anchor found in a zone-critical file"
  echo "under ${scan_dirs[*]} (RULE 1):"
  echo "$rule1_offenders"
  echo
  echo "A bare local DateTime(y, m, d, h, ...) resolves its underlying instant"
  echo "through the HOST PROCESS's own TZ. The dev VM this project is built on"
  echo "runs TZ=Europe/Kyiv — the SAME zone as the business timezone — so such"
  echo "a fixture is indistinguishable from a correctly-pinned one there and"
  echo "silently stops discriminating anything, while CI (TZ=UTC) or any other"
  echo "machine resolves it to a DIFFERENT instant. This exact defect class has"
  echo "shipped THREE times: Phase 225 audit cycles 4 and 5, and again on"
  echo "2026-08-02."
  echo
  echo "Pin the instant instead of the host clock:"
  echo "    DateTime.utc(2026, 8, 1, 23, 30)                               // a fixed instant"
  echo "    tz.TZDateTime(tz.getLocation('Asia/Tokyo'), 2026, 8, 2, 5, 0)  // a specific DEVICE zone"
  echo
  echo "Worked reference:"
  echo "    test/features/home/application/next_appointment_provider_test.dart:596-717"
  echo
  echo "If a bare local instant is genuinely correct here (rare — it means the"
  echo "test deliberately wants THIS PROCESS's own local clock, not a pinned"
  echo "one), annotate it:"
  echo "    // host-tz-ok: <why the host's own local clock is correct here>"
  echo
  echo "There is no allow-list for this gate and none should be added — every"
  echo "legitimate case is expressible as DateTime.utc(...) or a TZDateTime(...)"
  echo "pinned to a named device zone."
  echo
fi

if [ -n "$rule2_offenders" ]; then
  failed=1
  echo "Host-local DateTime instant fed through a clock: named argument found"
  echo "under ${scan_dirs[*]} (RULE 2 — no zone-critical filter; any file can"
  echo "hit this) — either inlined directly or via an identifier whose"
  echo "SAME-FILE declaration resolves to one (see the offender list below;"
  echo "an entry tagged \"[declaration of ...]\" is the resolved definition,"
  echo "not a second independent call site):"
  echo "$rule2_offenders"
  echo
  echo "A clock: argument supplies an INSTANT, not a calendar day. A bare local"
  echo "DateTime(...) resolves that instant through the HOST PROCESS's own TZ —"
  echo "so what it actually pins differs per machine. Downstream code (e.g."
  echo "lib/shared/time/kyiv_day.dart's kyivDayOf) then converts that instant"
  echo "through the Kyiv business zone to derive 'today', which can land on a"
  echo "different calendar day than the one the literal appears to name. On"
  echo "2026-08-02 this produced 28 deterministic failures: three schedule-"
  echo "widget test files anchored clock: with a host-local DateTime instant"
  echo "reached through variable indirection (clock: () => _today,"
  echo "clock: _testToday) — not an inline literal. Under TZ=Asia/Tokyo that"
  echo "instant is 18:00 June 12 in Kyiv, not the intended June 13."
  echo
  echo "Pin the instant instead of the host clock — at the clock: site if it is"
  echo "inlined, or at the declaration this offender resolved to if it is not:"
  echo "    clock: () => DateTime.utc(2026, 6, 13, 12),   // noon UTC round-trips"
  echo "                                                  // to the intended day"
  echo "                                                  // from any realistic"
  echo "                                                  // host zone"
  echo "    clock: () => tz.TZDateTime(tz.getLocation('Asia/Tokyo'), 2026, 6, 13, 12),"
  echo "                                                  // when the test needs a"
  echo "                                                  // SPECIFIC device zone"
  echo
  echo "If a bare local instant is genuinely correct here, annotate the"
  echo "clock: site itself:"
  echo "    // host-tz-ok: <why the host's own local clock is correct here>"
  echo
  echo "There is no allow-list for this gate and none should be added."
  echo
fi

if [ -n "$rule3_offenders" ]; then
  failed=1
  echo "Raw device-clock read (DateTime.now) found under $now_scan_dir/"
  echo "(RULE 3 — no zone-critical filter; call form AND bare tear-off):"
  echo "$rule3_offenders"
  echo
  echo "The E2E tier boots the REAL app with clockProvider overridden to a"
  echo "SINGLE pinned instant (integration_test/support/e2e_boot_policy.dart"
  echo "→ kFixedNow = 2026-06-14T12:00:00Z). A test that reads DateTime.now()"
  echo "is therefore reading a clock the app under test does not share. On"
  echo "2026-08-04 that shipped as a silent false PASS: an E2E picked a"
  echo "calendar cell from the HOST day-of-month while the app believed it was"
  echo "2026-06-14, so on any real-world day before the 14th it tapped a PAST"
  echo "cell. Past cells get onTap: null and render with NO GestureDetector,"
  echo "so the tap landed on the scroll view behind them, no slots fetch"
  echo "fired, and the test still went green — roughly 17 days out of 30."
  echo
  echo "Read the clock the APP is on, not the one the runner is on:"
  echo "    final DateTime today = kyivToday(() => kFixedNow);   // the injected clock"
  echo "    final DateTime start = fb.serverNow.add(...);        // FakeBackend's own server clock"
  echo
  echo "If this read is a genuine absolute-instant use — an elapsed-wall-time"
  echo "poll, a duration measurement, an instant ordering comparison — that"
  echo "Kyiv-anchoring or clock injection would not change, annotate it with"
  echo "the SAME marker scripts/forbid_raw_clock_read.sh uses in lib/:"
  echo "    // instant-ok: <why reading the DEVICE clock is correct here>"
  echo "Note that // host-tz-ok: does NOT suppress this rule — that marker"
  echo "answers a different question (see this script's header)."
  echo
  echo "There is no allow-list for this gate and none should be added."
  echo
fi

if [ "$failed" -eq 1 ]; then
  exit 1
fi

exit 0

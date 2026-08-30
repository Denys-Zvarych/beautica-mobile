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
# THIS SCRIPT NOW ENFORCES SEVEN RULES
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
# RULE 1'S STAGE-1 CLASSIFIER IS A TEXT FILTER — MEASURED LIMIT, DELIBERATELY
# NOT WIDENED (2026-08-04, third pass)
# ---------------------------------------------------------------------------
# Rule 1 narrows ~504 files to ~20 by grepping for `$zone_critical_pattern`
# before parsing. A genuine offender therefore sits INVISIBLE in any file that
# happens not to mention the seam by name — demonstrated, not theorised:
# adding an unrelated comment naming `clockProvider` to
# `booking_route_guard_test.dart` flipped it into the zone-critical class and
# exposed two real pre-existing offenders. Rule 2 already bypasses this
# classifier; Rule 1 does not.
#
# THE INVISIBLE SET WAS MEASURED BEFORE ANY DECISION WAS TAKEN. Rule 1's
# arity>=4 matcher was re-run across ALL of `test/` + `integration_test/` with
# Stage 1 disabled (`zone_critical_pattern='^'`):
#     classifier ON  ->   0 hits   (the real gate's baseline, still empty)
#     classifier OFF ->  74 hits across 14 files
# So 74 sites are currently invisible to Rule 1. Those 14 files were then run
# under `TZ=Europe/Kyiv`, `TZ=UTC` and `TZ=Pacific/Honolulu` — Honolulu
# (UTC-10) being the zone that actually splits from Kyiv on the day boundary;
# Kyiv/UTC/Tokyo all agree and prove nothing. Result:
#     1 genuine defect  — `booking_confirm_test.dart`'s
#       `_appointmentItemRescheduleArgs()` fed a host-local
#       `DateTime(2026, 7, 20, 14)` as a booking `startAt`, which
#       `booking_confirm_screen.dart:248` converts through
#       `dateOnly(toBeauticaTime(...))` to key its `bookingsDayProvider`
#       invalidation. Under Honolulu that instant is 03:00 July 21 in Kyiv, so
#       the "REGRESSION GUARD — ... invalidates bookingsDayProvider" test went
#       red. FIXED (re-anchored to `DateTime.utc(2026, 7, 20, 11)` == 14:00
#       Kyiv), red-under-Honolulu-then-green proven.
#     73 inert       — and a large fraction are inert *because* they are
#       host-local. `test/shared/formatters/api_date_test.dart`'s 9 hits are
#       the tests OF `dateOnly`/`toApiDate`, whose whole subject is that those
#       functions read LOCAL calendar fields; `slot_repository_test.dart`'s
#       carry the literal comment "time-of-day must be discarded". Re-anchoring
#       any of them to `.utc` would BREAK them — it would change what is under
#       test. The rest are opaque ordering keys and `startAt` fixtures that no
#       assertion ever compares against a zone-derived day.
#
# DECISION: DO NOT WIDEN THE CLASSIFIER. 1 defect in 74 hits is a 1.4%-
# precision gate. Its only realistic outcome is 73 rubber-stamped
# `// host-tz-ok:` markers on correct code until the marker means nothing —
# the exact failure mode Rule 4's own header already refused once (60 reads /
# 0 bugs), and the mirror-image-bug hazard Rule 5's header names. A guard whose
# baseline is not empty on the real tree without an allow-list is mis-scoped by
# this script's own standard, and a widened Rule 1 could only reach an empty
# baseline via 73 annotations.
#
# TWO NARROWER TEXT RULES WERE MEASURED AND ALSO REJECTED, not merely imagined:
#   - KEY ON THE DESTINATION, the way Rule 2 keys on `clock:` — flag a
#     host-local arity>=4 instant reaching `startAt:`/`endAt:`/`startsAt:`/
#     `endsAt:`. Measured: ~35 of the 74. Still 1 defect in 35.
#   - KEY ON COINCIDENCE — an instant `DateTime(y,m,d,H,...)` and a day token
#     `DateTime(y,m,d)` naming the SAME date in one file, the "two spellings of
#     one day mixed in one test" shape M15 describes. Measured: 10 of the 14
#     files, including `api_date_test.dart` and `slot_repository_test.dart`
#     where that coincidence IS the deliberate design of the test.
#
# WHAT A BETTER-TARGETED RULE WOULD ACTUALLY KEY ON — AND WHY IT IS NOT A GREP.
# The one property that separated the real defect from all 73 inert siblings is
# whether the fixture value reaches a `toBeauticaTime` / `kyivDayOf` in `lib/`.
# That discriminator lives in PRODUCTION code, in a different file, reached
# through a widget constructor and a provider — genuine cross-file dataflow,
# which every rule in this script explicitly declares out of scope (see Rule
# 2's "HONEST LIMITS OF IDENTIFIER RESOLUTION"). No text filter over the test
# file can recover it, and each attempt above degrades into a rubber stamp.
#
# THE AVAILABLE HIGH-PRECISION SUBSTITUTE IS NOT A GUARD AT ALL — IT IS A CI
# ZONE MATRIX. Running the existing suite a second time under
# `TZ=Pacific/Honolulu` found the defect with precision 1/1 and zero
# annotations, versus 1/74 for the widened classifier. It needs no marker
# vocabulary, cannot be rubber-stamped, and covers every shape Rules 1-6 miss
# (including the dataflow ones) because it EXECUTES the disagreement instead of
# pattern-matching for it. RECOMMENDED, NOT WIRED HERE: adding a
# `TZ=Pacific/Honolulu` job to `.github/workflows/pr-validate.yml` is a CI
# change, outside this script. Note the honest cost — it doubles test wall time
# — and the honest limit: it only catches fixtures whose assertions actually
# discriminate, so it is complementary to Rules 1-6, not a replacement.
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
# RULE 4 (added 2026-08-04 — the `test/` residue Rule 3 deliberately left,
# closed as a COHERENCE gate rather than a declaration one)
# ------------------------------------------------------------------------
# WHAT WAS MEASURED FIRST. Rule 3's own header (see "SCAN ROOT" above) named
# the gap plainly: "a `test/` widget test that overrides `clockProvider` and
# then reads `DateTime.now()` to build a fixture has the same defect and is
# NOT caught by any gate today". Before writing this rule, that residue was
# measured rather than assumed: 60 live `DateTime.now` references across 31
# files under `test/`, of which the number matching the actual bug shape —
# a host-clock fixture read inside a test that ALSO pins `clockProvider` —
# was ZERO. Only 5 files under `test/` reference `clockProvider` at all, and
# every one already keeps the two sides consistent.
#
# WHY THIS IS **NOT** A COPY OF RULE 3. Rule 3 can be a blanket declaration
# gate because the E2E tier pins ONE clock tier-wide (`e2e_boot_policy.dart`),
# so every host read there is wrong by construction. `test/` has no tier-wide
# policy: each test chooses. There are TWO internally-consistent choices, and
# the overwhelming majority of this tier uses the second:
#   (1) BOTH PINNED — override `clockProvider` and derive the fixture from
#       the same instant.
#   (2) BOTH LIVE — override nothing, and derive the fixture with
#       `kyivToday(DateTime.now)` so it lands on the same Kyiv day the widget
#       derives from the same real clock.
# 53 of the 60 reads are choice (2) and are CORRECT PRECISELY BECAUSE they
# read the host clock; the remaining 7 are genuine elapsed-time or epoch
# uses (bracketing a call, JWT `exp` arithmetic, the clock provider's own
# "the default really does advance" test). A Rule-3-style blanket gate here
# would therefore have fired on 60 sites of which 0 were bugs — a 100%
# false-positive rate, whose only realistic outcome is authors rubber-
# stamping `// instant-ok:` onto correct code until the marker means nothing.
# That is worse than no gate. Equally, mechanically re-anchoring those 53
# reads onto a single fixed test-tier constant (the `test/` analogue of
# `kFixedNow`) would BREAK them: a fixture pinned to a constant while the
# widget under test still reads the real clock reintroduces exactly the same
# disagreement, in mirror image.
#
# THE RULE. Under the `test/` scan root ONLY (`$mix_scan_dir`), flag a live
# `DateTime.now` reference that sits inside a SINGLE `test(` / `testWidgets(`
# body which ALSO pins the clock. The invariant being enforced is coherence,
# not abstinence: a test's fixture clock and the app-under-test's clock must
# be the SAME clock. Mixing the two choices above is the bug, and is all this
# rule fires on.
#
# Detection, precisely:
#   1. SCOPE. Bracket depth is tracked across the whole file; a `test(` or
#      `testWidgets(` token (word-bounded, and not preceded by `.` — so
#      `foo.test(` never opens a scope) pushes a scope that closes when depth
#      returns to where it started. Scoping to the individual test body is
#      load-bearing, NOT incidental: `slot_picker_test.dart` pins the clock in
#      one group and reads the host clock in twelve tests outside it, so a
#      file-scoped version of this rule would produce 12 false positives in
#      that one file alone.
#   2. PIN, shape (a) — `clockProvider.override` (any variant) inside the body.
#   3. PIN, shape (b) — a `clock:` or `now:` named argument whose value is not
#      `null`. This is the shape EVERY real pin in this tree uses: the
#      override lives inside a pump helper taking `{DateTime? clock}`, so the
#      only evidence at the test body is the argument passed in. `null` is
#      excluded because passing null is precisely how those helpers say
#      "leave the real clock alone".
#   4. READ — the literal `DateTime.now`, word-bounded (excludes
#      `tz.TZDateTime.now`), live code only (string-stripped, comment-aware).
#   5. NOT ANNOTATED — `// instant-ok: <reason>`, same marker and same
#      same-line-or-directly-above placement as Rule 3. Reused deliberately:
#      the question is the same one ("why is reading the DEVICE clock correct
#      here"), and a genuine elapsed-time measurement inside a pinned test is
#      a real, if rare, answer.
# When flagged, the PIN SITE is printed alongside the read — the fix needs
# both halves in view, and which one is wrong is the author's call.
#
# BOTH ORIGINAL BLIND SPOTS ARE NOW CLOSED (2026-08-04, second pass)
#   - (a) A PIN AT `setUp` / `setUpAll` / `group` SCOPE, rather than inside the
#     test body, is now seen. The scope stack pushes for `group(`, `setUp(` and
#     `setUpAll(` as well as `test(` / `testWidgets(`; a pin found directly in a
#     `group` body marks that group, a pin found in a `setUp` / `setUpAll` body
#     marks the nearest ENCLOSING group (or, with no enclosing group, the whole
#     file from that point on), and a test is treated as pinned when it or ANY
#     scope enclosing it is. Adding this contributed ZERO new hits on the real
#     tree — measured, not assumed: no file pins at that scope today, which is
#     exactly why closing the hole is safe to do pre-emptively rather than after
#     the next incident.
#   - (b) A PIN REACHED THROUGH A HELPER PARAMETER NAMED SOMETHING OTHER THAN
#     `clock:` / `now:` is now recognised, WITHOUT hardcoding a guessed list of
#     names. A BEGIN pre-pass reads the file for
#     `clockProvider.overrideWithValue(<x>)` (optionally through a `() =>`
#     closure) and adds `<x>` to THIS FILE's set of pin-argument names, on top
#     of the seeded `clock` / `now`. So a helper declared
#     `_pump(..., {DateTime? fixedNow})` whose body does
#     `if (fixedNow != null) clockProvider.overrideWithValue(fixedNow)` makes
#     `fixedNow:` a recognised pin argument in that file automatically — the
#     name is DERIVED from what the file actually overrides the provider with,
#     not from a convention this gate hopes authors follow.
#     `clockProvider.overrideWith((ref) { ... })` is deliberately NOT harvested:
#     its argument is a closure PARAMETER (`ref`, `_`), and adding `ref` to the
#     pin-name set would make any `ref:` named argument read as a clock pin.
#
# REMAINING HONEST LIMIT — STATED, NOT PAPERED OVER
#   - Bucket (2) above — the un-pinned majority — is not policed BY THIS RULE.
#     Those tests still depend on the host clock, and `kyivToday(DateTime.now)`
#     rather than a bare `DateTime.now()` is what keeps them honest across
#     zones. That convention was un-enforced when Rule 4 shipped; RULE 5 (below)
#     now holds it.
#
# RULE 5 (added 2026-08-04, second pass — the un-pinned MAJORITY, which
# Rule 4 explicitly left un-gated)
# ------------------------------------------------------------------------
# WHAT RULE 4 LEFT OPEN, IN ITS OWN WORDS. Rule 4 fires only when a test PINS
# the clock. The other 53 of the 60 `test/` host-clock reads pin nothing: they
# are correct BECAUSE they read the host clock, since the widget under test
# reads the same real clock. But "correct" there depends entirely on a
# CONVENTION — wrapping the read in `kyivToday(...)` so the fixture lands on
# the KYIV calendar day the widget derives, not the DEVICE's. Rule 4's own
# limits section conceded that convention "is not machine-enforced". A test
# writing a bare `DateTime.now().day`, `.month`, or assigning `DateTime.now()`
# to a local and reading `.month` off it sits in exactly the trap Rules 1-4
# exist for, and nothing caught it.
#
# WHY THIS IS EXPRESSIBLE NOW AND WAS NOT BEFORE. A prior pass normalised the
# spellings: `kyivToday(DateTime.now)` is the ONLY form for "Kyiv today from
# the host clock" under `test/` — `dateOnly(toBeauticaTime(DateTime.now()))`
# and `kyivDayOf(DateTime.now())` have zero residual. With ONE canonical
# spelling, "is this read going through the seam" becomes a text question
# rather than a dataflow one.
#
# WHY THIS IS **NOT** RULE 3 UNDER A DIFFERENT ROOT. Rule 3 is a blanket
# DECLARATION gate: under `integration_test/` every host read is wrong by
# construction. Applying that to `test/` was measured and rejected — it would
# have fired on 60 sites of which 0 were bugs, and the only realistic outcome
# of a 100%-false-positive gate is `// instant-ok:` rubber-stamped onto
# correct code until the marker means nothing. Rule 5 instead asks what the
# read is FOR, which the read site itself already says:
#   - It is the clock argument to the canonical seam — `kyivToday(DateTime.now)`
#     — i.e. the author is deriving a KYIV CALENDAR DAY, correctly. CLEAN.
#   - Its result is immediately consumed by an INSTANT-ONLY operation
#     (`.add`, `.subtract`, `.toUtc`, `.difference`, `.isBefore`, `.isAfter`,
#     `.isAtSameMomentAs`, `.compareTo`, `.millisecondsSinceEpoch`,
#     `.microsecondsSinceEpoch`) — i.e. the author is using an INSTANT, which
#     no zone conversion would change. CLEAN.
#   - Anything else — a bare `DateTime.now()` handed to a variable, an
#     argument, or a calendar-field read — has not said which it is, and is
#     exactly the shape that turned out to be wrong at all four sites this
#     rule was written against. FLAGGED.
#
# Detection, precisely:
#   1. SCAN ROOT — `test/` ONLY (`$mix_scan_dir`). `integration_test/` is
#      already covered, more strictly, by Rule 3; running both there would
#      double-report every hit.
#   2. READ — the literal `DateTime.now`, in the string-stripped buffer, not on
#      a whole-comment line, before any real trailing `//`, and not preceded by
#      a word character (excludes `tz.TZDateTime.now`). Identical to Rule 3's
#      row 1-3.
#   3. SEAM FORM (clean) — the 10 characters immediately before the match are
#      literally `kyivToday(` AND the character immediately after `DateTime.now`
#      is `)`. This is a TEAR-OFF being handed to the seam; note it deliberately
#      does NOT accept `kyivToday(DateTime.now())` (a call, not a tear-off) or
#      `kyivDayOf(DateTime.now())`, because the normalisation pass made
#      `kyivToday(DateTime.now)` the single spelling and this rule is what keeps
#      it single. A hit on either of those spellings is not a false positive:
#      the fix is to write the canonical form.
#   4. INSTANT FORM (clean) — the match is followed by exactly `().`, then an
#      identifier drawn from the instant-only member list in row 3 above.
#      Chained forms are covered by their FIRST member, which is what decides
#      whether a zone ever entered the picture: `DateTime.now().toUtc().subtract(...)`
#      is clean via `toUtc`. `.toIso8601String()` is deliberately NOT on the
#      list — on a local `DateTime` it renders HOST wall-clock time with no
#      offset, which is zone-dependent output, not an instant operation.
#   5. NOT ANNOTATED — `// instant-ok: <reason>`, same marker, same
#      same-line-or-directly-above placement, as Rules 3 and 4. Same vocabulary
#      because it is the same question.
#
# BASELINE: EMPTY ON THE REAL TREE, WITH NO ALLOW-LIST AND NO PATH EXEMPTION.
# Reaching that took FOUR genuine fixes and TWO annotations, not sixty:
#   - `slot_picker_test.dart` (2 sites) and
#     `period_range_picker_initial_scroll_test.dart` (1 site) each read
#     `DateTime.now().year`/`.month` off a local to compute a target month,
#     while the widget under test derives its own `_today` through
#     `kyivToday`/`kyivDayOf`. Re-anchored to `kyivToday(DateTime.now)`.
#   - `booking_route_guard_test.dart` seeded `SlotPickerState.selectedDate` — a
#     DATE TOKEN — with a raw host instant. Re-anchored likewise.
#   - `clock_provider_test.dart`'s `before`/`after` bracket genuinely ARE
#     absolute instants: that test's SUBJECT is that the un-overridden
#     `clockProvider` returns the real device clock, and both values are
#     consumed only by `.isBefore`/`.isAfter`. Annotated, with that reason.
# Two annotations out of sixty reads is a marker that still carries
# information. Sixty out of sixty would not have been, which is why Rule 4
# stopped where it did and why this rule classifies instead of declaring.
#
# HONEST LIMIT — Rule 5 gates the READ SHAPE, not the downstream use. A value
# built as `DateTime.now().add(const Duration(days: 2))` is waved through as an
# instant, and if a later line reads `.day` off it to build an expectation, that
# is the same defect and this rule does not see it. Chasing that is genuine
# dataflow analysis, out of scope here exactly as it is for Rule 2's identifier
# resolution. What Rule 5 does guarantee is that every host-clock read in this
# tier has DECLARED, at the read site, whether it is a calendar-day derivation
# (must go through the seam) or an instant (must be consumed as one).
#
# RULE 6 (added 2026-08-04, second pass — DATE TOKEN treated as an INSTANT)
# ------------------------------------------------------------------------
# `lib/shared/time/kyiv_day.dart`'s header defines a **date token**: a
# host-local `DateTime` at host-local midnight whose `.year`/`.month`/`.day`
# carry the KYIV calendar day. It is not an instant, though Dart gives it the
# identical runtime type — and that type-level indistinguishability is named
# there as "the real root cause of this whole bug class". That header lists
# `.toUtc()` on a token as explicitly ILLEGAL ("there is no meaningful UTC form
# of a value that was never really an instant; the call compiles, runs, and
# returns garbage") and then concedes: "Nothing statically catches misusing an
# already-derived date token — that stays a review responsibility."
#
# Review did not catch it. A sweep on 2026-08-04 found THREE live instances,
# only one of which had ever been reported:
#   - `bookings_day_rebuild_isolation_test.dart` — `today.toUtc().add(12h)`
#   - `master_bookings_screen_test.dart` (2 sites) — `_kyivToday.toUtc().add(...)`
# All three read "an instant at midday on Kyiv today" and all three got it by
# reinterpreting host-local midnight as an instant. MEASURED, not reasoned
# about — `kyivDayOf(token.toUtc().add(12h))` against the token it came from,
# on five host zones:
#     Europe/Kyiv (+3)      Aug 4 -> Aug 4   agrees
#     UTC (+0)              Aug 4 -> Aug 4   agrees
#     Asia/Tokyo (+9)       Aug 4 -> Aug 4   agrees
#     America/Anchorage (-8) Aug 4 -> Aug 4  agrees
#     Pacific/Honolulu (-10) Aug 4 -> Aug 5  DISAGREES
# The `DateTime.utc(token.year, token.month, token.day, 12)` form agrees on all
# five. So the old derivation genuinely produces the wrong Kyiv day past about
# UTC-9.
#
# BE PRECISE ABOUT WHAT WENT WRONG: those test files did NOT fail under
# `TZ=Pacific/Honolulu` — that was checked, before and after the fix, and both
# were green. They did not fail because the repository is mocked with
# `any(named: 'from')`, so the day the fixture names and the day the screen
# queries were never compared to begin with. That is the WORSE outcome, and the
# one this whole script's header opens by naming: the fixture had silently
# stopped discriminating the thing it was written to pin, and would have gone
# on doing so until an assertion tightened. It is the same class as the
# 2026-08-02 incident reached from the other direction — not an instant
# mis-typed as a day, but a day mis-typed as an instant.
#
# THE RULE. Flag `.toUtc(` or `.toLocal(` applied to a value that is a date
# token, in two forms:
#   (a) DIRECT — the seam call itself: `kyivToday(...).toUtc()`,
#       `kyivDayOf(...).toUtc()`, `dateOnly(...).toLocal()`. The matching `)`
#       is found by forward depth-tracking (same technique as
#       `count_top_commas`), never by a `[^)]*` regex, so a nested call inside
#       the seam's own argument list does not truncate the match.
#   (b) INDIRECT — an identifier whose SAME-FILE declaration's initializer
#       STARTS with one of those seam calls. A BEGIN pre-pass collects
#       `final DateTime x = kyivToday(...)`, `DateTime x = ...`,
#       `DateTime x() => ...`, `DateTime get x => ...`, and the untyped
#       `final x = ...` / `var x = ...` forms. The initializer only has to
#       START on the declaration line, so a seam call whose ARGUMENTS wrap onto
#       following lines is still recognised.
#   `_dateOnly` (the private re-implementations in
#   `master_schedule_screen.dart`, `period_range_picker.dart`,
#   `schedule_date_math.dart`, `apply_schedule_sheet.dart`) is matched too — a
#   single leading `_` is allowed on the seam name.
#
# ONLY `.toUtc()` / `.toLocal()`, AND WHY NOT THE REST OF THE ILLEGAL LIST. The
# header also bans `.difference(...)` and `.isBefore`/`.isAfter` — but ONLY
# against an INSTANT; against another date token all three are explicitly
# LEGAL. Deciding which side you have is dataflow, so those stay a review
# responsibility and this rule does not pretend otherwise. `.toUtc()` and
# `.toLocal()` are unconditional: there is no operand that makes them
# meaningful on a token, which is precisely what makes them gateable.
#
# SCAN ROOT — `lib/`, `test/` AND `integration_test/` (`${token_scan_dirs[@]}`),
# a DIFFERENT and WIDER set than every other rule here. Rules 1-5 police test
# ANCHORS, which is why they stop at the test tiers. Rule 6 polices a type
# confusion that production code is at least as exposed to: `lib/` declares
# four date tokens today (`day_hours_sheet.dart`, `master_schedule_screen.dart`,
# `booked_days_notifier.dart`, `working_hours_repository.dart`) and any of them
# is one `.toUtc()` away from the same silent garbage. `lib/` was swept by hand
# at the time this rule was added and was clean — every `.toUtc()` there is on
# a `DateTime.parse(...)` or a `DateTime.now()`, both genuine instants.
#
# MARKER — `// date-token-ok: <reason>`, a THIRD marker, deliberately distinct
# from `host-tz-ok:` ("why is this host-local literal's zone resolution
# correct") and `instant-ok:` ("why is reading the DEVICE clock correct"). This
# one asks a third question: "why is treating a KYIV DAY TOKEN as an instant
# correct here". Reusing either of the others would have merged two unrelated
# review questions under one word.
#
# BASELINE: EMPTY, after the three fixes above plus exactly ONE annotation —
# `test/shared/time/kyiv_day_test.dart`, whose `expect(instant,
# isNot(token.toUtc()))` IS the runnable demonstration that the operation
# returns garbage. That is the one place in the tree where performing the
# banned operation is the point, and it is annotated rather than left to pass
# by accident of the declaration happening to span lines.
#
# RULE 7 (added 2026-08-30, Phase 284 D4 — DATE TOKEN reaching .difference,
# the arity-3 hole RULE 1's own exclusion #2 opened)
# ------------------------------------------------------------------------
# WHAT SHIPPED, AND WHY EVERY EXISTING RULE WAVED IT THROUGH.
# `lib/shared/formatters/relative_date.dart` computed its calendar-day delta
# as:
#     final DateTime todayStart = DateTime(nowKyiv.year, nowKyiv.month, nowKyiv.day);
#     final DateTime thenStart  = DateTime(then.year, then.month, then.day);
#     final int days = todayStart.difference(thenStart).inDays;
# Both operands carry KYIV calendar components but are constructed as
# HOST-LOCAL `DateTime`s — i.e. they are DATE TOKENS. `DateTime.difference`
# measures elapsed ABSOLUTE time, so when the host zone crosses a DST
# transition between the two midnights the span is 23 h (spring forward) or
# 25 h (fall back) and `.inDays` truncates toward zero. On a Europe/Kyiv host
# — the market's own devices, and most installs — a review or invite from
# 29 March rendered «Сьогодні» on 30 March. Annually, silently, in production.
#
#   - RULE 1 requires ARITY >= 4 (rule 3) *and* a LITERAL DIGIT first argument
#     (rule 2). This construction is arity 3 with a `.year` component read, so
#     it misses on BOTH counts — and rule 2's own comment says why it excludes
#     the derived form: "reads a real calendar day rather than pinning an
#     arbitrary host-resolved one". That is true of the VALUE and false of the
#     ARITHMETIC, which is exactly the gap.
#   - RULE 2 only inspects values reaching a `clock:` named argument.
#   - RULES 3/4/5 are about `DateTime.now`; there is no clock read here.
#   - RULE 6 gates `.toUtc()`/`.toLocal()` on a token, and its own header
#     explains why it stops there: `.difference(...)` is ILLEGAL against an
#     INSTANT but explicitly LEGAL against another date token, and deciding
#     which side you have is dataflow. TRUE IN GENERAL — but there is one
#     syntactic shape where BOTH sides are provably tokens, and that is the
#     shape below.
#
# THE RULE — DELIBERATELY NARROW, AND MEASURED BEFORE IT WAS WRITTEN. Under
# `lib/`, `test/` and `integration_test/` (`${token_scan_dirs[@]}` — the same
# WIDER roots as Rule 6, because this defect shipped in `lib/`, not in a
# fixture), flag a `.difference(` whose RECEIVER or ARGUMENT is a
# COMPONENT-DERIVED DATE TOKEN, in two forms:
#   (a) DIRECT — the construction inlined at the call site:
#           DateTime(a.year, a.month, a.day).difference(b)
#   (b) INDIRECT — an identifier whose SAME-FILE declaration's initializer is
#       that construction (the shape that actually shipped), used either as
#       the receiver (`todayStart.difference(...)`) or as the argument
#       (`x.difference(thenStart)`).
# A COMPONENT-DERIVED DATE TOKEN is, precisely: a bare local `DateTime(` call
# (not preceded by `.` or a word character — so `DateTime.utc(` and
# `tz.TZDateTime(` never match, same exclusion as Rule 1's rule 1), of ARITY
# EXACTLY 3 (depth-tracked comma counting, never a `[^)]*` regex), whose first
# argument — whitespace skipped — is a `<expr>.year` component read. That is
# the hand-rolled-`dateOnly` idiom and nothing else.
#
# WHY NOT THE BROADER "ANY DATE TOKEN REACHING .difference". It was BUILT AND
# MEASURED, not imagined. Widening the token definition to include
# `dateOnly(...)` / `_dateOnly(...)` / `kyivDayOf(...)` / `kyivToday(...)`
# initializers and any arity-3 `DateTime(` gives SIX hits on the real tree:
#     lib/features/schedule/domain/schedule_date_math.dart:44,156
#     lib/features/schedule/presentation/master_schedule_screen.dart:267
#     test/features/schedule/presentation/master_schedule_screen_test.dart:3330
#     test/shared/time/kyiv_day_test.dart:164,226   (deliberate demonstrations)
# Precision on that set is excellent — a hand audit found ALL FOUR non-
# demonstration hits to be genuine latent DST off-by-ones, and a further two
# the same audit found (`schedule_model.dart:743`,
# `day_off_conflict_dialog.dart:226`, `schedule_repository.dart:138`) that
# this text rule cannot reach because their operands are class FIELDS rather
# than same-file locals. So the broad rule is NOT rejected on precision, the
# way the widened Rule 1 classifier was (1 defect in 74). It is deferred for
# one reason only: its baseline on the real tree is NOT EMPTY, and this
# script's "NO LEGACY BASELINE" section forbids both an allow-list and the
# rubber-stamping of four `date-token-ok:` markers onto code that is genuinely
# wrong. Fixing those four — one of which
# (`master_schedule_screen.dart:267`, live week re-anchoring) changes real
# navigation behaviour and needs the schedule suite plus its goldens behind it
# — is a phase of its own, not a side effect of this one. IT IS WRITTEN DOWN
# HERE RATHER THAN LEFT SILENT, WHICH IS THE WHOLE POINT: the narrow rule
# below ships with an empty baseline today and closes the shape that actually
# reached production; widening it is a scoped, costed follow-up with a named
# residue, not an open question.
#
# BASELINE: EMPTY on the real tree, with NO allow-list and NO annotations —
# verified after the Phase 284 fix, and verified to FIRE on the pre-fix
# content of `relative_date.dart` (which is the only reason to believe it).
#
# MARKER — `// date-token-ok: <reason>`, shared with Rule 6. Same question
# ("why is treating a KYIV DAY TOKEN as an instant correct here"), so the same
# vocabulary; a `host-tz-ok:` or `instant-ok:` marker does NOT suppress it.
#
# ACCEPTED FIX (RULE 7)
# ----------------------
#     kyivDaysBetween(earlierToken, laterToken)   // lib/shared/time/kyiv_day.dart
# It re-anchors both tokens at UTC midnight before subtracting. UTC observes
# no transitions, so every calendar day there is uniformly 24 h and the count
# is always exact. `calendarDayCount` in
# `features/booking/presentation/widgets/bookings_day_rail.dart` is a
# delegating alias of it; there is no third implementation and there should
# never be one.
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

# RULE 4's AND RULE 5's scan root — `test/`, the tier Rule 3 deliberately does
# NOT cover. Both reuse Rule 3's `instant-ok:` marker (`$now_annotation`): they
# ask the same question ("why is reading the DEVICE clock correct here"), just
# in a tier where the answer is wrong for different reasons — Rule 4 when the
# test ALSO pinned the clock, Rule 5 when the read neither goes through the
# Kyiv-day seam nor is consumed as an instant.
mix_scan_dir='test'

# RULE 6's marker — `// date-token-ok:`, a THIRD vocabulary, deliberately not
# `host-tz-ok:` or `instant-ok:`. See header "RULE 6".
token_annotation='[/][/][[:space:]]*date-token-ok:'

# RULE 6's scan roots — WIDER than every other rule here, `lib/` included. A
# date token mis-typed as an instant is a production hazard, not only a fixture
# one; see header "RULE 6 — SCAN ROOT".
token_scan_dirs=(
  "lib"
  "test"
  "integration_test"
)

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
  local do_rule5="${4:-0}"
  awk -v file="$1" -v ann="$annotation" -v do_rule1="$do_rule1" \
      -v now_ann="$now_annotation" -v do_rule3="$do_rule3" \
      -v do_rule5="$do_rule5" '
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
    # RULE 5 — the instant-only member allow-list. A `DateTime.now()` whose
    # result is IMMEDIATELY consumed by one of these is using an INSTANT, which
    # no zone conversion would change; anything else has not said what it is.
    # `toIso8601String` is deliberately absent: on a LOCAL DateTime it renders
    # host wall-clock time with no offset — zone-dependent output, not an
    # instant operation.
    function instant_member(m) {
      return (m == "add" || m == "subtract" || m == "toUtc" ||
              m == "difference" || m == "isBefore" || m == "isAfter" ||
              m == "isAtSameMomentAs" || m == "compareTo" ||
              m == "millisecondsSinceEpoch" || m == "microsecondsSinceEpoch")
    }

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

      # ============ RULE 5 (test/ only, host-clock read discipline) =================
      # A CLASSIFYING gate, unlike Rule 3: a raw `DateTime.now` is clean only
      # when the read site itself says what it is for — either the canonical
      # Kyiv-day seam (`kyivToday(DateTime.now)`, tear-off form) or an
      # immediately instant-only consumption. See header "RULE 5".
      is_offender5 = 0
      if (do_rule5 == "1") {
        pos = 1
        while (1) {
          idx = index(substr(codeonly, pos), "DateTime.now")
          if (idx == 0) { break }
          abs = pos + idx - 1
          pos = abs + 12   # length("DateTime.now")

          # Match sits at/after a trailing comment in the stripped buffer.
          if (cs > 0 && abs >= cs) { continue }

          # Exclude a longer identifier merely ENDING in "DateTime.now"
          # (tz.TZDateTime.now(loc) / TZDateTime.now(...)).
          if (abs > 1) {
            prevc = substr(codeonly, abs - 1, 1)
            if (prevc ~ /[A-Za-z0-9_]/) { continue }
          }

          # (3) SEAM FORM — exactly `kyivToday(DateTime.now)`, a TEAR-OFF fed
          # to the canonical seam. `kyivToday(DateTime.now())` (a call) and
          # `kyivDayOf(DateTime.now())` do NOT match, on purpose: the
          # normalisation pass made one spelling canonical and this is what
          # keeps it that way (see header).
          if (abs > 10 && substr(codeonly, abs - 10, 10) == "kyivToday(" &&
              substr(codeonly, abs + 12, 1) == ")") { continue }

          # (4) INSTANT FORM — `DateTime.now().<instant-only member>`.
          if (substr(codeonly, abs + 12, 3) == "().") {
            rest = substr(codeonly, abs + 15)
            if (match(rest, /^[A-Za-z_][A-Za-z0-9_]*/) && RSTART == 1) {
              if (instant_member(substr(rest, 1, RLENGTH))) { continue }
            }
          }

          is_offender5 = 1
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
      # RULE 5 shares the `instant-ok:` marker RULE 3 uses — same question,
      # different tier (see header).
      if (is_offender5) {
        if ($0 ~ now_ann || prev ~ now_ann) { is_offender5 = 0 }
      }

      if (is_offender1 || is_offender2 || is_offender3 || is_offender5) {
        if (is_offender1) { printf "R1:%s:%d:%s\n", file, NR, $0 }
        if (is_offender3) { printf "R3:%s:%d:%s\n", file, NR, $0 }
        if (is_offender5) { printf "R5:%s:%d:%s\n", file, NR, $0 }
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
# scan_file_rule4 <path>
#   Emits "R4:<path>:<line>:<text>" for each un-annotated, live-code
#   `DateTime.now` reference that sits INSIDE a single `test(` / `testWidgets(`
#   body which ALSO pins the clock. See header "RULE 4" for the full spec.
#   A separate awk program from scan_file on purpose: Rule 4 is the only rule
#   here that needs whole-file BRACKET-DEPTH state (to know where one test
#   body ends and the next begins), and threading that through scan_file's
#   per-line matching would destabilise three rules that currently work.
# ---------------------------------------------------------------------------
scan_file_rule4() {
  awk -v file="$1" -v now_ann="$now_annotation" '
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
    # A token boundary before position i: not a word character and not "."
    # (so `foo.test(` / `_test(` never open a scope, and
    # `tz.TZDateTime.now` never counts as a host-clock read).
    function boundary(s, i,   p) {
      if (i <= 1) { return 1 }
      p = substr(s, i - 1, 1)
      if (p ~ /[A-Za-z0-9_.]/) { return 0 }
      return 1
    }
    # BLIND SPOT (a), CLOSED — WHERE A PIN LANDS ON THE SCOPE STACK.
    # A pin inside a TEST or GROUP body marks that scope. A pin inside a
    # `setUp` / `setUpAll` body marks BOTH that scope (so reads in the same
    # setUp are caught) AND the nearest ENCLOSING GROUP — or, with no enclosing
    # group, the whole file from this point on, since a top-level `setUp`
    # applies to every test in the file. A pin at FILE scope (`sp == 0`, e.g.
    # inside a pump helper declared outside `main()`) is NOT attributed to
    # anything: that helper only pins when a caller passes a non-null argument,
    # which is what the pin-ARGUMENT detection below is for.
    function record_pin(ln, txt,   j) {
      if (sp == 0) { return }
      if (st_pin[sp] == 0) { st_pin[sp] = 1; st_pinline[sp] = ln; st_pintext[sp] = txt }
      if (st_kind[sp] != 3) { return }
      for (j = sp - 1; j >= 1; j--) {
        if (st_kind[j] == 2) {
          if (st_pin[j] == 0) { st_pin[j] = 1; st_pinline[j] = ln; st_pintext[j] = txt }
          return
        }
      }
      if (file_pin == 0) { file_pin = 1; file_pinline = ln; file_pintext = txt }
    }
    # The innermost pin in force for the scope at `sp` — its own, one on any
    # enclosing scope, or a file-wide one from a top-level setUp. Writes
    # ep_line/ep_text (awk has no out-params); returns 1 when a pin is in force.
    function effective_pin(   j) {
      for (j = sp; j >= 1; j--) {
        if (st_pin[j]) { ep_line = st_pinline[j]; ep_text = st_pintext[j]; return 1 }
      }
      if (file_pin) { ep_line = file_pinline; ep_text = file_pintext; return 1 }
      return 0
    }
    # BLIND SPOT (b), CLOSED — DERIVED PIN-ARGUMENT NAMES.
    # Seeds `clock` / `now`, then reads the file once for
    # `clockProvider.overrideWithValue(<x>)` (optionally through a `() =>`
    # closure) and adds each bare `<x>` to the pin-argument name set of THIS
    # FILE.
    # A helper declared `{DateTime? fixedNow}` whose body overrides the provider
    # with `fixedNow` therefore makes `fixedNow:` a recognised pin argument
    # automatically — the name comes from what the file actually overrides the
    # provider with, not from a convention this gate hopes for.
    # `clockProvider.overrideWith((ref) {...})` is NOT harvested: its argument
    # is a closure PARAMETER, and adding `ref` would make any `ref:` named
    # argument read as a clock pin.
    BEGIN {
      pinarg["clock"] = 1
      pinarg["now"] = 1
      while ((getline praw < file) > 0) {
        pcode = strip_strings(praw)
        pcs = comment_start(pcode)
        if (pcs > 0) { pcode = substr(pcode, 1, pcs - 1) }
        ppos = 1
        while (1) {
          pidx = index(substr(pcode, ppos), "clockProvider.overrideWithValue(")
          if (pidx == 0) { break }
          pabs = ppos + pidx - 1
          ppos = pabs + 32   # length("clockProvider.overrideWithValue(")
          prest = substr(pcode, ppos)
          sub(/^[[:space:]]*/, "", prest)
          sub(/^\(\)[[:space:]]*=>[[:space:]]*/, "", prest)
          if (match(prest, /^[A-Za-z_][A-Za-z0-9_]*/) && RSTART == 1) {
            pname = substr(prest, 1, RLENGTH)
            ptail = substr(prest, RLENGTH + 1)
            sub(/^[[:space:]]*/, "", ptail)
            ptailc = substr(ptail, 1, 1)
            if (ptailc == ")" || ptailc == "," || ptailc == "") {
              pinarg[pname] = 1
            }
          }
        }
      }
      close(file)
    }
    {
      raw = $0
      firsttok = raw
      sub(/^[[:space:]]+/, "", firsttok)
      code = strip_strings(raw)
      cs = comment_start(code)
      if (cs > 0) { code = substr(code, 1, cs - 1) }
      if (firsttok ~ /^[/][/]/) { code = "" }

      # instant-ok on this line or the line directly above suppresses a read
      # found on THIS line (same placement rule as Rules 1-3).
      annotated = (raw ~ now_ann || prev ~ now_ann)

      n = length(code)
      for (i = 1; i <= n; i++) {
        c = substr(code, i, 1)

        # ---- scope openers ----
        # KIND 1 = test body, KIND 2 = group, KIND 3 = setUp/setUpAll. Groups
        # and setUps are tracked so a pin installed at THOSE scopes is seen —
        # blind spot (a), closed (see header).
        newkind = 0
        if ((substr(code, i, 12) == "testWidgets(" || substr(code, i, 5) == "test(") && boundary(code, i)) {
          newkind = 1
        } else if (substr(code, i, 6) == "group(" && boundary(code, i)) {
          newkind = 2
        } else if ((substr(code, i, 9) == "setUpAll(" || substr(code, i, 6) == "setUp(") && boundary(code, i)) {
          newkind = 3
        }
        if (newkind > 0) {
          sp++
          st_depth[sp] = depth; st_pin[sp] = 0; st_nown[sp] = 0
          st_kind[sp] = newkind
        }

        # ---- pin (a): an explicit clockProvider override ----
        if (substr(code, i, 22) == "clockProvider.override" && boundary(code, i)) {
          record_pin(NR, raw)
        }

        # ---- pin (b): a clock:/now: named argument with a NON-null value ----
        # This is the shape every real pin in this tree actually uses: a pump
        # helper takes `{DateTime? clock}` / `{DateTime Function()? now}` and
        # installs the override itself, so the only evidence at the TEST body
        # is the argument passed in. `null` is excluded — passing null is
        # exactly how these helpers say "leave the real clock alone".
        # The NAME SET is per-file and derived (see the BEGIN pre-pass above),
        # seeded with `clock` / `now` — blind spot (b), closed.
        if (substr(code, i, 1) ~ /[A-Za-z_]/ && boundary(code, i)) {
          argrest = substr(code, i)
          if (match(argrest, /^[A-Za-z_][A-Za-z0-9_]*:/)) {
            argname = substr(argrest, 1, RLENGTH - 1)
            if (argname in pinarg) {
              rest = substr(argrest, RLENGTH + 1)
              sub(/^[[:space:]]*/, "", rest)
              if (rest !~ /^null([^A-Za-z0-9_]|$)/) { record_pin(NR, raw) }
            }
          }
        }

        # ---- the host-clock read ----
        if (substr(code, i, 12) == "DateTime.now" && boundary(code, i)) {
          if (sp > 0 && !annotated) {
            k = ++st_nown[sp]
            st_nowline[sp, k] = NR; st_nowtext[sp, k] = raw
          }
        }

        # ---- depth tracking / scope close ----
        if (c == "(" || c == "[" || c == "{") {
          depth++
        } else if (c == ")" || c == "]" || c == "}") {
          depth--
          while (sp > 0 && depth <= st_depth[sp]) {
            if (st_nown[sp] > 0 && effective_pin()) {
              for (k = 1; k <= st_nown[sp]; k++) {
                printf "R4:%s:%d:%s\n", file, st_nowline[sp, k], st_nowtext[sp, k]
              }
              printf "R4:%s:%d:%s    [this test PINS the clock here — the read(s) above disagree with it]\n", file, ep_line, ep_text
            }
            sp--
          }
        }
      }
      prev = raw
    }
  ' "$1"
}

# ---------------------------------------------------------------------------
# scan_file_rule6 <path>
#   Emits "R6:<path>:<line>:<text>" for each un-annotated, live-code
#   `.toUtc(` / `.toLocal(` applied to a DATE TOKEN — either the seam call
#   itself (`kyivToday(...).toUtc()`) or an identifier whose same-file
#   declaration's initializer starts with one. See header "RULE 6".
#   A separate awk program because its BEGIN pre-pass builds a DIFFERENT table
#   (date-token names) from scan_file's (DateTime-typed declarations for Rule
#   2's identifier resolution), and because it runs over a WIDER root set
#   (`lib/` included).
# ---------------------------------------------------------------------------
scan_file_rule6() {
  awk -v file="$1" -v tok_ann="$token_annotation" '
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
    function comment_start(s,   i, c) {
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c == "/" && substr(s, i + 1, 1) == "/") { return i }
      }
      return 0
    }
    # 1 iff the bracketed expression opening at s[start] (the "(" of a seam
    # call) is immediately followed, after its MATCHING ")", by `.toUtc(` or
    # `.toLocal(`. Depth-tracked forward — never a `[^)]*` regex, which would
    # truncate at the first `)` of a nested call inside the seam argument.
    function closes_into_instant_call(s, start,   i, c, depth, n, tail) {
      n = length(s); depth = 0
      for (i = start; i <= n; i++) {
        c = substr(s, i, 1)
        if (c == "(" || c == "[" || c == "{") { depth++ }
        else if (c == ")" || c == "]" || c == "}") {
          depth--
          if (depth == 0) {
            tail = substr(s, i + 1)
            return (tail ~ /^\.toUtc\(/ || tail ~ /^\.toLocal\(/)
          }
        }
      }
      return 0
    }
    # Seam-name boundary. A single leading "_" is allowed so the private
    # `_dateOnly` re-implementations (master_schedule_screen.dart,
    # period_range_picker.dart, schedule_date_math.dart,
    # apply_schedule_sheet.dart) are matched too.
    function seam_boundary(s, abs,   p, p2) {
      if (abs <= 1) { return 1 }
      p = substr(s, abs - 1, 1)
      if (p == "_") {
        if (abs <= 2) { return 1 }
        p2 = substr(s, abs - 2, 1)
        return (p2 !~ /[A-Za-z0-9_.]/)
      }
      return (p !~ /[A-Za-z0-9_.]/)
    }
    function is_token_init(v) {
      return (v ~ /^kyivToday\(/ || v ~ /^kyivDayOf\(/ || v ~ /^_?dateOnly\(/)
    }
    # Pre-pass: same-file declarations whose initializer STARTS with a seam
    # call. Only the START has to be on the declaration line, so a seam call
    # whose arguments wrap onto following lines is still recognised.
    BEGIN {
      while ((getline draw < file) > 0) {
        dcode = strip_strings(draw)
        dcs = comment_start(dcode); if (dcs > 0) { dcode = substr(dcode, 1, dcs - 1) }
        dtrim = dcode; sub(/^[[:space:]]+/, "", dtrim)
        sub(/^(final|const|var)[[:space:]]+/, "", dtrim)
        sub(/^DateTime\??[[:space:]]+/, "", dtrim)
        sub(/^get[[:space:]]+/, "", dtrim)
        if (!match(dtrim, /^[A-Za-z_][A-Za-z0-9_]*/) || RSTART != 1) { continue }
        dname = substr(dtrim, 1, RLENGTH)
        dafter = substr(dtrim, RLENGTH + 1)
        sub(/^[[:space:]]*/, "", dafter)
        if (substr(dafter, 1, 2) == "()") {
          dafter = substr(dafter, 3); sub(/^[[:space:]]*/, "", dafter)
        }
        dinit = ""
        if (substr(dafter, 1, 2) == "=>") { dinit = substr(dafter, 3) }
        else if (substr(dafter, 1, 1) == "=" && substr(dafter, 2, 1) != "=") {
          dinit = substr(dafter, 2)
        }
        if (dinit == "") { continue }
        sub(/^[[:space:]]*/, "", dinit)
        if (is_token_init(dinit) && !(dname in tok)) { tok[dname] = 1 }
      }
      close(file)
    }
    {
      raw = $0
      firsttok = raw; sub(/^[[:space:]]+/, "", firsttok)
      code = strip_strings(raw)
      cs = comment_start(code); if (cs > 0) { code = substr(code, 1, cs - 1) }
      if (firsttok ~ /^[/][/]/) { code = "" }
      annotated = (raw ~ tok_ann || prev ~ tok_ann)
      hit = 0

      # (b) INDIRECT — <declared-token-name>.toUtc( / .toLocal(
      n = length(code)
      for (i = 1; i <= n; i++) {
        if (substr(code, i, 1) !~ /[A-Za-z_]/) { continue }
        if (i > 1 && substr(code, i - 1, 1) ~ /[A-Za-z0-9_.]/) { continue }
        rest = substr(code, i)
        if (!match(rest, /^[A-Za-z_][A-Za-z0-9_]*/)) { continue }
        nm = substr(rest, 1, RLENGTH)
        if (!(nm in tok)) { continue }
        tail = substr(rest, RLENGTH + 1)
        # A function-form token declaration (`DateTime tokC() => dateOnly(x);`)
        # is referenced as `tokC()`, so skip a zero-argument call before looking
        # for the instant member.
        if (substr(tail, 1, 2) == "()") { tail = substr(tail, 3) }
        if (tail ~ /^\.toUtc\(/ || tail ~ /^\.toLocal\(/) { hit = 1 }
      }

      # (a) DIRECT — kyivToday(...) / kyivDayOf(...) / dateOnly(...).toUtc(
      split("kyivToday( kyivDayOf( dateOnly(", seams, " ")
      for (k = 1; k <= 3; k++) {
        pos = 1
        while (1) {
          idx = index(substr(code, pos), seams[k])
          if (idx == 0) { break }
          abs = pos + idx - 1
          pos = abs + 1
          if (!seam_boundary(code, abs)) { continue }
          if (closes_into_instant_call(code, abs + length(seams[k]) - 1)) { hit = 1 }
        }
      }

      if (hit && !annotated) { printf "R6:%s:%d:%s\n", file, NR, raw }
      prev = raw
    }
  ' "$1"
}

# ---------------------------------------------------------------------------
# scan_file_rule7 <path>
#   Emits "R7:<path>:<line>:<text>" for each un-annotated, live-code
#   `.difference(` whose RECEIVER or ARGUMENT is a COMPONENT-DERIVED DATE
#   TOKEN — a bare local `DateTime(x.year, x.month, x.day)`, inlined at the
#   call site or resolved through a same-file declaration. See header "RULE 7".
#   A separate awk program because its BEGIN pre-pass builds a THIRD table
#   (component-derived-token names), distinct from scan_file's DateTime-typed
#   declarations and scan_file_rule6's seam-initialised ones.
# ---------------------------------------------------------------------------
scan_file_rule7() {
  awk -v file="$1" -v tok_ann="$token_annotation" '
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
    function comment_start(s,   i, c) {
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c == "/" && substr(s, i + 1, 1) == "/") { return i }
      }
      return 0
    }
    # Top-level commas between s[start] (the "(" of a call) and its MATCHING
    # ")". Depth-tracked forward; stops the instant depth returns to 0, so a
    # nested call never leaks commas in and an enclosing one never leaks in.
    # Deliberately not a `[^)]*` regex.
    function count_top_commas(s, start,   i, c, depth, commas, n) {
      n = length(s); depth = 0; commas = 0
      for (i = start; i <= n; i++) {
        c = substr(s, i, 1)
        if (c == "(" || c == "[" || c == "{") { depth++ }
        else if (c == ")" || c == "]" || c == "}") {
          depth--
          if (depth == 0) { return commas }
        } else if (c == "," && depth == 1) { commas++ }
      }
      return commas
    }
    # The text of the FIRST argument of the call whose "(" is at s[start],
    # trimmed. Same depth tracking, stopping at the first depth-1 comma.
    function first_arg(s, start,   i, c, depth, n, out) {
      n = length(s); depth = 0; out = ""
      for (i = start; i <= n; i++) {
        c = substr(s, i, 1)
        if (c == "(" || c == "[" || c == "{") {
          depth++
          if (depth == 1) { continue }
        } else if (c == ")" || c == "]" || c == "}") {
          depth--
          if (depth == 0) { break }
        } else if (c == "," && depth == 1) { break }
        if (depth >= 1) { out = out c }
      }
      sub(/^[[:space:]]+/, "", out); sub(/[[:space:]]+$/, "", out)
      return out
    }
    # Index of the matching ")" for the "(" at s[start]; 0 if unbalanced on
    # this line.
    function match_close(s, start,   i, c, depth, n) {
      n = length(s); depth = 0
      for (i = start; i <= n; i++) {
        c = substr(s, i, 1)
        if (c == "(" || c == "[" || c == "{") { depth++ }
        else if (c == ")" || c == "]" || c == "}") {
          depth--
          if (depth == 0) { return i }
        }
      }
      return 0
    }
    # 1 iff s[abs..] begins a COMPONENT-DERIVED DATE TOKEN construction:
    # a bare local `DateTime(` (abs is the index of the "D"), arity EXACTLY 3,
    # first argument a `<expr>.year` component read. `prevok` is the caller"s
    # already-checked "not preceded by . or a word char" verdict.
    function is_component_token(s, abs,   op, fa) {
      if (substr(s, abs, 9) != "DateTime(") { return 0 }
      op = abs + 8
      if (count_top_commas(s, op) != 2) { return 0 }
      fa = first_arg(s, op)
      return (fa ~ /^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*\.year$/)
    }
    # Pre-pass: same-file declarations whose initializer IS a component-derived
    # token construction. Recognises the same declaration forms Rule 6 does.
    BEGIN {
      while ((getline draw < file) > 0) {
        dcode = strip_strings(draw)
        dcs = comment_start(dcode); if (dcs > 0) { dcode = substr(dcode, 1, dcs - 1) }
        dtrim = dcode; sub(/^[[:space:]]+/, "", dtrim)
        sub(/^(final|const|var)[[:space:]]+/, "", dtrim)
        sub(/^DateTime\??[[:space:]]+/, "", dtrim)
        sub(/^get[[:space:]]+/, "", dtrim)
        if (!match(dtrim, /^[A-Za-z_][A-Za-z0-9_]*/) || RSTART != 1) { continue }
        dname = substr(dtrim, 1, RLENGTH)
        dafter = substr(dtrim, RLENGTH + 1)
        sub(/^[[:space:]]*/, "", dafter)
        if (substr(dafter, 1, 2) == "()") {
          dafter = substr(dafter, 3); sub(/^[[:space:]]*/, "", dafter)
        }
        dinit = ""
        if (substr(dafter, 1, 2) == "=>") { dinit = substr(dafter, 3) }
        else if (substr(dafter, 1, 1) == "=" && substr(dafter, 2, 1) != "=") {
          dinit = substr(dafter, 2)
        }
        if (dinit == "") { continue }
        sub(/^[[:space:]]*/, "", dinit)
        if (is_component_token(dinit, 1) && !(dname in tok)) { tok[dname] = 1 }
      }
      close(file)
    }
    {
      raw = $0
      firsttok = raw; sub(/^[[:space:]]+/, "", firsttok)
      code = strip_strings(raw)
      cs = comment_start(code); if (cs > 0) { code = substr(code, 1, cs - 1) }
      if (firsttok ~ /^[/][/]/) { code = "" }
      annotated = (raw ~ tok_ann || prev ~ tok_ann)
      hit = 0
      n = length(code)

      for (i = 1; i <= n; i++) {
        if (substr(code, i, 1) !~ /[A-Za-z_]/) { continue }
        if (i > 1 && substr(code, i - 1, 1) ~ /[A-Za-z0-9_.]/) { continue }
        rest = substr(code, i)
        if (!match(rest, /^[A-Za-z_][A-Za-z0-9_]*/)) { continue }
        nm = substr(rest, 1, RLENGTH)

        # (a) DIRECT — the construction inlined, then `.difference(`.
        if (nm == "DateTime" && is_component_token(code, i)) {
          cl = match_close(code, i + 8)
          if (cl > 0 && substr(code, cl + 1) ~ /^\.difference\(/) { hit = 1 }
        }

        # (b) INDIRECT — a resolved token name as RECEIVER, or as ARGUMENT.
        if (nm in tok) {
          tail = substr(rest, RLENGTH + 1)
          if (substr(tail, 1, 2) == "()") { tail = substr(tail, 3) }
          if (tail ~ /^\.difference\(/) { hit = 1 }
          if (i > 12 && substr(code, i - 12, 12) == ".difference(") { hit = 1 }
        }
      }

      if (hit && !annotated) { printf "R7:%s:%d:%s\n", file, NR, raw }
      prev = raw
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
  local d f do_rule1 do_rule3 do_rule5
  for d in "${scan_dirs[@]}"; do
    do_rule3=0
    if [ "$d" = "$now_scan_dir" ]; then
      do_rule3=1
    fi
    do_rule5=0
    if [ "$d" = "$mix_scan_dir" ]; then
      do_rule5=1
    fi
    while IFS= read -r -d '' f; do
      [ -z "$f" ] && continue
      do_rule1=0
      if grep -qE "$zone_critical_pattern" "$f" 2>/dev/null; then
        do_rule1=1
      fi
      scan_file "$f" "$do_rule1" "$do_rule3" "$do_rule5"
      if [ "$d" = "$mix_scan_dir" ]; then
        scan_file_rule4 "$f"
      fi
    done < <(find "$tree_root/$d" -type f -name '*.dart' -print0 2>/dev/null | sort -z)
  done

  # RULE 6 walks its OWN, WIDER root set (`lib/` included) — see header
  # "RULE 6 — SCAN ROOT". Kept as a separate loop rather than folded into the
  # one above precisely so the wider root cannot silently leak into Rules 1-5,
  # whose scope is deliberately the test tiers only.
  for d in "${token_scan_dirs[@]}"; do
    while IFS= read -r -d '' f; do
      [ -z "$f" ] && continue
      # PURE PERFORMANCE PREFILTER — not a classifier, and it must never become
      # one. A file containing neither `.toUtc(` nor `.toLocal(` anywhere in its
      # RAW text cannot possibly produce a Rule 6 hit, since BOTH detection
      # forms end in matching one of those two literals. Skipping it is
      # therefore observationally identical to scanning it, and only exists
      # because this root set is ~1000 files (lib/ included) and the awk
      # program reads each one twice. Do NOT extend this grep with anything
      # semantic — that is how Rule 1's Stage 1 filter came to hide the whole
      # 2026-08-02 incident class from Rule 2.
      grep -qF -e '.toUtc(' -e '.toLocal(' "$f" 2>/dev/null || continue
      scan_file_rule6 "$f"
    done < <(find "$tree_root/$d" -type f -name '*.dart' -print0 2>/dev/null | sort -z)
  done

  # RULE 7 walks the SAME wider root set as Rule 6 (`lib/` included) — the
  # defect it gates shipped in `lib/`, not in a fixture. Kept as its own loop
  # for the same reason Rule 6's is: the wider root must not be able to leak
  # into Rules 1-5, whose scope is deliberately the test tiers only, and the
  # performance prefilter differs (`.difference(` rather than `.toUtc(`).
  for d in "${token_scan_dirs[@]}"; do
    while IFS= read -r -d '' f; do
      [ -z "$f" ] && continue
      # PURE PERFORMANCE PREFILTER, exactly as Rule 6's — and subject to the
      # same standing warning: do NOT extend it with anything semantic. A file
      # containing no `.difference(` anywhere in its RAW text cannot produce a
      # Rule 7 hit, since both detection forms end in matching that literal.
      grep -qF -e '.difference(' "$f" 2>/dev/null || continue
      scan_file_rule7 "$f"
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
// NOT integration_test/, and carries a `DateTime.now` read of exactly the kind
// RULE 3 flags on sight in its own tier — call form AND bare tear-off. RULE 3
// must contribute ZERO offenders from it, because the widget/unit tier has no
// single app-wide injected clock the way the E2E tier does.
//
// Both rows are deliberately written in RULE 5-CLEAN form (the canonical seam
// tear-off, and an instant-only consumption). If they were bare reads they
// would legitimately trip Rule 5, and this control could no longer assert
// "zero offenders from this file" — it would be asserting that Rule 5 is
// broken instead. The Rule-3 property under test is unaffected: both lines
// still contain a live `DateTime.now`, which is all Rule 3 looks at.
final DateTime a = kyivToday(DateTime.now);
final DateTime b = DateTime.now().add(const Duration(days: 1));
EOF

  # RULE 4 probe — clock-coherence in the widget/unit tier. Lives under
  # `test/` because that is RULE 4's ONLY scan root. Unlike Rule 3, this is
  # NOT a blanket declaration gate: the negative rows below (especially
  # r4-3) are the whole point, because an un-pinned host read is the
  # DOMINANT and CORRECT pattern in this tier and flagging it would make the
  # gate pure noise.
  mix_probe="test/features/booking/presentation/clock_mix_probe_test.dart"
  mkdir -p "$tmp/$(dirname "$mix_probe")"
  cat > "$tmp/$mix_probe" <<'EOF'
// Probe for RULE 4 (clock-coherence, widget/unit tier) — exercised row by
// row. This file deliberately names clockProvider, which makes Stage 1
// classify it zone-critical and therefore ENABLES Rule 1 here; every
// instant below is written .utc so Rule 1 stays silent, and every clock:
// site resolves to a .utc declaration so Rule 2 does too. Rule 3 does not
// scan test/ at all.

final DateTime pinned = DateTime.utc(2026, 6, 14, 12);

// (r4-1) override pin + host read in the SAME test — read and pin MUST both
// be flagged.
testWidgets('override pin, host read', (tester) async {
  final DateTime today = kyivToday(DateTime.now);
  await pumpIt(overrides: [clockProvider.overrideWithValue(() => pinned)]);
});

// (r4-2) helper-argument pin + host read — both MUST be flagged. This is the
// shape every real pin in this tree actually uses.
testWidgets('helper-arg pin, host read', (tester) async {
  await pumpIt(tester, clock: () => pinned);
  final DateTime day = kyivToday(DateTime.now);
});

// (r4-3) NO pin + host read — MUST stay clean. This is the dominant and
// CORRECT pattern in this tier: the widget reads the real clock too, so the
// fixture and the app agree. Flagging this would make Rule 4 a gate whose
// every hit on the real tree is a false positive.
testWidgets('no pin, host read', (tester) async {
  final DateTime today = kyivToday(DateTime.now);
  await pumpIt(tester);
});

// (r4-4) pin + an ANNOTATED host read — MUST stay clean.
testWidgets('pinned, annotated elapsed-time read', (tester) async {
  await pumpIt(tester, clock: () => pinned);
  // instant-ok: elapsed-wall-time measurement, unaffected by the pin
  final DateTime t0 = DateTime.now();
});

// (r4-5) clock: null is NOT a pin (it is how these helpers say "leave the
// real clock alone") — MUST stay clean.
testWidgets('explicit null clock, host read', (tester) async {
  await pumpIt(tester, clock: null);
  final DateTime today = kyivToday(DateTime.now);
});

// (r4-6) pin with no host read at all — MUST stay clean.
testWidgets('pinned, no host read', (tester) async {
  await pumpIt(tester, clock: () => pinned);
  expect(find.byType(Widget), findsOneWidget);
});

// (r4-7) a longer identifier merely ENDING in DateTime.now, inside a PINNED
// test — MUST stay clean (boundary check).
testWidgets('pinned, TZDateTime.now', (tester) async {
  await pumpIt(tester, clock: () => pinned);
  final DateTime z = tz.TZDateTime.now(loc);
});

// (r4-8) a host read at FILE scope, outside any test body — MUST stay clean.
// Rule 4 is scoped to a test/group/setUp body; a file-scope read cannot be
// correlated with any one pin.
final DateTime fileScope = kyivToday(DateTime.now);

// (r4-9) BLIND SPOT (a), CLOSED — a pin installed in a group-level setUp, with
// the host read in a SIBLING test body. Before this was closed, scopes were
// per-test and this pin was invisible. BOTH the read and the setUp pin MUST be
// flagged.
group('pinned via setUp', () {
  setUp(() {
    installOverrides([clockProvider.overrideWithValue(() => pinned)]);
  });

  testWidgets('host read under a setUp pin', (tester) async {
    final DateTime today = kyivToday(DateTime.now);
    await pumpIt(tester);
  });
});

// (r4-10) an UNPINNED group containing a host read, both in a test body and
// directly in the group body — MUST stay clean. This is the row that keeps
// group-scope tracking from turning Rule 4 into the noise gate Rule 3 would
// have been in this tier.
group('unpinned group', () {
  final DateTime groupScope = kyivToday(DateTime.now);

  testWidgets('host read, no pin anywhere', (tester) async {
    final DateTime today = kyivToday(DateTime.now);
    await pumpIt(tester);
  });
});

// (r4-11) BLIND SPOT (b), CLOSED — the pin arrives through a helper parameter
// named neither `clock:` nor `now:`. The name is DERIVED from the
// clockProvider.overrideWithValue(fixedNow) below, not hardcoded. Read and pin
// MUST both be flagged.
Future<void> pumpFixed(WidgetTester tester, {DateTime Function()? fixedNow}) =>
    pumpIt(tester, overrides: [
      if (fixedNow != null) clockProvider.overrideWithValue(fixedNow),
    ]);

testWidgets('helper-arg pin under a derived name', (tester) async {
  await pumpFixed(tester, fixedNow: () => pinned);
  final DateTime today = kyivToday(DateTime.now);
});

// (r4-12) the SAME derived name passed as null — not a pin, MUST stay clean.
testWidgets('derived-name arg explicitly null', (tester) async {
  await pumpFixed(tester, fixedNow: null);
  final DateTime today = kyivToday(DateTime.now);
});
EOF
  # r4-1's read (13) and pin (14); r4-2's pin (20) and read (21); r4-9's setUp
  # pin (71) and the SIBLING test's read (75); r4-11's derived-name pin (103)
  # and read (104).
  mix_offender_lines=(13 14 20 21 71 75 103 104)
  # Reads that must NOT be flagged: unpinned (29), annotated under a pin (37),
  # under an explicit clock: null (44), a longer identifier (57), file scope
  # (63), directly inside an UNPINNED group body (85), inside an unpinned
  # group's test (88), and under a derived-name argument explicitly null (110).
  mix_clean_lines=(29 37 44 57 63 85 88 110)

  # RULE 5 probe — host-clock read discipline in the widget/unit tier. Lives
  # under `test/` because that is RULE 5's ONLY scan root; the
  # `integration_test/`-side control below carries the same shapes and must
  # contribute no R5 at all (Rule 3 covers that tier, more strictly).
  read_probe="test/features/booking/presentation/host_read_probe_test.dart"
  mkdir -p "$tmp/$(dirname "$read_probe")"
  cat > "$tmp/$read_probe" <<'EOF'
// Probe for RULE 5 (host-clock read discipline, widget/unit tier), row by row.
// Carries no clockProvider/clock: pin anywhere, so RULE 4 must find nothing;
// no bare DateTime(<digit>, ...) call, so RULE 1 must find nothing either.

// (r5-1) the canonical seam, TEAR-OFF form — MUST stay clean.
final DateTime a = kyivToday(DateTime.now);

// (r5-2) instant form, .add — MUST stay clean.
final DateTime b = DateTime.now().add(const Duration(days: 2));

// (r5-3) instant form, .subtract — MUST stay clean.
final DateTime c = DateTime.now().subtract(const Duration(seconds: 5));

// (r5-4) instant form, chained through .toUtc — clean via the FIRST member.
final DateTime d = DateTime.now().toUtc().subtract(const Duration(hours: 1));

// (r5-5) instant form, a non-call member — MUST stay clean.
final int e = DateTime.now().millisecondsSinceEpoch;

// (r5-6) BARE read assigned to a local — MUST be flagged. This is the shape
// all four real defects had; whether it becomes a calendar day or an instant
// is not stated at the read site.
final DateTime f = DateTime.now();

// (r5-7) a calendar field read straight off the device clock — MUST be
// flagged. The literal shape this rule was written to name.
final int g = DateTime.now().month;

// (r5-8) passed as an argument, bare — MUST be flagged.
final h = State(selectedDate: DateTime.now());

// (r5-9) kyivDayOf(DateTime.now()) — MUST be flagged. Semantically identical
// to (r5-1) but NOT the canonical spelling; the fix is to rewrite it, which is
// what keeps one spelling in this tier.
final DateTime i = kyivDayOf(DateTime.now());

// (r5-10) kyivToday(DateTime.now()) — a CALL, not the tear-off — MUST be
// flagged, same reason as (r5-9).
final DateTime j = kyivToday(DateTime.now());

// (r5-11) .toIso8601String() is NOT an instant operation on a local DateTime
// (it renders HOST wall-clock time with no offset) — MUST be flagged.
final String k = DateTime.now().toIso8601String();

// (r5-12) same-line instant-ok marker — MUST stay clean.
final DateTime l = DateTime.now(); // instant-ok: elapsed-wall-time bracket

// (r5-13) marker on the line directly above — MUST stay clean.
// instant-ok: elapsed-wall-time bracket
final DateTime m = DateTime.now();

// (r5-14) whole-line comment — MUST stay clean.
// final DateTime n = DateTime.now();

// (r5-15) inside a string literal — MUST stay clean (strip_strings).
const String s = "DateTime.now()";

// (r5-16) trailing comment hides the read — MUST stay clean.
final DateTime o = p; // DateTime.now()

// (r5-17) a longer identifier merely ENDING in DateTime.now — MUST stay clean.
final DateTime q = tz.TZDateTime.now(loc);

// (r5-18) host-tz-ok is RULES 1/2's marker, not RULE 5's — MUST still be
// flagged (same non-interchangeability Rule 3 pins).
// host-tz-ok: wrong marker for a raw device-clock read
final DateTime r = DateTime.now();
EOF
  read_offender_lines=(23 27 30 35 39 43 67)
  read_clean_lines=(6 9 12 15 18 46 50 53 56 59 62)

  # RULE 5 scan-root control — the same flagged shapes under
  # `integration_test/`. Must contribute ZERO **R5** offenders (Rule 3 flags
  # them there instead, which is exactly the point: one report per hit).
  read_control_path="integration_test/support/host_read_scope_control.dart"
  mkdir -p "$tmp/$(dirname "$read_control_path")"
  cat > "$tmp/$read_control_path" <<'EOF'
// Control for RULE 5's scan-root restriction: this file sits under
// integration_test/, NOT test/, and carries RULE 5's flagged shape. RULE 5
// must contribute ZERO offenders from it — RULE 3 already covers this tier as
// a blanket declaration gate, and double-reporting one hit under two rule
// names would make both harder to act on.
final DateTime a = DateTime.now();
final int b = DateTime.now().month;
EOF
  # These two lines DO trip RULE 3 — that is the point of the pair. Rule 5's
  # root restriction is only worth having if the hit is still reported, once,
  # by the rule that owns that tier. Asserted explicitly below rather than left
  # to the total.
  read_control_r3_lines=(6 7)

  # RULE 6 probe — a date token treated as an instant. Lives under `lib/`
  # specifically: RULE 6 is the ONLY rule here whose scan root includes lib/,
  # and putting the positive probe there is what pins that root independently
  # of the matching logic.
  token_probe="lib/features/booking/presentation/date_token_probe.dart"
  mkdir -p "$tmp/$(dirname "$token_probe")"
  cat > "$tmp/$token_probe" <<'EOF'
// Probe for RULE 6 (date token treated as an instant), row by row. Sits under
// lib/, which ONLY Rule 6 scans.

// ---- date-token declarations the indirect form resolves against ----
final DateTime tokA = kyivToday(clock);
DateTime get tokB => kyivDayOf(instant);
DateTime tokC() => dateOnly(other);
final tokD = kyivToday(clock);
// A declaration whose seam call WRAPS onto the following lines — the
// initializer only has to START here.
final DateTime tokE = kyivDayOf(
  someInstant,
);
// NOT a date token — a genuine instant.
final DateTime notTok = DateTime.utc(2026, 8, 2, 12);

// ---- flagged rows ----

// (r6-1) indirect, .toUtc() on a token — MUST be flagged.
final DateTime x1 = tokA.toUtc().add(const Duration(hours: 12));

// (r6-2) indirect, .toLocal() on a getter-declared token — MUST be flagged.
final DateTime x2 = tokB.toLocal();

// (r6-3) indirect through a function-form declaration — MUST be flagged.
final DateTime x3 = tokC().toUtc();

// (r6-4) indirect through an untyped `final` declaration — MUST be flagged.
final DateTime x4 = tokD.toUtc();

// (r6-5) indirect through a declaration whose seam call wrapped lines — MUST
// be flagged.
final DateTime x5 = tokE.toUtc();

// (r6-6) DIRECT — the seam call itself — MUST be flagged.
final DateTime x6 = kyivToday(clock).toUtc();

// (r6-7) DIRECT with a NESTED call inside the seam's own argument list — MUST
// be flagged; pins that the matching ")" is found by depth tracking, not by a
// [^)]* regex that would truncate at the inner call's ")".
final DateTime x7 = kyivDayOf(pick(a, b)).toUtc();

// (r6-8) DIRECT on the private _dateOnly re-implementation — MUST be flagged.
final DateTime x8 = _dateOnly(day).toUtc();

// ---- clean rows ----

// (r6-9) .toUtc() on a genuine instant — MUST stay clean.
final DateTime y1 = notTok.toUtc();

// (r6-10) a LEGAL operation on a token — MUST stay clean. .isBefore against
// another token is explicitly legal; deciding whether the other side is an
// instant is dataflow and deliberately out of scope.
final bool y2 = tokA.isBefore(tokB);

// (r6-11) reading calendar fields off a token — the documented LEGAL use.
final int y3 = tokA.day;

// (r6-12) an identifier not declared as a token in this file — MUST stay
// clean (the same-file/undeclared honest limit).
final DateTime y4 = someOtherThing.toUtc();

// (r6-13) same-line date-token-ok marker — MUST stay clean.
final DateTime y5 = tokA.toUtc(); // date-token-ok: demonstrating the failure

// (r6-14) marker on the line directly above — MUST stay clean.
// date-token-ok: demonstrating the failure
final DateTime y6 = tokA.toUtc();

// (r6-15) whole-line comment — MUST stay clean.
// final DateTime y7 = tokA.toUtc();

// (r6-16) inside a string literal — MUST stay clean.
const String y8 = "tokA.toUtc()";

// (r6-17) trailing comment hides it — MUST stay clean.
final DateTime y9 = z; // tokA.toUtc()

// (r6-18) a LONGER identifier merely ENDING in a token name — MUST stay clean.
final DateTime y10 = myTokA.toUtc();
EOF
  token_offender_lines=(20 23 26 29 33 36 41 44)
  token_clean_lines=(49 54 57 61 64 68 71 74 77 80)

  # RULE 7 probe — a component-derived date token reaching .difference(.
  # Lives under `lib/` for the same reason Rule 6's does: `lib/` is a root
  # ONLY Rules 6 and 7 walk, so a positive probe there pins that root
  # independently of the matching logic. It is a SEPARATE file from the Rule 6
  # probe so neither rule's hits can be mistaken for the other's, and it
  # carries NO `.toUtc(`/`.toLocal(` so Rule 6's prefilter skips it entirely.
  seam_probe="lib/features/booking/presentation/token_difference_probe.dart"
  mkdir -p "$tmp/$(dirname "$seam_probe")"
  cat > "$tmp/$seam_probe" <<'EOF'
// Probe for RULE 7 (date token subtracted with .difference), row by row.
// Sits under lib/, which only Rules 6 and 7 scan.

// ---- component-derived token declarations the indirect form resolves against ----
final DateTime todayStart = DateTime(nowKyiv.year, nowKyiv.month, nowKyiv.day);
final DateTime thenStart = DateTime(then.year, then.month, then.day);
DateTime tokFn() => DateTime(a.year, a.month, a.day);
final loose = DateTime(deep.nested.value.year, deep.nested.value.month, deep.nested.value.day);
// NOT component-derived — a literal-year arity-3 token. Rule 7 deliberately
// does not claim this shape; see the header's "WHY NOT THE BROADER" section.
final DateTime literalTok = DateTime(2026, 3, 29);
// NOT a token at all — genuine instants.
final DateTime realInstant = DateTime.utc(2026, 3, 29, 12);
final DateTime otherInstant = DateTime.utc(2026, 3, 30, 12);

// ---- flagged rows ----

// (r7-1) INDIRECT, receiver form — the EXACT shape that shipped in
// relative_date.dart. MUST be flagged.
final int d1 = todayStart.difference(thenStart).inDays;

// (r7-2) INDIRECT, ARGUMENT form — the token is the subtrahend and the
// RECEIVER is a genuine instant, so a gate that only inspects receivers
// misses this half entirely. MUST be flagged.
final int d2 = realInstant.difference(thenStart).inDays;

// (r7-3) INDIRECT through a zero-arg function declaration. MUST be flagged.
final int d3 = tokFn().difference(otherInstant).inDays;

// (r7-4) INDIRECT through an UNTYPED final whose initializer reads a deeply
// qualified `.year`. MUST be flagged.
final int d4 = loose.difference(otherInstant).inDays;

// (r7-5) DIRECT — the construction inlined at the call site. MUST be flagged.
final int d5 = DateTime(x.year, x.month, x.day).difference(otherInstant).inDays;

// (r7-6) DIRECT, NESTED inside an enclosing call — pins that the token's
// matching ")" is found by depth tracking, not by a [^)]* regex that would
// run past it to the ENCLOSING call's ")". MUST be flagged.
final int d6 = wrap(DateTime(x.year, x.month, x.day).difference(otherInstant).inDays, 3);

// ---- clean rows ----

// (r7-7) DateTime.utc — a qualified constructor, never a host-local token.
final int c1 = DateTime.utc(2026, 3, 29).difference(realInstant).inDays;

// (r7-8) tz.TZDateTime — contains "DateTime(" as a SUBSTRING, preceded by a
// word character. MUST stay clean (same exclusion as Rule 1's rule 1).
final int c2 = tz.TZDateTime(zone, a.year, a.month, a.day).difference(o).inMinutes;

// (r7-9) ARITY 4 — carries a time-of-day component, so it is an INSTANT, not
// a date token. Rule 1's territory, not Rule 7's; this row is what separates
// the two rules.
final int c3 = DateTime(a.year, a.month, a.day, 12).difference(otherInstant).inDays;

// (r7-10) LITERAL-year arity-3 token on BOTH sides — deliberately out of this
// rule's claim; see the header's measured residue.
final int c4 = literalTok.difference(literalTok2).inDays;

// (r7-11) genuine instants on both sides.
final int c5 = realInstant.difference(otherInstant).inDays;

// (r7-12) a LEGAL operation on a token — comparison, not subtraction.
final bool c6 = todayStart.isBefore(thenStart);

// (r7-13) an identifier not declared as a token in this file, on BOTH sides
// (the same-file honest limit — a cross-file declaration is never looked up).
final int c7 = someOtherThing.difference(thenStart2).inDays;

// (r7-14) same-line date-token-ok marker.
final int c8 = todayStart.difference(thenStart).inDays; // date-token-ok: demo

// (r7-15) marker on the line directly above.
// date-token-ok: demonstrating the failure
final int c9 = todayStart.difference(thenStart).inDays;

// (r7-16) whole-line comment.
// final int c10 = todayStart.difference(thenStart).inDays;

// (r7-17) inside a string literal.
const String c11 = "todayStart.difference(thenStart)";

// (r7-18) trailing comment hides it.
final int c12 = z; // todayStart.difference(thenStart)

// (r7-19) a LONGER identifier merely ENDING in a token name, on both sides.
final int c13 = myTodayStart.difference(myThenStart).inDays;
EOF
  seam_offender_lines=(20 25 28 32 35 40)
  seam_clean_lines=(45 49 54 58 61 64 68 71 75 81 84 87)

  # RULE 7 SCAN-ROOT CONTROL — the same flagged shape under a root Rule 7 does
  # NOT walk. `token_scan_dirs` is lib/ + test/ + integration_test/, all of
  # which it DOES walk, so there is no out-of-scope root to control against;
  # instead this control proves the reverse direction, which is the one that
  # can silently regress: Rule 7's probe must contribute nothing to Rules 1-6.
  # (Asserted below rather than with a separate file.)

  out="$(run_scan "$tmp")"
  flagged="$(printf '%s\n' "$out" | grep -c . || true)"
  expected=$(( ${#probe_paths[@]} * offenders_per_probe + ${#clock_probe_paths[@]} * clock_offenders_per_probe + identifier_offenders_total + ${#now_offender_lines[@]} + ${#mix_offender_lines[@]} + ${#read_offender_lines[@]} + ${#token_offender_lines[@]} + ${#seam_offender_lines[@]} + ${#read_control_r3_lines[@]} ))
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

  # ---- RULE 4 assertions -----------------------------------------------
  for ln in "${mix_offender_lines[@]}"; do
    if ! printf '%s\n' "$out" | grep -q "^R4:$tmp/$mix_probe:$ln:"; then
      echo "SELF-TEST FAIL: expected a Rule-4 offender at $mix_probe:$ln,"
      echo "                none found. Is '$mix_scan_dir' still walked with"
      echo "                scan_file_rule4 by run_scan? Lines 13/14 pin the"
      echo "                clockProvider-override shape, 20/21 the"
      echo "                helper-argument shape (which is the one every"
      echo "                real pin in this tree actually uses)."
      printf '%s\n' "$out"
      exit 1
    fi
  done
  for ln in "${mix_clean_lines[@]}"; do
    if printf '%s\n' "$out" | grep -q "^R4:$tmp/$mix_probe:$ln:"; then
      echo "SELF-TEST FAIL: line $ln of $mix_probe should NOT be flagged by"
      echo "                Rule 4 (unpinned host read / instant-ok annotated /"
      echo "                clock: null is not a pin / longer identifier /"
      echo "                file-scope read), but was. Line 28 in particular is"
      echo "                the DOMINANT correct pattern in this tier — a Rule 4"
      echo "                that flags it is pure noise, not a gate:"
      printf '%s\n' "$out"
      exit 1
    fi
  done
  if printf '%s\n' "$out" | grep -qE "^R[1235]:$tmp/$mix_probe:"; then
    echo "SELF-TEST FAIL: $mix_probe was flagged by Rule 1, 2, 3 or 5 — it"
    echo "                contains only .utc instants, clock: sites resolving"
    echo "                to a .utc declaration, host reads written in RULE"
    echo "                5-clean form, and sits under test/ (which Rule 3"
    echo "                does not scan):"
    printf '%s\n' "$out"
    exit 1
  fi

  # ---- RULE 5 assertions -----------------------------------------------
  for ln in "${read_offender_lines[@]}"; do
    if ! printf '%s\n' "$out" | grep -q "^R5:$tmp/$read_probe:$ln:"; then
      echo "SELF-TEST FAIL: expected a Rule-5 offender at $read_probe:$ln,"
      echo "                none found. Is '$mix_scan_dir' still walked with"
      echo "                do_rule5=1 by run_scan? Lines 39/43 in particular"
      echo "                pin that kyivDayOf(DateTime.now()) and"
      echo "                kyivToday(DateTime.now()) are NOT accepted"
      echo "                spellings — only the kyivToday(DateTime.now)"
      echo "                tear-off is."
      printf '%s\n' "$out"
      exit 1
    fi
  done
  for ln in "${read_clean_lines[@]}"; do
    if printf '%s\n' "$out" | grep -q "^R5:$tmp/$read_probe:$ln:"; then
      echo "SELF-TEST FAIL: line $ln of $read_probe should NOT be flagged by"
      echo "                Rule 5 (canonical seam tear-off / instant-only"
      echo "                consumption / instant-ok annotated / whole-line"
      echo "                comment / string literal / trailing comment /"
      echo "                longer identifier), but was. Line 6 in particular"
      echo "                is the DOMINANT correct pattern in this tier:"
      printf '%s\n' "$out"
      exit 1
    fi
  done
  for ln in "${read_control_r3_lines[@]}"; do
    if ! printf '%s\n' "$out" | grep -q "^R3:$tmp/$read_control_path:$ln:"; then
      echo "SELF-TEST FAIL: $read_control_path:$ln should still be reported by"
      echo "                RULE 3 — restricting Rule 5 to $mix_scan_dir/ is"
      echo "                only sound because the E2E tier is covered by a"
      echo "                stricter rule, and this is what proves the hit is"
      echo "                not simply lost:"
      printf '%s\n' "$out"
      exit 1
    fi
  done
  if printf '%s\n' "$out" | grep -q "^R5:$tmp/$read_control_path:"; then
    echo "SELF-TEST FAIL: the integration_test/-side Rule-5 scan-root control"
    echo "                was flagged by Rule 5 — Rule 5 is not restricted to"
    echo "                $mix_scan_dir/ at all, and every hit there is now"
    echo "                double-reported under both R3 and R5:"
    printf '%s\n' "$out"
    exit 1
  fi

  # ---- RULE 6 assertions -----------------------------------------------
  for ln in "${token_offender_lines[@]}"; do
    if ! printf '%s\n' "$out" | grep -q "^R6:$tmp/$token_probe:$ln:"; then
      echo "SELF-TEST FAIL: expected a Rule-6 offender at $token_probe:$ln,"
      echo "                none found. This probe lives under lib/ — is"
      echo "                'lib' still in token_scan_dirs AND actually walked"
      echo "                by run_scan's second loop? (Line 40 pins that the"
      echo "                seam's matching ')' is found by depth tracking, not"
      echo "                by a regex that truncates at a nested call.)"
      printf '%s\n' "$out"
      exit 1
    fi
  done
  for ln in "${token_clean_lines[@]}"; do
    if printf '%s\n' "$out" | grep -q "^R6:$tmp/$token_probe:$ln:"; then
      echo "SELF-TEST FAIL: line $ln of $token_probe should NOT be flagged by"
      echo "                Rule 6 (.toUtc on a genuine instant / a LEGAL token"
      echo "                operation / calendar-field read / undeclared name /"
      echo "                date-token-ok annotated / comment / string literal /"
      echo "                longer identifier), but was:"
      printf '%s\n' "$out"
      exit 1
    fi
  done

  # ---- RULE 7 assertions -----------------------------------------------
  for ln in "${seam_offender_lines[@]}"; do
    if ! printf '%s\n' "$out" | grep -q "^R7:$tmp/$seam_probe:$ln:"; then
      echo "SELF-TEST FAIL: expected a Rule-7 offender at $seam_probe:$ln,"
      echo "                none found. This probe lives under lib/ — is 'lib'"
      echo "                still in token_scan_dirs AND actually walked by"
      echo "                run_scan's THIRD loop (the .difference( prefilter"
      echo "                one)? Line 16 is the EXACT shape that shipped in"
      echo "                relative_date.dart; line 20 pins the ARGUMENT form"
      echo "                (a gate that only checks the receiver misses half"
      echo "                the defect); line 30 pins depth-tracked paren"
      echo "                matching against a nested call in the token's own"
      echo "                argument list."
      printf '%s\n' "$out"
      exit 1
    fi
  done
  for ln in "${seam_clean_lines[@]}"; do
    if printf '%s\n' "$out" | grep -q "^R7:$tmp/$seam_probe:$ln:"; then
      echo "SELF-TEST FAIL: line $ln of $seam_probe should NOT be flagged by"
      echo "                Rule 7 (qualified constructor / TZDateTime /"
      echo "                arity 4 = an instant / literal-year token,"
      echo "                deliberately unclaimed / genuine instants / a LEGAL"
      echo "                token comparison / undeclared name / date-token-ok"
      echo "                annotated / comment / string literal / longer"
      echo "                identifier), but was. Line 44 in particular pins"
      echo "                the TZDateTime substring exclusion, and line 48"
      echo "                pins that arity is what separates Rule 7 from"
      echo "                Rule 1:"
      printf '%s\n' "$out"
      exit 1
    fi
  done
  if printf '%s\n' "$out" | grep -qE "^R[123456]:$tmp/$seam_probe:"; then
    echo "SELF-TEST FAIL: $seam_probe was flagged by Rules 1-6. It contains no"
    echo "                clock read and no .toUtc()/.toLocal(), sits outside"
    echo "                the test tiers Rules 1-5 scan, and its only arity>=4"
    echo "                DateTime( has a DERIVED first argument (which Rule 1"
    echo "                excludes) — so a hit here means a rule's scope has"
    echo "                leaked:"
    printf '%s\n' "$out"
    exit 1
  fi
  if printf '%s\n' "$out" | grep -q "^R7:$tmp/$token_probe:"; then
    echo "SELF-TEST FAIL: the RULE 6 probe was flagged by Rule 7 — it contains"
    echo "                no .difference( at all, so Rule 7's matching is"
    echo "                firing on something other than the subtraction:"
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
  echo "                RULE 4 — a host-clock read inside a SINGLE test body"
  echo "                that also pins the clock is flagged together with the"
  echo "                pin site, for BOTH pin shapes (a clockProvider"
  echo "                override, and a non-null clock:/now: argument to a"
  echo "                pump helper — the shape every real pin in this tree"
  echo "                uses); while an UNPINNED host read (the dominant and"
  echo "                correct pattern in this tier, and the row that keeps"
  echo "                this gate from being pure noise), an instant-ok"
  echo "                annotated read under a pin, an explicit clock: null,"
  echo "                a longer identifier ending in DateTime.now, and a"
  echo "                file-scope read outside any test body all stay clean."
  echo "                Both of Rule 4's originally-documented blind spots are"
  echo "                pinned closed: a pin installed in a group-level setUp"
  echo "                is now seen by a SIBLING test in that group, and a pin"
  echo "                arriving under a helper parameter named neither clock:"
  echo "                nor now: is recognised via a name DERIVED from the"
  echo "                file's own clockProvider.overrideWithValue(...) call —"
  echo "                while an UNPINNED group and the same derived name"
  echo "                passed explicitly null both stay clean."
  echo "                RULE 5 — a raw DateTime.now under $mix_scan_dir/ that"
  echo "                neither reaches the canonical seam nor is consumed as"
  echo "                an instant is flagged: a bare read into a local, into"
  echo "                an argument, a direct calendar-field read, the"
  echo "                non-canonical kyivDayOf(DateTime.now()) and"
  echo "                kyivToday(DateTime.now()) spellings, and"
  echo "                .toIso8601String() (host wall-clock output, not an"
  echo "                instant op); while kyivToday(DateTime.now), .add /"
  echo "                .subtract / .toUtc / .millisecondsSinceEpoch, an"
  echo "                instant-ok annotation, comments, string literals and a"
  echo "                longer identifier all stay clean — and the SAME shapes"
  echo "                under $now_scan_dir/ contribute no R5 while still being"
  echo "                reported by Rule 3, so no hit is lost and none is"
  echo "                double-reported."
  echo "                RULE 6 — .toUtc()/.toLocal() on a DATE TOKEN is flagged"
  echo "                both DIRECTLY on the seam call (including with a nested"
  echo "                call inside its own argument list, pinning depth-tracked"
  echo "                paren matching) and INDIRECTLY through a same-file"
  echo "                declaration in every form (typed, getter, zero-arg"
  echo "                function, untyped final, and one whose seam call wraps"
  echo "                onto following lines), including the private _dateOnly"
  echo "                re-implementations; while .toUtc() on a genuine instant,"
  echo "                a LEGAL token operation (.isBefore, calendar fields), an"
  echo "                undeclared name, a date-token-ok annotation, comments,"
  echo "                string literals and a longer identifier all stay clean."
  echo "                Its probe lives under lib/ — the one root only Rule 6"
  echo "                walks — which pins that wider scan root independently"
  echo "                of the matching logic."
  echo "                RULE 7 — a COMPONENT-DERIVED date token"
  echo "                (DateTime(x.year, x.month, x.day)) reaching"
  echo "                .difference( is flagged both DIRECTLY at the call site"
  echo "                (including with a nested call inside the token's own"
  echo "                argument list, pinning depth-tracked paren matching)"
  echo "                and INDIRECTLY through a same-file declaration, in"
  echo "                BOTH the receiver and the ARGUMENT position — the"
  echo "                receiver form is the exact shape that shipped in"
  echo "                relative_date.dart and rendered «Сьогодні» for"
  echo "                «Вчора» every March; while DateTime.utc,"
  echo "                tz.TZDateTime, an arity-4 instant (Rule 1's"
  echo "                territory, and what separates the two rules), a"
  echo "                literal-year token (deliberately unclaimed — see the"
  echo "                header's measured six-hit residue), a LEGAL token"
  echo "                comparison, an undeclared name, a date-token-ok"
  echo "                annotation, comments, string literals and a longer"
  echo "                identifier all stay clean. Its probe also lives under"
  echo "                lib/ and contributes nothing to Rules 1-6, pinning"
  echo "                that the wider root has not leaked."
  echo "SELF-TEST OK: forbid_host_local_instant_anchor.sh"
  exit 0
fi

# ---------------------------------------------------------------------------
# Real run over the working tree. No allow-list — see header.
# ---------------------------------------------------------------------------
offenders="$(run_scan "$root")"
rule1_offenders="$(printf '%s\n' "$offenders" | grep '^R1:' | sed 's/^R1://' || true)"
rule2_offenders="$(printf '%s\n' "$offenders" | grep '^R2:' | sed 's/^R2://' || true)"
rule3_offenders="$(printf '%s\n' "$offenders" | grep '^R3:' | sed 's/^R3://' || true)"
rule4_offenders="$(printf '%s\n' "$offenders" | grep '^R4:' | sed 's/^R4://' || true)"
rule5_offenders="$(printf '%s\n' "$offenders" | grep '^R5:' | sed 's/^R5://' || true)"
rule6_offenders="$(printf '%s\n' "$offenders" | grep '^R6:' | sed 's/^R6://' || true)"
rule7_offenders="$(printf '%s\n' "$offenders" | grep '^R7:' | sed 's/^R7://' || true)"

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

if [ -n "$rule4_offenders" ]; then
  failed=1
  echo "Host-clock read inside a test that PINS the clock, under $mix_scan_dir/"
  echo "(RULE 4 — clock-coherence; an entry tagged \"[this test PINS ...]\" is"
  echo "the override site, not a second independent read):"
  echo "$rule4_offenders"
  echo
  echo "This single test body both pins the app's clock (clockProvider override,"
  echo "or a non-null clock:/now: argument to a pump helper that installs one)"
  echo "AND reads the HOST clock to build a fixture. Those are two DIFFERENT"
  echo "clocks: the widget derives 'today' from the pinned instant while the"
  echo "fixture describes whatever day the machine running the suite is on, so"
  echo "the test asserts against a day the app never renders. On the dev VM"
  echo "(TZ=Europe/Kyiv, the business zone) this is invisible whenever the two"
  echo "happen to coincide, which is exactly why it has recurred four times."
  echo
  echo "Derive the fixture from the SAME instant the test pins:"
  echo "    final DateTime pinned = DateTime.utc(2026, 6, 14, 12);"
  echo "    ... clockProvider.overrideWithValue(() => pinned) ..."
  echo "    final DateTime today = kyivToday(() => pinned);   // fixture agrees"
  echo
  echo "The other consistent option is to pin NOTHING and let both sides read"
  echo "the real clock — which is what most of this tier already does, via"
  echo "kyivToday(DateTime.now). Either is fine; MIXING them is the bug."
  echo
  echo "If this read is a genuine elapsed-wall-time use (a timeout, a duration"
  echo "measurement) that the pinned clock is irrelevant to, annotate it:"
  echo "    // instant-ok: <why the DEVICE clock is correct despite the pin>"
  echo
  echo "There is no allow-list for this gate and none should be added."
  echo
fi

if [ -n "$rule5_offenders" ]; then
  failed=1
  echo "Raw device-clock read that neither goes through the Kyiv-day seam nor"
  echo "is consumed as an instant, under $mix_scan_dir/ (RULE 5):"
  echo "$rule5_offenders"
  echo
  echo "This tier has no single injected clock, so reading the DEVICE clock is"
  echo "often exactly right — but only when the fixture lands on the same KYIV"
  echo "calendar day the widget derives from that same clock. A bare"
  echo "DateTime.now().month / .day / .year is the DEVICE's calendar, which"
  echo "differs from Kyiv's for part of every 24h window on any non-Kyiv host."
  echo
  echo "Say which one this read is, at the read site:"
  echo "    final DateTime today = kyivToday(DateTime.now);   // a KYIV calendar day"
  echo "    DateTime.now().add(const Duration(days: 2))       // an INSTANT"
  echo "    DateTime.now().toUtc().subtract(...)              // an INSTANT"
  echo
  echo "kyivToday(DateTime.now) — the TEAR-OFF form — is the single canonical"
  echo "spelling under $mix_scan_dir/. kyivToday(DateTime.now()) and"
  echo "kyivDayOf(DateTime.now()) are deliberately NOT accepted: they mean the"
  echo "same thing and the normalisation pass removed them, so a hit on either"
  echo "is a spelling to fix, not a false positive."
  echo
  echo "If this read is a genuine absolute-instant use that no zone conversion"
  echo "would change — a duration measurement, an elapsed-wall-time bracket —"
  echo "annotate it with the same marker Rules 3 and 4 use:"
  echo "    // instant-ok: <why the DEVICE clock is correct here>"
  echo
  echo "There is no allow-list for this gate and none should be added."
  echo
fi

if [ -n "$rule6_offenders" ]; then
  failed=1
  echo ".toUtc()/.toLocal() applied to a DATE TOKEN, under ${token_scan_dirs[*]}"
  echo "(RULE 6 — the only rule here that also scans lib/):"
  echo "$rule6_offenders"
  echo
  echo "kyivToday(...) / kyivDayOf(...) / dateOnly(...) return a DATE TOKEN, not"
  echo "an instant: a host-local DateTime sitting at host-local MIDNIGHT whose"
  echo ".year/.month/.day carry the KYIV calendar day. lib/shared/time/"
  echo "kyiv_day.dart's header lists .toUtc() on such a value as explicitly"
  echo "ILLEGAL — 'there is no meaningful UTC form of a value that was never"
  echo "really an instant; the call compiles, runs, and returns garbage.'"
  echo
  echo "What it actually computes is 'host-local midnight on that day, expressed"
  echo "as UTC', which shifts with the HOST's zone. token.toUtc().add(12h) lands"
  echo "inside the intended Kyiv day from Kyiv/UTC/Tokyo but rolls a day FORWARD"
  echo "from any western host (UTC-10: midnight local is 10:00Z, +12h = 22:00Z,"
  echo "already the next Kyiv day)."
  echo
  echo "Rebuild the instant from the token's calendar fields instead:"
  echo "    asClockInstant(dayToken)                       // test/helpers/clock_instant.dart — noon UTC on that day"
  echo "    DateTime.utc(d.year, d.month, d.day, hourUtc)  // when a specific hour is needed"
  echo "    tz.TZDateTime(beauticaZone, d.year, d.month, d.day, h).toUtc()  // a specific KYIV wall time"
  echo
  echo "If performing the banned operation is genuinely the subject here (there"
  echo "is exactly ONE such place in this tree — kyiv_day_test.dart's runnable"
  echo "demonstration that it returns garbage), annotate it:"
  echo "    // date-token-ok: <why treating a Kyiv day token as an instant is correct here>"
  echo
  echo "There is no allow-list for this gate and none should be added."
  echo
fi

if [ -n "$rule7_offenders" ]; then
  failed=1
  echo "DATE TOKEN subtracted with .difference(), under ${token_scan_dirs[*]}"
  echo "(RULE 7 — the second rule here that also scans lib/):"
  echo "$rule7_offenders"
  echo
  echo "DateTime(x.year, x.month, x.day) is a DATE TOKEN — a HOST-LOCAL"
  echo "DateTime at host-local MIDNIGHT whose .year/.month/.day carry a"
  echo "calendar day. DateTime.difference measures elapsed ABSOLUTE time, so"
  echo "when the HOST zone crosses a DST transition between the two midnights"
  echo "the span is 23 h (spring forward) or 25 h (fall back) and .inDays"
  echo "truncates toward zero — silently returning ONE DAY FEWER than the"
  echo "calendar spans. Fall-back is benign (25 h still truncates to 1), which"
  echo "is precisely what makes the spring-forward half so easy to miss."
  echo
  echo "This shipped: lib/shared/formatters/relative_date.dart counted this way"
  echo "until Phase 284, so on a Europe/Kyiv device — the market's own, i.e."
  echo "most installs — a review or invite from 29 March rendered «Сьогодні»"
  echo "on 30 March, every year. RULE 1 waved it through because it requires"
  echo "arity >= 4 AND a literal-digit first argument; this construction is"
  echo "arity 3 with a component read, and misses on both counts."
  echo
  echo "Subtract through the sanctioned helper instead:"
  echo "    kyivDaysBetween(earlierToken, laterToken)  // lib/shared/time/kyiv_day.dart"
  echo "It re-anchors both tokens at UTC midnight first. UTC observes no"
  echo "transitions, so every calendar day there is uniformly 24 h and the"
  echo "count is exact. (calendarDayCount in bookings_day_rail.dart is a"
  echo "delegating alias of it — do not write a third implementation.)"
  echo
  echo "If performing the banned subtraction is genuinely the subject here —"
  echo "e.g. a runnable demonstration that it returns the wrong answer —"
  echo "annotate it with the same marker Rule 6 uses:"
  echo "    // date-token-ok: <why subtracting a Kyiv day token raw is correct here>"
  echo
  echo "There is no allow-list for this gate and none should be added."
  echo
fi

if [ "$failed" -eq 1 ]; then
  exit 1
fi

exit 0

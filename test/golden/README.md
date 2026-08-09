# Golden Test Suite — Phase 17.4

Pixel-level regression guard for high-risk / high-traffic screens across phone widths and text scales.

## Quick reference

| Command | Purpose |
|---|---|
| `flutter test test/golden/` | Run all goldens — MUST pass (byte-stable). |
| `flutter test --update-goldens test/golden/` | Re-bless masters after an intentional design change. |
| `flutter test --update-goldens test/golden/auth_login_golden_test.dart` | Re-bless a single screen. |

## Matrix

Every golden covers: **{320, 360, 414} dp × {textScale 1.0, 1.3}**

| Test file | Screens / widgets goldened | PNGs |
|---|---|---|
| `auth_login_golden_test.dart` | LoginScreen | 6 |
| `auth_register_golden_test.dart` | RegisterStep1Screen, RegisterStep2Screen (INDEPENDENT_MASTER + SALON_OWNER) | 18 |
| `services_pricing_field_golden_test.dart` | PricingField (FIXED + RANGE) | 12 |
| `services_form_golden_test.dart` | ServiceForm (CREATE + EDIT) | 12 |
| `calendar_working_hours_golden_test.dart` | WorkingHoursScreen (LOADED + LOADING) | 12 |
| `master_profile_golden_test.dart` | MasterProfileScreen (DATA) | 6 |
| `error_state_golden_test.dart` | shared ErrorState (4 failure variants + no-retry) + ResultsError (2 variants) | 7 |
| `velvet_snack_golden_test.dart` | VelvetSnack (4 variants + action+close combo), single 360dp width | 5 |
| `passport_golden_test.dart` | PassportScreen (DATA + NO HISTORY) — identity strip, derived block, wish-list line/empty card | 12 |

**Total: 90 goldens**

> `passport_golden_test.dart`'s baselines are a DRIFT GUARD, not acceptance. They encode a
> known divergence from the approved preview in `PassportIdentityStrip`'s blush gradient
> (axis, stop count and highlight colour) — see that file's header. Re-bless once the design
> owner settles it.

Masters live in `test/golden/goldens/` and are committed to git.

## Alchemist CI mode

All goldens use **alchemist CI mode** (`obscureText: true`, `renderShadows: false`):

- Text is rendered as coloured blocks — byte-identical across Linux, macOS, Windows runners.
- Shadows are disabled — no inter-version blending drift.
- The global config is set in `test/flutter_test_config.dart` via `AlchemistConfig.runWithConfig`.

## How to re-bless (runbook)

A re-bless is needed when a screen's visual design changes intentionally (not a bug).

**Steps:**

1. Confirm the change is intentional by reviewing the PR diff for the affected widget/screen.
2. Run the update on the **same OS / Flutter version that CI uses** (Ubuntu, Flutter 3.41.x stable):
   ```bash
   flutter test --update-goldens test/golden/<file>_golden_test.dart
   ```
   Or for the entire suite:
   ```bash
   flutter test --update-goldens test/golden/
   ```
3. Review each changed PNG in the git diff. Confirm only the expected pixels changed.
4. Commit the updated PNGs as part of the same PR as the design change:
   ```bash
   git add test/golden/goldens/
   git commit -m "test(goldens): re-bless after <description of visual change>"
   ```
5. Push and verify CI passes with the new masters.

**Never re-bless blindly after a CI failure** — investigate the diff first.  
Golden diffs from failed CI runs are downloadable from the workflow's artifact tab
(`golden-failure-diffs` artifact — uploaded on failure only).

## Clock determinism

Screens that render dates inject a **fixed clock** via `clockProvider.overrideWithValue(...)`.
Currently, none of the goldened screens render date-dependent UI (working hours is a weekly
template, not a specific date). If a date-rendering screen is added to this suite,
override the clock to `DateTime.utc(2026, 6, 13)` (Phase 17.4 anchor date) to prevent drift.

## Existing schedule goldens

The schedule goldens under `test/features/schedule/presentation/goldens/` predate this suite
and use `matchesGoldenFile` directly (not alchemist). They render at a single device size.
They remain as-is (not migrated) to avoid scope creep; see `mobile-backlog.md` line 128
for the tracked stabilization ticket.

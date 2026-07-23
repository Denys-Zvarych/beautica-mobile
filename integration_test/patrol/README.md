# patrol native E2E (Phase 17.5)

Native-interaction E2E tests driven by [`patrol`](https://pub.dev/packages/patrol)
`4.6.x`. These cover what `integration_test` cannot reach: OS-level deep-link
intents, permission dialogs, notifications, and WebViews via `$.native.*`.

## What lives here

| File | Kind | Runnable today? |
|---|---|---|
| `auth_login_patrol_test.dart` | Ported template (fake backend) | Yes — porting reference for converting an `integration_test` flow to a patrol binding |
| `deep_link_patrol_test.dart` | Native: deep link → `/invite/accept` | Yes — real `ACTION_VIEW` App Link intent |
| `deep_link_patrol_test.dart` (FCM cases) | Native: FCM tap-through + notification permission | **No — skip-marked**; Firebase push is deferred (`FIREBASE_ENABLED=false`). Enable when Phase 8.x FCM lands |
| `support/patrol_harness.dart` | Boot helper (fake backend) for the template | — |

The pure-Flutter flows stay under `integration_test/*.dart` and run on the FAST
headless job via `flutter test integration_test/all_tests.dart`. The aggregator
(`integration_test/all_tests.dart`) does **not** import anything under
`integration_test/patrol/`, so the fast path is unaffected by this folder.

## These tests do NOT run under `flutter test`

patrol native tests require native instrumentation (`PatrolJUnitRunner`) and a
real Android emulator/device. They are driven by the `patrol_cli` global tool —
**not** `flutter test`, and **not** on the Ubuntu dev VM (the emulator lives on
the Windows host and patrol needs native instrumentation the VM can't provide).
The authoritative runtime gate is the **CI patrol emulator job** in
`.github/workflows/pr-validate.yml`.

## Running locally (against a connected emulator)

```bash
# 1. Install the patrol CLI (global tool — intentionally NOT a repo dependency).
dart pub global activate patrol_cli

# 2. Make sure an Android emulator/device is connected.
#    On this project, bridge the Windows-host emulator first:
./scripts/connect_adb.sh
flutter devices            # confirm a device is listed

# 3. Run all patrol targets under this folder.
patrol test --target integration_test/patrol

# Or a single patrol target (single-file form).
patrol test --target integration_test/patrol/deep_link_patrol_test.dart
```

> `--target integration_test/patrol` is required: `pubspec.yaml` sets
> `patrol: test_directory: integration_test`, so a bare `patrol test` would also
> pick up the non-patrol `testWidgets` flows that live directly under
> `integration_test/`. Always scope to the `patrol` subfolder.

> **patrol test descriptions must not contain `/`** (it breaks the AndroidX Test
> Orchestrator's per-test output filename — `File ...txt contains a path
> separator`). Use route assertions inside the test, never `/` in the test name.

`patrol test` builds the `androidTest` variant (PatrolJUnitRunner +
ANDROIDX_TEST_ORCHESTRATOR — configured in `android/app/build.gradle.kts`),
installs the app + test APKs, enumerates the Dart `patrolTest(...)` cases via
`MainActivityTest.java`, and drives each on-device.

## Native config touch-points (do not remove)

- `pubspec.yaml` → `patrol:` block (`android.package_name` must equal the
  `applicationId` in `android/app/build.gradle.kts`).
- `android/app/build.gradle.kts` → `testInstrumentationRunner`,
  `testInstrumentationRunnerArguments["clearPackageData"]`, `testOptions {
  execution = "ANDROIDX_TEST_ORCHESTRATOR" }`, core library desugaring, and the
  `androidTestUtil` orchestrator dependency.
- `android/app/src/androidTest/java/com/beautica/beautica_mobile/MainActivityTest.java`
  — the JUnit ↔ Dart bridge. Must be in the app package so `MainActivity.class`
  resolves.

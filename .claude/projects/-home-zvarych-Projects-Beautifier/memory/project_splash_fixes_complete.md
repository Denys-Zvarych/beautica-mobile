---
name: project-splash-fixes-complete
description: Phase 2.15 splash screen AOT crash + HIGH-2 PNG bloat + MEDIUM-1 constant duplication — all resolved and committed
metadata:
  type: project
---

## Phase 2.15 splash-screen fix cycle — COMPLETE (2026-05-26)

Commit: `b9cf2cf` on `feat/phase-2.x-auth` in `beautica-mobile/`

### What was fixed
1. **AOT animation race** — `addPostFrameCallback` → `initState` for `_wordmarkController.forward()`; go_router was navigating away before callback fired in release mode
2. **AppStartTime 950ms gate** — parks router on /splash until 950ms elapsed; `_onAnimationStatus` calls `GoRouter.refresh()` after remainder; prevents synchronous auth bypass of splash in release AOT
3. **HIGH-2 (PNG bloat)** — drawable PNGs 725KB → 309KB via PIL `optimize=True, compress_level=9`; `optimize_drawables()` added to `generate_splash_logo.py`
4. **MEDIUM-1 (constant duplication)** — `AppStartTime.minSplashDuration = Duration(milliseconds: 950)` is the single source; `auth_redirect.dart` and `splash_screen.dart` both reference it
5. **MS6 ProGuard** — added `screen_protector` keep rule to `proguard-rules.pro`
6. **CormorantGaramond crash** — replaced with `GoogleFonts.comfortaa()` in `registration_progress.dart`; font not bundled with `allowRuntimeFetching=false`
7. **GoogleFonts.config.allowRuntimeFetching = false** — always set, not guarded by `kDebugMode`

### Test state
- `splash_screen_test.dart` 12/12
- `auth_redirect_test.dart` 37/37
- `app_start_time_test.dart` 5/5 (NEW)
- All 395 auth+routing tests pass

### Audit scores
- Perf: 94/100 (up from 90 pre-fix)
- Security: 97/100
- QA: 89/100

### Remaining LOW items (in backlog)
- `_onAnimationStatus` / Timer GoRouter-wired test missing (test 13)
- Test 5 magic 880ms coupling to `_animDuration`
- `RepaintBoundary` around animated logo in `SplashScreen.build()`
- `VelvetLogo.build()` `markStyle` copyWith allocation

# Splash wordmark Lottie animation

Drop a Lottie `.json` file at this path:

    assets/lottie/splash_wordmark.json

The Flutter SplashScreen will automatically detect and render it via
`Lottie.asset(...)` when the file exists. Until then, the splash shows a
static "B pillow + beautica" composite (the same one baked into the
native splash PNG) and routes to /login after the minSplashDuration
gate (currently 2000 ms).

## Design spec for the animation

- **Canvas**: 400 × 80 (logical px). Fits below the B pillow with comfortable margin.
- **Text**: "beautica" (lowercase, 8 letters)
- **Font**: Comfortaa Bold (weight 700). Source TTF: `assets/fonts/Comfortaa-Bold.ttf`.
- **Color**: `#4A3322` (`BrandColors.text`, WCAG-AA compliant on `#E6DDD0` warm-taupe background).
- **Font size**: 17 px (= 17/92 of the B pillow size, matching the design).
- **Letter spacing**: 2.72 px (`fontSize × 0.16`).
- **Per-letter animation**:
  - Opacity: 0 → 1 over 250 ms (easeOut).
  - Position Y: +8 px → 0 px over 250 ms (easeOut). The letter slides up into place.
- **Stagger**: 90 ms between consecutive letter starts.
- **Total duration**: 90 ms × 7 + 250 ms = **880 ms**.
- **Frame rate**: 60 fps recommended.

## Where to create the file

Three options:
1. **After Effects**: animate letter-by-letter, export with [Bodymovin](https://aescripts.com/bodymovin/).
2. **LottieFiles editor** ([lottiefiles.com/editor](https://app.lottiefiles.com/editor)) — browser-based, free for simple text reveals.
3. **Figma** with the [LottieFiles plugin](https://www.lottiefiles.com/plugins/figma).

## Wire-up

No further code changes needed once the JSON is at the right path. The Flutter splash auto-detects the file at startup via `rootBundle.load()`; if it loads successfully the Lottie widget renders, if it throws `FileNotFoundException` the static fallback renders.

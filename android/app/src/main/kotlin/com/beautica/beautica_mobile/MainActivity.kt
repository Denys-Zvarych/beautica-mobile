package com.beautica.beautica_mobile

import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // PRODUCT DECISION 2026-08-20 — SCREENSHOTS ARE ALLOWED. DO NOT RE-ADD FLAG_SECURE.
        //
        // WHAT USED TO BE HERE: `window.setFlags(FLAG_SECURE, FLAG_SECURE)` on every
        // non-debug build, blocking screenshots, screen recording and casting app-wide.
        // It cited MASVS-PLATFORM MS6 / mobile-security finding MS-4.
        //
        // WHY IT IS GONE: that flag was introduced by a SECURITY AUDIT, never by a
        // product decision, and its product cost was never weighed. Beautica is a beauty
        // discovery/booking marketplace: sharing what you found IS the growth loop.
        // FLAG_SECURE stopped a user screenshotting their own booking confirmation,
        // sharing a master's profile or a result photo with a friend, saving a price
        // list, attaching a screenshot to a support request, or casting the app.
        // The user weighed capture-blocking against sharing on 2026-08-20 and chose
        // sharing. This is a deliberate, accepted risk — not an oversight.
        //
        // WHAT IS RETAINED: the Recents / task-switcher thumbnail is still blanked.
        // That is a real leak to anyone who picks up an unlocked phone, and — unlike
        // FLAG_SECURE — it can be blanked WITHOUT blocking the user's own captures.
        // The iOS equivalent (app-switcher snapshot blur) is kept in
        // `lib/core/security/screen_protection.dart`.
        //
        // TO A FUTURE SECURITY AUDITOR: filing MASVS-PLATFORM MS6 / MS-4 against this
        // file again is a re-litigation of a settled decision. It is WON'T FIX. Raise
        // it with the user as a product question, do not re-land FLAG_SECURE.
        //
        // API FLOOR: `Activity.setRecentsScreenshotEnabled` is API 33 (verified against
        // platforms/android-36 `data/api-versions.xml`, since="33"), while minSdk is 26,
        // so the guard below is REQUIRED. On API 26–32 the ONLY way to blank the Recents
        // thumbnail is FLAG_SECURE, which would also block user screenshots — so those
        // devices deliberately get no Recents blanking. Accepted as part of the same
        // trade-off.
        //
        // Applied unconditionally, debug included: blanking the task-switcher thumbnail
        // costs a developer nothing (screen recording and `adb screencap` still work),
        // so the old BuildConfig.DEBUG exemption no longer earns its keep.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            setRecentsScreenshotEnabled(false)
        }
    }
}

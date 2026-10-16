package com.beautica.beautica_mobile

import android.os.Build
import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Audit L1 — logout clears the notification tray (previous user's pushes).
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.beautica.beautica_mobile/notification_tray",
        ).setMethodCallHandler { call, result ->
            if (call.method == "cancelAll") {
                try {
                    (getSystemService(NOTIFICATION_SERVICE) as? NotificationManager)?.cancelAll()
                    result.success(null)
                } catch (e: Exception) {
                    result.error("tray", e.javaClass.simpleName, null)
                }
            } else if (call.method == "openNotificationSettings") {
                // «Акаунт» → «Сповіщення» switch: an app cannot grant or revoke its
                // own notification permission, so the switch opens the OS screen.
                try {
                    openNotificationSettings()
                    result.success(null)
                } catch (e: Exception) {
                    result.error("settings", e.javaClass.simpleName, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    // Opens Android's per-app notification settings for Beautica (API 26+, which
    // is minSdk — no pre-O branch needed). Falls back to the app-details screen
    // when an OEM build resolves no activity for ACTION_APP_NOTIFICATION_SETTINGS.
    private fun openNotificationSettings() {
        val notifications = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        try {
            startActivity(notifications)
        } catch (e: ActivityNotFoundException) {
            startActivity(
                Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.fromParts("package", packageName, null),
                ),
            )
        }
    }

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

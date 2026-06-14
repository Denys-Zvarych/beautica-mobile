package com.beautica.beautica_mobile

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Prevent screenshots and screen recording — protects booking/payment
        // screens from appearing in the system task switcher thumbnail and from
        // third-party screen-capture tools (MASVS-PLATFORM MS6 / mobile-security MS-4).
        //
        // Debug builds skip FLAG_SECURE so developers can screen-record demos
        // on their device. Release and profile builds always enforce this flag.
        if (!BuildConfig.DEBUG) {
            window.setFlags(
                WindowManager.LayoutParams.FLAG_SECURE,
                WindowManager.LayoutParams.FLAG_SECURE,
            )
        }
    }
}

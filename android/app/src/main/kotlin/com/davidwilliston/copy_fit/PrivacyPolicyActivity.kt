package com.davidwilliston.copy_fit

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Bundle

/**
 * Health Connect opens this when someone asks to read Copy Fit's privacy policy
 * from its permission screen. It hands the policy's URL to the browser and
 * closes without drawing anything.
 *
 * The browser does the fetching, so the app itself still needs no internet
 * permission — which is the central claim of the policy it opens.
 */
class PrivacyPolicyActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(PRIVACY_URL)))
        } catch (_: ActivityNotFoundException) {
            // No browser installed. There is nothing sensible to show instead.
        }
        finish()
    }

    companion object {
        // Served from website/content/privacy.md. If the site moves, change it here.
        const val PRIVACY_URL = "https://david-williston.github.io/copy-fit/privacy/"
    }
}

package com.visionclaw.android

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.visionclaw.android.ui.navigation.NavGraph
import com.visionclaw.android.ui.theme.VisionClawTheme
import dagger.hilt.android.AndroidEntryPoint

@AndroidEntryPoint
class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        handleDatCallback(intent)
        setContent {
            VisionClawTheme {
                NavGraph()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleDatCallback(intent)
    }

    /**
     * Handle deep link callbacks from Meta AI app during DAT SDK registration.
     * Equivalent to iOS RegistrationView.onOpenURL.
     */
    private fun handleDatCallback(intent: Intent?) {
        val uri = intent?.data ?: return
        val hasWearablesAction = uri.getQueryParameter("metaWearablesAction") != null
        if (!hasWearablesAction) return
        // The DAT SDK will pick up the callback URL via its internal handler.
        // If additional manual handling is needed, it can be done here.
        android.util.Log.i("VisionClaw", "DAT callback received: $uri")
    }
}

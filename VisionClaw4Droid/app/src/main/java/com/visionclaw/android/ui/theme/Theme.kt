package com.visionclaw.android.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable

private val LightColorScheme = lightColorScheme(
    primary = AppPrimary,
    onPrimary = androidx.compose.ui.graphics.Color.White,
    error = DestructiveForeground,
)

@Composable
fun VisionClawTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = LightColorScheme,
        typography = VisionClawTypography,
        content = content,
    )
}

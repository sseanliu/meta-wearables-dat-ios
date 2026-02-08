package com.visionclaw.android.ui.components

import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.visionclaw.android.service.gemini.GeminiLiveService
import com.visionclaw.android.service.gemini.ToolCallStatus
import com.visionclaw.android.ui.theme.*

// ---- GeminiStatusBar ----

@Composable
fun GeminiStatusBar(
    connectionState: GeminiLiveService.ConnectionState,
) {
    val (statusColor, statusText) = when (connectionState) {
        GeminiLiveService.ConnectionState.READY -> StatusGreen to "AI Active"
        GeminiLiveService.ConnectionState.CONNECTING,
        GeminiLiveService.ConnectionState.SETTING_UP -> StatusYellow to "Connecting..."
        GeminiLiveService.ConnectionState.ERROR -> StatusRed to "Error"
        GeminiLiveService.ConnectionState.DISCONNECTED -> StatusGray to "Disconnected"
    }

    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .clip(RoundedCornerShape(16.dp))
            .background(Color.Black.copy(alpha = 0.6f))
            .padding(horizontal = 12.dp, vertical = 6.dp),
    ) {
        Box(
            modifier = Modifier
                .size(8.dp)
                .clip(CircleShape)
                .background(statusColor)
        )
        Spacer(modifier = Modifier.width(6.dp))
        Text(
            text = statusText,
            color = Color.White,
            fontSize = 12.sp,
            fontWeight = FontWeight.Medium,
        )
    }
}

// ---- TranscriptView ----

@Composable
fun TranscriptView(
    userText: String,
    aiText: String,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(Color.Black.copy(alpha = 0.6f))
            .padding(horizontal = 16.dp, vertical = 10.dp),
        horizontalAlignment = Alignment.Start,
    ) {
        if (userText.isNotEmpty()) {
            Text(
                text = userText,
                color = Color.White.copy(alpha = 0.7f),
                fontSize = 14.sp,
            )
        }
        if (aiText.isNotEmpty()) {
            Text(
                text = aiText,
                color = Color.White,
                fontSize = 16.sp,
                fontWeight = FontWeight.Medium,
            )
        }
    }
}

// ---- ToolCallStatusView ----

@Composable
fun ToolCallStatusView(status: ToolCallStatus) {
    if (status is ToolCallStatus.Idle) return

    val bgColor = when (status) {
        is ToolCallStatus.Executing -> Color.Black.copy(alpha = 0.7f)
        is ToolCallStatus.Completed -> Color.Black.copy(alpha = 0.6f)
        is ToolCallStatus.Failed -> Color.Red.copy(alpha = 0.3f)
        is ToolCallStatus.Cancelled -> Color.Black.copy(alpha = 0.6f)
        else -> Color.Transparent
    }

    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .clip(RoundedCornerShape(16.dp))
            .background(bgColor)
            .padding(horizontal = 14.dp, vertical = 8.dp),
    ) {
        when (status) {
            is ToolCallStatus.Executing -> {
                CircularProgressIndicator(
                    modifier = Modifier.size(14.dp),
                    color = Color.White,
                    strokeWidth = 2.dp,
                )
            }
            is ToolCallStatus.Completed -> {
                Icon(Icons.Default.CheckCircle, null, tint = StatusGreen, modifier = Modifier.size(14.dp))
            }
            is ToolCallStatus.Failed -> {
                Icon(Icons.Default.Error, null, tint = StatusRed, modifier = Modifier.size(14.dp))
            }
            is ToolCallStatus.Cancelled -> {
                Icon(Icons.Default.Cancel, null, tint = StatusYellow, modifier = Modifier.size(14.dp))
            }
            else -> {}
        }
        Spacer(modifier = Modifier.width(8.dp))
        Text(
            text = status.displayText,
            color = Color.White,
            fontSize = 13.sp,
            fontWeight = FontWeight.Medium,
            maxLines = 1,
        )
    }
}

// ---- SpeakingIndicator ----

@Composable
fun SpeakingIndicator() {
    val infiniteTransition = rememberInfiniteTransition(label = "speaking")

    Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
        repeat(4) { index ->
            val height by infiniteTransition.animateFloat(
                initialValue = 6f,
                targetValue = 20f,
                animationSpec = infiniteRepeatable(
                    animation = tween(300, easing = EaseInOut, delayMillis = index * 100),
                    repeatMode = RepeatMode.Reverse,
                ),
                label = "bar$index",
            )
            Box(
                modifier = Modifier
                    .width(3.dp)
                    .height(height.dp)
                    .clip(RoundedCornerShape(1.5.dp))
                    .background(Color.White)
            )
        }
    }
}

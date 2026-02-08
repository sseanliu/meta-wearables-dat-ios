package com.visionclaw.android.ui.screens

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.visionclaw.android.service.gemini.GeminiLiveService
import com.visionclaw.android.service.gemini.ToolCallStatus
import com.visionclaw.android.ui.components.*
import com.visionclaw.android.viewmodel.GeminiSessionViewModel
import com.visionclaw.android.viewmodel.StreamSessionViewModel
import kotlinx.coroutines.launch

/**
 * Active streaming screen with video feed, Gemini overlay, and controls.
 * Equivalent to iOS StreamView.swift.
 */
@Composable
fun StreamContent(
    streamVM: StreamSessionViewModel,
    geminiVM: GeminiSessionViewModel,
) {
    val currentFrame by streamVM.currentVideoFrame.collectAsState()
    val hasFirstFrame by streamVM.hasReceivedFirstFrame.collectAsState()
    val streamingMode by streamVM.streamingMode.collectAsState()

    val isGeminiActive by geminiVM.isGeminiActive.collectAsState()
    val connectionState by geminiVM.connectionState.collectAsState()
    val isModelSpeaking by geminiVM.isModelSpeaking.collectAsState()
    val userTranscript by geminiVM.userTranscript.collectAsState()
    val aiTranscript by geminiVM.aiTranscript.collectAsState()
    val toolCallStatus by geminiVM.toolCallStatus.collectAsState()
    val geminiError by geminiVM.errorMessage.collectAsState()

    val scope = rememberCoroutineScope()

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black),
    ) {
        // Video feed
        if (currentFrame != null && hasFirstFrame) {
            Image(
                bitmap = currentFrame!!.asImageBitmap(),
                contentDescription = "Camera feed",
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        } else {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center,
            ) {
                CircularProgressIndicator(
                    color = Color.White,
                    modifier = Modifier.size(48.dp),
                )
            }
        }

        // Gemini overlay
        if (isGeminiActive) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .systemBarsPadding()
                    .padding(24.dp),
            ) {
                // Status bar (top)
                GeminiStatusBar(connectionState = connectionState)

                Spacer(modifier = Modifier.weight(1f))

                // Transcripts + tool status + speaking indicator (bottom, above controls)
                Column(
                    modifier = Modifier.padding(bottom = 80.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    if (userTranscript.isNotEmpty() || aiTranscript.isNotEmpty()) {
                        TranscriptView(userText = userTranscript, aiText = aiTranscript)
                    }

                    ToolCallStatusView(status = toolCallStatus)

                    if (isModelSpeaking) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier
                                .clip(RoundedCornerShape(20.dp))
                                .background(Color.Black.copy(alpha = 0.5f))
                                .padding(horizontal = 16.dp, vertical = 8.dp),
                        ) {
                            Icon(
                                Icons.Default.VolumeUp,
                                contentDescription = null,
                                tint = Color.White,
                                modifier = Modifier.size(14.dp),
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            SpeakingIndicator()
                        }
                    }
                }
            }
        }

        // Bottom controls
        Column(
            modifier = Modifier
                .fillMaxSize()
                .systemBarsPadding()
                .padding(24.dp),
            verticalArrangement = Arrangement.Bottom,
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                // Stop streaming button
                Box(modifier = Modifier.weight(1f)) {
                    CustomButton(
                        title = "Stop streaming",
                        style = ButtonStyle.DESTRUCTIVE,
                        onClick = { streamVM.stopStreaming() },
                    )
                }

                // Photo button (glasses mode only)
                if (streamingMode == StreamSessionViewModel.StreamingMode.GLASSES) {
                    CircleButton(
                        icon = Icons.Default.CameraAlt,
                        onClick = { streamVM.capturePhoto() },
                    )
                }

                // Gemini AI toggle
                CircleButton(
                    icon = if (isGeminiActive) Icons.Default.GraphicEq else Icons.Default.Mic,
                    text = "AI",
                ) {
                    scope.launch {
                        if (isGeminiActive) {
                            geminiVM.stopSession()
                        } else {
                            geminiVM.startSession()
                        }
                    }
                }
            }
        }
    }

    // Gemini error dialog
    if (geminiError != null) {
        AlertDialog(
            onDismissRequest = { geminiVM.clearError() },
            title = { Text("AI Assistant") },
            text = { Text(geminiError ?: "") },
            confirmButton = {
                TextButton(onClick = { geminiVM.clearError() }) { Text("OK") }
            },
        )
    }
}

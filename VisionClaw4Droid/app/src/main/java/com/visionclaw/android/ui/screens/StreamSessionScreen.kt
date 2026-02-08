package com.visionclaw.android.ui.screens

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.*
import androidx.hilt.navigation.compose.hiltViewModel
import com.visionclaw.android.viewmodel.GeminiSessionViewModel
import com.visionclaw.android.viewmodel.StreamSessionViewModel
import com.visionclaw.android.viewmodel.WearablesViewModel

/**
 * Top-level stream session screen. Shows either NonStreamContent or StreamContent.
 * Equivalent to iOS StreamSessionView.swift.
 */
@Composable
fun StreamSessionScreen(
    wearablesVM: WearablesViewModel,
    onDisconnected: () -> Unit,
    streamVM: StreamSessionViewModel = hiltViewModel(),
    geminiVM: GeminiSessionViewModel = hiltViewModel(),
) {
    val streamingStatus by streamVM.streamingStatus.collectAsState()
    val showError by streamVM.showError.collectAsState()
    val errorMsg by streamVM.errorMessage.collectAsState()
    val streamingMode by streamVM.streamingMode.collectAsState()

    // Wire Gemini VM to Stream VM
    LaunchedEffect(Unit) {
        streamVM.geminiSessionVM = geminiVM
    }

    // Sync streaming mode
    LaunchedEffect(streamingMode) {
        geminiVM.streamingMode = when (streamingMode) {
            StreamSessionViewModel.StreamingMode.PHONE -> streamingMode
            StreamSessionViewModel.StreamingMode.GLASSES -> streamingMode
        }
    }

    if (streamingStatus != StreamSessionViewModel.StreamingStatus.STOPPED) {
        StreamContent(
            streamVM = streamVM,
            geminiVM = geminiVM,
        )
    } else {
        NonStreamContent(
            streamVM = streamVM,
            wearablesVM = wearablesVM,
            onDisconnected = onDisconnected,
        )
    }

    // Error alert
    if (showError) {
        AlertDialog(
            onDismissRequest = { streamVM.dismissError() },
            title = { Text("Error") },
            text = { Text(errorMsg) },
            confirmButton = {
                TextButton(onClick = { streamVM.dismissError() }) { Text("OK") }
            },
        )
    }
}

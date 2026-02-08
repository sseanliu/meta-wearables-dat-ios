package com.visionclaw.android.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.outlined.HourglassEmpty
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.visionclaw.android.ui.components.ButtonStyle
import com.visionclaw.android.ui.components.CustomButton
import com.visionclaw.android.viewmodel.StreamSessionViewModel
import com.visionclaw.android.viewmodel.WearablesViewModel

/**
 * Pre-streaming screen with start buttons.
 * Equivalent to iOS NonStreamView.swift.
 */
@Composable
fun NonStreamContent(
    streamVM: StreamSessionViewModel,
    wearablesVM: WearablesViewModel,
    onDisconnected: () -> Unit,
) {
    val hasActiveDevice by streamVM.hasActiveDevice.collectAsState()
    val regState by wearablesVM.registrationState.collectAsState()
    val lifecycleOwner = LocalLifecycleOwner.current
    var showMenu by remember { mutableStateOf(false) }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .systemBarsPadding(),
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(24.dp),
        ) {
            // Settings menu (top-right)
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End,
            ) {
                Box {
                    IconButton(onClick = { showMenu = true }) {
                        Icon(
                            Icons.Default.Settings,
                            contentDescription = "Settings",
                            tint = Color.White,
                            modifier = Modifier.size(24.dp),
                        )
                    }
                    DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
                        DropdownMenuItem(
                            text = { Text("Disconnect", color = Color.Red) },
                            enabled = regState == WearablesViewModel.RegState.REGISTERED,
                            onClick = {
                                showMenu = false
                                wearablesVM.disconnectGlasses()
                                onDisconnected()
                            },
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.weight(1f))

            // Center content
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Icon(
                    imageVector = Icons.Outlined.Visibility,
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.size(80.dp),
                )
                Spacer(modifier = Modifier.height(12.dp))
                Text(
                    text = "Stream Your Glasses Camera",
                    color = Color.White,
                    fontSize = 20.sp,
                    fontWeight = FontWeight.SemiBold,
                )
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = "Tap the Start streaming button to stream video from your glasses or use the camera button to take a photo from your glasses.",
                    color = Color.White,
                    fontSize = 15.sp,
                    textAlign = TextAlign.Center,
                )
            }

            Spacer(modifier = Modifier.weight(1f))

            // Waiting indicator
            if (!hasActiveDevice) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(bottom = 12.dp),
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        Icons.Outlined.HourglassEmpty,
                        contentDescription = null,
                        tint = Color.White.copy(alpha = 0.7f),
                        modifier = Modifier.size(16.dp),
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = "Waiting for an active device",
                        color = Color.White.copy(alpha = 0.7f),
                        fontSize = 14.sp,
                    )
                }
            }

            CustomButton(
                title = "Start on Phone",
                style = ButtonStyle.SECONDARY,
                onClick = { streamVM.startPhoneCamera(lifecycleOwner, null) },
            )
            Spacer(modifier = Modifier.height(8.dp))
            CustomButton(
                title = "Start streaming",
                style = ButtonStyle.PRIMARY,
                isDisabled = !hasActiveDevice,
                onClick = { streamVM.startGlassesStreaming() },
            )
        }
    }
}

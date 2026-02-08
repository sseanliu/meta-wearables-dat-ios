package com.visionclaw.android.ui.screens

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.visionclaw.android.ui.components.ButtonStyle
import com.visionclaw.android.ui.components.CustomButton
import com.visionclaw.android.viewmodel.WearablesViewModel

/**
 * Welcome/registration screen.
 * Equivalent to iOS HomeScreenView.swift.
 */
@Composable
fun HomeScreen(
    wearablesVM: WearablesViewModel,
    onRegistered: () -> Unit,
) {
    val regState by wearablesVM.registrationState.collectAsState()

    // Navigate when registered
    LaunchedEffect(regState) {
        if (regState == WearablesViewModel.RegState.REGISTERED) {
            onRegistered()
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.White)
            .systemBarsPadding(),
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(modifier = Modifier.weight(1f))

            // App icon placeholder
            Icon(
                imageVector = Icons.Outlined.Visibility,
                contentDescription = "VisionClaw",
                tint = Color.Black,
                modifier = Modifier.size(80.dp),
            )
            Spacer(modifier = Modifier.height(24.dp))

            // Feature tips
            HomeTipItem(
                icon = Icons.Outlined.Videocam,
                title = "Video Capture",
                text = "Record videos directly from your glasses, from your point of view.",
            )
            Spacer(modifier = Modifier.height(12.dp))
            HomeTipItem(
                icon = Icons.Outlined.VolumeUp,
                title = "Open-Ear Audio",
                text = "Hear notifications while keeping your ears open to the world around you.",
            )
            Spacer(modifier = Modifier.height(12.dp))
            HomeTipItem(
                icon = Icons.Outlined.DirectionsWalk,
                title = "Enjoy On-the-Go",
                text = "Stay hands-free while you move through your day. Move freely, stay connected.",
            )

            Spacer(modifier = Modifier.weight(1f))

            Text(
                text = "You'll be redirected to the Meta AI app to confirm your connection.",
                color = Color.Gray,
                fontSize = 14.sp,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(horizontal = 12.dp),
            )
            Spacer(modifier = Modifier.height(20.dp))

            CustomButton(
                title = if (regState == WearablesViewModel.RegState.REGISTERING) "Connecting..." else "Connect my glasses",
                style = ButtonStyle.PRIMARY,
                isDisabled = regState == WearablesViewModel.RegState.REGISTERING,
                onClick = { wearablesVM.connectGlasses() },
            )
        }
    }
}

@Composable
private fun HomeTipItem(
    icon: ImageVector,
    title: String,
    text: String,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.Top,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = Color.Black,
            modifier = Modifier
                .size(24.dp)
                .padding(start = 4.dp, top = 4.dp),
        )
        Spacer(modifier = Modifier.width(12.dp))
        Column {
            Text(
                text = title,
                fontWeight = FontWeight.SemiBold,
                fontSize = 18.sp,
                color = Color.Black,
            )
            Spacer(modifier = Modifier.height(6.dp))
            Text(
                text = text,
                fontSize = 15.sp,
                color = Color.Gray,
            )
        }
    }
}

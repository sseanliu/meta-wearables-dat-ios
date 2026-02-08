package com.visionclaw.android.ui.components

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.visionclaw.android.ui.theme.AppPrimary
import com.visionclaw.android.ui.theme.DestructiveBackground
import com.visionclaw.android.ui.theme.DestructiveForeground
import com.visionclaw.android.ui.theme.SecondaryButton

enum class ButtonStyle {
    PRIMARY, SECONDARY, DESTRUCTIVE;

    val backgroundColor: Color
        get() = when (this) {
            PRIMARY -> AppPrimary
            SECONDARY -> SecondaryButton
            DESTRUCTIVE -> DestructiveBackground
        }

    val foregroundColor: Color
        get() = when (this) {
            PRIMARY, SECONDARY -> Color.White
            DESTRUCTIVE -> DestructiveForeground
        }
}

@Composable
fun CustomButton(
    title: String,
    style: ButtonStyle,
    isDisabled: Boolean = false,
    onClick: () -> Unit,
) {
    Button(
        onClick = onClick,
        enabled = !isDisabled,
        shape = RoundedCornerShape(30.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = style.backgroundColor,
            contentColor = style.foregroundColor,
            disabledContainerColor = style.backgroundColor.copy(alpha = 0.6f),
            disabledContentColor = style.foregroundColor.copy(alpha = 0.6f),
        ),
        modifier = Modifier
            .fillMaxWidth()
            .height(56.dp),
    ) {
        Text(
            text = title,
            fontSize = 15.sp,
            fontWeight = FontWeight.SemiBold,
        )
    }
}

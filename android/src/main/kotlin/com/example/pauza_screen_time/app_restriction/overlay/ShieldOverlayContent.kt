package com.example.pauza_screen_time.app_restriction.overlay

import android.graphics.BitmapFactory
import android.os.Build
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.pauza_screen_time.app_restriction.model.ShieldConfig

/**
 * Composable UI for the shield screen that blocks restricted applications.
 *
 * This component renders a full-screen shield with configurable title, subtitle,
 * icon, and action buttons based on the provided [ShieldConfig].
 *
 * Used by [LockActivity] to display the blocking UI.
 */

/**
 * Main composable content for the shield screen.
 *
 * @param config The shield configuration containing visual properties
 * @param onPrimaryClick Callback when primary button is tapped
 * @param onSecondaryClick Callback when secondary button is tapped
 */
@Composable
fun ShieldOverlayContent(
    config: ShieldConfig,
    onPrimaryClick: () -> Unit,
    onSecondaryClick: () -> Unit
) {
    val backgroundColor = Color(config.backgroundColor)
    val titleColor = Color(config.titleColor)
    val subtitleColor = Color(config.subtitleColor)

    // Determine blur amount based on style
    val blurAmount = when (config.backgroundBlurStyle) {
        "extraLight" -> 20.dp
        "light" -> 15.dp
        "dark" -> 15.dp
        "regular" -> 10.dp
        "prominent" -> 25.dp
        else -> 0.dp
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .then(
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && blurAmount > 0.dp) {
                    Modifier.blur(blurAmount)
                } else {
                    Modifier
                }
            )
            .background(backgroundColor.copy(alpha = 0.95f)),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
            modifier = Modifier.padding(32.dp)
        ) {
            // Icon
            ShieldIcon(iconBytes = config.iconBytes)

            // Title
            Text(
                text = config.title,
                color = titleColor,
                fontSize = 36.sp,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center
            )

            // Subtitle
            config.subtitle?.let { subtitle ->
                Spacer(modifier = Modifier.height(12.dp))
                Text(
                    text = subtitle,
                    color = subtitleColor,
                    fontSize = 22.sp,
                    textAlign = TextAlign.Center
                )
            }

            Spacer(modifier = Modifier.height(40.dp))

            // Primary button
            PrimaryButton(
                label = config.primaryButtonLabel,
                backgroundColor = config.primaryButtonBackgroundColor,
                textColor = config.primaryButtonTextColor,
                onClick = onPrimaryClick
            )

            // Secondary button
            SecondaryButton(
                label = config.secondaryButtonLabel,
                textColor = config.secondaryButtonTextColor ?: config.subtitleColor,
                onClick = onSecondaryClick
            )
        }
    }
}

/**
 * Displays the optional shield icon from byte array data.
 */
@Composable
private fun ShieldIcon(iconBytes: ByteArray?) {
    if (iconBytes != null) {
        val bitmap = BitmapFactory.decodeByteArray(iconBytes, 0, iconBytes.size)
        if (bitmap != null) {
            Image(
                bitmap = bitmap.asImageBitmap(),
                contentDescription = "Shield icon",
                modifier = Modifier.size(80.dp)
            )
        } else {
            Box(
                modifier = Modifier
                    .size(80.dp)
                    .background(Color.White.copy(alpha = 0.15f), RoundedCornerShape(16.dp)),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = "?",
                    color = Color.White,
                    fontSize = 36.sp,
                    fontWeight = FontWeight.Bold,
                )
            }
        }
        Spacer(modifier = Modifier.height(24.dp))
    }
}

/**
 * Primary action button with customizable colors.
 */
@Composable
private fun PrimaryButton(
    label: String?,
    backgroundColor: Int?,
    textColor: Int?,
    onClick: () -> Unit
) {
    label?.let {
        val buttonBgColor = backgroundColor?.let { Color(it) } ?: Color(0xFF6366F1)
        val buttonTextColor = textColor?.let { Color(it) } ?: Color.White

        Button(
            onClick = onClick,
            colors = ButtonDefaults.buttonColors(
                containerColor = buttonBgColor,
                contentColor = buttonTextColor
            ),
            shape = RoundedCornerShape(12.dp),
            modifier = Modifier.padding(horizontal = 24.dp)
        ) {
            Text(
                text = it,
                fontSize = 16.sp,
                fontWeight = FontWeight.Medium,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
            )
        }
    }
}

/**
 * Secondary text button for alternative actions.
 */
@Composable
private fun SecondaryButton(
    label: String?,
    textColor: Int,
    onClick: () -> Unit
) {
    label?.let {
        Spacer(modifier = Modifier.height(12.dp))

        TextButton(
            onClick = onClick,
            colors = ButtonDefaults.textButtonColors(
                contentColor = Color(textColor)
            )
        ) {
            Text(
                text = it,
                fontSize = 14.sp
            )
        }
    }
}

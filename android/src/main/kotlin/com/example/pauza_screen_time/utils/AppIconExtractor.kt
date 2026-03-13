package com.example.pauza_screen_time.utils

import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.util.Log
import java.io.ByteArrayOutputStream

/**
 * Extracts application icons as PNG byte arrays.
 *
 * [extract] throws on failure so callers can decide how to handle it.
 * [extractOrNull] catches exceptions and returns null instead.
 */
object AppIconExtractor {

    private const val TAG = "AppIconExtractor"

    /**
     * Extracts the icon of [appInfo] as a PNG-encoded [ByteArray].
     *
     * @throws Exception if the drawable cannot be loaded or encoded.
     */
    fun extract(appInfo: ApplicationInfo, packageManager: PackageManager): ByteArray {
        val drawable = appInfo.loadIcon(packageManager)
        val bitmap = drawableToBitmap(drawable)
        val outputStream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, outputStream)
        return outputStream.toByteArray()
    }

    /**
     * Like [extract], but returns null on failure instead of throwing.
     */
    fun extractOrNull(appInfo: ApplicationInfo, packageManager: PackageManager): ByteArray? {
        return try {
            extract(appInfo, packageManager)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to extract icon for ${appInfo.packageName}: ${e.message}")
            null
        }
    }

    private fun drawableToBitmap(drawable: Drawable): Bitmap {
        if (drawable is BitmapDrawable && drawable.bitmap != null) {
            return drawable.bitmap
        }

        val width = if (drawable.intrinsicWidth > 0) drawable.intrinsicWidth else 1
        val height = if (drawable.intrinsicHeight > 0) drawable.intrinsicHeight else 1
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, canvas.width, canvas.height)
        drawable.draw(canvas)
        return bitmap
    }
}

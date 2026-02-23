package com.example.pauza_screen_time.utils

import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import java.io.ByteArrayOutputStream

/**
 * Extracts application icons as PNG byte arrays.
 *
 * Unlike the old [AppInfoUtils.extractAppIcon], this object **throws** on
 * failure rather than returning null. The call-site decides whether to treat
 * the error as fatal or downgrade to a null icon.
 */
object AppIconExtractor {

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

package com.tiles.launcher

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.LauncherApps
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.AdaptiveIconDrawable
import android.graphics.drawable.Drawable
import android.os.Build
import android.os.Process
import android.os.UserHandle
import android.provider.MediaStore
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.core.graphics.drawable.toBitmap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

data class AppEntry(
    val key: String,
    val label: String,
    val component: ComponentName,
    val user: UserHandle,
    val icon: ImageBitmap,
    /** White single-colour glyph from the app's themed icon, when it has one. */
    val glyph: ImageBitmap?,
)

suspend fun loadApps(context: Context): List<AppEntry> = withContext(Dispatchers.Default) {
    val launcherApps = context.getSystemService(LauncherApps::class.java)
    val dpi = context.resources.displayMetrics.densityDpi
    launcherApps.getActivityList(null, Process.myUserHandle())
        .filter { it.componentName.packageName != context.packageName }
        .map { info ->
            val drawable = info.getIcon(dpi)
            AppEntry(
                key = info.componentName.flattenToShortString(),
                label = info.label.toString(),
                component = info.componentName,
                user = info.user,
                icon = drawable.toBitmap(192, 192).asImageBitmap(),
                glyph = runCatching { whiteGlyph(drawable) }.getOrNull(),
            )
        }
        .sortedBy { it.label.lowercase() }
}

/**
 * Android 13+ themed-icon layer, drawn white and cropped to the visible
 * part of the adaptive icon (the inner 72 of 108 units), so it fills like a normal icon.
 */
private fun whiteGlyph(drawable: Drawable): ImageBitmap? {
    if (Build.VERSION.SDK_INT < 33 || drawable !is AdaptiveIconDrawable) return null
    val mono = drawable.monochrome?.mutate() ?: return null
    val size = 192
    val pad = size / 4 // 108/72 = 1.5x, so half the size again split over both sides
    val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bmp)
    mono.setBounds(-pad, -pad, size + pad, size + pad)
    mono.setTint(android.graphics.Color.WHITE)
    mono.draw(canvas)
    return bmp.asImageBitmap()
}

/** First-run Start: phone, messages, camera, photos, browser, email, music, settings. */
fun defaultPins(context: Context, apps: List<AppEntry>): List<Pin> {
    val pm = context.packageManager
    fun selector(category: String) = Intent.makeMainSelectorActivity(Intent.ACTION_MAIN, category)
    val intents = listOf(
        Intent(Intent.ACTION_DIAL),
        selector(Intent.CATEGORY_APP_MESSAGING),
        Intent(MediaStore.INTENT_ACTION_STILL_IMAGE_CAMERA),
        selector(Intent.CATEGORY_APP_GALLERY),
        selector(Intent.CATEGORY_APP_BROWSER),
        selector(Intent.CATEGORY_APP_EMAIL),
        selector(Intent.CATEGORY_APP_MUSIC),
        Intent(android.provider.Settings.ACTION_SETTINGS),
    )
    val packages = intents.mapNotNull { intent ->
        runCatching {
            pm.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY)?.activityInfo?.packageName
        }.getOrNull()
    }.filter { it != "android" }.distinct()

    val keys = LinkedHashSet<String>()
    for (pkg in packages) apps.firstOrNull { it.component.packageName == pkg }?.let { keys += it.key }
    for (app in apps) {
        if (keys.size >= 8) break
        keys += app.key
    }
    val sizes = listOf(
        TileSize.Medium, TileSize.Medium,
        TileSize.Small, TileSize.Small, TileSize.Small, TileSize.Small,
        TileSize.Medium, TileSize.Wide,
    )
    return keys.take(8).mapIndexed { i, k -> Pin(k, sizes.getOrElse(i) { TileSize.Medium }) }
}

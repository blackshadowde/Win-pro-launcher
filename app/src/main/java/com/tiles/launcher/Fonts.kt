package com.tiles.launcher

import android.content.Context
import android.graphics.Typeface
import android.net.Uri
import android.provider.OpenableColumns
import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.TextUnit
import java.io.File

val LocalFont = staticCompositionLocalOf<FontFamily> { FontFamily.Default }

/** Every text style in the launcher goes through here so one font applies everywhere. */
@Composable
fun wpStyle(size: TextUnit, color: Color, weight: FontWeight = FontWeight.Normal) =
    TextStyle(color = color, fontSize = size, fontWeight = weight, fontFamily = LocalFont.current)

/**
 * Font files the user loads from their own phone (e.g. Segoe WP).
 * Kept in the app's private storage, never in the repo.
 */
object FontStore {
    private fun dir(context: Context) = File(context.filesDir, "fonts").apply { mkdirs() }

    /** Guess the weight from the file name: segoewp-light.ttf, segoewp-semibold.ttf, ... */
    fun weightFor(name: String): Int {
        val n = name.lowercase()
        return when {
            "semilight" in n -> 350
            "semibold" in n -> 600
            "light" in n -> 300
            "black" in n -> 900
            "bold" in n -> 700
            else -> 400
        }
    }

    /** Copies the picked files in; returns how many were valid fonts. */
    fun import(context: Context, uris: List<Uri>): Int {
        var ok = 0
        for (uri in uris) {
            val name = displayName(context, uri) ?: continue
            val ext = name.substringAfterLast('.', "").lowercase()
            if (ext != "ttf" && ext != "otf") continue
            val weight = weightFor(name)
            val tmp = File(dir(context), "incoming.$ext")
            runCatching {
                context.contentResolver.openInputStream(uri)?.use { input ->
                    tmp.outputStream().use { input.copyTo(it) }
                }
            }
            val valid = runCatching { Typeface.Builder(tmp).build() != null }.getOrDefault(false)
            if (valid) {
                dir(context).listFiles()?.filter { it.nameWithoutExtension == weight.toString() }?.forEach { it.delete() }
                if (tmp.renameTo(File(dir(context), "$weight.$ext"))) ok++
            } else {
                tmp.delete()
            }
        }
        return ok
    }

    fun clear(context: Context) {
        dir(context).listFiles()?.forEach { it.delete() }
    }

    fun count(context: Context): Int = files(context).size

    @OptIn(ExperimentalTextApi::class)
    fun family(context: Context): FontFamily? {
        val files = files(context)
        if (files.isEmpty()) return null
        return FontFamily(files.map { Font(it, FontWeight(it.nameWithoutExtension.toInt())) })
    }

    private fun files(context: Context): List<File> =
        dir(context).listFiles()
            ?.filter { (it.extension == "ttf" || it.extension == "otf") && it.nameWithoutExtension.toIntOrNull() != null }
            .orEmpty()

    private fun displayName(context: Context, uri: Uri): String? =
        runCatching {
            context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                if (it.moveToFirst()) it.getString(0) else null
            }
        }.getOrNull() ?: uri.lastPathSegment
}

/** Use the white themed-icon glyphs on tiles and in the app list. */
val LocalWhiteIcons = staticCompositionLocalOf { true }

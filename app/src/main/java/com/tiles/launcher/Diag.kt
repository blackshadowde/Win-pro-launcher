package com.tiles.launcher

import android.content.Context
import android.os.SystemClock
import android.provider.Settings
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/** Phase 0 measurements shown at the bottom of the screen. */
object Diag {
    private var stopAt = 0L
    private var startAt = 0L
    private var resumeAt = 0L

    var summary by mutableStateOf("Open an app, then swipe home to measure")

    fun stop() { stopAt = now() }
    fun start() { startAt = now() }
    fun resume() { resumeAt = now() }

    fun focus() {
        val f = now()
        if (stopAt > 0 && startAt >= stopAt && resumeAt >= startAt) {
            summary = "last return: start→resume ${resumeAt - startAt} ms · " +
                "resume→focus ${f - resumeAt} ms"
        }
    }

    private fun now() = SystemClock.uptimeMillis()
}

fun navModeLabel(context: Context): String =
    when (Settings.Secure.getInt(context.contentResolver, "navigation_mode", -1)) {
        0 -> "3-button"
        1 -> "2-button"
        2 -> "gestures"
        else -> "unknown"
    }

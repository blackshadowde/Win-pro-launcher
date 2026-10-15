package com.tiles.launcher

import android.content.Context
import android.os.SystemClock
import android.provider.Settings
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/** Timings of the last return home, shown in Start settings. */
object Diag {
    private var startAt = 0L
    private var resumeAt = 0L
    private var focusAt = 0L
    private var animAt = 0L

    var summary by mutableStateOf("Open an app, then swipe home to measure")
        private set

    fun start() {
        startAt = now()
        resumeAt = 0
        focusAt = 0
        animAt = 0
    }

    fun resume() { resumeAt = now(); update() }
    fun focus() { focusAt = now(); update() }
    fun anim() { animAt = now(); update() }

    private fun update() {
        if (startAt == 0L) return
        fun rel(t: Long) = if (t == 0L) "–" else "+${t - startAt} ms"
        summary = "after onStart: resume ${rel(resumeAt)} · focus ${rel(focusAt)} · " +
            "system animation done ${rel(animAt)}"
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

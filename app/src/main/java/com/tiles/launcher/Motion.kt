package com.tiles.launcher

import androidx.compose.animation.core.CubicBezierEasing

/** All animation numbers live here so they can be tuned on the phone in one place. */
object Motion {
    // Turnstile: tiles rotate around the left edge of the screen.
    const val IN_FROM = -80f        // degrees a tile starts at when swinging in
    const val OUT_TO = 80f          // degrees a tile ends at when swinging out
    const val IN_MS = 300
    const val OUT_MS = 220
    const val FADE_MS = 120

    // Stagger: top-left tiles move first.
    const val ROW_STAGGER_MS = 30L
    const val COL_STAGGER_MS = 12L
    const val MAX_STAGGER_ROWS = 3

    // The tapped tile leaves last, then the app opens.
    const val LAST_TILE_DELAY_MS = 140L
    const val OUT_TOTAL_MS = LAST_TILE_DELAY_MS + OUT_MS

    // Taps in the first moments after returning home are queued, not dropped.
    const val TAP_GRACE_MS = 150L

    // Tilt on press.
    const val TILT_DEG = 8f
    const val PRESS_SCALE = 0.97f
    const val PRESS_MS = 90

    val EnterEasing = CubicBezierEasing(0.1f, 0.9f, 0.2f, 1f)
    val ExitEasing = CubicBezierEasing(0.7f, 0f, 1f, 0.5f)

    fun stagger(relRow: Int, col: Int): Long =
        relRow.coerceIn(0, MAX_STAGGER_ROWS) * ROW_STAGGER_MS + col * COL_STAGGER_MS
}

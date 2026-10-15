package com.tiles.launcher

import androidx.compose.animation.core.CubicBezierEasing

/** All animation numbers live here so they can be tuned on the phone in one place. */
object Motion {
    // Turnstile: items rotate around the left edge of the screen.
    // Return home is the app-opening flip played in reverse, so both use OUT_ANGLE.
    const val OUT_ANGLE = 80f
    const val IN_MS = 260
    const val OUT_MS = 220
    const val FADE_MS = 120

    // Stagger: on the way out, top-left items move first.
    const val ROW_STAGGER_MS = 30L
    const val COL_STAGGER_MS = 12L
    const val MAX_STAGGER_ROWS = 3

    // The tapped item leaves last, then the app opens.
    const val LAST_TILE_DELAY_MS = 140L
    const val OUT_TOTAL_MS = LAST_TILE_DELAY_MS + OUT_MS

    // Taps in the first moments after returning home are queued, not dropped.
    const val TAP_GRACE_MS = 150L

    // Tilt on press.
    const val TILT_DEG = 8f
    const val PRESS_SCALE = 0.97f
    const val PRESS_MS = 90

    val ExitEasing = CubicBezierEasing(0.7f, 0f, 1f, 0.5f)
    /** Exit easing mirrored in time, so the return looks like the opening rewound. */
    val EnterEasing = CubicBezierEasing(0f, 0.5f, 0.3f, 1f)

    fun stagger(relRow: Int, col: Int): Long =
        relRow.coerceIn(0, MAX_STAGGER_ROWS) * ROW_STAGGER_MS + col * COL_STAGGER_MS

    // App list rows: one step per visible row.
    const val LIST_STAGGER_MS = 10L
    const val MAX_LIST_ROWS = 12

    fun listStagger(relIndex: Int): Long = relIndex.coerceIn(0, MAX_LIST_ROWS) * LIST_STAGGER_MS

    fun listReverseStagger(relIndex: Int, wasLaunched: Boolean): Long =
        if (wasLaunched) 0L else LAST_TILE_DELAY_MS - listStagger(relIndex)

    /** Out delay reversed: the last item to leave is the first to come back. */
    fun reverseStagger(relRow: Int, col: Int, wasLaunched: Boolean): Long =
        if (wasLaunched) 0L else LAST_TILE_DELAY_MS - stagger(relRow, col)
}

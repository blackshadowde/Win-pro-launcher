package com.tiles.launcher

import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

data class Accent(val name: String, val color: Color)

/** The 20 Windows Phone 8.1 accent colours. */
val Accents = listOf(
    Accent("lime", Color(0xFFA4C400)),
    Accent("green", Color(0xFF60A917)),
    Accent("emerald", Color(0xFF008A00)),
    Accent("teal", Color(0xFF00ABA9)),
    Accent("cyan", Color(0xFF1BA1E2)),
    Accent("cobalt", Color(0xFF0050EF)),
    Accent("indigo", Color(0xFF6A00FF)),
    Accent("violet", Color(0xFFAA00FF)),
    Accent("pink", Color(0xFFF472D0)),
    Accent("magenta", Color(0xFFD80073)),
    Accent("crimson", Color(0xFFA20025)),
    Accent("red", Color(0xFFE51400)),
    Accent("orange", Color(0xFFFA6800)),
    Accent("amber", Color(0xFFF0A30A)),
    Accent("yellow", Color(0xFFE3C800)),
    Accent("brown", Color(0xFF825A2C)),
    Accent("olive", Color(0xFF6D8764)),
    Accent("steel", Color(0xFF647687)),
    Accent("mauve", Color(0xFF76608A)),
    Accent("taupe", Color(0xFF87794E)),
)

const val DEFAULT_ACCENT = 4 // cyan

data class Palette(
    val bg: Color,
    val fg: Color,
    val sub: Color,
    val accent: Color,
    val chrome: Color,
)

fun paletteFor(dark: Boolean, accentIndex: Int): Palette {
    val accent = Accents.getOrElse(accentIndex) { Accents[DEFAULT_ACCENT] }.color
    return if (dark) {
        Palette(Color.Black, Color.White, Color(0xFF9A9A9A), accent, Color(0xFF1F1F1F))
    } else {
        Palette(Color.White, Color.Black, Color(0xFF6E6E6E), accent, Color(0xFFDDDDDD))
    }
}

val LocalPalette = staticCompositionLocalOf { paletteFor(true, DEFAULT_ACCENT) }

enum class UiStyle(val label: String) { Classic("classic 8.1"), Modern("modern") }

/** Shape and spacing that differ between the two styles. */
data class Look(val modern: Boolean) {
    val corner: Dp = if (modern) 10.dp else 0.dp
    val gap: Dp = if (modern) 8.dp else 6.dp
    /** Modern tiles let the wallpaper show through. */
    val tileAlpha: Float = if (modern) 0.82f else 1f
}

val LocalLook = staticCompositionLocalOf { Look(false) }

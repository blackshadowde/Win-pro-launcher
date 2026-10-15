package com.tiles.launcher

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun SettingsPage(
    prefs: Prefs,
    navMode: String,
    fontCount: Int,
    hasBundledFont: Boolean,
    onLoadFont: () -> Unit,
    onResetFont: () -> Unit,
    onClose: () -> Unit,
) {
    val pal = LocalPalette.current
    val source = remember { MutableInteractionSource() }
    val head = wpStyle(20.sp, pal.fg, FontWeight.Light)
    val body = wpStyle(17.sp, pal.fg)
    val note = wpStyle(14.sp, pal.sub)

    BackHandler(onBack = onClose)

    Column(
        Modifier
            .fillMaxSize()
            .background(pal.bg)
            .clickable(interactionSource = source, indication = null) {}
            .verticalScroll(rememberScrollState())
            .windowInsetsPadding(WindowInsets.navigationBars)
            .padding(horizontal = 20.dp, vertical = 12.dp)
    ) {
        BasicText("SETTINGS", style = wpStyle(14.sp, pal.fg, FontWeight.SemiBold))
        BasicText("start+theme", style = wpStyle(48.sp, pal.fg, FontWeight.Light))
        Spacer(Modifier.height(20.dp))

        BasicText("Style", style = head)
        Row(Modifier.padding(vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            UiStyle.entries.forEach { st ->
                Choice(st.label, prefs.style == st, pal) { prefs.setUiStyle(st) }
            }
        }
        BasicText(
            "Modern: wallpaper behind translucent rounded tiles, clock above the tiles, " +
                "colour icons and an A–Z strip in the app list. Animations stay Windows Phone.",
            style = note,
        )
        Spacer(Modifier.height(16.dp))

        BasicText("Background", style = head)
        Row(Modifier.padding(vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Choice("dark", prefs.dark, pal) { prefs.setDarkTheme(true) }
            Choice("light", !prefs.dark, pal) { prefs.setDarkTheme(false) }
        }
        Spacer(Modifier.height(16.dp))

        BasicText("Accent color", style = head)
        Spacer(Modifier.height(8.dp))
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Accents.indices.chunked(5).forEach { rowIdx ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    rowIdx.forEach { i ->
                        val chosen = i == prefs.accent
                        Box(
                            Modifier
                                .size(56.dp)
                                .background(Accents[i].color)
                                .then(if (chosen) Modifier.border(3.dp, pal.fg) else Modifier)
                                .clickable { prefs.setAccentIndex(i) }
                        )
                    }
                }
            }
        }
        BasicText(Accents[prefs.accent].name, style = note, modifier = Modifier.padding(top = 6.dp))
        Spacer(Modifier.height(20.dp))

        BasicText("Show more tiles", style = head)
        Toggle(prefs.moreTiles, pal) { prefs.setMoreTilesOn(it) }
        Spacer(Modifier.height(12.dp))

        BasicText("White tile icons", style = head)
        BasicText("Uses each app's themed icon where it has one.", style = note)
        Toggle(prefs.whiteIcons, pal) { prefs.setWhiteIconsOn(it) }
        Spacer(Modifier.height(20.dp))

        BasicText("Font", style = head)
        BasicText(
            when {
                fontCount > 0 -> "using your font files ($fontCount weight${if (fontCount == 1) "" else "s"})"
                hasBundledFont -> "using Selawik, the built-in Segoe-style font"
                else -> "using the system font"
            },
            style = note,
        )
        BasicText(
            "load your own font files instead (.ttf / .otf)",
            style = body,
            modifier = Modifier.clickable { onLoadFont() }.padding(vertical = 8.dp),
        )
        BasicText(
            "Pick all weights at once, e.g. segoewp.ttf, segoewp-light.ttf, segoewp-semibold.ttf. " +
                "The weight is read from the file name.",
            style = note,
        )
        if (fontCount > 0) {
            BasicText(
                if (hasBundledFont) "go back to Selawik" else "go back to the system font",
                style = body,
                modifier = Modifier.clickable { onResetFont() }.padding(vertical = 8.dp),
            )
        }
        Spacer(Modifier.height(20.dp))

        BasicText("Return-home animation", style = head)
        BasicText(
            "starts: ${prefs.trigger.label}  (tap to change)",
            style = body,
            modifier = Modifier.clickable { prefs.cycleTrigger() }.padding(vertical = 8.dp),
        )
        BasicText(
            "extra delay: ${prefs.enterDelay} ms  (tap to change)",
            style = body,
            modifier = Modifier.clickable { prefs.cycleDelay() }.padding(vertical = 8.dp),
        )
        BasicText("navigation: $navMode", style = note)
        BasicText(Diag.summary, style = note, modifier = Modifier.padding(top = 4.dp))
        Spacer(Modifier.height(24.dp))
    }
}

@Composable
private fun Choice(text: String, on: Boolean, pal: Palette, onClick: () -> Unit) {
    BasicText(
        text = text,
        style = wpStyle(17.sp, if (on) Color.White else pal.fg),
        modifier = Modifier
            .background(if (on) pal.accent else pal.chrome)
            .clickable(onClick = onClick)
            .padding(horizontal = 18.dp, vertical = 10.dp),
    )
}

@Composable
private fun Toggle(on: Boolean, pal: Palette, onChange: (Boolean) -> Unit) {
    Row(
        Modifier.clickable { onChange(!on) }.padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        BasicText(if (on) "On" else "Off", style = wpStyle(17.sp, pal.fg), modifier = Modifier.width(48.dp))
        Box(
            Modifier
                .size(width = 64.dp, height = 26.dp)
                .border(2.dp, pal.fg)
                .padding(4.dp),
            contentAlignment = if (on) Alignment.CenterEnd else Alignment.CenterStart,
        ) {
            Box(
                Modifier
                    .size(width = 32.dp, height = 18.dp)
                    .background(if (on) pal.accent else pal.sub)
            )
        }
    }
}

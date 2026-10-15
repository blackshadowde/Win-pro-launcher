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
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun SettingsPage(prefs: Prefs, navMode: String, onClose: () -> Unit) {
    val pal = LocalPalette.current
    val source = remember { MutableInteractionSource() }
    val head = TextStyle(color = pal.fg, fontSize = 20.sp, fontWeight = FontWeight.Light)
    val body = TextStyle(color = pal.fg, fontSize = 17.sp)
    val note = TextStyle(color = pal.sub, fontSize = 14.sp)

    BackHandler(onBack = onClose)

    Column(
        Modifier
            .fillMaxSize()
            .background(pal.bg)
            .clickable(interactionSource = source, indication = null) {}
            .verticalScroll(rememberScrollState())
            .windowInsetsPadding(WindowInsets.systemBars)
            .padding(horizontal = 20.dp, vertical = 16.dp)
    ) {
        BasicText("SETTINGS", style = TextStyle(color = pal.fg, fontSize = 14.sp, fontWeight = FontWeight.SemiBold))
        BasicText("start+theme", style = TextStyle(color = pal.fg, fontSize = 48.sp, fontWeight = FontWeight.Light))
        Spacer(Modifier.height(20.dp))

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
    }
}

@Composable
private fun Choice(text: String, on: Boolean, pal: Palette, onClick: () -> Unit) {
    BasicText(
        text = text,
        style = TextStyle(color = if (on) androidx.compose.ui.graphics.Color.White else pal.fg, fontSize = 17.sp),
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
        BasicText(if (on) "On" else "Off", style = TextStyle(color = pal.fg, fontSize = 17.sp), modifier = Modifier.width(48.dp))
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

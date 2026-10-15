package com.tiles.launcher

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import org.json.JSONArray
import org.json.JSONObject

/** Saved settings and the pinned tile layout. */
class Prefs(context: Context) {
    private val p = context.getSharedPreferences("start", Context.MODE_PRIVATE)

    var dark by mutableStateOf(p.getBoolean("dark", true))
        private set
    var accent by mutableIntStateOf(p.getInt("accent", DEFAULT_ACCENT).coerceIn(0, Accents.lastIndex))
        private set
    var moreTiles by mutableStateOf(p.getBoolean("moreTiles", false))
        private set
    var trigger by mutableStateOf(Trigger.entries.getOrElse(p.getInt("trigger2", 0)) { Trigger.OnEnterAnim })
        private set
    var enterDelay by mutableIntStateOf(p.getInt("enterDelay", 0))
        private set
    var whiteIcons by mutableStateOf(p.getBoolean("whiteIcons", true))
        private set
    var style by mutableStateOf(UiStyle.entries.getOrElse(p.getInt("style", 0)) { UiStyle.Classic })
        private set

    fun setUiStyle(s: UiStyle) {
        style = s
        p.edit().putInt("style", s.ordinal).apply()
    }

    fun setWhiteIconsOn(v: Boolean) {
        whiteIcons = v
        p.edit().putBoolean("whiteIcons", v).apply()
    }

    val columns: Int get() = if (moreTiles) 6 else 4

    fun setDarkTheme(v: Boolean) {
        dark = v
        p.edit().putBoolean("dark", v).apply()
    }

    fun setAccentIndex(i: Int) {
        accent = i
        p.edit().putInt("accent", i).apply()
    }

    fun setMoreTilesOn(v: Boolean) {
        moreTiles = v
        p.edit().putBoolean("moreTiles", v).apply()
    }

    fun cycleTrigger() {
        trigger = Trigger.entries[(trigger.ordinal + 1) % Trigger.entries.size]
        p.edit().putInt("trigger2", trigger.ordinal).apply()
    }

    fun cycleDelay() {
        val steps = listOf(0, 100, 200, 300)
        enterDelay = steps[(steps.indexOf(enterDelay) + 1).mod(steps.size)]
        p.edit().putInt("enterDelay", enterDelay).apply()
    }

    fun hasSavedPins(): Boolean = p.contains("pins")

    fun loadPins(): List<Pin>? {
        val raw = p.getString("pins", null) ?: return null
        return runCatching {
            val arr = JSONArray(raw)
            (0 until arr.length()).map { i ->
                val o = arr.getJSONObject(i)
                Pin(
                    key = o.getString("k"),
                    size = TileSize.entries.getOrElse(o.optInt("s", 1)) { TileSize.Medium },
                )
            }
        }.getOrNull()
    }

    fun savePins(pins: List<Pin>) {
        val arr = JSONArray()
        pins.forEach { arr.put(JSONObject().put("k", it.key).put("s", it.size.ordinal)) }
        p.edit().putString("pins", arr.toString()).apply()
    }
}

package com.tiles.launcher

import android.content.ComponentName
import android.content.Context
import android.content.pm.LauncherApps
import android.os.Process
import android.os.UserHandle
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
)

enum class TileSize(val w: Int, val h: Int) { Small(1, 1), Medium(2, 2), Wide(4, 2) }

data class PlacedTile(val app: AppEntry, val size: TileSize, val col: Int, val rowOffset: Int)

/** A band of the Start screen: 4 cells wide, 2 cells tall. */
data class Block(val tiles: List<PlacedTile>)

suspend fun loadApps(context: Context): List<AppEntry> = withContext(Dispatchers.Default) {
    val launcherApps = context.getSystemService(LauncherApps::class.java)
    val dpi = context.resources.displayMetrics.densityDpi
    launcherApps.getActivityList(null, Process.myUserHandle())
        .filter { it.componentName.packageName != context.packageName }
        .sortedBy { it.label.toString().lowercase() }
        .map { info ->
            AppEntry(
                key = info.componentName.flattenToShortString(),
                label = info.label.toString(),
                component = info.componentName,
                user = info.user,
                icon = info.getIcon(dpi).toBitmap(192, 192).asImageBitmap(),
            )
        }
}

private data class Slot(val size: TileSize, val col: Int, val rowOffset: Int)

private val patterns: List<List<Slot>> = listOf(
    listOf(Slot(TileSize.Medium, 0, 0), Slot(TileSize.Medium, 2, 0)),
    listOf(Slot(TileSize.Wide, 0, 0)),
    listOf(
        Slot(TileSize.Medium, 0, 0),
        Slot(TileSize.Small, 2, 0), Slot(TileSize.Small, 3, 0),
        Slot(TileSize.Small, 2, 1), Slot(TileSize.Small, 3, 1),
    ),
)

/** Phase 0 test layout: cycles through three band patterns to mix tile sizes. */
fun buildBlocks(apps: List<AppEntry>, maxTiles: Int = 30): List<Block> {
    val blocks = mutableListOf<Block>()
    var i = 0
    var p = 0
    val limit = minOf(apps.size, maxTiles)
    while (i < limit) {
        val tiles = mutableListOf<PlacedTile>()
        for (slot in patterns[p % patterns.size]) {
            if (i >= limit) break
            tiles += PlacedTile(apps[i], slot.size, slot.col, slot.rowOffset)
            i++
        }
        blocks += Block(tiles)
        p++
    }
    return blocks
}

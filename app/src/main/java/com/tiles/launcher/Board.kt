package com.tiles.launcher

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/** The Start screen's pins plus edit-mode state. */
class Board(private val prefs: Prefs) {
    val pins = mutableStateListOf<Pin>().apply { prefs.loadPins()?.let { addAll(it) } }

    val columns: Int get() = prefs.columns

    var editing by mutableStateOf(false)
        private set
    var selected by mutableStateOf<String?>(null)
    var dragKey by mutableStateOf<String?>(null)
        private set
    var dragTarget by mutableStateOf<Cell?>(null)

    fun isPinned(key: String) = pins.any { it.key == key }

    fun setInitial(list: List<Pin>) {
        pins.clear()
        pins.addAll(list)
        save()
    }

    fun pin(key: String) {
        if (!isPinned(key)) {
            pins.add(Pin(key, TileSize.Medium))
            save()
        }
    }

    fun unpin(key: String) {
        pins.removeAll { it.key == key }
        if (selected == key) selected = null
        if (pins.isEmpty()) exitEdit()
        save()
    }

    fun resize(key: String) {
        val i = pins.indexOfFirst { it.key == key }
        if (i >= 0) {
            pins[i] = pins[i].copy(size = pins[i].size.next())
            save()
        }
    }

    fun enterEdit(key: String) {
        editing = true
        selected = key
    }

    fun exitEdit() {
        editing = false
        selected = null
        dragKey = null
        dragTarget = null
    }

    fun startDrag(key: String) {
        editing = true
        selected = key
        dragKey = key
        dragTarget = null
    }

    /** Order with the dragged tile moved to where it would land if dropped now. */
    fun previewOrder(): List<Pin> {
        val key = dragKey ?: return pins
        val target = dragTarget ?: return pins
        val i = pins.indexOfFirst { it.key == key }
        if (i < 0) return pins
        val others = pins.toMutableList()
        val moving = others.removeAt(i)
        val cells = Grid.pack(others, columns)
        val targetPos = target.row * columns + target.col
        val idx = others.indices.count { j -> cells[j].row * columns + cells[j].col < targetPos }
        others.add(idx, moving)
        return others
    }

    fun drop() {
        if (dragKey == null) return
        val order = previewOrder()
        pins.clear()
        pins.addAll(order)
        dragKey = null
        dragTarget = null
        save()
    }

    private fun save() = prefs.savePins(pins.toList())
}

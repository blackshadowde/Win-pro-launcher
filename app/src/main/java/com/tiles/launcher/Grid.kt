package com.tiles.launcher

/** Windows Phone 8.1 tile sizes, in grid cells. */
enum class TileSize(val w: Int, val h: Int) {
    Small(1, 1),
    Medium(2, 2),
    Wide(4, 2);

    /** Same cycle as the resize button on Windows Phone. */
    fun next(): TileSize = when (this) {
        Medium -> Small
        Small -> Wide
        Wide -> Medium
    }
}

data class Pin(val key: String, val size: TileSize)

data class Cell(val col: Int, val row: Int)

object Grid {
    /**
     * Places tiles in order, first fit, never earlier than the previous tile's row.
     * Medium and wide tiles snap to even rows and columns (2x2 blocks), like WP;
     * small tiles fill the quarters of a block.
     */
    fun pack(pins: List<Pin>, columns: Int): List<Cell> {
        val occ = mutableListOf<BooleanArray>()
        fun ensure(r: Int) {
            while (occ.size <= r) occ.add(BooleanArray(columns))
        }
        fun fits(c: Int, r: Int, s: TileSize): Boolean {
            if (c + s.w > columns) return false
            ensure(r + s.h - 1)
            for (dr in 0 until s.h) for (dc in 0 until s.w) if (occ[r + dr][c + dc]) return false
            return true
        }

        val out = ArrayList<Cell>(pins.size)
        var cursor = 0
        for (pin in pins) {
            val s = pin.size
            val step = if (s == TileSize.Small) 1 else 2
            var placed: Cell? = null
            var r = cursor
            while (placed == null) {
                if (s == TileSize.Small || r % 2 == 0) {
                    var c = 0
                    while (c + s.w <= columns) {
                        if (fits(c, r, s)) {
                            placed = Cell(c, r)
                            break
                        }
                        c += step
                    }
                }
                if (placed == null) r++
            }
            for (dr in 0 until s.h) for (dc in 0 until s.w) occ[placed.row + dr][placed.col + dc] = true
            out += placed
            cursor = placed.row
        }
        return out
    }

    fun rows(pins: List<Pin>, cells: List<Cell>): Int =
        pins.indices.maxOfOrNull { cells[it].row + pins[it].size.h } ?: 0
}

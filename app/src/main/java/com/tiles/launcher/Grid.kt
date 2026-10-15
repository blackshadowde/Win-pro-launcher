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
     * Places tiles in order, first fit from the top, so gaps get filled.
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

        // Walk 2x2 blocks in reading order. Small tiles fill a block's quarters
        // (top-left, top-right, bottom-left, bottom-right), so 4 smalls make one square.
        val quarters = listOf(0 to 0, 1 to 0, 0 to 1, 1 to 1)
        val out = ArrayList<Cell>(pins.size)
        for (pin in pins) {
            val s = pin.size
            var placed: Cell? = null
            var r = 0 // first fit from the top, so later tiles fill earlier gaps
            while (placed == null) {
                var c = 0
                while (placed == null && c + minOf(s.w, 2) <= columns) {
                    if (s == TileSize.Small) {
                        for ((dc, dr) in quarters) {
                            if (fits(c + dc, r + dr, s)) {
                                placed = Cell(c + dc, r + dr)
                                break
                            }
                        }
                    } else if (fits(c, r, s)) {
                        placed = Cell(c, r)
                    }
                    c += 2
                }
                if (placed == null) r += 2
            }
            for (dr in 0 until s.h) for (dc in 0 until s.w) occ[placed.row + dr][placed.col + dc] = true
            out += placed
        }
        return out
    }

    fun rows(pins: List<Pin>, cells: List<Cell>): Int =
        pins.indices.maxOfOrNull { cells[it].row + pins[it].size.h } ?: 0
}

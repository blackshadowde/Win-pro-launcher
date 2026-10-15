package com.tiles.launcher

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlin.math.sqrt

enum class Glyph { Unpin, Grow, Shrink, Right }

/** Round Windows Phone-style button drawn in code (no bundled icon files). */
@Composable
fun CircleGlyph(
    glyph: Glyph,
    size: Dp,
    fill: Color,
    ink: Color,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    val source = remember { MutableInteractionSource() }
    Canvas(
        modifier
            .size(size)
            .clickable(interactionSource = source, indication = null, onClick = onClick)
    ) {
        val r = this.size.minDimension / 2f
        val sw = 2.dp.toPx()
        drawCircle(fill, r)
        drawCircle(ink, r - sw / 2f, style = Stroke(sw))
        val s = r * 0.42f
        val c = center
        when (glyph) {
            Glyph.Unpin -> {
                drawLine(ink, c + Offset(-s, -s), c + Offset(s, s), sw, StrokeCap.Round)
                drawLine(ink, c + Offset(s, -s), c + Offset(-s, s), sw, StrokeCap.Round)
            }
            Glyph.Grow -> arrow(ink, c + Offset(-s, -s), c + Offset(s, s), sw, s)
            Glyph.Shrink -> arrow(ink, c + Offset(s, s), c + Offset(-s, -s), sw, s)
            Glyph.Right -> arrow(ink, c + Offset(-s, 0f), c + Offset(s, 0f), sw, s)
        }
    }
}

private fun DrawScope.arrow(ink: Color, from: Offset, to: Offset, sw: Float, s: Float) {
    drawLine(ink, from, to, sw, StrokeCap.Round)
    val d = to - from
    val len = sqrt(d.x * d.x + d.y * d.y).coerceAtLeast(0.001f)
    val back = Offset(-d.x / len, -d.y / len) * (s * 0.7f)
    val k = 0.7071f
    val left = Offset(back.x * k - back.y * k, back.x * k + back.y * k)
    val right = Offset(back.x * k + back.y * k, -back.x * k + back.y * k)
    drawLine(ink, to, to + left, sw, StrokeCap.Round)
    drawLine(ink, to, to + right, sw, StrokeCap.Round)
}

/** Microphone outline. */
@Composable
fun MicGlyph(ink: Color, modifier: Modifier = Modifier) {
    Canvas(modifier) {
        val sw = 1.8.dp.toPx()
        val w = size.width
        val h = size.height
        val capW = w * 0.36f
        val capH = h * 0.52f
        val left = (w - capW) / 2f
        drawRoundRect(
            ink,
            topLeft = Offset(left, h * 0.06f),
            size = androidx.compose.ui.geometry.Size(capW, capH),
            cornerRadius = androidx.compose.ui.geometry.CornerRadius(capW / 2f),
            style = Stroke(sw),
        )
        drawArc(
            ink, startAngle = 0f, sweepAngle = 180f, useCenter = false,
            topLeft = Offset(w * 0.2f, h * 0.22f),
            size = androidx.compose.ui.geometry.Size(w * 0.6f, h * 0.5f),
            style = Stroke(sw, cap = StrokeCap.Round),
        )
        drawLine(ink, Offset(w / 2f, h * 0.72f), Offset(w / 2f, h * 0.92f), sw, StrokeCap.Round)
    }
}

/** Four square panes, used as the search bar's start button. */
@Composable
fun PanesGlyph(ink: Color, modifier: Modifier = Modifier) {
    Canvas(modifier) {
        val gap = size.minDimension * 0.08f
        val cell = (size.minDimension - gap) / 2f
        for (r in 0..1) for (c in 0..1) {
            drawRect(
                ink,
                topLeft = Offset(c * (cell + gap), r * (cell + gap)),
                size = androidx.compose.ui.geometry.Size(cell, cell),
            )
        }
    }
}

package com.tiles.launcher

import android.graphics.Rect
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.VectorConverter
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.roundToInt
import android.content.Intent
import android.provider.AlarmClock
import android.text.format.DateFormat
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

private val Margin = 12.dp

@Composable
fun StartPage(
    state: StartState,
    board: Board,
    apps: Map<String, AppEntry>,
    scroll: ScrollState,
    onLaunchTile: (AppEntry, Rect) -> Unit,
    onOpenAppList: () -> Unit,
) {
    val pal = LocalPalette.current
    val density = LocalDensity.current
    val look = LocalLook.current
    val gap = look.gap
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val cols = board.columns
        val cell = (maxWidth - Margin * 2 - gap * (cols - 1)) / cols
        val pitch = cell + gap
        val pitchPx = with(density) { pitch.toPx() }
        val marginPx = with(density) { Margin.toPx() }
        val order = board.previewOrder().filter { apps.containsKey(it.key) }
        val cells = Grid.pack(order, cols)
        val rows = Grid.rows(order, cells)
        val topPad = 12.dp // the solid status bar sits above this page

        Box(
            Modifier
                .fillMaxSize()
                // A tap on empty space leaves edit mode.
                .pointerInput(Unit) {
                    awaitEachGesture {
                        awaitFirstDown(requireUnconsumed = false)
                        val up = waitForUpOrCancellation()
                        if (up != null && board.editing) board.exitEdit()
                    }
                }
                .verticalScroll(scroll, enabled = board.dragKey == null)
        ) {
            Column(Modifier.fillMaxWidth().padding(top = topPad)) {
                if (look.modern) ClockHeader(state)
                Box(
                    Modifier
                        .padding(horizontal = Margin)
                        .fillMaxWidth()
                        .height(pitch * rows)
                ) {
                    order.forEachIndexed { i, pin ->
                        val app = apps.getValue(pin.key)
                        key(pin.key) {
                            TileView(pin, app, cells[i], cell, pitchPx, marginPx, state, board, scroll, onLaunchTile)
                        }
                    }
                }
                Box(
                    Modifier
                        .fillMaxWidth()
                        .windowInsetsPadding(WindowInsets.navigationBars)
                        .padding(start = Margin, end = Margin, top = 20.dp, bottom = 28.dp)
                ) {
                    if (!board.editing) {
                        CircleGlyph(
                            glyph = Glyph.Right,
                            size = 44.dp,
                            fill = Color.Transparent,
                            ink = pal.fg,
                            modifier = Modifier.align(Alignment.CenterEnd),
                            onClick = onOpenAppList,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun TileView(
    pin: Pin,
    app: AppEntry,
    cell: Cell,
    cellDp: Dp,
    pitchPx: Float,
    marginPx: Float,
    state: StartState,
    board: Board,
    scroll: ScrollState,
    onLaunchTile: (AppEntry, Rect) -> Unit,
) {
    val pal = LocalPalette.current
    val scope = rememberCoroutineScope()
    val haptics = LocalHapticFeedback.current
    val gap = LocalLook.current.gap
    val w = cellDp * pin.size.w + gap * (pin.size.w - 1)
    val h = cellDp * pin.size.h + gap * (pin.size.h - 1)

    // Position: springs to its packed cell; follows the finger while dragged.
    val target = Offset(cell.col * pitchPx, cell.row * pitchPx)
    val pos = remember { Animatable(target, Offset.VectorConverter) }
    val dragging = board.dragKey == pin.key
    LaunchedEffect(target, dragging) {
        if (!dragging) pos.animateTo(target, spring(dampingRatio = 0.85f, stiffness = 500f))
    }

    // Turnstile.
    val rot = remember { Animatable(Motion.OUT_ANGLE) }
    val fade = remember { Animatable(0f) }
    var readyEpoch by remember { mutableIntStateOf(-1) }
    LaunchedEffect(state.epoch, state.phase) {
        val relRow = ((cell.row * pitchPx - scroll.value) / pitchPx).toInt()
        val d = Motion.stagger(relRow, cell.col)
        when (state.phase) {
            Phase.Hidden -> {
                rot.snapTo(Motion.OUT_ANGLE)
                fade.snapTo(0f)
                readyEpoch = state.epoch
            }
            Phase.In -> {
                if (readyEpoch != state.epoch) {
                    rot.snapTo(Motion.OUT_ANGLE)
                    fade.snapTo(0f)
                    readyEpoch = state.epoch
                }
                // The opening flip played backwards: the tile that opened the app returns first.
                delay(Motion.reverseStagger(relRow, cell.col, pin.key == state.returnKey))
                launch { fade.animateTo(1f, tween(Motion.FADE_MS)) }
                rot.animateTo(0f, tween(Motion.IN_MS, easing = Motion.EnterEasing))
            }
            Phase.Out -> {
                val od = if (pin.key == state.launchingKey) Motion.LAST_TILE_DELAY_MS else d
                delay(od)
                launch { fade.animateTo(0f, tween(Motion.OUT_MS, easing = Motion.ExitEasing)) }
                rot.animateTo(Motion.OUT_ANGLE, tween(Motion.OUT_MS, easing = Motion.ExitEasing))
            }
        }
    }

    // Edit mode look: others shrink and dim, and gently float.
    val selected = board.editing && board.selected == pin.key
    val editScale by animateFloatAsState(
        if (board.editing && !selected) 0.9f else 1f, tween(200), label = "editScale",
    )
    val editAlpha by animateFloatAsState(
        if (board.editing && !selected) 0.6f else 1f, tween(200), label = "editAlpha",
    )
    val lift by animateFloatAsState(if (dragging) 1.08f else 1f, tween(120), label = "lift")
    val bob = if (board.editing && !selected) {
        val t = rememberInfiniteTransition(label = "bob")
        t.animateFloat(
            initialValue = -1f,
            targetValue = 1f,
            animationSpec = infiniteRepeatable(
                tween(1300 + (pin.key.hashCode() and 511), easing = FastOutSlowInEasing),
                RepeatMode.Reverse,
            ),
            label = "bobValue",
        ).value
    } else 0f

    // Tilt on press.
    var pressed by remember { mutableStateOf(false) }
    var pressAt by remember { mutableStateOf(Offset.Zero) }
    val tx by animateFloatAsState(if (pressed) pressAt.x else 0f, tween(Motion.PRESS_MS), label = "tiltX")
    val ty by animateFloatAsState(if (pressed) pressAt.y else 0f, tween(Motion.PRESS_MS), label = "tiltY")
    val press by animateFloatAsState(if (pressed) Motion.PRESS_SCALE else 1f, tween(Motion.PRESS_MS), label = "press")

    val bounds = remember { Rect() }
    val pinNow by rememberUpdatedState(pin)
    val cellNow by rememberUpdatedState(cell)
    val pitchNow by rememberUpdatedState(pitchPx)
    val appNow by rememberUpdatedState(app)
    val launchNow by rememberUpdatedState(onLaunchTile)

    Box(
        Modifier
            .zIndex(if (dragging) 1f else 0f)
            .offset { IntOffset(pos.value.x.roundToInt(), pos.value.y.roundToInt()) }
            .size(w, h)
            .onGloballyPositioned { c ->
                val p = c.positionInWindow()
                bounds.set(
                    p.x.toInt(), p.y.toInt(),
                    (p.x + c.size.width).toInt(), (p.y + c.size.height).toInt(),
                )
            }
            .graphicsLayer {
                // Hidden until reset for this visit, so the system zoom never shows stale tiles.
                val ready = readyEpoch == state.epoch
                alpha = if (ready) fade.value else 0f
                rotationY = rot.value
                cameraDistance = 14f * density
                // Hinge on the screen's left edge.
                val windowX = marginPx + pos.value.x
                transformOrigin = TransformOrigin(
                    if (size.width > 0f) -windowX / size.width else 0f, 0.5f,
                )
            }
            .graphicsLayer {
                val s = editScale * lift
                scaleX = s
                scaleY = s
                alpha = editAlpha
                translationX = bob * 1.dp.toPx()
                translationY = bob * 2.dp.toPx()
            }
            .pointerInput(pin.key) {
                var origin = Offset.Zero
                fun beginDrag() {
                    origin = Offset(cellNow.col * pitchNow, cellNow.row * pitchNow)
                    board.startDrag(pinNow.key)
                }
                fun moveDrag(total: Offset) {
                    val p = origin + total
                    scope.launch(start = CoroutineStart.UNDISPATCHED) { pos.snapTo(p) }
                    val cols = board.columns
                    val t = Cell(
                        col = (p.x / pitchNow).roundToInt().coerceIn(0, (cols - pinNow.size.w).coerceAtLeast(0)),
                        row = (p.y / pitchNow).roundToInt().coerceAtLeast(0),
                    )
                    if (t != board.dragTarget) board.dragTarget = t
                }

                awaitEachGesture {
                    val down = awaitFirstDown()
                    val editingAtDown = board.editing
                    val selectedAtDown = board.selected == pinNow.key

                    if (editingAtDown && selectedAtDown) {
                        // Selected tile in edit mode: drag right away once past touch slop.
                        var total = Offset.Zero
                        var moving = false
                        while (true) {
                            val ev = awaitPointerEvent()
                            val ch = ev.changes.firstOrNull { it.id == down.id } ?: break
                            if (!ch.pressed) {
                                ch.consume()
                                break
                            }
                            total += ch.positionChange()
                            if (!moving && total.getDistance() > viewConfiguration.touchSlop) {
                                moving = true
                                beginDrag()
                            }
                            if (moving) {
                                moveDrag(total)
                                ch.consume()
                            }
                        }
                        if (moving) board.drop()
                    } else {
                        if (!editingAtDown) {
                            pressAt = Offset(
                                down.position.x / size.width.coerceAtLeast(1) * 2f - 1f,
                                down.position.y / size.height.coerceAtLeast(1) * 2f - 1f,
                            )
                            pressed = true
                        }
                        var cancelled = false
                        val result = withTimeoutOrNull(viewConfiguration.longPressTimeoutMillis) {
                            val up = waitForUpOrCancellation()
                            if (up == null) cancelled = true else up.consume()
                            up ?: down
                        }
                        pressed = false
                        if (result == null) {
                            // Long press: enter edit mode, lift the tile and follow the finger.
                            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                            board.enterEdit(pinNow.key)
                            beginDrag()
                            var total = Offset.Zero
                            while (true) {
                                val ev = awaitPointerEvent()
                                val ch = ev.changes.firstOrNull { it.id == down.id } ?: break
                                if (!ch.pressed) {
                                    ch.consume()
                                    break
                                }
                                total += ch.positionChange()
                                moveDrag(total)
                                ch.consume()
                            }
                            board.drop()
                        } else if (!cancelled) {
                            if (editingAtDown) board.selected = pinNow.key
                            else launchNow(appNow, Rect(bounds))
                        }
                    }
                }
            }
    ) {
        Box(
            Modifier
                .fillMaxSize()
                .graphicsLayer {
                    rotationY = tx * Motion.TILT_DEG
                    rotationX = -ty * Motion.TILT_DEG
                    scaleX = press
                    scaleY = press
                    cameraDistance = 12f * density
                }
        ) {
            TileFace(pin, app, pal)
        }
        if (selected && !dragging) {
            CircleGlyph(
                glyph = Glyph.Unpin,
                size = 34.dp,
                fill = pal.bg,
                ink = pal.fg,
                modifier = Modifier.align(Alignment.TopEnd).padding(4.dp),
                onClick = { board.unpin(pin.key) },
            )
            CircleGlyph(
                glyph = if (pin.size.next() == TileSize.Small) Glyph.Shrink else Glyph.Grow,
                size = 34.dp,
                fill = pal.bg,
                ink = pal.fg,
                modifier = Modifier.align(Alignment.BottomEnd).padding(4.dp),
                onClick = { board.resize(pin.key) },
            )
        }
    }
}

@Composable
private fun TileFace(pin: Pin, app: AppEntry, pal: Palette) {
    val look = LocalLook.current
    Box(
        Modifier
            .fillMaxSize()
            .clip(RoundedCornerShape(look.corner))
            .background(pal.accent.copy(alpha = look.tileAlpha))
    ) {
        Image(
            bitmap = if (LocalWhiteIcons.current) app.glyph ?: app.icon else app.icon,
            contentDescription = app.label,
            modifier = Modifier
                .align(Alignment.Center)
                .fillMaxHeight(if (pin.size == TileSize.Small) 0.6f else 0.42f)
                .aspectRatio(1f),
        )
        if (pin.size != TileSize.Small) {
            BasicText(
                text = app.label,
                style = wpStyle(14.sp, Color.White),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier
                    .align(Alignment.BottomStart)
                    .padding(start = 8.dp, end = 8.dp, bottom = 6.dp),
            )
        }
    }
}

/** Modern style: big clock and date above the tiles; scrolls away with them. Tap opens alarms. */
@Composable
private fun ClockHeader(state: StartState) {
    val pal = LocalPalette.current
    val context = LocalContext.current
    val source = remember { MutableInteractionSource() }
    var now by remember { mutableStateOf(LocalDateTime.now()) }
    LaunchedEffect(state.epoch) {
        while (true) {
            now = LocalDateTime.now()
            delay(60_000L - System.currentTimeMillis() % 60_000L)
        }
    }
    val pattern = if (DateFormat.is24HourFormat(context)) "HH:mm" else "h:mm"
    val time = now.format(DateTimeFormatter.ofPattern(pattern))
    val date = now.format(DateTimeFormatter.ofPattern("EEE, MMM d, yyyy"))
    val shown = state.phase == Phase.In
    val alpha by animateFloatAsState(if (shown) 1f else 0f, tween(Motion.IN_MS), label = "header")
    Column(
        Modifier
            .padding(start = Margin + 4.dp, top = 20.dp, bottom = 28.dp)
            .graphicsLayer { this.alpha = alpha }
            .clickable(interactionSource = source, indication = null) {
                runCatching {
                    context.startActivity(
                        Intent(AlarmClock.ACTION_SHOW_ALARMS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                }
            }
    ) {
        BasicText(time, style = wpStyle(84.sp, pal.fg, FontWeight.Light))
        BasicText(date, style = wpStyle(22.sp, pal.fg))
    }
}

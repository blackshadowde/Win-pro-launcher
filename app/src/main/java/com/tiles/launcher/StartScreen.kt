package com.tiles.launcher

import android.graphics.Rect
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.asPaddingValues
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private val Accent = Color(0xFF1BA1E2)
private val TileMargin = 12.dp
private val TileGap = 6.dp

@Composable
fun StartScreen(
    state: StartState,
    onLaunch: (AppEntry, Rect) -> Unit,
    onCycleTrigger: () -> Unit,
) {
    val context = LocalContext.current
    var apps by remember { mutableStateOf<List<AppEntry>>(emptyList()) }
    LaunchedEffect(Unit) { apps = loadApps(context) }
    val blocks = remember(apps) { buildBlocks(apps) }
    val listState = rememberLazyListState()

    LaunchedEffect(state.scrollTopRequests) {
        if (state.scrollTopRequests > 0) listState.animateScrollToItem(0)
    }

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val cell = (maxWidth - TileMargin * 2 - TileGap * 3) / 4
            val topInset = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
            LazyColumn(
                state = listState,
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(
                    start = TileMargin,
                    end = TileMargin,
                    top = topInset + 24.dp,
                    bottom = 140.dp,
                ),
                verticalArrangement = Arrangement.spacedBy(TileGap),
            ) {
                itemsIndexed(blocks) { index, block ->
                    Box(Modifier.fillMaxWidth().height(cell * 2 + TileGap)) {
                        block.tiles.forEach { t ->
                            key(t.app.key) {
                                Tile(t, index, cell, state, listState, onLaunch)
                            }
                        }
                    }
                }
            }
        }
        DiagnosticsBar(state, onCycleTrigger, Modifier.align(Alignment.BottomStart))
    }
}

@Composable
private fun Tile(
    t: PlacedTile,
    blockIndex: Int,
    cell: Dp,
    state: StartState,
    listState: LazyListState,
    onLaunch: (AppEntry, Rect) -> Unit,
) {
    val w = cell * t.size.w + TileGap * (t.size.w - 1)
    val h = cell * t.size.h + TileGap * (t.size.h - 1)
    val x = (cell + TileGap) * t.col
    val y = (cell + TileGap) * t.rowOffset

    val rot = remember { Animatable(Motion.IN_FROM) }
    val fade = remember { Animatable(0f) }
    var readyEpoch by remember { mutableIntStateOf(-1) }
    var pivotX by remember { mutableFloatStateOf(0f) }
    val bounds = remember { Rect() }

    LaunchedEffect(state.epoch, state.phase) {
        val relRow = (blockIndex - listState.firstVisibleItemIndex) * 2 + t.rowOffset
        val d = Motion.stagger(relRow, t.col)
        when (state.phase) {
            Phase.Hidden -> {
                rot.snapTo(Motion.IN_FROM)
                fade.snapTo(0f)
                readyEpoch = state.epoch
            }
            Phase.In -> {
                if (readyEpoch != state.epoch) {
                    rot.snapTo(Motion.IN_FROM)
                    fade.snapTo(0f)
                    readyEpoch = state.epoch
                }
                delay(d)
                launch { fade.animateTo(1f, tween(Motion.FADE_MS)) }
                rot.animateTo(0f, tween(Motion.IN_MS, easing = Motion.EnterEasing))
            }
            Phase.Out -> {
                val od = if (t.app.key == state.launchingKey) Motion.LAST_TILE_DELAY_MS else d
                delay(od)
                launch { fade.animateTo(0f, tween(Motion.OUT_MS, easing = Motion.ExitEasing)) }
                rot.animateTo(Motion.OUT_TO, tween(Motion.OUT_MS, easing = Motion.ExitEasing))
            }
        }
    }

    Box(
        Modifier
            .offset(x, y)
            .size(w, h)
            .onGloballyPositioned { c ->
                val p = c.positionInWindow()
                if (c.size.width > 0) pivotX = -p.x / c.size.width
                bounds.set(
                    p.x.toInt(), p.y.toInt(),
                    (p.x + c.size.width).toInt(), (p.y + c.size.height).toInt(),
                )
            }
            .graphicsLayer {
                // Until a tile has reset for this visit, keep it invisible.
                val ready = readyEpoch == state.epoch
                alpha = if (ready) fade.value else 0f
                rotationY = rot.value
                cameraDistance = 14f * density
                // Pivot at the screen's left edge, like Windows Phone's turnstile.
                transformOrigin = TransformOrigin(pivotX, 0.5f)
            }
    ) {
        TiltSurface(onTap = {
            if (state.phase != Phase.Out) onLaunch(t.app, Rect(bounds))
        }) {
            TileContent(t)
        }
    }
}

@Composable
private fun TiltSurface(onTap: () -> Unit, content: @Composable () -> Unit) {
    val tap by rememberUpdatedState(onTap)
    var pressed by remember { mutableStateOf(false) }
    var target by remember { mutableStateOf(Offset.Zero) }
    val tx by animateFloatAsState(if (pressed) target.x else 0f, tween(Motion.PRESS_MS), label = "tiltX")
    val ty by animateFloatAsState(if (pressed) target.y else 0f, tween(Motion.PRESS_MS), label = "tiltY")
    val sc by animateFloatAsState(if (pressed) Motion.PRESS_SCALE else 1f, tween(Motion.PRESS_MS), label = "press")

    Box(
        Modifier
            .fillMaxSize()
            .pointerInput(Unit) {
                awaitEachGesture {
                    val down = awaitFirstDown()
                    val sw = size.width.toFloat().coerceAtLeast(1f)
                    val sh = size.height.toFloat().coerceAtLeast(1f)
                    target = Offset(down.position.x / sw * 2f - 1f, down.position.y / sh * 2f - 1f)
                    pressed = true
                    val up = waitForUpOrCancellation()
                    pressed = false
                    if (up != null) tap()
                }
            }
            .graphicsLayer {
                rotationY = tx * Motion.TILT_DEG
                rotationX = -ty * Motion.TILT_DEG
                scaleX = sc
                scaleY = sc
                cameraDistance = 12f * density
            }
    ) {
        content()
    }
}

@Composable
private fun TileContent(t: PlacedTile) {
    Box(Modifier.fillMaxSize().background(Accent)) {
        val iconFraction = if (t.size == TileSize.Small) 0.6f else 0.42f
        Image(
            bitmap = t.app.icon,
            contentDescription = t.app.label,
            modifier = Modifier
                .align(Alignment.Center)
                .fillMaxHeight(iconFraction)
                .aspectRatio(1f),
        )
        if (t.size != TileSize.Small) {
            BasicText(
                text = t.app.label,
                style = TextStyle(color = Color.White, fontSize = 13.sp),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier
                    .align(Alignment.BottomStart)
                    .padding(start = 8.dp, end = 8.dp, bottom = 6.dp),
            )
        }
    }
}

@Composable
private fun DiagnosticsBar(state: StartState, onCycleTrigger: () -> Unit, modifier: Modifier) {
    val style = TextStyle(color = Color.White, fontSize = 12.sp)
    Column(
        modifier
            .fillMaxWidth()
            .background(Color(0xCC000000))
            .windowInsetsPadding(WindowInsets.navigationBars)
            .padding(horizontal = 12.dp, vertical = 8.dp)
    ) {
        BasicText(
            text = "nav: ${state.navMode} · animate on: ${state.trigger.label} (tap to change)",
            style = style,
            modifier = Modifier.clickable { onCycleTrigger() },
        )
        BasicText(text = Diag.summary, style = style.copy(color = Color(0xFFBBBBBB)))
    }
}

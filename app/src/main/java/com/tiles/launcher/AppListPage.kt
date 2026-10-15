package com.tiles.launcher

import android.graphics.Rect
import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private sealed interface ListRow {
    data class Header(val letter: Char) : ListRow
    data class App(val app: AppEntry) : ListRow
}

private fun letterOf(label: String): Char {
    val c = label.trim().firstOrNull()?.uppercaseChar() ?: '#'
    return if (c in 'A'..'Z') c else '#'
}

private const val LEADING_ITEMS = 2 // search box + settings row

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun AppListPage(
    apps: List<AppEntry>,
    board: Board,
    state: StartState,
    listState: LazyListState,
    onLaunch: (AppEntry, Rect) -> Unit,
    onUninstall: (AppEntry) -> Unit,
    onOpenSettings: () -> Unit,
) {
    val pal = LocalPalette.current
    val whiteIcons = LocalWhiteIcons.current
    val scope = rememberCoroutineScope()
    var query by remember { mutableStateOf("") }
    var menuFor by remember { mutableStateOf<String?>(null) }
    var jumpOpen by remember { mutableStateOf(false) }

    val filtered = remember(apps, query) {
        val q = query.trim()
        if (q.isEmpty()) apps else apps.filter { it.label.contains(q, ignoreCase = true) }
    }
    val rows = remember(filtered) {
        // '#' group first, then A to Z.
        val sorted = filtered.sortedWith(compareBy({ letterOf(it.label) != '#' }, { it.label.lowercase() }))
        buildList {
            var last: Char? = null
            for (a in sorted) {
                val l = letterOf(a.label)
                if (l != last) {
                    add(ListRow.Header(l))
                    last = l
                }
                add(ListRow.App(a))
            }
        }
    }

    val bottomPad = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding() + 24.dp
    val labelStyle = wpStyle(22.sp, pal.fg, FontWeight.Light)

    Box(Modifier.fillMaxSize()) {
        LazyColumn(
            state = listState,
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(start = 20.dp, end = 16.dp, top = 12.dp, bottom = bottomPad),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            item(key = "search") {
                BasicTextField(
                    value = query,
                    onValueChange = { query = it },
                    singleLine = true,
                    textStyle = wpStyle(18.sp, pal.fg),
                    cursorBrush = SolidColor(pal.accent),
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(bottom = 12.dp)
                        .border(2.dp, pal.sub)
                        .padding(horizontal = 12.dp, vertical = 10.dp),
                    decorationBox = { inner ->
                        Box {
                            if (query.isEmpty()) BasicText("search", style = wpStyle(18.sp, pal.sub))
                            inner()
                        }
                    },
                )
            }
            item(key = "settings") {
                if (query.isBlank()) {
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .clickable { onOpenSettings() }
                            .padding(vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Box(Modifier.size(50.dp).border(2.dp, pal.sub))
                        Spacer(Modifier.width(14.dp))
                        BasicText("start + theme", style = labelStyle)
                    }
                }
            }
            items(
                count = rows.size,
                key = { i ->
                    when (val r = rows[i]) {
                        is ListRow.Header -> "h_${r.letter}_$i"
                        is ListRow.App -> "a_${r.app.key}"
                    }
                },
            ) { i ->
                val itemIndex = i + LEADING_ITEMS
                when (val r = rows[i]) {
                    is ListRow.Header -> ListTurnstile(itemIndex, "h_$i", state, listState) {
                        Box(
                            Modifier
                                .padding(top = 10.dp, bottom = 4.dp)
                                .size(50.dp)
                                .border(2.dp, pal.accent)
                                .clickable { jumpOpen = true },
                            contentAlignment = Alignment.BottomStart,
                        ) {
                            BasicText(
                                text = r.letter.lowercaseChar().toString(),
                                style = wpStyle(26.sp, pal.accent, FontWeight.Light),
                                modifier = Modifier.padding(start = 6.dp, bottom = 2.dp),
                            )
                        }
                    }
                    is ListRow.App -> ListTurnstile(itemIndex, r.app.key, state, listState) {
                        val app = r.app
                        val bounds = remember { Rect() }
                        Column {
                            Row(
                                Modifier
                                    .fillMaxWidth()
                                    .onGloballyPositioned { c ->
                                        val p = c.positionInWindow()
                                        bounds.set(
                                            p.x.toInt(), p.y.toInt(),
                                            (p.x + c.size.width).toInt(), (p.y + c.size.height).toInt(),
                                        )
                                    }
                                    .combinedClickable(
                                        onClick = {
                                            if (menuFor != null) menuFor = null
                                            else onLaunch(app, Rect(bounds))
                                        },
                                        onLongClick = { menuFor = app.key },
                                    )
                                    .padding(vertical = 4.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Box(Modifier.size(50.dp).background(pal.accent), contentAlignment = Alignment.Center) {
                                    Image(
                                        bitmap = if (whiteIcons) app.glyph ?: app.icon else app.icon,
                                        contentDescription = null,
                                        modifier = Modifier.size(34.dp),
                                    )
                                }
                                Spacer(Modifier.width(14.dp))
                                BasicText(app.label, style = labelStyle, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            }
                            if (menuFor == app.key) {
                                val pinned = board.isPinned(app.key)
                                Column(Modifier.fillMaxWidth().background(pal.chrome).padding(vertical = 6.dp)) {
                                    MenuItem(if (pinned) "unpin from start" else "pin to start", pal) {
                                        if (pinned) board.unpin(app.key) else board.pin(app.key)
                                        menuFor = null
                                    }
                                    MenuItem("uninstall", pal) {
                                        menuFor = null
                                        onUninstall(app)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        if (jumpOpen) {
            val present = rows.filterIsInstance<ListRow.Header>().map { it.letter }.toSet()
            JumpGrid(
                present = present,
                onPick = { letter ->
                    jumpOpen = false
                    val idx = rows.indexOfFirst { it is ListRow.Header && it.letter == letter }
                    if (idx >= 0) scope.launch { listState.scrollToItem(idx + LEADING_ITEMS) }
                },
                onDismiss = { jumpOpen = false },
            )
        }
    }

    BackHandler(enabled = menuFor != null) { menuFor = null }
    BackHandler(enabled = jumpOpen) { jumpOpen = false }
}

/** Turnstile for one list row: swings out when an app opens, back in (reversed) on return. */
@Composable
private fun ListTurnstile(
    index: Int,
    itemKey: String,
    state: StartState,
    listState: LazyListState,
    content: @Composable () -> Unit,
) {
    val rot = remember { Animatable(0f) }
    val fade = remember { Animatable(1f) }
    LaunchedEffect(state.listEpoch, state.listPhase) {
        val rel = index - listState.firstVisibleItemIndex
        val launched = itemKey == state.listLaunchingKey
        when (state.listPhase) {
            ListPhase.Idle -> {
                rot.snapTo(0f)
                fade.snapTo(1f)
            }
            ListPhase.Out -> {
                delay(if (launched) Motion.LAST_TILE_DELAY_MS else Motion.listStagger(rel))
                launch { fade.animateTo(0f, tween(Motion.OUT_MS, easing = Motion.ExitEasing)) }
                rot.animateTo(Motion.OUT_ANGLE, tween(Motion.OUT_MS, easing = Motion.ExitEasing))
            }
            ListPhase.In -> {
                rot.snapTo(Motion.OUT_ANGLE)
                fade.snapTo(0f)
                delay(Motion.listReverseStagger(rel, launched))
                launch { fade.animateTo(1f, tween(Motion.FADE_MS)) }
                rot.animateTo(0f, tween(Motion.IN_MS, easing = Motion.EnterEasing))
            }
        }
    }
    Box(
        Modifier.graphicsLayer {
            rotationY = rot.value
            alpha = fade.value
            cameraDistance = 14f * density
            transformOrigin = TransformOrigin(0f, 0.5f)
        }
    ) {
        content()
    }
}

@Composable
private fun MenuItem(text: String, pal: Palette, onClick: () -> Unit) {
    BasicText(
        text = text,
        style = wpStyle(20.sp, pal.fg, FontWeight.Light),
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 10.dp),
    )
}

@Composable
private fun JumpGrid(present: Set<Char>, onPick: (Char) -> Unit, onDismiss: () -> Unit) {
    val pal = LocalPalette.current
    val letters = listOf('#') + ('A'..'Z').toList()
    val source = remember { MutableInteractionSource() }
    Box(
        Modifier
            .fillMaxSize()
            .background(pal.bg.copy(alpha = 0.94f))
            .clickable(interactionSource = source, indication = null, onClick = onDismiss),
        contentAlignment = Alignment.Center,
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            letters.chunked(4).forEach { rowLetters ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    rowLetters.forEach { l ->
                        val on = l in present
                        Box(
                            Modifier
                                .size(72.dp)
                                .background(if (on) pal.accent else pal.chrome)
                                .clickable(enabled = on) { onPick(l) },
                            contentAlignment = Alignment.BottomStart,
                        ) {
                            BasicText(
                                text = l.lowercaseChar().toString(),
                                style = wpStyle(30.sp, if (on) Color.White else pal.sub, FontWeight.Light),
                                modifier = Modifier.padding(start = 8.dp, bottom = 4.dp),
                            )
                        }
                    }
                }
            }
        }
    }
}

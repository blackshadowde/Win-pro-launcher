package com.tiles.launcher

import android.os.SystemClock
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

enum class Phase { Hidden, In, Out }

/** Which lifecycle moment starts the swing-in. Phase 0 tests all three. */
enum class Trigger(val label: String) {
    OnStart("onStart"),
    OnResume("onResume"),
    OnFocus("window focus"),
}

class StartState {
    var phase by mutableStateOf(Phase.Hidden)
    /** Bumped every time Start is left; tiles hide until they have reset for the new epoch. */
    var epoch by mutableIntStateOf(0)
    var launchingKey by mutableStateOf<String?>(null)
    var scrollTopRequests by mutableIntStateOf(0)
    var trigger by mutableStateOf(Trigger.OnResume)
    var navMode by mutableStateOf("unknown")
    var blockedUntil = 0L

    fun leave() {
        epoch++
        phase = Phase.Hidden
        launchingKey = null
    }

    fun enter() {
        if (phase == Phase.Hidden) {
            phase = Phase.In
            blockedUntil = SystemClock.uptimeMillis() + Motion.TAP_GRACE_MS
        }
    }

    fun beginLaunch(key: String) {
        launchingKey = key
        phase = Phase.Out
    }
}

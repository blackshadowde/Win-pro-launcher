package com.tiles.launcher

import android.os.SystemClock
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

enum class Phase { Hidden, In, Out }

enum class ListPhase { Idle, Out, In }

/** Which moment starts the swing-in after returning home. */
enum class Trigger(val label: String) {
    OnEnterAnim("after system animation"),
    OnStart("onStart"),
    OnResume("onResume"),
    OnFocus("window focus"),
}

class StartState {
    var phase by mutableStateOf(Phase.Hidden)
    /** Bumped every time Start is left; tiles stay invisible until they reset for the new epoch. */
    var epoch by mutableIntStateOf(0)
    var launchingKey by mutableStateOf<String?>(null)
    /** Tile that opened the last app: first to flip back in. */
    var returnKey by mutableStateOf<String?>(null)
    var navMode by mutableStateOf("unknown")
    var blockedUntil = 0L

    // App list turnstile.
    var listPhase by mutableStateOf(ListPhase.Idle)
    var listEpoch by mutableIntStateOf(0)
    var listLaunchingKey by mutableStateOf<String?>(null)

    /** Home pressed while already on Start: animate to the top. */
    var homeRequests by mutableIntStateOf(0)
    /** Returned home from an app: jump to the top of Start. */
    var snapHomeRequests by mutableIntStateOf(0)
    /** Bumped when apps are installed, removed or updated. */
    var appsVersion by mutableIntStateOf(0)

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
        if (listPhase == ListPhase.Out) {
            listPhase = ListPhase.In
            listEpoch++
        }
    }

    fun beginLaunch(key: String) {
        launchingKey = key
        returnKey = key
        phase = Phase.Out
    }

    fun beginListLaunch(key: String) {
        returnKey = null
        listLaunchingKey = key
        listPhase = ListPhase.Out
        listEpoch++
    }

    fun resetList() {
        if (listPhase != ListPhase.Idle) {
            listPhase = ListPhase.Idle
            listEpoch++
        }
    }
}

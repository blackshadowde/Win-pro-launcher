# Start launcher — Phase 0 test build

Private Windows Phone 8.1–style launcher. This first build only answers one
question: **can the vivo X300 return home smoothly with our own turnstile
animation while gesture navigation is on?**

What's in it: a scrolling Start screen of tiles (your first 30 apps, mixed
small / medium / wide), turnstile in on return home, turnstile out with the
tapped tile last when opening an app, tilt on press, and a diagnostics bar.

## Build

1. Create a **private** GitHub repo and push this folder.
2. Actions tab → **Build APK** → Run workflow.
3. Download the `start-launcher-apk` artifact, unzip, install the APK.

## Set up on the phone

1. Settings → Apps → Default apps → Home app → **Start**.
2. Keep gesture navigation on (the bar at the bottom shows `nav: gestures`).

## Test checklist

The bottom bar shows which moment starts the animation. Tap it to cycle
**onStart → onResume → window focus**. Run each test in all three modes.

| # | Test | What to note |
|---|------|--------------|
| 1 | Is "Start" allowed with gestures at all? | Does vivo force 3-button nav or show a warning? |
| 2 | Open an app, swipe up to go home | Do tiles swing in smoothly? Any flash of old tiles or black screen? |
| 3 | Swipe home, tap a tile immediately | Does the tap work (queued) or get lost? |
| 4 | Back gesture from an app to home | Does the turnstile still play? |
| 5 | Swipe home and hold (recents) | Does recents open? Any delay? |
| 6 | Home gesture while already on Start, scrolled down | Should scroll back to top. |
| 7 | Tap tiles | Tilt toward your finger, others swing out, tapped tile last, app opens. |
| 8 | Leave Start alone 10+ min in another app, return | Did OriginOS kill it? (blank / slow first frame) |

Also send the two numbers from the bottom bar after a normal swipe home
(`start→resume` and `resume→focus`) for each mode. Those decide the default.

## Tuning

All timings, angles and easing are in
`app/src/main/java/com/tiles/launcher/Motion.kt`.

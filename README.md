# Start launcher

Private Windows Phone 8.1–style launcher for Android (Kotlin + Jetpack Compose).

## Phase 1 (current)

- **Start screen**: small / medium / wide tiles packed like WP 8.1, saved between runs.
  First run pins phone, messages, camera, photos, browser, email, music and settings.
- **Edit mode**: long-press a tile. Others shrink, dim and float. The selected tile gets
  **unpin** (top right) and **resize** (bottom right, cycles medium → small → wide).
  Drag to move; the rest reflow. Tap empty space or press back to finish.
- **App list**: swipe left (or tap the arrow under the tiles). A–Z letter headers,
  tap a letter for the jump grid, search box, long-press an app for
  *pin to start* / *uninstall*.
- **start + theme** (top of the app list): dark / light background, 20 accent colours,
  *show more tiles* (6 columns), and return-animation tuning.
- **Turnstile**: tiles swing out when opening an app (tapped tile last) and swing in on
  return home. The swing-in now waits for the system's own home animation to finish.

## Phase 2 (current)

- **Return home = the opening flip in reverse**: tiles flip back in from the side they
  left, the tile that opened the app first, the rest in reverse order.
- **App list turnstile**: rows swing out when you open an app (tapped row last) and
  swing back in when you come back to the list.
- **Solid status bar**: tiles and lists start below it and never scroll under it.
- **White tile icons**: uses each app's Android 13+ themed icon where available
  (toggle in start + theme).
- **Font**: start + theme → *load font files*. Pick your own Segoe WP `.ttf` files
  (all weights at once); the weight is read from the file name. Font files stay on the
  phone and are never committed to this repo.

## Styles

**start + theme → Style**:

- **classic 8.1**: solid black or white background, square tiles, WP app list.
- **modern**: wallpaper behind translucent rounded tiles, big clock and date above the
  tiles (tap for alarms), app list with colour icons, search pill and an A–Z strip.
  Turn off *White tile icons* for colour icons on tiles too.

Both styles use the same Windows Phone animations.

## Return-home animation tuning

In **start + theme → Return-home animation**:

- *starts*: `after system animation` (default) · `onStart` · `onResume` · `window focus`
- *extra delay*: 0 / 100 / 200 / 300 ms
- The line under it shows the timings of your last return home.

If the swing-in still isn't visible, try `after system animation` with 100–200 ms delay.

## Build

Actions tab → **Build APK** → Run workflow → download the `start-launcher-apk` artifact.

## Tuning

Timings, angles and easing: `app/src/main/java/com/tiles/launcher/Motion.kt`.

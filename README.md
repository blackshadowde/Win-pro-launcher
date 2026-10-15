# Vibe AI

A native Android chat app for [FreeLLMAPI](https://github.com/tashfeenahmed/freellmapi)
running in Termux on the same phone, in Vibe's Discord style.

- **Left rail**: *Auto* at the top (FreeLLMAPI picks the best free model for each message),
  then one avatar per provider that has a working key (Gemini, Groq, Cerebras, …).
- **Middle pane**: that provider's chats, *New chat*, and its models (green = ready).
- **Chat**: slides over Vibe-style and drags back from anywhere. Replies stream in and
  show which provider and model actually answered.
- **Fusion**: second rail entry. Several models answer at once, one blended answer comes back.
- **Key health**: a dot on each provider avatar (green OK, yellow rate limited, red problem).
- **Chat extras**: per-chat instructions (system prompt), image creation (image button),
  voice input (mic, uses Android's speech recognition).
- **User bar**: server status, start/stop FreeLLMAPI in Termux, settings.
- **Settings → Dashboard**: sign in once (only a 30-day session is kept, not the password);
  the unified API key fills itself in, pick the routing strategy for Auto, check all keys.

## First-time setup

1. Install **Termux** from F-Droid.
2. In Termux, paste this once (lets Vibe AI send it commands):
   ```
   mkdir -p ~/.termux && echo "allow-external-apps=true" >> ~/.termux/termux.properties && termux-reload-settings
   ```
3. In Vibe AI: **Settings → Install FreeLLMAPI in Termux** (allow the permission it asks for).
4. Tap **Start** in the user bar, open the dashboard (**+** in the rail) and add your provider keys.
5. In **Settings → Dashboard**, sign in with the dashboard account. The API key fills itself in.

## Signing (one time)

Add these repo secrets (**Settings → Secrets and variables → Actions → New repository secret**).
They are the same names Vibe uses, so you can paste Vibe's values:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | your keystore file, base64 encoded |
| `ANDROID_KEYSTORE_PASSWORD` | the keystore (and key) password |
| `ANDROID_KEY_ALIAS` | optional; defaults to `vibe` |

Every build is then signed with your key, so new APKs install over the old one and chats stay.
Without the secrets the build still works but uses a throwaway debug key.

## Updates

Each **Build APK** run also publishes a GitHub Release (`v0.1.<run number>`) with the APK.
In the app: **Settings → Updates → Check for updates → Download**.

## Build

Actions tab → **Build APK** → Run workflow → download `vibe-ai-apk`.

The workflow runs `flutter create` to generate the standard Android files; only
`android/app/src/main/AndroidManifest.xml` and `MainActivity.kt` (the Termux bridge) are kept in the repo.

## Credits

The slide-over gesture, press motion and haptics (`lib/ui/`) come from Vibe (AGPL-3.0),
so this app is AGPL-3.0 too. Font: Figtree (SIL OFL).

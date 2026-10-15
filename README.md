# Vibe AI

A native Android chat app for [FreeLLMAPI](https://github.com/tashfeenahmed/freellmapi)
running in Termux on the same phone, in Vibe's Discord style.

- **Left rail**: *Auto* at the top (FreeLLMAPI picks the best free model for each message),
  then one avatar per provider that has a working key (Gemini, Groq, Cerebras, …).
- **Middle pane**: that provider's chats, *New chat*, and its models (green = ready).
- **Chat**: slides over Vibe-style and drags back from anywhere. Replies stream in and
  show which provider and model actually answered.
- **User bar**: server status, start/stop FreeLLMAPI in Termux, settings.

## First-time setup

1. Install **Termux** from F-Droid.
2. In Termux, paste this once (lets Vibe AI send it commands):
   ```
   mkdir -p ~/.termux && echo "allow-external-apps=true" >> ~/.termux/termux.properties && termux-reload-settings
   ```
3. In Vibe AI: **Settings → Install FreeLLMAPI in Termux** (allow the permission it asks for).
4. Tap **Start** in the user bar, open the dashboard (**+** in the rail), add your provider
   keys, copy the **unified API key** and paste it in **Settings**.

## Build

Actions tab → **Build APK** → Run workflow → download `vibe-ai-apk`.

The workflow runs `flutter create` to generate the standard Android files; only
`android/app/src/main/AndroidManifest.xml` and `MainActivity.kt` (the Termux bridge) are kept in the repo.

## Credits

The slide-over gesture, press motion and haptics (`lib/ui/`) come from Vibe (AGPL-3.0),
so this app is AGPL-3.0 too. Font: Figtree (SIL OFL).

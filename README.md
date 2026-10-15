# Vibe AI

A native Android app for [FreeLLMAPI](https://github.com/tashfeenahmed/freellmapi): one APK,
FreeLLMAPI runs inside it (no Termux, no PC, no server), and you chat with 30+ free AI
providers in a Discord-style app.

**Download:** [latest release](https://github.com/blackshadowde/Vibe-AI/releases) (Android 8+, arm64).

- **Left rail**: *Auto* at the top (FreeLLMAPI picks the best free model for each message),
  then one avatar per provider that has a working key (Gemini, Groq, Cerebras, …).
- **Middle pane**: that provider's chats, *New chat*, and its models (green = ready).
- **Chat**: slides over Vibe-style and drags back from anywhere. Replies stream in and
  show which provider and model actually answered.
- **Fusion**: second rail entry. Several models answer at once, one blended answer comes back.
- **Key health**: a dot on each provider avatar (green OK, yellow rate limited, red problem).
- **Chat extras**: per-chat instructions (system prompt), image creation (image button),
  voice input (mic, uses Android's speech recognition).
- **User bar**: server status, start/stop the built-in server, live server logs, settings.
- **Settings → Dashboard**: sign in once (only a 30-day session is kept, not the password);
  the unified API key fills itself in, pick the routing strategy for Auto, check all keys.

## First-time setup (built-in server, default)

1. Tap **Start** in the user bar. The first start unpacks FreeLLMAPI (up to a minute);
   a notification shows while it runs. The terminal icon opens the live **server logs**.
2. Tap **+** in the rail to open the dashboard: create your account and add provider keys.
3. **Settings → Dashboard**: sign in with that account. The API key fills itself in.
4. **Settings → Keep it running → Allow running in the background** (recommended on vivo).

Termux is optional: **Settings → Server → Termux** switches back to running it there.

## Dashboard

The FreeLLMAPI dashboard opens inside the app (Settings → Open dashboard, or the dashboard button on the home screen). If you signed in under Settings, the dashboard uses the same session, so you don't log in twice.

## Plugins

The AI can use tools while it answers. Set them up in Settings → Plugins and integrations:

- **GitHub**: list repos, read files, search code, look at commits, issues and Actions runs. It can also explain why a build failed (failed steps, error annotations, end of the log). With write access it can open issues, comment, and commit a file.
- **Web page reader**: opens a link and reads the page.
- **MCP servers**: connect any MCP server that works over HTTP (Streamable HTTP), and its tools appear in chat.

Anything that changes something asks you first (Allow / Deny). Use the puzzle icon in a chat to turn plugins off for that chat. Fusion chats don't use tools. If a model rejects tools, the app retries once without them.

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

**[FreeLLMAPI](https://github.com/tashfeenahmed/freellmapi)** by Tashfeen Ahmed (MIT License) does
all the routing. Vibe AI bundles its production build (code unchanged; only x64-only native modules removed) and runs it with a bundled
Node.js (from Termux packages). FreeLLMAPI's MIT license notice is kept inside the bundle and
copied below. Please report routing or provider problems to FreeLLMAPI only if they also happen
outside this app.

<details><summary>FreeLLMAPI license</summary>

```
MIT License

Copyright (c) 2026 Tashfeen Ahmed

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
</details>

The slide-over gesture, press motion and haptics (`lib/ui/`) come from Vibe (AGPL-3.0),
so this app is AGPL-3.0 too. Font: Figtree (SIL OFL).

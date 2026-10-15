#!/usr/bin/env bash
# Builds FreeLLMAPI the way its own Docker image does (build, then drop dev packages)
# and packs the result into assets/server/ so the app can run it with its bundled Node.
#
# Usage (in CI, from the repo root): bash scripts/bundle_server.sh
set -euo pipefail

REPO_ROOT="$(pwd)"
OUT_DIR="$REPO_ROOT/assets/server"
WORK="$(mktemp -d)"

git clone --depth 1 https://github.com/tashfeenahmed/freellmapi.git "$WORK/src"
cd "$WORK/src"
COMMIT="$(git rev-parse --short HEAD)"
SERVER_VERSION="$(node -p "require('./server/package.json').version")"
echo "FreeLLMAPI $SERVER_VERSION ($COMMIT)"

npm ci --no-audit --no-fund
npm run build
npm prune --omit=dev

STAGE="$WORK/stage"
mkdir -p "$STAGE/server" "$STAGE/client"
cp package.json package-lock.json "$STAGE/"
cp LICENSE "$STAGE/LICENSE"  # keep the MIT notice inside the app
cp -R node_modules "$STAGE/node_modules"
if [ -d server/node_modules ]; then cp -R server/node_modules "$STAGE/server/node_modules"; fi
cp -R shared "$STAGE/shared"
cp server/package.json "$STAGE/server/"
if [ -f desktop/package.json ]; then mkdir -p "$STAGE/desktop" && cp desktop/package.json "$STAGE/desktop/"; fi
cp -R server/dist "$STAGE/server/dist"
cp -R client/dist "$STAGE/client/dist"

# Workspace packages are symlinks in node_modules; keep a real copy of `shared`, drop the rest.
rm -rf "$STAGE/node_modules/@freellmapi"
mkdir -p "$STAGE/node_modules/@freellmapi"
cp -R shared "$STAGE/node_modules/@freellmapi/shared"

# Native Linux x64 binaries can't run on Android. FreeLLMAPI uses Node's built-in SQLite
# on Android and loads sharp (image resizing) optionally, so these can go.
rm -rf "$STAGE/node_modules/@img" "$STAGE/node_modules/sharp" \
       "$STAGE/node_modules/better-sqlite3" "$STAGE/node_modules/.bin" \
       "$STAGE/server/node_modules/.bin"
find "$STAGE" -name "*.node" -type f -print -delete

mkdir -p "$OUT_DIR"
python3 - "$STAGE" "$OUT_DIR/freellmapi.zip" <<'PY'
import os, sys, zipfile
src, dst = sys.argv[1], sys.argv[2]
count = 0
with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for root, dirs, files in os.walk(src):
        dirs[:] = [d for d in dirs if not os.path.islink(os.path.join(root, d))]
        for f in files:
            p = os.path.join(root, f)
            if os.path.islink(p):
                continue
            z.write(p, os.path.relpath(p, src))
            count += 1
print(f"zipped {count} files")
PY

echo "$SERVER_VERSION-$COMMIT" > "$OUT_DIR/version.txt"
du -sh "$STAGE" "$OUT_DIR/freellmapi.zip"

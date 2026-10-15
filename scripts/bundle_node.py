#!/usr/bin/env python3
"""
Bundle Termux's Node.js (arm64) into the APK as native libraries.

Android only lets an app run programs that ship inside its APK (extracted to the
app's native library folder). So we download Termux's prebuilt `nodejs-lts` and
every library it needs, then rename them to lib*.so files the APK can carry and
rewrite their links with patchelf so they find each other there.

Usage (in CI): python3 scripts/bundle_node.py android/app/src/main/jniLibs/arm64-v8a
"""
import gzip
import io
import lzma
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request

MIRRORS = [
    "https://packages.termux.dev/apt/termux-main",
    "https://packages-cf.termux.dev/apt/termux-main",
    "https://grimler.se/termux/termux-main",
]
ARCH = "aarch64"
ROOT_PKG = "nodejs-lts"
NODE_OUT = "libvn_node.so"


def fetch(url):
    print("GET", url, flush=True)
    req = urllib.request.Request(url, headers={"User-Agent": "vibe-ai-ci"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def load_index():
    for base in MIRRORS:
        for suffix, decode in (("Packages", lambda b: b), ("Packages.xz", lzma.decompress), ("Packages.gz", gzip.decompress)):
            try:
                data = decode(fetch(f"{base}/dists/stable/main/binary-{ARCH}/{suffix}"))
                return base, data.decode("utf-8", "replace")
            except Exception as e:  # try next form / mirror
                print("  failed:", e)
    sys.exit("Could not download the Termux package index.")


def parse_index(text):
    pkgs = {}
    for stanza in text.split("\n\n"):
        fields = {}
        key = None
        for line in stanza.splitlines():
            if line.startswith(" ") and key:
                fields[key] += "\n" + line.strip()
            elif ":" in line:
                key, _, val = line.partition(":")
                fields[key.strip()] = val.strip()
        if "Package" in fields:
            pkgs[fields["Package"]] = fields
    return pkgs


def deps_of(fields):
    out = []
    for part in fields.get("Depends", "").split(","):
        part = part.strip()
        if not part:
            continue
        first = part.split("|")[0].strip()  # take the first alternative
        out.append(re.sub(r"\s*\(.*\)", "", first).strip())
    return out


def resolve(pkgs, root):
    seen, todo = [], [root]
    while todo:
        name = todo.pop()
        if name in seen or name not in pkgs:
            continue
        seen.append(name)
        todo.extend(deps_of(pkgs[name]))
    return seen


def extract_deb(data, dest):
    """Minimal `ar` reader: finds data.tar.* inside the .deb and extracts it."""
    assert data[:8] == b"!<arch>\n", "not a .deb"
    pos = 8
    while pos < len(data):
        header = data[pos:pos + 60]
        name = header[:16].decode().strip().rstrip("/")
        size = int(header[48:58].decode().strip())
        body = data[pos + 60:pos + 60 + size]
        pos += 60 + size + (size % 2)
        if not name.startswith("data.tar"):
            continue
        if name.endswith(".xz"):
            raw = lzma.decompress(body)
        elif name.endswith(".gz"):
            raw = gzip.decompress(body)
        elif name.endswith(".zst"):
            import zstandard  # pip install zstandard
            raw = zstandard.ZstdDecompressor().decompressobj().decompress(body)
        else:
            raw = body
        with tarfile.open(fileobj=io.BytesIO(raw)) as tar:
            tar.extractall(dest, filter="tar") if sys.version_info >= (3, 12) else tar.extractall(dest)
        return
    raise RuntimeError("no data.tar in .deb")


def needed(path):
    out = subprocess.run(["patchelf", "--print-needed", path], capture_output=True, text=True)
    return [l.strip() for l in out.stdout.splitlines() if l.strip()]


def android_name(orig):
    return "libvn_" + re.sub(r"[^A-Za-z0-9]", "_", orig) + ".so"


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    out_dir = sys.argv[1]
    os.makedirs(out_dir, exist_ok=True)

    base, text = load_index()
    pkgs = parse_index(text)
    names = resolve(pkgs, ROOT_PKG)
    print("Packages:", ", ".join(names), flush=True)
    if ROOT_PKG not in names:
        sys.exit(f"{ROOT_PKG} not found in the Termux index.")
    print(f"{ROOT_PKG} version:", pkgs[ROOT_PKG].get("Version"), flush=True)

    work = tempfile.mkdtemp(prefix="termux-")
    for n in names:
        extract_deb(fetch(f"{base}/{pkgs[n]['Filename']}"), work)

    usr = os.path.join(work, "data/data/com.termux/files/usr")
    node = os.path.join(usr, "bin/node")
    libdir = os.path.join(usr, "lib")
    if not os.path.isfile(node):
        sys.exit("node binary not found in the packages.")

    # Walk DT_NEEDED from node; anything not in Termux's lib folder comes from Android itself.
    mapping = {}  # needed name -> real file in termux
    todo = [node]
    done = set()
    while todo:
        f = todo.pop()
        if f in done:
            continue
        done.add(f)
        for lib in needed(f):
            cand = os.path.join(libdir, lib)
            if os.path.exists(cand):
                real = os.path.realpath(cand)
                mapping[lib] = real
                todo.append(real)
            else:
                print("  system lib:", lib)

    # Copy with Android-friendly names, then rewrite links between them.
    copies = {node: os.path.join(out_dir, NODE_OUT)}
    for lib, real in mapping.items():
        copies.setdefault(real, os.path.join(out_dir, android_name(lib)))
    for src, dst in copies.items():
        shutil.copyfile(src, dst)
        os.chmod(dst, 0o755)

    real_to_new = {real: os.path.basename(copies[real]) for real in mapping.values()}
    for src, dst in copies.items():
        subprocess.run(["patchelf", "--remove-rpath", dst], check=True)
        if src != node:
            subprocess.run(["patchelf", "--set-soname", os.path.basename(dst), dst], check=True)
        for lib in needed(dst):
            if lib in mapping:
                subprocess.run(["patchelf", "--replace-needed", lib, real_to_new[mapping[lib]], dst], check=True)

    total = 0
    for f in sorted(os.listdir(out_dir)):
        size = os.path.getsize(os.path.join(out_dir, f))
        total += size
        print(f"  {f}  {size / 1e6:.1f} MB  needs: {', '.join(needed(os.path.join(out_dir, f)))}")
    print(f"Bundled {len(copies)} files, {total / 1e6:.1f} MB", flush=True)


if __name__ == "__main__":
    main()

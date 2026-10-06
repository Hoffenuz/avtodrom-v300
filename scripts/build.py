"""
Builds everything that ships:

  1. native module (C++ GDExtension): host desktop (Windows x86_64, or Linux /
     macOS when building there), Android arm64 + x86_64
  2. course bake (res://data/course_baked.scn)
  3. exports: export/windows/Avtodrom.exe (Windows hosts only, since the Windows
     DLL needs MSVC), export/android/avtodrom.apk (release-signed with
     keys/avtodrom-release.keystore) and avtodrom-debug.apk

    python scripts/build.py               # everything
    python scripts/build.py --no-native   # skip the C++ builds
    python scripts/build.py --android     # only the Android exports (APK, debug APK, AAB)
    python scripts/build.py --windows     # only the Windows export (no C++ build)
    python scripts/build.py --installer   # the Windows export and its Setup .exe (Inno Setup 6)
    python scripts/build.py --web         # the wasm module and the browser export (export/web)
    python scripts/build.py --deploy-web  # export/web to Cloudflare (avtodrom.avtotestu.uz)

Web: Emscripten from emsdk (EMSDK, else C:/emsdk), the version Godot's web
templates were built with (4.0.11 for 4.7.2), and the 4.7.2 web templates
installed in Godot's export_templates folder.

Android SDK/NDK: ANDROID_HOME must not contain spaces (SCons response files).
On Windows this script uses C:/android_sdk, a junction to the SDK (created if
missing). On Linux/macOS it uses ANDROID_HOME, or ~/Android/Sdk (Linux) /
~/Library/Android/sdk (macOS) when that is unset.

Godot: see scripts/host.py (GODOT env var overrides the bundled binary).
"""
import os
import subprocess
import sys
from pathlib import Path

from host import MACOS, ROOT, WINDOWS, godot

GODOT = godot()
GAME = ROOT / "game"
NATIVE = ROOT / "native"
NDK = "28.2.13676358"
SDK_LINK = Path("C:/android_sdk")


def sh(cmd, cwd, env=None, timeout=None):
    print(">", " ".join(str(c) for c in cmd))
    try:
        r = subprocess.run(cmd, cwd=cwd, env=env, timeout=timeout)
    except subprocess.TimeoutExpired:
        sys.exit(f"timed out after {timeout} s (a script error can leave Godot waiting): {cmd}")
    if r.returncode != 0:
        sys.exit(f"failed: {cmd}")


def ensure_sdk_link():
    if SDK_LINK.exists():
        return
    sdk = Path(os.environ["LOCALAPPDATA"]) / "Android" / "Sdk"
    subprocess.run(["cmd", "/c", "mklink", "/J", str(SDK_LINK), str(sdk)], check=True)


def android_home():
    if WINDOWS:
        ensure_sdk_link()
        return str(SDK_LINK).replace("\\", "/")
    if os.environ.get("ANDROID_HOME"):
        sdk = os.environ["ANDROID_HOME"]
    elif MACOS:
        sdk = str(Path.home() / "Library" / "Android" / "sdk")
    else:
        sdk = str(Path.home() / "Android" / "Sdk")
    if " " in sdk:
        sys.exit(f"ANDROID_HOME must not contain spaces (symlink it somewhere without them): {sdk}")
    return sdk


def native():
    scons = [sys.executable, "-m", "SCons", "-j12"]
    sh(scons + ["target=template_debug"], NATIVE)
    sh(scons + ["target=template_release"], NATIVE)
    env = dict(os.environ, ANDROID_HOME=android_home())
    for arch in ("arm64", "x86_64"):
        for target in ("template_debug", "template_release"):
            sh(scons + ["platform=android", f"arch={arch}", f"target={target}", f"ndk_version={NDK}"], NATIVE, env)


def emsdk_env():
    """The environment emsdk_env would set up: emcc and its own Python and Node on PATH."""
    root = Path(os.environ.get("EMSDK", "C:/emsdk" if WINDOWS else str(Path.home() / "emsdk")))
    emcc = root / "upstream" / "emscripten"
    if not emcc.exists():
        sys.exit(f"Emscripten not found in {root} (emsdk install 4.0.11 && emsdk activate 4.0.11)")
    env = dict(os.environ, EMSDK=str(root))
    paths = [str(root), str(emcc)]
    for tool, var, exe in (("python", "EMSDK_PY", "python.exe" if WINDOWS else "bin/python3"),
                           ("node", "EMSDK_NODE", "bin/node.exe" if WINDOWS else "bin/node")):
        found = sorted((root / tool).glob("*/" + exe))
        if found:
            env[var] = str(found[-1])
            paths.append(str(found[-1].parent))
    env["PATH"] = os.pathsep.join(paths + [os.environ.get("PATH", "")])
    return env


def native_web():
    sh([sys.executable, "-m", "SCons", "-j12", "platform=web", "target=template_release", "threads=no"],
       NATIVE, emsdk_env())


def export_web():
    """Browser build: no threads, so any static host serves it (no COOP/COEP
    headers needed)."""
    import shutil
    out = ROOT / "export" / "web"
    shutil.rmtree(out, ignore_errors=True)
    out.mkdir(parents=True, exist_ok=True)
    sh([str(GODOT), "--headless", "--path", str(GAME), "--export-release", "Web", str(out / "index.html")], GAME)


def deploy_web():
    """export/web -> Cloudflare (deploy/cloudflare): every file gzipped, the
    ones over the 25 MiB static-asset limit split into parts that the Worker
    joins again. Needs `npx wrangler login` once."""
    import gzip
    import json
    import shutil
    import time
    src = ROOT / "export" / "web"
    if not (src / "index.html").exists():
        sys.exit("no export/web: run with --web first")
    out = ROOT / "export" / "web-cf"
    shutil.rmtree(out, ignore_errors=True)
    out.mkdir(parents=True)
    part_max = 24 * 1024 * 1024
    build = "%s-%s" % (version(), time.strftime("%Y%m%d%H%M%S"))
    files = {}
    for f in sorted(src.iterdir()):
        if not f.is_file() or f.suffix == ".gz":
            continue
        data = gzip.compress(f.read_bytes(), compresslevel=9, mtime=0)
        parts = []
        for i in range(0, len(data), part_max):
            name = "%s.gz.%d" % (f.name, len(parts))
            (out / name).write_bytes(data[i:i + part_max])
            parts.append(name)
        files[f.name] = {"size": len(data), "parts": parts}
    (out / "_manifest.json").write_text(json.dumps({"build": build, "files": files}, indent=1), encoding="utf-8")
    print("web build %s: %d files, %.1f MB gzipped" % (build, len(files),
          sum(e["size"] for e in files.values()) / 1e6))
    npx = shutil.which("npx") or "npx"
    sh([npx, "-y", "wrangler@4", "deploy"], ROOT / "deploy" / "cloudflare")


def bake():
    sh([str(GODOT), "--headless", "--path", str(GAME), "--import"], GAME)
    # The bake takes about a second; a compile error in a script it loads
    # leaves Godot waiting for ever instead of failing.
    sh([str(GODOT), "--headless", "--path", str(GAME), "--script", "res://tests/bake_course.gd"], GAME, timeout=300)


def credentials():
    creds = {}
    path = ROOT / "keys" / "release_credentials.txt"
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            creds[k.strip()] = v.strip()
    return creds


def export_android():
    out = ROOT / "export" / "android"
    out.mkdir(parents=True, exist_ok=True)
    c = credentials()
    env = dict(os.environ,
               GODOT_ANDROID_KEYSTORE_RELEASE_PATH=str(ROOT / c["keystore"]),
               GODOT_ANDROID_KEYSTORE_RELEASE_USER=c["alias"],
               GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=c["password"])
    sh([str(GODOT), "--headless", "--path", str(GAME), "--export-release", "Android", str(out / "avtodrom.apk")],
       GAME, env)
    sh([str(GODOT), "--headless", "--path", str(GAME), "--export-debug", "Android", str(out / "avtodrom-debug.apk")],
       GAME, env)
    # The Play Store bundle: a Gradle build from the installed Android build
    # template (game/android/build; see README), signed with the same key.
    sh([str(GODOT), "--headless", "--path", str(GAME), "--export-release", "Android AAB", str(out / "avtodrom.aab")],
       GAME, env)


def export_windows():
    out = ROOT / "export" / "windows"
    out.mkdir(parents=True, exist_ok=True)
    sh([str(GODOT), "--headless", "--path", str(GAME), "--export-release", "Windows", str(out / "Avtodrom.exe")], GAME)


def iscc():
    """Inno Setup's compiler: ISCC on PATH, or the per-user / machine install."""
    import shutil
    found = shutil.which("ISCC")
    if found:
        return found
    for base in (os.environ.get("LOCALAPPDATA", ""), os.environ.get("ProgramFiles(x86)", ""),
                 os.environ.get("ProgramFiles", "")):
        c = Path(base) / ("Programs" if base == os.environ.get("LOCALAPPDATA") else "") / "Inno Setup 6" / "ISCC.exe"
        if c.exists():
            return str(c)
    sys.exit("Inno Setup 6 not found (winget install JRSoftware.InnoSetup)")


def version():
    for line in (GAME / "project.godot").read_text(encoding="utf-8").splitlines():
        if line.startswith("config/version="):
            return line.split("=", 1)[1].strip().strip('"')
    return "1.0.0"


def build_installer():
    sh([iscc(), f"/DAppVersion={version()}", str(ROOT / "scripts" / "installer.iss")], ROOT)


def main():
    args = sys.argv[1:]
    only_android = "--android" in args
    if "--web" in args or "--deploy-web" in args:
        if "--web" in args:
            if "--no-native" not in args:
                native_web()
            bake()
            export_web()
            print("done ->", ROOT / "export" / "web")
        if "--deploy-web" in args:
            deploy_web()
        return
    if "--windows" in args or "--installer" in args:
        bake()
        export_windows()
        if "--installer" in args:
            build_installer()
        print("done ->", ROOT / "export")
        return
    if "--no-native" not in args and not only_android:
        native()
    bake()
    export_android()
    if not only_android:
        if WINDOWS:
            export_windows()
        else:
            print("skipping Windows export: the Windows DLL is only built on Windows hosts")
    print("done ->", ROOT / "export")


if __name__ == "__main__":
    main()

"""
Builds everything that ships:

  1. native module (C++ GDExtension): Windows x86_64, Android arm64 + x86_64
  2. course bake (res://data/course_baked.scn)
  3. exports: export/windows/Avtodrom.exe, export/android/avtodrom.apk
     (release-signed with keys/avtodrom-release.keystore) and avtodrom-debug.apk

    python scripts/build.py               # everything
    python scripts/build.py --no-native   # skip the C++ builds
    python scripts/build.py --android     # only the Android export

Android SDK/NDK: ANDROID_HOME must not contain spaces (SCons response files);
this script uses C:/android_sdk, a junction to the SDK (created if missing).
"""
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GODOT = ROOT / "tools" / "godot" / "Godot_v4.7.2-stable_win64_console.exe"
GAME = ROOT / "game"
NATIVE = ROOT / "native"
NDK = "28.2.13676358"
SDK_LINK = Path("C:/android_sdk")


def sh(cmd, cwd, env=None):
    print(">", " ".join(str(c) for c in cmd))
    r = subprocess.run(cmd, cwd=cwd, env=env)
    if r.returncode != 0:
        sys.exit(f"failed: {cmd}")


def ensure_sdk_link():
    if SDK_LINK.exists():
        return
    sdk = Path(os.environ["LOCALAPPDATA"]) / "Android" / "Sdk"
    subprocess.run(["cmd", "/c", "mklink", "/J", str(SDK_LINK), str(sdk)], check=True)


def native():
    scons = [sys.executable, "-m", "SCons", "-j12"]
    sh(scons + ["target=template_debug"], NATIVE)
    sh(scons + ["target=template_release"], NATIVE)
    ensure_sdk_link()
    env = dict(os.environ, ANDROID_HOME=str(SDK_LINK).replace("\\", "/"))
    for arch in ("arm64", "x86_64"):
        for target in ("template_debug", "template_release"):
            sh(scons + ["platform=android", f"arch={arch}", f"target={target}", f"ndk_version={NDK}"], NATIVE, env)


def bake():
    sh([str(GODOT), "--headless", "--path", str(GAME), "--import"], GAME)
    sh([str(GODOT), "--headless", "--path", str(GAME), "--script", "res://tests/bake_course.gd"], GAME)


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


def export_windows():
    out = ROOT / "export" / "windows"
    out.mkdir(parents=True, exist_ok=True)
    sh([str(GODOT), "--headless", "--path", str(GAME), "--export-release", "Windows", str(out / "Avtodrom.exe")], GAME)


def main():
    args = sys.argv[1:]
    only_android = "--android" in args
    if "--no-native" not in args and not only_android:
        native()
    bake()
    export_android()
    if not only_android:
        export_windows()
    print("done ->", ROOT / "export")


if __name__ == "__main__":
    main()

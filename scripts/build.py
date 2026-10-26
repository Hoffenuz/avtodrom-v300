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
    python scripts/build.py --web-engine  # the slim web engine the Web export then uses (see web_engine())
    python scripts/build.py --publish-web # export/web to github.com/avtodrom/avtodrom-web (Cloudflare deploys it)
    python scripts/build.py --deploy-web  # export/web straight to Cloudflare (wrangler login)

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


# The slim web engine (--web-engine): Godot's source of the bundled version
# (GODOT_SRC, else C:/gsrc/godot-4.7.2-stable: a short path, SCons on Windows
# trips over long ones) built with scripts/web_engine_profile.py. The Web
# export uses it when it is there, the stock template otherwise.
WEB_TEMPLATE = ROOT / "tools" / "web_template" / "web_dlink_nothreads_release.zip"


def web_engine():
    import shutil
    src = Path(os.environ.get("GODOT_SRC", "C:/gsrc/godot-4.7.2-stable"))
    if not (src / "SConstruct").exists():
        sys.exit(f"Godot source not found in {src} (godot-4.7.2-stable.tar.xz from the GitHub release)")
    sh([sys.executable, "-m", "SCons", "-j12", "platform=web", "target=template_release", "threads=no",
        "dlink_enabled=yes", "optimize=size", "lto=full",
        "profile=" + str(ROOT / "scripts" / "web_engine_profile.py")],
       src, emsdk_env())
    WEB_TEMPLATE.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy(src / "bin" / "godot.web.template_release.wasm32.nothreads.dlink.zip", WEB_TEMPLATE)


def web_preset_template(path):
    """Points the Web preset's release template at [path] ("" for the stock
    one) in export_presets.cfg; returns the file's text before."""
    cfg = GAME / "export_presets.cfg"
    text = cfg.read_bytes().decode("utf-8")
    head, sep, rest = text.partition('[preset.3.options]')
    if 'name="Web"' not in head.rsplit("[preset.3]", 1)[-1]:
        sys.exit("export_presets.cfg: preset 3 is not Web")
    rest = rest.replace('custom_template/release=""', 'custom_template/release="%s"' % path, 1)
    cfg.write_bytes((head + sep + rest).encode("utf-8"))
    return text


# Textures the phones' pack carries smaller (size limit, pixels): the ground's
# normal and roughness maps (fine detail a phone's screen hardly shows) and
# the road-sign atlas. The colour maps and the sky stay as they are.
MOBILE_SMALL = {
    **{"assets/textures/%s/%s.jpg" % (g, m): 512 for g in ("asphalt", "concrete", "grass") for m in ("normal", "arm")},
    "assets/signs/atlas.png": 1024,
}
MOBILE_TEX = "_mobile_tex" # in game/, left out of every pack (export_presets.cfg)


def _import_remap(path):
    """The [remap] values of a .import file."""
    out = {}
    section = ""
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("["):
            section = line.strip("[]")
        elif section == "remap" and "=" in line:
            k, v = line.split("=", 1)
            out[k] = v.strip('"')
    return out


def mobile_textures():
    """Copies of the MOBILE_SMALL textures, imported at their phone size.
    Returns {pack path of an original's ETC2 file: the smaller copy's bytes}."""
    import shutil
    tmp = GAME / MOBILE_TEX
    tmp.mkdir(exist_ok=True)
    for src, limit in MOBILE_SMALL.items():
        copy = tmp / src.replace("/", "_")
        if not copy.exists() or copy.stat().st_mtime < (GAME / src).stat().st_mtime:
            shutil.copy2(GAME / src, copy)
        # The original's import settings, the size limit lowered; Godot fills
        # in the rest (uid, imported paths) when it imports the copy.
        params = (GAME / (src + ".import")).read_text(encoding="utf-8").split("[params]", 1)[1]
        params = "\n".join("process/size_limit=%d" % limit if l.startswith("process/size_limit=") else l
                           for l in params.splitlines())
        want = '[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]' + params
        imp = Path(str(copy) + ".import")
        if not imp.exists() or "process/size_limit=%d" % limit not in imp.read_text(encoding="utf-8"):
            imp.write_text(want, encoding="utf-8")
    sh([str(GODOT), "--headless", "--path", str(GAME), "--import"], GAME)
    swap = {}
    for src in MOBILE_SMALL:
        orig = _import_remap(GAME / (src + ".import")).get("path.etc2", "")
        small = _import_remap(Path(str(tmp / src.replace("/", "_")) + ".import")).get("path.etc2", "")
        if not orig or not small:
            sys.exit("no ETC2 import for %s" % src)
        swap[orig.replace("res://", "")] = (GAME / small.replace("res://", "")).read_bytes()
    return swap


def patch_pack(pck, swap):
    """Rewrites a .pck (format 3+, offsets from the file base) with the
    contents of some of its files replaced: {path in the pack: new bytes}."""
    import hashlib
    import struct
    data = pck.read_bytes()
    magic, ver = struct.unpack_from("<II", data, 0)
    flags, base, diroff = struct.unpack_from("<IQQ", data, 20)
    if magic != 0x43504447 or ver < 3 or not flags & 2:
        sys.exit("unexpected pack format in %s" % pck)
    count, = struct.unpack_from("<I", data, diroff)
    pos = diroff + 4
    entries = []
    for _ in range(count):
        plen, = struct.unpack_from("<I", data, pos)
        raw_path = data[pos + 4:pos + 4 + plen]
        off, size = struct.unpack_from("<QQ", data, pos + 4 + plen)
        efl, = struct.unpack_from("<I", data, pos + 4 + plen + 32)
        entries.append([raw_path, off, size, efl])
        pos += 4 + plen + 36
    tail = data[pos:]
    body = bytearray()
    done = set()
    for e in sorted(entries, key=lambda e: e[1]):
        path = e[0].rstrip(b"\0").decode()
        content = swap[path] if path in swap else data[base + e[1]:base + e[1] + e[2]]
        if path in swap:
            done.add(path)
        body += b"\0" * ((-(base + len(body))) % 16)
        e[1] = len(body)
        e[2] = len(content)
        e.append(hashlib.md5(content).digest())
        body += content
    if done != set(swap):
        sys.exit("not in %s: %s" % (pck.name, sorted(set(swap) - done)))
    body += b"\0" * ((-(base + len(body))) % 16)
    out = bytearray(data[:base])
    struct.pack_into("<Q", out, 32, base + len(body))
    out += body
    out += struct.pack("<I", count)
    for raw_path, off, size, efl, md5 in entries:
        out += struct.pack("<I", len(raw_path)) + raw_path + struct.pack("<QQ", off, size) + md5 + struct.pack("<I", efl)
    out += tail
    pck.write_bytes(bytes(out))


def export_web():
    """Browser build: no threads, so any static host serves it (no COOP/COEP
    headers needed)."""
    import shutil
    out = ROOT / "export" / "web"
    shutil.rmtree(out, ignore_errors=True)
    out.mkdir(parents=True, exist_ok=True)
    if WEB_TEMPLATE.exists():
        presets = web_preset_template(WEB_TEMPLATE.as_posix())
        try:
            sh([str(GODOT), "--headless", "--path", str(GAME), "--export-release", "Web", str(out / "index.html")],
               GAME)
        finally:
            (GAME / "export_presets.cfg").write_bytes(presets.encode("utf-8"))
    else:
        print("no slim web engine (--web-engine): exporting with the stock template")
        sh([str(GODOT), "--headless", "--path", str(GAME), "--export-release", "Web", str(out / "index.html")], GAME)
    # Textures come in one GPU format a pack: computers' browsers read S3TC
    # (index.pck), phones' ETC2 (this one); the page picks the pack the GPU
    # reads, so nobody downloads (and holds in memory) both.
    sh([str(GODOT), "--headless", "--path", str(GAME), "--export-pack", "Web Mobile", str(out / "index.mobile.pck")],
       GAME)
    before = (out / "index.mobile.pck").stat().st_size
    patch_pack(out / "index.mobile.pck", mobile_textures())
    print("phones' pack: %.1f -> %.1f MB" % (before / 1e6, (out / "index.mobile.pck").stat().st_size / 1e6))
    # The engine's service worker served a stale page; this one removes it
    # from the browsers that have it (see game/web/service_worker.js).
    shutil.copy(GAME / "web" / "service_worker.js", out / "index.service.worker.js")
    # For search engines and link previews: robots.txt, sitemap.xml (dated
    # by this build), the preview picture og.jpg, Google's site check file.
    import time
    for f in (ROOT / "deploy" / "web").iterdir():
        if f.name == "sitemap.xml":
            (out / f.name).write_text(f.read_text(encoding="utf-8").replace("__LASTMOD__", time.strftime("%Y-%m-%d")),
                                      encoding="utf-8")
        else:
            shutil.copy(f, out / f.name)


WEB_REPO = "https://github.com/avtodrom/avtodrom-web.git"


def package_web(out):
    """export/web -> a Cloudflare Worker project in `out` (worker.js,
    wrangler.toml, public/): every file gzipped, the ones over the 25 MiB
    static-asset limit split into parts that the Worker joins again. Each
    file carries a hash of its content: its ETag, and the page's cache key,
    so a release re-downloads only the files it changed."""
    import gzip
    import hashlib
    import json
    import shutil
    import time
    src = ROOT / "export" / "web"
    if not (src / "index.html").exists():
        sys.exit("no export/web: run with --web first")
    pub = out / "public"
    shutil.rmtree(pub, ignore_errors=True)
    pub.mkdir(parents=True, exist_ok=True) # a running `wrangler dev` may keep the folder
    for old in pub.iterdir():
        old.unlink()
    part_max = 24 * 1024 * 1024
    build = "%s-%s" % (version(), time.strftime("%Y%m%d%H%M%S"))
    files = {}
    packed = {}
    hashes = {}
    for f in sorted(src.iterdir()):
        if f.is_file() and f.suffix != ".gz" and f.name != "index.html":
            raw = f.read_bytes()
            packed[f.name] = gzip.compress(raw, compresslevel=9, mtime=0)
            hashes[f.name] = hashlib.sha256(raw).hexdigest()[:16]
    # The page shows the download in real (gzipped) megabytes: it gets every
    # file the engine fetches with its unpacked and packed size, and the hash
    # it keeps the file under.
    sizes = {n: [(src / n).stat().st_size, len(d), hashes[n]] for n, d in packed.items()
             if n.endswith((".pck", ".wasm"))}
    # The build names the page's own cache of the engine and the pack.
    html = (src / "index.html").read_text(encoding="utf-8").replace("__AVTODROM_SIZES__", json.dumps(sizes)) \
        .replace("__AVTODROM_BUILD__", build)
    packed["index.html"] = gzip.compress(html.encode("utf-8"), compresslevel=9, mtime=0)
    hashes["index.html"] = hashlib.sha256(html.encode("utf-8")).hexdigest()[:16]
    for name in sorted(packed):
        f = src / name
        data = packed[name]
        parts = []
        for i in range(0, len(data), part_max):
            part = "%s.gz.%d" % (f.name, len(parts))
            (pub / part).write_bytes(data[i:i + part_max])
            parts.append(part)
        files[f.name] = {"size": len(data), "parts": parts, "hash": hashes[name]}
    (pub / "_manifest.json").write_text(json.dumps({"build": build, "files": files}, indent=1), encoding="utf-8")
    cf = ROOT / "deploy" / "cloudflare"
    for name in ("worker.js", "wrangler.toml", "README.md"):
        shutil.copy(cf / name, out / name)
    print("web build %s: %d files, %.1f MB gzipped" % (build, len(files),
          sum(e["size"] for e in files.values()) / 1e6))
    return build


def deploy_web():
    """Straight to Cloudflare from this machine (needs `npx wrangler login`)."""
    import shutil
    out = ROOT / "export" / "web-cf"
    package_web(out)
    sh([shutil.which("npx") or "npx", "-y", "wrangler@4", "deploy"], out)


def publish_web():
    """To the avtodrom-web repository; Cloudflare (Workers Builds) deploys
    each push. One commit only: the repository holds the current build, not a
    history of 40 MB builds."""
    out = ROOT / "export" / "web-repo"
    if not (out / ".git").exists():
        out.mkdir(parents=True, exist_ok=True)
        sh(["git", "init", "-q", "-b", "main"], out)
        sh(["git", "remote", "add", "origin", WEB_REPO], out)
    build = package_web(out)
    sh(["git", "checkout", "-q", "--orphan", "build"], out)
    sh(["git", "add", "-A"], out)
    sh(["git", "commit", "-q", "-m", "Web build " + build], out)
    sh(["git", "branch", "-q", "-M", "main"], out)
    sh(["git", "push", "-q", "-f", "origin", "main"], out)


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
    if WINDOWS:
        ensure_sdk_link() # the editor settings point Godot there, also with --no-native
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
    if "--web-engine" in args:
        web_engine()
    if "--web" in args or "--deploy-web" in args or "--publish-web" in args:
        if "--web" in args:
            if "--no-native" not in args:
                native_web()
            bake()
            export_web()
            print("done ->", ROOT / "export" / "web")
        if "--deploy-web" in args:
            deploy_web()
        if "--publish-web" in args:
            publish_web()
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

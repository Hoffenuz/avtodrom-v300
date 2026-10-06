---
name: avtodrom-godot
description: AvtoSmart Avtodrom (Godot 4.7.2 + C++ GDExtension haydovchilik imtihoni simulyatori) loyihasida ishlash tartibi — build/test buyruqlari, debug bayroqlari, skrinshot olish, Blender pipeline, Android AAB/APK, ma'lum tuzoqlar. Shu repozitoriyda istalgan vazifa (xato tuzatish, grafika, mashina qo'shish, build, Play Store) boshlanganda ishlating.
---

# AvtoSmart Avtodrom — ish tartibi

Har qadamdan oldin: kerakli faylni `Grep` bilan toping, `Read` ni `offset/limit` bilan o'qing
(`token-limit-discipline` skilli). Bu yerdagi buyruqlarni qayta "kashf qilmang".

## Tuzilma (qisqa)
- `native/src/sim` — fizika (C++, Godot'siz), `native/src/godot` — `AvtoVehicle` (RigidBody3D).
- `game/src/exam` — `ExamDirector` + `ex_*.gd` mashqlar; `game/src/game/drive.gd` — haydash sahnasi;
  `autopilot.gd` — "Namuna" va e2e test; `traffic_cars.gd` — boshqa qatnashchilar.
- `game/src/course/surroundings.gd` — bino, daraxt, shahar (har yuklashda qayta quriladi).
- `pipeline/course_def.py` — avtodrom geometriyasi → `game/data/course.json`;
  `--truck` → `course_truck.json` (Gazelle, BC toifa marshruti). O'zgartirgach bake qiling.
  Yengil/yuk farqi (sxema bo'yicha): 90° — yuk 1-yo'lak, yengil 2-; zmeyka — yengil B (sharqiy, 1-),
  yuk A (g'arbiy, keng); quti — yuk P1; parallel — yengil cho'ntaklar (7.6.1+7.4.3), yuk finish
  orolidagi uzun cho'ntak (7.6.1+7.4.1, TRUCK_POCKET_PX). `--debug` ikkala rejimda overlay chizadi
  (`reference/debug_course[_truck].png`). Belgi rasmi o'zgarsa: `python pipeline/make_sign_atlas.py` + import.
- Mashinalar: `car.gd` `MODELS` + C++ preset (`vehicle_params.cpp`). Yuk: `CourseData.TRUCKS`.

## Buyruqlar (repo ildizidan, Git Bash)
```
G=tools/godot/Godot_v4.7.2-stable_win64_console.exe
py scripts/run_tests.py --quick              # C++ 63 + Jolt 20 (~1 daq). `python` 3.11 da SCons yo'q → `py` (3.14)
python scripts/run_tests.py                  # to'liq: 4 mashina e2e, xato aniqlash, 60 namuna (~50 daq, fonda!)
(cd game && ../$G --headless --path . --import)                       # yangi class_name / asset'dan keyin
(cd game && ../$G --headless --path . --script res://tests/bake_course.gd)  # course.json o'zgarsa
python pipeline/course_def.py [--debug] ; python pipeline/course_def.py --truck
python pipeline/i18n_source.py               # matnlar (3 til) -> game/data/i18n.json
python scripts/build.py --installer          # bake + Windows EXE + Inno Setup o'rnatuvchi
python scripts/build.py --android            # APK + debug APK + AAB (imzolangan)
py scripts/build.py --web [--no-native]      # wasm (emsdk C:/emsdk, 4.0.11) + export/web (threadsiz, dlink)
py -m http.server 8060 --directory export/web   # lokal sinov (eksportdan OLDIN serverni to'xtating — papka band bo'ladi)
(cd native && python -m SCons -j12 target=template_release)  # C++ o'zgarsa; Android: platform=android arch=arm64 ndk_version=28.2.13676358
```
Bitta mashq/imtihon tekshiruvi (headless, tez):
`(cd game && ../$G --headless --path . res://scenes/drive.tscn --fixed-fps 120 -- --autopilot-test --quit-after-s=600 --car=gazelle --mode=practice --exercise=box --demo) | grep -E "^RESULT|^PENALTY"`
Kutilgan natija: `RESULT ... penalty=0`.

## Debug bayroqlari (`--` dan keyin)
`--mode=exam|practice|free --exercise=<id> --demo --car=nexia2|cobalt_at|gentra|gazelle --camera=cockpit|chase|top
--autopilot --seed=N --traffic=N --traffic-near --traffic-log --quality=0..2 --set=key:value --perf
--shots=<dir> --shot-every=S --quit-after-s=S --menu-page=... --settings-tab=... --start=exam|free|<id>
--stall-test --print-diagnostics --physics-hz=60 --no-process=<node,...> --keys-sheet (F1 oynasi ochiq) --hang-test`
- Eksport EXE sahna yo'lini qabul qilmaydi → `--start=` bilan menyudan kiring.
- Skrinshot: `--windowed --resolution 1920x1080` (aks holda to'liq ekran va fokusni oladi).
- Statik ko'rinishlar: `res://tests/scenery_shots.tscn -- <dir> <quality> <shots.json>`;
  mashina yaqindan: `res://tests/car_render_test.tscn -- <dir> <car> [detail|detail_lit|spin|brake|turn]`
  (`turn` — chap burilish chiroqlari yonib turadi; kabina suratlarida `set_interior_audio(true)`).

## Tuzoqlar (har safar tekshiring)
- Bake (`tests/bake_course.gd`) `--script` rejimida ishlaydi — autoload'lar (`Loading`, `Settings`, `Session`,
  `Loc`) yo'q. `course/`, `vehicle/car.gd` va ular yuklaydigan skriptlarda autoload'ni NOM bilan chaqirmang
  (kompilyatsiya xatosi → bake abadiy kutadi). Daraxt orqali: `(Engine.get_main_loop() as SceneTree).root.get_node_or_null("Loading")`.
- Cursor'dagi godot-tools LSP (`--lsp-port`) DLL'ni band qiladi → import/bake/export oldidan o'ldiring.
- Foydalanuvchi `export/windows/Avtodrom.exe` ni ochib qo'yishi mumkin → eksport `.tmp` bo'lib qoladi.
- Bu tarmoqda katta HTTPS yuklamalar buziladi: `curl -C -` bilan qayta urining; Gradle `tools/gradle/` dan.
- AAB eksporti birinchi urinishda Maven xatosi bilan yiqilishi mumkin — qayta ishga tushiring.
- AAB yozilgandan keyin Godot jarayoni yopilmay qolsa — Gradle demoni oqimni ushlagan:
  `game/android/build/gradle.properties` da `org.gradle.daemon=false` bo'lishi kerak (shablon qayta
  o'rnatilsa yana qo'shing). Fon build'lari tugaganini fayl vaqtidan ham tekshiring.
- Heredoc ichida apostrof (`'`) bo'lgan uzun Python tahrirlar Bash'da buziladi → skriptni fayl qilib yozing.
- Blender: `"/c/Program Files/Blender Foundation/Blender 5.1/blender.exe" -b --python <script> -- ...`;
  skriptni `inspect.py` deb nomlamang (std modulni yopadi).
- Sozlamalar foydalanuvchiniki: `%APPDATA%/Godot/app_userdata/Avtodrom/settings.cfg` — testda `--set` saqlab
  qo'yishi mumkin, oldin nusxa oling.
- Versiya 3 joyda: `project.godot config/version`, `export_presets.cfg` (2 ta Android preset: code+name,
  Windows file/product_version). Play'ga har yuklashda versionCode +1.

## Yuklash muammosi (loading'da qotish)
- Butun dastur qotsa (GPU drayveri pipeline yaratishda osiladi) hech qanday kod ishlamaydi. Shuning uchun
  "himoya belgisi": `Loading.guard_begin/guard_end` → `user://hang_guard.cfg`; keyingi ishga tushishda
  belgi qolgan bo'lsa → `user://graphics_override.cfg` (OpenGL) + past sifat + menyuda ogohlantirish.
  Faqat release build'da (`--guard-test` bilan editor'da ham). `--no-restart` — avtomatik qayta ishga tushmasin.
- Tasdiqlangan sabab: AMD integrated GPU Vulkan'da osiladi, OpenGL'da ishlaydi. 1.0.4 dan: Android standart
  OpenGL; desktop integrated GPU birinchi ishga tushishda OpenGL'ga o'tadi (`renderer_checked`); watchdog oqimi
  guard paytida 20 s kadr bo'lmasa OpenGL yozib darhol qayta ishga tushiradi (`relaunch_now`). Sinov:
  `--guard-test --start=free --hang-test` (Vulkan'da 120 s osiladi → 20 s da OpenGL'da qayta ochiladi).
  Qayta ochilgan jarayon alohida — natijani `logs/godot.log` dan o'qing; testdan keyin override va settings'ni tiklang.
- Renderer'ni almashtirish: `project.godot` → `config/project_settings_override="user://graphics_override.cfg"`;
  Sozlamalar → Grafika → "OpenGL (moslik) rejimi". Testlardan keyin bu faylni o'chiring.
- `Loading.stage("<nom>")` har bosqichni jurnalga yozadi (`LOAD step ...`). 30 s ichida tugamasa
  ekranda "Yuklash to'xtab qoldi" + "Jurnalni nusxalash". Sozlamalar → Ilova haqida → "Jurnalni nusxalash"
  qurilma/GPU/sozlama + oxirgi 2 jurnalni beradi. Foydalanuvchidan shu matnni so'rang.
- Sifat: `Settings.detect_quality()` GPU turiga qarab; `drive.gd _watch_frame_rate` FPS < 22 bo'lsa
  avtomatik pasaytiradi (`quality_user` true bo'lsa yo'q).

## Web (brauzer) versiyasi
- Renderer faqat WebGL2 = gl_compatibility, telefon bilan bir xil yo'l. `OS.has_feature("web")`; Android brauzer `web_android` → `Settings.is_mobile()` true.
- Godot web shablonlari: `%APPDATA%/Godot/export_templates/4.7.2.stable/web_dlink_nothreads_*.zip` (tpz dan ochilgan). Preset "Web": extensions_support=true, thread_support=false (COOP/COEP kerak emas).
- project.godot web overridelari: `audio/general/default_playback_type.web=0` (Stream; aks holda EngineSound generator jim), `window/size/mode.web=0`, `limits/opengl/max_*lights*.web=2` (omni/spot yo'q; D3D kompilyatsiyasi ~20% tezroq).
- Webda yashirilgan: OpenGL tanlovi, to'liq ekran, "Chiqish". Fizika 60 Hz (telefondek).
- **Shader warmup** (`ShaderWarmup`, faqat gl_compatibility: web, Android, desktop OpenGL): yuklash paytida `root.disable_3d`, `Loading.finish()` da har bir noyob material kamera oldidagi kvadratda kadrma-kadr chiziladi (cull_mask 1<<19). Avval birinchi kadr 27 s qotardi (Chrome "sahifa javob bermayapti"). Keshdan ~25 ms/qadam.
- `shading/overrides/force_vertex_shading.web=true`: ANGLE D3D11 kompilyatsiyasi ~4x tez (sovuq: menyu 3.7 s, haydash 6.9 s; oldin 16.5 + 34). Faqat quyosh bor — ko'rinish deyarli bir xil.
- To'liq ekran / telefon: preset `html/head_include` JS — birinchi bosish/tugmada requestFullscreen (+ telefonda landscape lock, desktopda Escape keyboard.lock), tik holatda `#rotate-hint`. PWA yoqilgan (display fullscreen, landscape, ikonkalar).
- Sovuq kirishni natively takrorlash: shader_cache'ni o'chirib `--rendering-driver opengl3_angle` (ANGLE D3D11, brauzer bilan bir xil vaqtlar).
- Headless sinov: Playwright (scratchpad/webtest/run.js, `channel:'chrome'`, `--use-angle=d3d11`, persistent profile). `--use-angle=gl` NVIDIA drayver keshi tufayli sovuq kompilyatsiyani yashiradi.

## Mashina vizual tuzoqlari
- Kabinadan BodyOuter yashirin (LAYER_EXTERIOR). Gazelle'da `cockpit_shell`: kuzov kabinadan ko'rinadi, ichki
  tomoni `cabin_shell.gdshader` (faqat orqa yuzlar), oyna ichkaridan alohida `GlassInside`; LAYER_INTERIOR
  (17-qatlam) — ko'zgular chizmaydi, `Car.set_interior_audio()` yoqadi.
- Soya proksisi (LOD) kuzovdan chiqib tursa bo'yoqda dog'lar: `shadow_inset` (m) + bo'yoq soya qabul qilmaydi.
- Burilish chiroqlari linza ortida kichik bo'lsa: `turn_glow` [old, yon, orqa] o'lchamlari (`lamp_glow.gdshader`).
- Klaviatura yordami bitta joyda: `ui/widgets/keys_help.gd` (sozlamalar + F1). DriverControls bilan mos tuting.
- OpenGL (gl_compatibility): soya xaritasi mashina soyasini teshik/zinapoya qiladi → `_simple_shadow`, proksi
  yo'q, `car_shadow.gdshader` (yerga quad, kuzov+kabina qutisi quyosh bo'yicha suriladi). Vulkan'da quyosh
  soyasi o'chiq bo'lsa ham shu ko'rinadi. Yo'l yozuvlari alpha scissor (blend bo'lsa soya ustidan chiqadi),
  `RouteGuide` priority 2 → soya 3.
- Chiroqlar: Mobile renderer ~2x da kesadi, OpenGL kesmaydi → 7x qizil oqarib ketadi. `_make_lamp_materials`
  va turn_glow OpenGL'da toza rang + ~0.36x energiya. Test: `car_render_test ... brake q=1` +
  `--rendering-method gl_compatibility --rendering-driver opengl3`.
- O'yinchi mashinasi `lod_bias = 4` (telefonda avto-LOD kuzovda "buklangan" qirralar beradi).
- Osmon (`EnvironmentSetup._sky`) sessiyada bitta: radiance bir marta filtrlanadi. Jurnalda
  `LOAD uncovered ... after N ms` — sahifa yopilgan payt (telefondan jurnal so'rang).

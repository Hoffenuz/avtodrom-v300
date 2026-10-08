# AvtoSmart Avtodrom

Toshkent imtihon olish markazi (YIM) avtodromidagi amaliy haydovchilik
imtihonining simulyatori. Android (asosiy) va Windows uchun. AvtoSmart
(avtotestu.uz) oilasining ilovasi — logotip va ranglar `brand/` da
(`brand/README.md`).

- Avtodrom rasmiy sxema bo'yicha qurilgan (12 px = 1 m; yo'l bo'laklari
  ~3.2–3.7 m). Marshrutdagi har bir burilishdan oldin buyuruvchi belgi
  (4.1.x) turadi.
- 90° burilish: chap yo'ldan birinchi koridor yuk avtomobillari uchun (oyog'i
  7.3 m, sxemadagidek), ikkinchisi yengil avtomobillar uchun (oyog'i 4.7 m —
  sxemadagi 4.9 m dan biroz tor); kirishdan oldingi 4.1.3 belgilari ostida
  7.4.1 (yuk) va 7.4.3 (yengil) lavhalari. Yuk toifasi (Gazelle) imtihonda
  yuk koridori va keng yuk boksidan (P1) o'tadi —
  `game/data/course_truck.json` (`python pipeline/course_def.py --truck`).
- 12 ta mashq va imtihon rasmiy 32 bandli jarima jadvali bo'yicha baholanadi
  (100 balldan kam — "o'tdi"; 100 ga yetganda imtihon darhol to'xtaydi).
- Haqiqiy fizika: dvigatel, ilashish (mufta), 5 pog'onali mexanika yoki
  avtomat, shinalar modeli, ABS, osma — hammasi C++ da.
- To'rt mashina: **Nexia 2** (mexanika, 5 pog'ona), **Cobalt** (avtomat,
  6 pog'ona), **Gentra** (qora, mexanika, 5 pog'ona) — B toifa, va
  **Gazelle NEXT** furgon (BC toifa, Cummins 2.8 dizel, mexanika, orqa
  yuritma) — har biri zavod ma'lumotlari bo'yicha (massa, dvigatel momenti,
  uzatmalar, g'ildirak bazasi, shinalar).
- Uch rejim:
  - **Imtihon** — to'liq marshrut, ko'rsatmalarsiz, natija tarixga yoziladi;
    imtihon paytida "qaytadan boshlash" yo'q (chiqish = o'tmadi, №26).
    Kirish sahifasida "Namuna" — butun imtihonni avtopilot topshiradi.
  - **Mashqlar** — istalgan mashq alohida, qisqa ko'rsatmalar va marshrut
    chizig'i bilan; har birida "Namuna".
  - **Erkin haydash**.
- **Boshqa qatnashchilar** (Sozlamalar → Avtodrom, yoki bosh menyudagi
  tugma): avtodromda 1–4 ta boshqa o'quv mashinasi (Nexia/Cobalt/Gentra,
  yorqin ranglarda) marshrut bo'ylab yuradi — piyoda o'tish, estakada va
  temir yo'lda to'xtaydi, svetoforga bo'ysunadi, o'yinchiga yo'l beradi
  (`game/src/game/traffic_cars.gd`). Ular o'yinning o'z modellari (kabinasiz,
  tonirovkali), tormozda stop-chiroq, burilishdan oldin burilish chirog'i
  yonadi; past sifatda yengil modellar. "Namuna" va avtomatik testlarda o'chiq.
- Maydon atrofida: aylanma yo'l, AvtoSmart imtihon markazi (shisha atrium,
  brend paneli, bayroqlar, gulzorlar) va turargoh (turgan mashinalar), olti
  xil daraxt (chinor, qayrag'och, terak, archa, bezak daraxti, buta) tabiiy
  guruhlarda, uzoqda shahar (panel uylar, minoralar, gumbazlar, teleminora).
- Barcha mashinalarda "01 AVTOSMART" raqam belgisi
  (`pipeline/make_car_plate.py`).
- Kamera: kabina, orqadan (yaqin), yuqoridan. Ekranning bo'sh joyini surib
  360° aylantirish, ikki barmoq / g'ildirak bilan yaqinlashtirish; ustun va
  belgilar orqasiga tushmaydi.
- Tillar: o'zbek (lotin), o'zbek (kirill), rus.

## Texnologiyalar

| Qatlam | Nima |
|---|---|
| Dvigatel | Godot 4.7.2 (Mobile renderer, Vulkan), Jolt fizika, 120 Hz fizika + interpolyatsiya |
| Avtomobil fizikasi | C++17, GDExtension (godot-cpp 10.0.0, API 4.7) — `native/` |
| O'yin mantig'i, UI | GDScript — `game/src/` |
| Ma'lumot tayyorlash | Python 3 (OpenCV, shapely, Blender) — `pipeline/` |

## Katalog tuzilmasi

```
native/            C++ modul
  src/sim/         platformaga bog'liq bo'lmagan simulyator (shina, transmissiya, dvigatel)
  src/godot/       Godot bog'lamalari: AvtoVehicle (RigidBody3D), EngineSound
  tests/           C++ unit testlar (sim_tests)
game/              Godot loyihasi
  src/autoload/    Settings, Loc (tarjimalar), Session, DebugShots
  src/course/      avtodrom sahnasini qurish (yo'llar, chiziqlar, belgilar, svetoforlar)
  src/vehicle/     Car (model, chiroqlar, tovush), kamera
  src/exam/        imtihon: ExamDirector, mashqlar (ex_*.gd), marshrut kuzatuvchi, jarimalar
  src/game/        haydash sahnasi, avtopilot, ko'zgular, marshrut ko'rsatkichi
  src/ui/          menyu, HUD, pedallar, rul, sozlamalar, natijalar
  data/            course.json, penalties.json, i18n.json, sirt xaritalari (*.bin), course_baked.scn
  assets/          mashina modeli, teksturalar, belgilar, shrift, shaderlar
  tests/           vehicle_test.gd, render_test, bake_course.gd
pipeline/          sxemadan avtodrom geometriyasini chiqarish, tarjimalar, ikonka, teksturalar
  blender/         mashina modellarini o'yinga tayyorlash (build_nexia.py, build_cobalt.py,
                   build_car_lod.py — turargohdagi mashinalar uchun yengil versiya)
reference/         rasmiy sxema va mashqlar jadvallari (manba)
scripts/           build.py (to'liq yig'ish), run_tests.py (barcha testlar)
tools/             Godot va eksport shablonlari (git'da emas)
keys/              release keystore (MAXFIY — git'da emas)
export/            tayyor APK va EXE (git'da emas)
```

## Arxitektura qisqacha

- **VehicleSim (C++)** har bir fizika qadamida (1/120 s) shinalarni
  (deflection/relaxation-length + Magic Formula), transmissiya cheklovlarini
  (PGS yechuvchi: dvigatel, mufta, uzatmalar, tormoz, park qulfi), salt yurish
  regulyatori, o'chib qolish va starterni hisoblaydi. `AvtoVehicle` uni Jolt
  `RigidBody3D` ga ulaydi (osma — silindr shape-cast).
- **ExamDirector** mashqlarni (`Exercise` holat mashinalari) boshqaradi,
  umumiy qoidalarni (kamar, tezlik, o'chib qolish, marshrutdan chiqish,
  to'qnashuv, vaqt, burilish chiroqlari) kuzatadi va jarimalarni rasmiy jadval
  raqamlari bilan yozadi.
- **Avtodrom** `pipeline/course_def.py` da rasmiy sxemadan aniqlanadi va
  `game/data/course.json` + sirt/masofa xaritalariga yoziladi. O'yinda sahna
  oldindan "pishirilgan" (`course_baked.scn`) — telefonda tez yuklanadi.
- **Avtopilot** (pure pursuit + mashqlar uchun maxsus manevrlar) "Namuna"
  rejimida ishlaydi va avtomatik end-to-end test sifatida butun imtihonni 0
  jarima bilan topshiradi.

## Mashina modellari

Manba modellar `projects/car-game/assets-src/car-3d/` dan olinadi va Blender
(headless) skriptlari bilan qayta ishlanadi:

```
blender -b --python pipeline/blender/build_cobalt.py -- <chevrolet_cobalt_ltz.glb> game/assets/cars/cobalt/cobalt.glb
```

Skript haqiqiy o'lchamlarga moslaydi (Cobalt: uzunlik 4479 mm, baza 2620 mm),
g'ildiraklarni `Wheel_XX/Spin_XX`, chiroqlarni `Lamp_*`, rulni
`SteeringPivot/SteeringWheel` qilib ajratadi, uchburchaklar sonini mobil
byudjetgacha kamaytiradi (~110k) va to'qnashuv qobig'ini yasaydi.
Keyin `refine_car.py` tozalash bosqichi kuzov normallarini qayta hisoblaydi
(eshik va bagajdagi qora dog'lar yo'qoladi), kuzovni ~34–40k uchburchakgacha
yengillashtiradi va buzilgan torpedoni sodda modellangan torpedo, jonli
spidometr va taxometr (`GaugeSpeed`/`GaugeRpm`, `gauge.gdshader`) bilan
almashtiradi:

```
blender -b --python pipeline/blender/refine_car.py -- cobalt.glb game/assets/cars/cobalt/cobalt.glb cobalt_at
```

Gentra (Sketchfab, CC BY 4.0 — pastdagi "Litsenziyalar"ga qarang) xuddi
shunday ikki bosqichda: `build_gentra.py` modelni +Y ga buradi, g'ildirak
bazasi 2600 mm bo'yicha bir xil masshtablaydi, disk logotiplari va raqam
yozuvlarini olib tashlaydi, shinalarni toza aylanma (lathe) shina bilan
almashtiradi; `refine_car.py ... gentra` torpedo va ko'rsatkichlarni
yasaydi:

```
blender -b --python pipeline/blender/build_gentra.py -- daewoo__gentra.glb gentra_build.glb
blender -b --python pipeline/blender/refine_car.py -- gentra_build.glb game/assets/cars/gentra/gentra.glb gentra
blender -b --python pipeline/blender/build_car_lod.py -- game/assets/cars/gentra/gentra.glb game/assets/cars/lod/gentra_lod.glb
blender -b --python pipeline/blender/build_parked_car.py -- game/assets/cars/gentra/gentra.glb game/assets/cars/lod/gentra_parked.glb
```

Onix (Sketchfab, CC BY 4.0) ham ikki bosqichda: `build_onix.py` g'ildiraklarni
bir izga tekislaydi, antenna, rul ostidagi ortiqcha chiroq nusxasi va raqam
yozuvlarini olib tashlaydi, 310 ming uchburchakni kamaytiradi, salon ichidagi
bo'yoq yuzlarini kulrang qoplamaga o'tkazadi (rang almashsa salon bo'yalmaydi);
`refine_car.py ... onix` torpedo va ko'rsatkichlarni yasaydi. Mexanika va
avtomat bitta model: C++ presetlari `onix` / `onix_at`
(Sozlamalar → "Uzatmalar qutisi"):

```
blender -b --python pipeline/blender/build_onix.py -- "chevrolet_onix (2).glb" onix_build.glb
blender -b --python pipeline/blender/refine_car.py -- onix_build.glb game/assets/cars/onix/onix.glb onix
blender -b --python pipeline/blender/build_car_lod.py -- game/assets/cars/onix/onix.glb game/assets/cars/lod/onix_lod.glb
```

Ilova ochilishidagi rasm (Godot boot splash — skriptlardan oldin
ko'rinadi, keyin uni loading sahifasi davom ettiradi):
`python pipeline/make_splash.py` → `game/assets/ui/boot_splash.png`.
Raqam belgisi va bayroqlar: `python pipeline/make_car_plate.py`,
`python pipeline/make_flags.py`.

Turargohdagi mashinalar va "boshqa qatnashchilar" uchun yengil modellar
(bitta material, ko'rinish vertex rangida; `--npc` — g'ildiraksiz kuzov +
aylanuvchi g'ildirak):

```
blender -b --python pipeline/blender/build_parked_car.py -- game/assets/cars/cobalt/cobalt.glb game/assets/cars/lod/cobalt_parked.glb 4200 0.026
blender -b --python pipeline/blender/build_parked_car.py -- game/assets/cars/cobalt/cobalt.glb game/assets/cars/lod/cobalt_npc.glb 5200 0.024 --npc
```

Cobalt faralarining ichki qismi (korpus, reflektor kosalari, sariq burilish
chirog'i) `game/assets/shaders/headlamp.gdshader` da chiziladi.

G'ildiraklarni alohida tuzatish (kuzovga tegmasdan):
`replace_wheels.py` — Nexia g'ildiraklarini manbadan qayta yig'adi (silliq
shina, kolpak ~2200 uchburchak, support aylanmaydi); `fix_wheels.py --align
--drop metal` — Cobalt'ning chap g'ildiraklari 3.4° qiyshiq edi (aylanganda
tebranardi), o'qiga to'g'rilanadi va aylanuvchi plastinasi olib tashlanadi.

Gazelle NEXT (Sketchfab, CC BY 4.0) — `build_gazelle.py` (joylashtirish
3745 mm bazaga, g'ildiraklar, chiroqlar, modellashtirilgan rul, ko'zgular),
keyin `refine_car.py ... gazelle` (torpedo, ko'rsatkichlar):

```
blender -b --python pipeline/blender/build_gazelle.py -- free_gazelle_next_-_pro.glb gazelle_build.glb
blender -b --python pipeline/blender/refine_car.py -- gazelle_build.glb game/assets/cars/gazelle/gazelle.glb gazelle
blender -b --python pipeline/blender/build_car_lod.py -- game/assets/cars/gazelle/gazelle.glb game/assets/cars/lod/gazelle_lod.glb
```

Kuzov rangi `car.gd` dagi `MODELS[...]["paint"]` da (Gentra — qora,
qolganlari oq).

Natijani tekshirish: `godot --path game res://tests/car_render_test.tscn -- <papka> <nexia2|gentra|cobalt_at>`
(tashqi va saloni suratlari). Chiqqan
o'lchamlar (bamperlargacha masofa, ko'zgu nuqtasi) `game/src/vehicle/car.gd`
dagi `MODELS` ga, g'ildirak bazasi/koleya C++ presetiga yoziladi.

## Yig'ish

Talablar (Windows): Python 3.12+ (`pip install scons opencv-python shapely numpy`),
Visual Studio 2022 Build Tools (MSVC), Android uchun JDK 17 va Android SDK +
NDK 28.2.13676358. Godot 4.7.2 va eksport shablonlari `tools/` ichida.

Linux/macOS: MSVC o'rniga GCC/Clang. Godot `tools/godot/` dan
(`Godot_v4.7.2-stable_linux.x86_64` yoki `Godot.app`), `GODOT` muhit
o'zgaruvchisidan yoki PATH dagi `godot` dan olinadi; Android SDK `ANDROID_HOME`
dan. Windows eksporti faqat Windows'da yig'iladi.

Yangi klondan keyin avval `git submodule update --init` (godot-cpp), keyin
`build.py` — u `game/bin/` dagi C++ kutubxonalarni ham yaratadi.

```
python scripts/build.py               # C++ modul (Windows + Android), bake, eksportlar
python scripts/build.py --no-native   # faqat bake + eksport
python scripts/build.py --android     # faqat Android APK
python scripts/build.py --windows     # faqat bake + Windows EXE
python scripts/build.py --installer   # EXE + Windows o'rnatuvchi (Inno Setup 6)
```

O'rnatuvchi: `export/installer/AvtoSmart-Avtodrom-Setup-<versiya>.exe`
(`scripts/installer.iss`; rasmlari `python pipeline/make_installer_art.py`).
Kompyuterda o'yin to'liq ekranda ochiladi (F11 / Alt+Enter — oynali rejim;
Sozlamalar → Grafika → To'liq ekran).

Natija: `export/windows/Avtodrom.exe`, `export/android/avtodrom.apk`
(release, imzolangan), `avtodrom-debug.apk` va Google Play uchun
`avtodrom.aab` (release, imzolangan).

AAB Gradle orqali yig'iladi ("Android AAB" preseti). Bir marta kerak:
eksport shablonlaridagi `android_source.zip` ni `game/android/build/` ga
ochish (`.gdignore` bilan) va `game/android/.build_version` ga
`4.7.2.stable` yozish (Godot muharririda: Project → Install Android Build
Template), SDK'da `build-tools;36.1.0` va platforma 36. Muharrir
sozlamasidagi SDK yo'li probelsiz bo'lsin (`C:/android_sdk`).

Logotiplar (`brand/`): Windows EXE, oyna va vazifalar paneli — dumaloq
`windows/avtodrom.ico` (`game/assets/ui/icon_windows.ico`); Android
launcher — kvadrat `icon_192` va adaptive (fg/bg/monochrome); Play Store
sahifasi — `play-store/app-icon-512.png` va `feature-graphic-1024x500.png`;
o'yin ichidagi belgi (menyu, yuklanish, bino) — `png/avtodrom-icon-512.png`
(`game/assets/ui/brand_mark.png`).

Release APK imzosi uchun `keys/avtodrom-release.keystore` va parollar
`keys/release_credentials.txt` da. **Bu fayllarni hech qachon repozitoriyga
qo'shmang va boshqalarga bermang** — Play Market'dagi ilovani yangilash faqat
shu kalit bilan mumkin; zaxira nusxasini xavfsiz joyda saqlang.

## Testlar

```
python scripts/run_tests.py           # hammasi (~35 daqiqa)
python scripts/run_tests.py --quick   # faqat C++ va avtomobil testlari
```

1. C++ simulyator unit testlari (63 ta tekshiruv).
2. Godot/Jolt avtomobil integratsiya testi (20 ta tekshiruv).
3. Butun imtihon avtopilot bilan, uchala mashinada — 0 jarima kutiladi.
4. Ataylab xato qilish (kamarsiz, to'xtamaslik, qizil chiroq, burilish
   chirog'isiz, tezlikni oshirish) — to'g'ri jarima bandlari chiqishi kerak.
5. Har bir mashqning "Namuna"si alohida, uchala mashinada — 0 jarima.

Qo'lda tekshirish uchun buyruq qatori (Godot `--` dan keyin):
`--mode=practice --exercise=box --demo`, `--car=cobalt_at` (yoki `gentra`), `--camera=chase`, `--autopilot`,
`--seed=<n>` (svetofor fazalari takrorlanadi), `--touch` (telefon ko'rinishi kompyuterda),
`--shots=<papka>`, `--quit-after-s=<s>`, `--menu-page=exam|practice|rules|history|settings`,
`--settings-tab=general|avtodrom|controls|graphics|sound|about`,
`--traffic=<n>` (boshqa qatnashchilar), `--traffic-log`, `--traffic-near`,
`--perf` (kadr vaqti, draw call va uchburchaklar soni).

Avtodromni turli nuqtalardan suratga olish (GPU kerak):
`godot --path game res://tests/scenery_shots.tscn -- <papka> [sifat] [shots.json]` —
`shots.json`: `[["nom", [kamera x, y, z], [nishon x, y, z]], ...]` (metr).

## Boshqaruv (kompyuter)

Kompyuterda standart holda klaviatura bilan boshqariladi; ekrandagi rul va
pedallarni Sozlamalar → Boshqaruv → "Ekrandagi rul va pedallar" orqali yoqish
mumkin (sensorli ekranli noutbuklar uchun). Telefonda rul turi: rul,
strelkalar yoki telefonni qiyalatish.

| Tugma | Amal |
|---|---|
| W / ↑ | gaz |
| S / ↓ | tormoz |
| Shift / C | ilashish (mufta) |
| A D / ← → | rul |
| 1–5, R, N | uzatma (avtomatda P R N D: P, R, N, G) |
| I (bosib turish) | kalit / starter |
| B | xavfsizlik kamari |
| Space | qo'l tormozi |
| Q / E | chap / o'ng burilish chirog'i |
| H | avariya signali |
| V | kamera |
| Esc | pauza |
| sichqoncha bilan surish / g'ildirak | kamerani aylantirish / yaqinlashtirish |

Telefonda: rul (yoki tugmalar), gaz/tormoz/mufta pedallari, uzatma dastagi,
kalit/kamar/qo'l tormozi, burilish va avariya chiroqlari; ekranning bo'sh
joyini surish — kamerani aylantirish.

## Litsenziyalar va manbalar

- Gentra 3D modeli: "Daewoo_ Gentra"
  (https://sketchfab.com/3d-models/daewoo--gentra-bf6d601e37ef4b829f27998d1c7b36c1),
  muallif Doniyor 3D (https://sketchfab.com/doniyorgroup), litsenziya
  CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/). O'zgartirilgan:
  burilgan va masshtablangan, uchburchaklar kamaytirilgan, shinalar,
  torpedo va raqam belgilari almashtirilgan, rangi qora. Muallif o'yinda
  ham ko'rsatilgan (Sozlamalar → Manbalar).
- Gazelle NEXT 3D modeli: "[FREE] GAZelle Next - Pro"
  (https://sketchfab.com/3d-models/free-gazelle-next-pro-6f5f115cb8fc4bb2933b317f505d5708),
  muallif UralStrong_lybnineg (https://sketchfab.com/lybnineg), litsenziya
  CC-BY-4.0. O'zgartirilgan: masshtablangan, shinalar almashtirilgan, rul va
  torpedo qo'shilgan, uchburchaklar kamaytirilgan, rangi oq.
- Onix 3D modeli: "chevrolet onix"
  (https://sketchfab.com/3d-models/chevrolet-onix-bfd798c2695847b28ab681d42abc7056),
  muallif uzb_rx7 (https://sketchfab.com/uzbek_supra), litsenziya CC-BY-4.0.
  O'zgartirilgan: masshtablangan, g'ildiraklar tekislangan, antenna va ortiqcha
  qismlar olib tashlangan, uchburchaklar 310 mingdan ~80 minggacha kamaytirilgan,
  torpedo va ko'rsatkichlar qayta qurilgan, raqam belgilari almashtirilgan.
- Teksturalar va osmon: Poly Haven (CC0).
- Shriftlar: Inter va Montserrat (SIL Open Font License, `game/assets/fonts/OFL.txt`).
- Yo'l belgilari va jarima jadvali: AvtoSmart (variant-vision-quiz) ma'lumotlari.
- Avtodrom sxemasi va mashqlar tavsifi: Toshkent YIM qo'llanmasi.

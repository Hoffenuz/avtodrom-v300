# Audit — AvtoSmart Avtodrom 1.0.15 (2026-10-28)

Faqat o'qish bosqichi. Har band: fayl:qator — ta'siri — tuzatish narxi (K kichik / O o'rta / B katta).
Muhit: Linux konteyner, Godot binarisi yo'q (yuklab olishga ruxsat berilmadi), shuning uchun faqat
C++ sim testlari (`g++` bilan, 92 check) va statik o'qish; Godot headless testlari ishlatilmadi.

## 0. Branchlar
- `origin/main` == `origin/web-version` (9b71b6b). 11 ta `origin/claude/*` branchdan 10 tasi main'ga
  to'liq kirgan; `claude/project-thread-ovh43k` da 1 ta commit bor, u faqat merge commit (main'ga
  nisbatan foydali diff yo'q — eski holat, 20k qator o'chirish). O'chirish kerak emas, lekin saqlashga ham sabab yo'q.

## 1. Xatolar (mantiq, crash, leak)

### Imtihon qoidalari (game/src/exam)
- B1 `ex_emergency.gd:63-66` — STOPPED fazasida haydovchi avariya ishorasini yoqmay 3 s o'tmasdan
  jo'nab ketsa (`not p.stopped ... > 0.5`), №20 (ishorani 3 s ichida yoqmadi) berilmaydi: faza
  RELEASED'ga o'tadi, u yerda faqat №21 tekshiriladi. Ta'sir: real xato jarimasiz qoladi. Narx: K.
- B2 `ex_emergency.gd:64` — `p.travelled > 0.0` doim true (travelled umumiy masofa). O'lik shart. K.
- B3 `ex_finish.gd:21,44` — `travel` har tikda hisoblanadi va ishlatilmaydi (`var _unused := travel`);
  chiziq kesib o'tilgani qattiq `Vector2(1, 0)` yo'nalishda tekshiriladi (marshrut yo'nalishi emas).
  Hozirgi avtodromda to'g'ri ishlaydi, lekin yuk marshruti/boshqa sxema uchun mo'rt. K.
- B4 `exam_director.gd:262-264` — №1 kamar sharhi "har safar yechilganda" deydi, kod bir marta
  (`_belt_flagged`) beradi. Hujjat/kod mos emas; qoida bo'yicha bir marta to'g'ri → sharhni tuzatish. K.
- B5 `exam_director.gd:296-306` — №28 (marshrutdan chiqish) `_off_route_flagged` hech qachon
  tiklanmaydi: 100 ball bo'lgani uchun imtihonda ahamiyatsiz, lekin "Yiqitish" o'chiq rejimda va
  mashqda ikkinchi chiqish hisoblanmaydi. Qasddan bo'lsa ham izoh yo'q. K.
- B6 `ex_accel.gd:44-46` + `exam_director.gd:276-279` — tezlashish qismida 40 km/soat oshsa №6 (5) va
  №31 (100) birga tushadi. Jadval bo'yicha №31 umumiy qoida — to'g'ri, lekin foydalanuvchiga ikki
  yozuv "bir xato" sifatida ko'rinadi. Izoh yoki natija matnida tushuntirish. K.
- B7 `ex_stop_line.gd:38` — to'xtash 8 m oldin ham "to'xtash" hisoblanadi (`front_past > -8`), keyin
  yaqinlashib qayta to'xtasa `stop_gap` faqat `< -max_gap-2` bo'lsa tiklanadi — 1–3 m oraliqdagi
  birinchi to'xtash №4 beradi, qayta yaqinlashish hisobga olinmaydi. Haqiqiy imtihonda ham shunday
  (birinchi to'xtash baholanadi) — o'zgartirish shart emas, hujjatlashtirish. K.
- B8 `exam_director.gd:259` — `CourseData.poly(zone)` har fizika tikida har aktiv mashq zonasi uchun
  yangi PackedVector2Array quradi (allokatsiya 120 Hz). Oldindan keshlab bo'ladi. K.

### C++ (native/)
- C1 `avto_vehicle.cpp:178-184` — har fizika tikida `PhysicsShapeQueryParameters3D` + `TypedArray<RID>`
  yaratiladi (120 Hz × har mashina). Telefonda allokatsiya shovqini; a'zo sifatida bir marta yaratish
  mumkin. Ta'sir past-o'rta (o'lchanmagan). K.
- C2 `vehicle_sim.cpp` — yadro toza: constraints_ reserve(12), substep ichida allokatsiya yo'q,
  `g++ -Wall -Wextra` ogohlantirishsiz. 92 check o'tdi.
- C3 Sim testlar yetishmaydi: (a) avtomat uzatmada P/R ni 1.2 m/s dan tez harakatda rad etish;
  (b) `request_gear` mexanikada 1.5 m/s dan tez R ga o'tish "grind"; (c) ABS faollashuvi
  (`abs_active`) qattiq tormozda; (d) `auto_clutch` bilan "stall protection" (rpm < idle-120 → 0).
  Narx: K (har biri 10–20 qator).

### GDScript umumiy
- G1 `drive.gd:33` — `Settings.changed` ga lambda: HAR qanday sozlama (kamera almashtirish ham)
  `_apply_graphics()` → `apply_viewport` chaqiradi. Zararsiz, lekin keraksiz ish. K.
- G2 `settings.gd:74` — `lite_scenery` qatoridagi ikkinchi izoh (`web_warm`niki) noto'g'ri joyda. K.
- G3 `session.gd:135-143` — `history.json` buzilgan bo'lsa (`data` Array emas) jim o'tiladi — yaxshi;
  lekin `record_result` da `result["track"]` o'chiriladi, `exercises[].name` dict saqlanadi — tarix
  faylida har urinish ~2–4 KB, 50 ta → 200 KB, muammo yo'q.

## 2. Foydalanuvchi tajribasi (menyu, oqimlar, sozlamalar)
Oqim: Home → (a) Imtihon 2 bosish (karta + Boshlash), lekin haydashgacha ~6 (kalit, kamar, ruchnoy, "Tayyor");
(b) Mashq 2 bosish; (c) Erkin 1 bosish, lekin dvigatelni qanday yoqish haqida hech qanday ko'rsatma yo'q (sensorli).
- U1 `main_menu.gd:200-202,923` — Sozlamalar ichida tilni almashtirish `_rebuild_ui` → butun UI (SettingsPanel
  bilan) o'chiriladi, foydalanuvchi Home'ga tushadi; `_settings_panel` o'chirilgan tugunga ishora qilib qoladi
  (Android back → `.closed.emit()` freed node). `reset_to_defaults` ham `language` emit qiladi. XATO. O.
- U2 `drive.gd:467` vs `pause_menu.gd:58,64-65` — pauzadagi "Qaytadan" imtihonda "bu urinish o'tmagan" deb
  ogohlantiradi, lekin `abandon()` chaqirilmaydi — tarixga yozilmaydi. Matn va xulq mos emas. K.
- U3 `drive.gd:491-492` — `_on_finished` 1.8 s `await`; "Menyuga" (abandon → finished) dan keyin sahna
  almashadi → freed instance'da davom etish xatosi (jurnalda). K.
- U4 `pause_menu.gd:24-61` — pauza menyusi bir marta quriladi, `Loc.language_changed` ni eshitmaydi. K.
- U5 Orqaga: desktop/webda menyuda Escape ishlamaydi (`main_menu.gd` da handler yo'q); Android back
  Home'da dialog (rang/ilova) ochiq bo'lsa ilovadan chiqadi (`:938-939`); "Erkin haydash" yuklanishi paytida
  back → chiqish; natija ekranida Back/Esc yutiladi (`drive.gd:419,440`); layout muharririda "bekor" yo'q. O.
- U6 Sozlamalar: `abs` o'lik kalit (hech qayerda o'qilmaydi); `onix_gearbox` har mashina uchun ko'rinadi;
  `auto_clutch` avtomat mashinada ham ko'rinadi; `screen_controls` Off/On — "Avto" (-1) ga qaytish yo'q;
  `quality` da "Avto" yo'q (bir bosish `quality_user=true` abadiy); `shadows` Low'da hech narsa qilmaydi;
  `show_route` ikki joyda ikki nom ("Yo‘nalish" / "Yordamchi navigator"), `set.route_desc` kamroq tasvirlaydi;
  `exam_fail` faqat imtihon sahifasida; ko'p qatorlarda tavsif yo'q. O.
- U7 OpenGL tugmasi (`settings_panel.gd:329-337`) tasdiqsiz darhol qayta ishga tushiradi/yopadi — pauzadan
  imtihon o'rtasida ham (urinish yo'qoladi). "Standart holat" tasdiqsiz, yashirin bayroqlarni ham tiklaydi. K.
- U8 Xato holatlar: GDExtension yuklanmasa `drive.gd:48-52` faqat `push_error` — ekranda hech narsa, 30 s dan
  keyin umumiy "to'xtab qoldi" oynasi (izoh "loading page'da aytiladi" deydi — yolg'on). `Car extends AvtoVehicle`
  bo'lgani uchun menyu skripti ham buzilishi ehtimoli bor. Stall oynasi inglizcha bosqich nomini ("car") o'zbek
  matn ichida ko'rsatadi. O.
- U9 Natija ekrani: xaritasiz (practice) qatorlar bosilmaydi → to'liq qoida matni yetib bo'lmaydi; "nima qilish
  kerak edi" yo'q; "shu mashqni qayta mashq qilish / namunani ko'rish" yo'q; eng yaxshi natija bilan taqqoslash yo'q
  (`best_exam_score` ishlatilmaydi); safe area e'tiborga olinmaydi (24 px, 1180 px kenglik). O.
- U10 Sensorli: faralar (L) uchun ekran tugmasi yo'q; F1 yordam mobil'da o'chiq → sensorli foydalanuvchiga
  boshqaruv yo'riqnomasi yo'q; Home'dagi "Harakat" CheckButton minimal o'lchamsiz, faqat tugma o'zi bosiladi;
  MenuCard sarlavhasi uzun bo'lsa kesiladi (ellipsis yo'q, `menu_card.gd:84-90`). O.
- U11 `main_menu.gd:884-886` — tarix bo'sh: faqat "Hali natija yo‘q", `_stats` label hech qachon yaratilmaydi
  (`_update_stats` o'lik). Vaqt limiti HUD'da o'tgan vaqt ko'rsatiladi, qolgan vaqt emas. K.
- U12 `debug_shots.gd:6` — `--menu-page` ro'yxatida mavjud bo'lmagan `help`, `exam` yo'q. K.

## 3. Matnlar (i18n) — manba `pipeline/i18n_source.py` (316 kalit, 3 til), `game/data/penalties.json`
Til tizimi BOR: `Loc.t/pick`, i18n.json manba bilan 1:1 mos, barcha kalitlar 3 matnli, tutuq/apostrof izchil (U+2018/2019).
Kodda ishlatilgan, lekin yo'q kalit: 0. Aniqlangan muammolar:
- T1 `main_menu.gd:462` — xavfsiz rejim oynasida qattiq `"OK"` (kalit `app.ok` bor). K.
- T2 `settings_panel.gd:268` — til nomlari qayta yozilgan, `Loc.LANGUAGE_NAMES` ishlatilmaydi. K.
- T3 `surroundings.gd:399,401` — binodagi 3D yozuv faqat o'zbekcha (dunyo matni, qoldirish mumkin). —
- T4 `game/web/shell.html` — ~20 ko'rinadigan matn faqat lotin o'zbekcha (yuklanish, xatolar, "Qayta yuklash",
  ilova kartalari); `:99` ASCII apostrof. Tarjima tizimi yo'q (Godot yuklanmasidan oldin ko'rinadi). O.
- T5 Ishlatilmaydigan 17 kalit: `menu.back, menu.loading, menu.demo_exam, menu.try`, eski `key.*` (13, `key.space` dan tashqari). K.
- T6 Atama bir xil emas (uz): "burilish chirog‘i / chap chiroq / burilish ishorasi"; "marshrut chizig‘i /
  yo‘nalish chizig‘i"; "stop chizig‘i / To‘xtash chizig‘i / STOP chizig‘i / Chiziq"; "Avtomatik mufta / avtomat mufta";
  "ilova / O‘yin"; "Yoqilgan / O‘chiq"; "Standart holat / Standart / Sozlamalarni tiklash";
  `set.steer_buttons` va `set.wheel_scale` da "Strelkalar" ikki ma'noda. O.
- T7 Grammatika (uz): `pen.6` "belgisi"→"belgilari"; `pen.14` "0,3 m dan ko‘p" tushib qolgan; `pen.16` fe'lsiz;
  `pen.30` boshqa TV bilan to'qnashuv yo'q; `pen.25` "temir yo‘l kesishmasida"; `set.quality_desc` "qo‘llaniladi";
  `safe.*` "Grafika’da"→"Grafikada"; `exam.opt_fail` "Yiqitish" — jargon. K.
- T8 Ruscha: `safe.*` "в Настройки"→"в Настройках"; `res.total`/`hud.points` "балл."→to'g'ri ko'plik;
  `hud.clutch` "Сцепл."; `hint.box_fix` infinitiv; `keys.gear_step` fe'lsiz; `set.reset` fe'l vs ot;
  `car.gazelle` "Газель NEXT" vs "Gazelle NEXT"; `car.*_desc` kichik harf bilan boshlanadi. K.
- T9 `penalties.json` “ ” vs i18n « » qo'shtirnoq uslubi; START/FINISH kirillda, STOP lotinda. K.

## 4. Unumdorlik (kod o'qish; o'lchov Godot yo'qligi sabab bu sessiyada qilinmadi)
Eng katta kutilayotgan foyda (tartib bilan):
- P1 `course_builder.gd:119-134` — `course_baked.scn` headless bake'da MultiMesh ma'lumotini saqlamaydi →
  HAR yuklash va HAR qayta boshlashda Surroundings (halqa yo'l, markaz binosi SurfaceTool+tangent, 3 glb mashina,
  ~15 daraxt toji vertex-vertex, shahar) GDScript'da qayta quriladi. Yuklanish vaqti. Tuzatish: bake'da
  MultiMesh buffer'ni meta sifatida saqlash yoki qurilgan Surroundings'ni static'da (quality, lite) kaliti
  bilan qayta ishlatish. B (o'lchov kerak: `LOAD step surroundings` jurnali).
- P2 `course_builder.gd:73-93`, `surroundings.gd:853-909` — lite/past sifatda shahar, mashinalar, props
  to'liq quriladi, keyin `visible=false`; daraxtlarning 3/4 qismi yashiriladi; 3 toj varianti quriladi, 1 tasi
  ishlatiladi. Aynan eng kuchsiz qurilmalarda ortiqcha yuklanish. O.
- P3 `minimap.gd:165-217` — har kadrda (mashina yurganda) ~970 vertexli poligonlar `draw_colored_polygon`
  (har chaqiriqda qayta triangulyatsiya) + yangi StyleBoxFlat + 240 nuqtali marshrut massivi.
  Statik qismlarni bitta bola CanvasItem'ga bir marta chizish. O.
- P4 `traffic_cars.gd:663-705` — har mashina har tikda 2 `intersect_ray` (yangi query obyekt bilan), 5 mashina
  → 600 nur/s; `_blocked_ahead` har tikda Array-of-Array; `_curve_factor` 12 binary search. O.
- P5 `mirror_views.gd:45-60` — ko'zgu SubViewport 360×200 har darajada, `mesh_lod_threshold` sukut (1.0, asosiy
  kameradan nozikroq), glow/tuman ko'zguda ham. Orqaga yurishda telefonda sezilarli. K-O.
Kichikroq (har kadr allokatsiya):
- P6 `hud.gd:588` — `wheel.set_angle` har kadr → `queue_redraw` (tekstura+StyleBox+satr). Threshold 0.2°. K.
- P7 `hud.gd:594`, `driver_controls.gd` — `Settings.is_mobile()` har kadr `OS.get_cmdline_user_args()` chaqiradi
  (yangi PackedStringArray). Natijani keshlash. K.
- P8 `hud.gd:613-616, 682-687, 662-675` — har kadr satr formatlash (ball, vaqt, burilish, tayyorgarlik). K.
- P9 Widget `_draw` ichida `UITheme.box()` yangi StyleBoxFlat: steering_wheel_widget:96, pedal:110/123,
  gear_selector:78, signal_badge:38, minimap:180. K.
- P10 `camera_rig.gd:207-219` — har 2-kadrda yangi PhysicsShapeQueryParameters3D + exclude massivi. K.
- P11 `exam_director.gd:259` `CourseData.poly` har tik; `:263` `active.duplicate()`; `ex_parallel.gd:45,64`
  `Geometry2D.offset_polygon` (Clipper) har tik; `geo.gd` line_a/b har chaqiriqda dict→Vector2. K.
- P12 `drive.gd:33` — har sozlama o'zgarishi `_apply_graphics` (kamera almashtirishda viewport setterlar +
  settings.cfg sinxron yozish). Faqat grafika kalitlarida chaqirish. K.
- P13 `car.gd:1045-1049` — kabina asboblari shader parametrlari har kadr, kabina ko'rinmasa ham;
  `:1066-1079` lamp yangilash har kadr 2 massiv literal. K.
- P14 `web_engine_sound.gd:50` — webda har kadr JS bridge chaqiruvi; faqat o'zgarishda yuborish. K-O.
- P15 `traffic_light.gd:187-201` — GREEN_BLINK davrida har kadr 3 lampaga material_override. K.
Yaxshi holatda (tegmaslik): kurs bake, material bo'yicha birlashtirilgan manzara, daraxt MultiMesh 4 sektor,
HLOD, ShaderWarmup, lamp prewarm, FPS kuzatuvchi (median), RouteGuide statik lenta, AudioSynth kesh,
ko'zgular faqat orqaga yurishda, change-gated setterlar (pedal, gauge, lamps, hint).

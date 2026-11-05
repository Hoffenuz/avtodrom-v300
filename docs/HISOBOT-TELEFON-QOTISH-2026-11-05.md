# Avtodrom web: telefonda qotish — tashxis va tuzatishlar (2026-11-05)

Qurilma: Redmi Note 13 Pro+ (Snapdragon 7s Gen 2, Adreno 710, 12 GB), Chrome 156, WebGL = ANGLE/OpenGL ES.
O'lchash: telefon Chrome'i `adb forward` + DevTools (CDP) orqali, o'yin `?args=--perf --start=exam --autopilot`
bilan, WebGL `linkProgram` chaqiriqlari JS o'rami bilan yozib olindi.

## Nima topildi

| O'lchov | Oldin | Keyin |
|---|---|---|
| Haydash kadr tezligi (avtopilot, 75 s) | 60 fps, p99 17–18 ms | 60 fps, p99 17,7 ms |
| Shader warm-up (yuklash ekrani) | 12,8–14,5 s | **5,7 s** |
| Yuklash ekrani yopilguncha | 15,4–17,3 s | **8,7 s** |
| Kompilyatsiya qilingan dasturlar | 202 (11,0 s) | **83 (3,0 s)** |
| Haydash paytida kompilyatsiya (qotish) | 0,3–1,2 s × 2–3 marta | **0** |
| Bitta eng uzun kadr yuklashda | 3,1–4,2 s («Course») | bo'laklab, 0,5 s dan kam |

Xulosa: haydashning o'zi telefonda ravon edi — sifat darajasi, soya, yengil manzara, render masshtabi
(6 variant A/B) hech narsani o'zgartirmadi. «Qotish» shader kompilyatsiyasi: Chrome Android kompilyatsiya
qilingan dasturlarni saqlamaydi (bir sessiyada qayta yuklaganda ham hammasi qaytadan), har material
~0,45 s. Binolar va daraxtlarni olib tashlash foyda bermasdi — ular GPU'ga emas, draw chaqiriqlari bilan
CPU'ga tushadi, u ham telefonda yetarli edi.

## Tuzatishlar

1. **Godot dvigateli (web shablon):** `ShaderGLES3::_initialize_version` har material uchun 4 ta standart
   variantni (color, color+instancing, depth, depth+instancing) kompilyatsiya qilardi — sahna ularning
   birortasini ishlatmaydi, keyin haqiqiy spetsializatsiya alohida kompilyatsiya bo'lardi. Webda endi
   faqat kerakli variant, bog'langan payti (`drivers/gles3/shader_gles3.cpp`, `#ifndef WEB_ENABLED`).
2. **Warm-up to'liq:** svetoforning yongan materiallari ro'yxatga olinadi (`ShaderWarmup.register`),
   MultiMesh rang/custom-data variantlari kvadratlarda, sahna qismlari tepadan ortografik kamera bilan
   ko'rsatiladi (kamera ko'rmagan tomondagi belgilar, Label3D yozuvlar ham), kurs va atrof bo'laklab
   (bitta 3–4 s kadr o'rniga ko'p qisqa kadr).
3. **Ko'zgular:** soyasiz quyosh nusxasi faqat quyosh soyali bo'lsa — aks holda birinchi orqa yurishda
   hamma material qayta kompilyatsiya bo'lardi.
4. **Telefon brauzerida sifat ≤1 da quyosh soyasi o'chiq:** OpenGL soyali quyoshni additiv o'tish bilan
   chizadi (har obyekt ikki marta + soya xaritasi + har materialga yana bitta dastur); mashinaning o'z
   soyasi qoladi, daraxt/ustun soyalari bu darajada avval ham yo'q edi.
5. **Daraxtlar:** telefonda sifat ≤1 da 2 sektor va bitta toj shakli — 60+ draw o'rniga ~20.
6. **Hang guard webda o'chiq:** yuklash paytida tab yopilsa keyingi kirish «oxirgi safar qotgan» deb eng
   past sifatga tushar va ogohlantirish chiqarardi.
7. **Menyu:** webda `max_fps=30` cheklovi yo'q (brauzerda notekis kadr berardi).
8. **Rul va ikkinchi barmoq:** rul, pedal, richag yoki burilish tugmasi ushlangan payt boshqa barmoq
   kamerani aylantirmaydi (`LookPad.hold_check`).
9. **`?lang=uz_lat|uz_cyr|ru`** o'yinni shu tilda ochadi, **`?src=app`** ilova ichida ekanini bildiradi
   (app-card va «Ilova» oynasi yo'q). Mobil ilova shu parametrlarni beradi.
10. Yuklash matni telefonda rost: «10–20 soniya» («faqat bir marta» emas).

## Qanday tekshirish

```
# telefon (USB), Chrome ochiq
adb forward tcp:9222 localabstract:chrome_devtools_remote
node phone_glspy3.js "https://avtodrom.avtotestu.uz/" "--perf --start=exam --autopilot --quit-after-s=75" 110 prod
```
`WARM N shaders in … ms`, `LOAD uncovered … after … ms`, `PROGRAMS linked=…`, haydashda `GLLINK` qatorlari
bo'lmasligi kerak. Lokal: `package_web(Path('export/web-cf'))`, `npx wrangler@4 dev --port 8787`,
`adb reverse tcp:8787 tcp:8787`.

## Qolgan g'oyalar (qilinmadi)

- Kompilyatsiyani parallel qilish (KHR_parallel_shader_compile): Godot har dasturni darhol kutadi;
  dvigatelda kattaroq o'zgarish kerak, 5,7 s ni ~2 s ga tushirishi mumkin.
- Materiallar sonini kamaytirish (StandardMaterial variantlarini birlashtirish): har material ~150 ms.
- Yuklashda `getBufferSubData` bilan mesh o'qish (~0,4 s): bake'da tayyorlash mumkin.

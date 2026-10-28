# Yo'l xaritasi — yangi imkoniyatlar (2026-10-28)

Mezon: o'quvchi haydovchiga haqiqiy imtihonga tayyorlanishda foyda beradi va mavjud kodga kam tegadi.
Narx: K kichik (≤1 kun), O o'rta (2–4 kun), B katta. Xavf: mavjud ishlaydigan oqimga ta'sir ehtimoli.

| № | G'oya | Foydalanuvchi qiymati | Narx | Xavf | Holat |
|---|-------|-----------------------|------|------|-------|
| 1 | **Natijadan to'g'ri mashqqa** — natija ekranida eng ko'p ball yo'qotilgan mashqni "Mashq qilish" tugmasi; mashqdan keyin "Keyingi mashq" | Xatodan darhol mashqqa o'tish, menyu aylanmasdan | K | past | **qilindi** |
| 2 | **Mashq progressi** — har mashq uchun urinishlar soni, eng yaxshi ball; mashq kartasida ko'rinadi (`user://progress.json`) | Qaysi mashq "tayyor", qaysi biri ustida ishlash kerakligi ko'rinadi | K | past | **qilindi** |
| 3 | **Natijada qoida matni va oldingi eng yaxshi natija** — qator bosilsa qoidaning to'liq matni (xaritasiz ham), imtihonda oldingi eng yaxshi ball | Xatoni tushunish, o'sishni ko'rish | K | past | **qilindi** |
| 4 | **Imtihonda qolgan vaqt** — HUD'da o'tgan vaqt o'rniga qolgan vaqt, 3 daqiqa qolganda sariq | №32 (vaqt tugadi) kutilmagan bo'lmaydi | K | past | **qilindi** |
| 5 | **Xato bo'yicha maslahat** — har jarima raqami uchun 1–2 gapli "nima qilish kerak edi" (`tip.N`, 3 til), natija qatorida | Xatoni takrorlamaslik | O (96 matn) | past | reja |
| 6 | **Xatolar tahlili sahifasi** — tarix bo'yicha eng ko'p takrorlangan 3 jarima va tegishli mashqlar; Home'da "Zaif joylaringiz" kartasi | Maqsadli tayyorgarlik | O | past | reja |
| 7 | **Qiyinlik darajalari** — "O'rganish" (navigator + ko'rsatmalar + yiqitish yo'q), "Imtihon" (haqiqiy), "Qattiq" (harakat + yomg'ir/tun) — mavjud sozlamalarning 3 ta tayyor to'plami | Bir bosishda to'g'ri rejim, sozlamalarda adashmaslik | K–O | past | reja |
| 8 | **Ovozli yo'riqnoma to'ldirish** — `docs/VOICE_LINES.md` dagi satrlar yozib olinishi (kod tayyor, fayllar yo'q); TTS bilan vaqtinchalik variant | Ekranga qaramay mashq qilish | O (yozuv) | past | reja |
| 9 | **Takroriy ko'rish (replay)** — `ExamDirector.track` bor; jarima nuqtasidan 10 s oldin kamera bilan qayta ko'rsatish (sim qayta ijro emas, kuzatuv yozuvi) | Xatoni ko'z bilan ko'rish | B | o'rta | reja |
| 10 | **Natijani ulashish** — natija varag'ini PNG (viewport screenshot) sifatida saqlash/ulashish (Android share intent, webda yuklab olish) | Instruktor/do'stlarga ko'rsatish | O | o'rta (platforma API) | reja |
| 11 | **Bosqichma-bosqich o'quv rejasi** — mashqlar tartibi "ochiladi": oldingisi 0 ball bilan bajarilgach keyingisi; ixtiyoriy rejim | Yangi o'quvchi uchun yo'l | K (progress ustiga) | past | reja |
| 12 | **Sensorli boshqaruv yo'riqnomasi** — birinchi haydashda 3 kartali qisqa ko'rsatma (rul, pedallar, kalit); faralar uchun ekran tugmasi | Telefonda birinchi daqiqalar tushunarli | K–O | past | reja |

Keyingi navbat (tavsiya): 5 → 7 → 12 → 6.

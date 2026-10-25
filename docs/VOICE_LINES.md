# Instruktor ovozi — yoziladigan gaplar

O'yin har bir gapni fayl nomi bo'yicha qidiradi:

- o'zbekcha (lotin va kirill uchun bitta): `game/audio/voice/uz/<nom>.ogg`
- ruscha: `game/audio/voice/ru/<nom>.ogg`

`.wav` ham bo'ladi. Qaysidir fayl bo'lmasa, o'sha gap shunchaki aytilmaydi, ekrandagi yozuv esa avvalgidek chiqadi. Shuning uchun gaplarni bittalab qo'shib borish mumkin.

**Yozish bo'yicha maslahatlar**
- Tinch xonada, telefon ovoz yozgichi ham bo'ladi.
- Mono, 44,1 yoki 48 kHz.
- Har gapdan oldin va keyin 0,2 soniyadan ortiq jimlik qoldirmang.
- Ovoz baland va aniq bo'lsin, lekin baqirmang: instruktor mashinaning yonida o'tirgandek.
- Har gap 1–3 soniya. Qisqa gap tez eshitiladi va keyingi xatoga xalal bermaydi.
- Fayllarni menga bering: ovoz balandligini tenglab, `.ogg` ga o'girib, joyiga qo'yaman.

## Imtihon boshlanishi va yakuni

| Fayl | O'zbekcha | Ruscha |
|---|---|---|
| `start` | Start! Harakatni boshlang. | Старт! Начинайте движение. |
| `emergency` | Avariya! Darhol to'xtang! | Авария! Немедленно остановитесь! |
| `end_passed` | Tabriklayman, imtihondan o'tdingiz! | Поздравляю, экзамен сдан! |
| `end_failed` | Afsuski, imtihondan o'tmadingiz. Xatolarni ko'rib chiqing. | К сожалению, экзамен не сдан. Посмотрите ошибки. |
| `end_finished` | Imtihon tugadi. Natijani ko'ring. | Экзамен окончен. Посмотрите результат. |
| `end_practice` | Mashq tugadi. | Упражнение окончено. |

## Mashq boshlanishi

| Fayl | O'zbekcha | Ruscha |
|---|---|---|
| `ex_crosswalk` | Piyodalar o'tish joyi. To'xtash chizig'i oldida to'xtang. | Пешеходный переход. Остановитесь у стоп-линии. |
| `ex_hill` | Estakada. To'xtang, so'ng orqaga ketmasdan qo'zg'aling. | Эстакада. Остановитесь и тронитесь без отката. |
| `ex_turn90` | To'qson gradus burilish. | Поворот на девяносто градусов. |
| `ex_intersection` | Chorraha. Svetoforga qarang. | Перекрёсток. Следите за светофором. |
| `ex_zigzag` | Ilon izi. | Змейка. |
| `ex_emergency` | Avariya holatda to'xtash. Ishorani kuting. | Аварийная остановка. Ждите сигнала. |
| `ex_box` | Boksga orqa bilan kiring. | Въезд в бокс задним ходом. |
| `ex_railway` | Temir yo'l kesishmasi. To'xtang. | Железнодорожный переезд. Остановитесь. |
| `ex_accel` | Tezlashish. Ikkinchi uzatmani qo'shing. | Разгон. Включите вторую передачу. |
| `ex_parallel` | Parallel to'xtash. | Параллельная парковка. |
| `ex_finish` | Finish. O'ngga burilish chirog'ini yoqing. | Финиш. Включите правый поворотник. |

## To'g'ri bajarildi

| Fayl | O'zbekcha | Ruscha |
|---|---|---|
| `done_hold` | To'g'ri. Harakatni davom ettiring. | Правильно. Продолжайте движение. |
| `done_box_parked` | To'g'ri to'xtadingiz. Boksdan chiqing. | Правильно. Выезжайте из бокса. |
| `done_parallel_parked` | To'g'ri to'xtadingiz. Chiqishingiz mumkin. | Правильно. Можно выезжать. |
| `done_exercise` | Barakalla, mashq bajarildi. | Отлично, упражнение выполнено. |

## Xatolar (rasmiy jadval raqami bo'yicha)

| Fayl | O'zbekcha | Ruscha |
|---|---|---|
| `pen_1` | Xavfsizlik kamari taqilmagan. | Не пристёгнут ремень безопасности. |
| `pen_2` | Startda chap burilish chirog'i yoqilmadi. | На старте не включён левый поворотник. |
| `pen_3` | Chap burilish chirog'i o'chirilmadi. | Не выключен левый поворотник. |
| `pen_4` | To'xtash chizig'idan uzoqda to'xtadingiz. | Остановились далеко от стоп-линии. |
| `pen_5` | Burilish chirog'i yoqilmadi. | Не включён поворотник. |
| `pen_6` | Yo'l belgisi talabi buzildi. | Нарушено требование знака. |
| `pen_7` | Finishda o'ng burilish chirog'i yoqilmadi. | На финише не включён правый поворотник. |
| `pen_8` | Tezlik yigirma kilometrdan oshdi. | Скорость выше двадцати километров. |
| `pen_9` | Chorrahada uzoq turib qoldingiz. | Слишком долго на перекрёстке. |
| `pen_10` | Startdan keyin o'ttiz soniya qo'zg'almadingiz. | Не тронулись тридцать секунд после старта. |
| `pen_11` | To'xtash chizig'ida to'xtamadingiz. | Не остановились у стоп-линии. |
| `pen_12` | Uch soniya kutmasdan yurdingiz. | Тронулись раньше трёх секунд. |
| `pen_13` | Estakadada uzoq turib qoldingiz. | Слишком долго на эстакаде. |
| `pen_14` | Estakadada orqaga ketdingiz. | Откат на эстакаде. |
| `pen_15` | Nazorat chizig'ini bosdingiz. | Наезд на контрольную линию. |
| `pen_16` | Mashqqa ikki daqiqadan ko'p vaqt ketdi. | Упражнение заняло больше двух минут. |
| `pen_17` | G'ildirak qayd chizig'iga qo'yilmadi. | Колёса не на линии фиксации. |
| `pen_18` | Ikkinchi uzatma qo'shilmadi. | Не включена вторая передача. |
| `pen_19` | Ishoradan keyin o'z vaqtida to'xtamadingiz. | Не остановились вовремя после сигнала. |
| `pen_20` | Avariya chirog'i yoqilmadi. | Не включена аварийная сигнализация. |
| `pen_21` | Avariya chirog'i o'chirilmadi. | Не выключена аварийная сигнализация. |
| `pen_22` | Dvigatel o'chib qoldi. | Заглох двигатель. |
| `pen_23` | Startdan keyin qirq soniya qo'zg'almadingiz. | Не тронулись сорок секунд после старта. |
| `pen_24` | Qizil chiroqqa o'tdingiz! | Проезд на красный! |
| `pen_25` | Temir yo'lda to'xtamadingiz! | Не остановились перед переездом! |
| `pen_26` | Imtihon tark etildi. | Экзамен прерван. |
| `pen_27` | Mashq bajarilmadi. | Упражнение не выполнено. |
| `pen_28` | Marshrutdan chiqib ketdingiz. | Вы съехали с маршрута. |
| `pen_29` | Bu yerda orqaga yurish mumkin emas. | Здесь нельзя двигаться задним ходом. |
| `pen_30` | To'siqqa urildingiz! | Наезд на препятствие! |
| `pen_31` | Tezlik qirq kilometrdan oshdi! | Скорость выше сорока километров! |
| `pen_32` | Imtihon vaqti tugadi. | Время экзамена истекло. |

Jami: 53 ta gap, har bir til uchun.

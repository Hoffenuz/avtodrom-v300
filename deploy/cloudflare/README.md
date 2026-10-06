# AvtoSmart Avtodrom — web versiya

Brauzerda ishlaydigan build (Godot 4.7.2, WebGL2) va uni Cloudflare'da
uzatadigan Worker. Bu repozitoriyni qo'lda o'zgartirmang: uni o'yin
repozitoriysidagi `py scripts/build.py --web --publish-web` buyrug'i
to'liq yangilaydi (bitta commit, eski build'lar tarixda saqlanmaydi).

## Tarkibi

| Fayl | Vazifasi |
|---|---|
| `public/` | O'yin fayllari, gzip bilan siqilgan. 25 MiB dan kattalari `.gz.0`, `.gz.1` bo'laklariga bo'lingan (Cloudflare static assets cheklovi) |
| `public/_manifest.json` | Har fayl qaysi bo'laklardan iboratligi va build raqami |
| `worker.js` | Bo'laklarni bitta gzip oqimiga birlashtirib uzatadi (`Content-Encoding: gzip`), ETag bilan keshlaydi |
| `wrangler.toml` | Worker nomi `avtodrom-web`, domen `avtodrom.avtotestu.uz` |

## Cloudflare'ga ulash (bir marta)

1. Cloudflare dashboard → **Workers & Pages** → **Create** → **Import a repository**.
2. GitHub'ni ulang va `avtodrom/avtodrom-web` ni tanlang.
3. Sozlamalar:
   - Project name: `avtodrom-web` (wrangler.toml'dagi `name` bilan bir xil bo'lishi shart)
   - Build command: bo'sh qoldiring
   - Deploy command: `npx wrangler deploy`
   - Root directory: `/`
4. **Deploy**. Har `main` ga push'dan keyin Cloudflare o'zi qayta joylaydi.
5. `avtodrom.avtotestu.uz` domeni wrangler.toml'dagi `routes` orqali avtomatik
   ulanadi (avtotestu.uz zonasi shu Cloudflare hisobida bo'lishi kerak).
   Sinov manzili: `https://avtodrom-web.<hisob>.workers.dev`.

Pages emas, Worker: Pages ham 25 MiB dan katta fayllarni qabul qilmaydi va
bo'laklarni birlashtira olmaydi.

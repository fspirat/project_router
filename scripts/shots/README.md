# Скриншоты панели на демо-данных

Открывает настоящую страницу из `web/` в Chromium (Playwright), а ответы роутера и сервера подменяет
выдуманными данными из `demo_data.js`: устройства, адреса (диапазоны для документации), MAC 02:00:00:…
Реальных данных и сети не нужно — удобно смотреть правки панели до выкладки.

```bash
node scripts/shots/shots.js                       # ночная тема: VPN, Сеть, Устройства, телефон
THEME=light PFX=light- node scripts/shots/shots.js  # дневная тема
THEME=light EXTRA=1 node scripts/shots/shots.js m   # только телефон + меню «⋯» и окно подтверждения
DEAD=1 node scripts/shots/shots.js m              # список «Не отвечают»
```

Файлы — в `scripts/shots/out/` (не коммитятся; папку можно сменить переменной `OUT`).

Переменные: `THEME` (`dark`/`light`), `PFX` — приставка к именам файлов, `CHROME` — путь к Chromium, если Playwright не находит свой.
Нужен Node.js и пакет `playwright` (`npm i -g playwright`).

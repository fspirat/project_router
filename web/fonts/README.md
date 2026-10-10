# Шрифты панели (свои, без Google Fonts и CDN)

| Файл | Что | Лицензия |
|---|---|---|
| `inter-latin-wght-normal.woff2`, `inter-cyrillic-wght-normal.woff2` | Inter (Rasmus Andersson), переменная толщина 100–900, npm `@fontsource-variable/inter` 5.1.0 | SIL Open Font License 1.1 |
| `jetbrains-mono-latin-wght-normal.woff2`, `jetbrains-mono-cyrillic-wght-normal.woff2` | JetBrains Mono — числа, IP и MAC, npm `@fontsource-variable/jetbrains-mono` 5.1.0 | SIL Open Font License 1.1 |
| `TwemojiCountryFlags.woff2` | флаги стран для Windows (npm `country-flag-emoji-polyfill` 0.1.10) | код MIT (TalkJS), рисунки Twemoji — CC-BY 4.0 (Twitter) |

Папка `/router/fonts/` открыта без входа (nginx, `location ^~ /router/fonts/`): шрифты берёт и страница входа.

Иконки панели — `web/icons.svg`: спрайт из [Lucide](https://lucide.dev) 0.460.0 (лицензия ISC), подключается как
`<svg class="ic"><use href="icons.svg#имя"/></svg>`; цвет линий — цвет текста.

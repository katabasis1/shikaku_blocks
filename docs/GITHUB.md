# Проект в GitHub (PLAN 20.0)

Зачем: история всех правок, откат к любой версии, проект не теряется при пересоздании Pod. Позже (20.0b) — CI:
GitHub сам прогоняет selftest и проверки на каждый коммит.

## Первая загрузка

1. Скачайте `shikaku_blocks_latest.zip` (файлы беседы или `backups/` в Pod) и распакуйте. Внутри — папка
   `shikaku_blocks/`, в ней `project.godot`. Если у вас есть локальная папка проекта с кадрами `docs/promo/shots/`
   и видео — можно грузить и её: лишнее отсечёт `.gitignore`.
2. **Не загружайте через страницу «Upload files» на сайте.** Там предел 100 файлов за раз, а в проекте их ≈310.

### Вариант А — GitHub Desktop (проще)
1. Установите GitHub Desktop (desktop.github.com) и войдите в свой аккаунт GitHub.
2. File → Add local repository → выберите папку `shikaku_blocks`. Desktop скажет, что это не репозиторий, —
   нажмите «create a repository» → Create repository (README, `.gitignore` и лицензию не добавлять — они уже есть).
3. Слева внизу: Summary — «Первая версия», → Commit to main.
4. Publish repository → оставьте галочку **Keep this code private** → Publish.

### Вариант Б — командная строка
Создайте на github.com пустой приватный репозиторий `shikaku_blocks` (без README, `.gitignore` и лицензии), затем:
```
cd shikaku_blocks
git init -b main
git add .
git commit -m "Первая версия"
git remote add origin https://github.com/ВАШ_ЛОГИН/shikaku_blocks.git
git push -u origin main
```

## Что не попадает в репозиторий (`.gitignore`)
- `.godot/` — кэш импорта Godot, пересоздаётся при открытии проекта;
- `build/` — экспорт для Яндекса; `export_credentials.cfg` — пароли экспорта;
- `music_out/`, `tools/.levels_cache.jsonl`, `__pycache__/` — промежуточные файлы скриптов;
- `docs/promo/shots/`, `docs/promo/video/`, `*.mp4` — скриншоты и видео промо (пересобираются, видео — сотни МБ);
- `*.zip`, системные файлы (`.DS_Store`, `Thumbs.db`, `desktop.ini`).

Паролей и ключей в проекте нет. Номер счётчика Метрики не секрет — он виден в коде страницы игры. Репозиторий всё
равно лучше держать приватным.

`.gitattributes`: текстовые файлы хранятся с переводом строки LF на любой системе (как рекомендует Godot),
картинки, звук и шрифты — как бинарные.

## После каждой сессии с агентом
Агент в Компьютере не имеет доступа в интернет и сам в GitHub не отправляет. Перенос — через вас:
1. Скачайте свежий `shikaku_blocks_latest.zip` из беседы.
2. Распакуйте во временную папку и скопируйте содержимое её `shikaku_blocks/` **поверх** папки репозитория с
   заменой файлов (папку `.git` не трогать).
3. Если в логе сессии (`PROGRESS.md`, последняя запись) написано, что файлы удалены или переименованы, — удалите
   старые вручную.
4. GitHub Desktop покажет изменения → Summary — заголовок записи лога → Commit → Push origin.

## Если Pod пересоздали
Вместо архива можно взять проект прямо из репозитория: на странице репозитория Code → Download ZIP, распаковать и
загрузить папку в Pod. Агент найдёт `project.godot` и `tools/save.py` (см. начало `PROGRESS.md`).

## CI (20.0b)
Нужна точная версия Godot: в редакторе Справка → О Godot (например, 4.7.1.stable). Агент добавит
`.github/workflows/selftest.yml`, и вкладка Actions на GitHub будет показывать, прошли ли selftest и проверки.

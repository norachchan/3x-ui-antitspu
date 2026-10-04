# Встроенный установщик 3X-UI KIT

Файлы в этой папке — **копия** релиза [3X-UI_KIT](https://github.com/itsnotkubrick/3X-UI_KIT)
(версия в `VERSION`), не форк. Используются только как базовый стек (панель, протоколы, nginx, kit-sub).

После установки KIT репозиторий **3x-ui-antitspu** накладывает anti-TSPU overlay (`overlay/kit_sub.py`, nginx, hooks).

Обновить vendor с upstream:

```bash
bash /opt/3x-ui-antitspu/scripts/sync-kit-vendor.sh [тег, по умолчанию v1.1.2]
```

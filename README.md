# 3x-ui-antitspu

**Один репозиторий** — полная установка VPN-узла на [3X-UI](https://github.com/MHSanaei/3x-ui) и встроенном [3X-UI KIT](https://github.com/itsnotkubrick/3X-UI_KIT) (vendor, не форк) + overlay против типичных срабатываний ТСПУ.

Отдельно качать KIT не нужно: установщик лежит в `vendor/kit/`.

## Одна команда (новый VPS)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/norachchan/3x-ui-antitspu/main/install.sh)
```

Интерактивно спросит **IP/хост в ссылках**, **домен** (опционально), **имя узла** (`NODE_REMARK` в панели).  
Домен на этапе KIT (self-steal, Let's Encrypt):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/norachchan/3x-ui-antitspu/main/install.sh) -- --domain stats.example.com -y
```

Или заранее в `/etc/3x-ui-antitspu.env`: `LINK_DOMAIN=…`, `PUBLIC_HOST=…`, `NODE_REMARK=NL-02`.

## Только overlay (панель уже есть)

```bash
SKIP_BASE_INSTALL=1 bash <(curl -fsSL https://raw.githubusercontent.com/norachchan/3x-ui-antitspu/main/install.sh)
```

## Состав

| Часть | Путь |
|--------|------|
| KIT (панель, протоколы, nginx, kit-sub) | `vendor/kit/3x-ui.sh` |
| Anti-TSPU overlay | `overlay/kit_sub.py`, `scripts/apply.sh` |
| Мастер IP/домен/имя узла | `scripts/configure-prompt.sh` |
| Self-steal nginx | `templates/nginx-selfsteal.conf.template` |

## Что даёт overlay

| Компонент | Назначение |
|-----------|------------|
| `overlay/kit_sub.py` | SNI для WS/gRPC по IP; `link_domain`; xHTTP `xmux.maxConnections: 3` |
| `scripts/reapply-sub.sh` | После `kit update` (hook в `kit-update.service`) |
| `scripts/kit-ip-cert-sync.sh` | acme IP-сертификат → `/root/cert/custom` |
| `scripts/upgrade-xray.sh` | Опционально Xray 26.7+ (`XRAY_VERSION` в env) |

## Настройка

```bash
nano /etc/3x-ui-antitspu.env
bash /opt/3x-ui-antitspu/scripts/apply.sh
```

См. `config/antitspu.env.example`.

Ручная донастройка inbound'ов (firefox, self-steal inbound, AWG): `docs/PANEL-TUNING.md`.

## Обновить встроенный KIT

```bash
bash /opt/3x-ui-antitspu/scripts/sync-kit-vendor.sh v1.1.2
git -C /opt/3x-ui-antitspu commit -am "vendor: kit v1.1.2"   # если ведёте свой форк
```

## Проверка подписки

```bash
curl -sk "https://<IP>/<sub-path>/<subId>" | base64 -d | grep -E 'xmux|sni='
```

## Лицензия и атрибуция

- `vendor/kit/*` — проект [itsnotkubrick/3X-UI_KIT](https://github.com/itsnotkubrick/3X-UI_KIT), см. `vendor/kit/NOTICE.md`.
- `overlay/kit_sub.py` — производная от kit-sub KIT; остальные файлы — по вашему усмотрению.

# 3x-ui-antitspu

Установка VPN-узла на [3X-UI](https://github.com/MHSanaei/3x-ui) с протоколами, nginx и overlay против типичных срабатываний ТСПУ. Всё в одном репозитории (`vendor/stack`).

## Одна команда

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/norachchan/3x-ui-antitspu/main/install.sh)
```

Спросит **IP/хост**, **домен** (опционально), **имя узла** в панели (`NODE_REMARK`).

Домен (self-steal, Let's Encrypt):

```bash
bash <(curl -fsSL …/install.sh) -- --domain stats.example.com -y
```

## Только overlay

```bash
SKIP_BASE_INSTALL=1 bash <(curl -fsSL …/install.sh)
```

## Состав

| Часть | Путь |
|--------|------|
| Базовый установщик | `vendor/stack/3x-ui.sh` |
| Overlay подписки | `overlay/sub_proxy.py`, `scripts/apply.sh` |
| Мастер настроек | `scripts/configure-prompt.sh` |

## Overlay

| Файл | Назначение |
|------|------------|
| `overlay/sub_proxy.py` | SNI для WS/gRPC; `link_domain`; xHTTP `xmux.maxConnections: 3` |
| `scripts/reapply-sub.sh` | После автообновления панели |
| `scripts/ip-cert-sync.sh` | IP-сертификат acme → `/root/cert/custom` |
| `scripts/upgrade-xray.sh` | Опционально Xray 26.7+ |

Настройка: `/etc/3x-ui-antitspu.env`, `bash scripts/apply.sh`.  
Ручная донастройка inbound'ов: `docs/PANEL-TUNING.md`.

## Обновить vendor/stack

```bash
bash /opt/3x-ui-antitspu/scripts/sync-vendor.sh v1.1.2
```

## Проверка подписки

```bash
curl -sk "https://<IP>/<sub-path>/<subId>" | base64 -d | grep -E 'xmux|sni='
```

## Атрибуция

Базовый установщик — upstream-копия (см. `vendor/stack/UPSTREAM.md`). Overlay — репозиторий **norachchan/3x-ui-antitspu**.

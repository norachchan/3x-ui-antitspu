# 3x-ui-antitspu

Overlay для сервера на базе [3X-UI](https://github.com/MHSanaei/3x-ui) (установка через [3X-UI_KIT](https://github.com/itsnotkubrick/3X-UI_KIT)): подписка и nginx с упором на обход типичных срабатываний ТСПУ.

**Не форк панели** — поверх уже установленного стека накладываются скрипты и `kit_sub.py`.

## Одна команда (новый VPS)

Репозиторий: [merritt-e/3x-ui-antitspu](https://cursor.com/codebase/merritt-e/3x-ui-antitspu)

```bash
git clone https://origin.cursor.com/merritt-e/3x-ui-antitspu.git /opt/3x-ui-antitspu
bash /opt/3x-ui-antitspu/install.sh
```

(Нужен вход в Cursor: `origin auth login` на сервере.)

## Только overlay (панель уже есть)

```bash
git clone https://origin.cursor.com/merritt-e/3x-ui-antitspu.git /opt/3x-ui-antitspu
SKIP_BASE_INSTALL=1 bash /opt/3x-ui-antitspu/install.sh
```

## Что делает overlay

| Компонент | Назначение |
|-----------|------------|
| `overlay/kit_sub.py` | SNI для WS/gRPC по IP; опционально `link_domain`; **xHTTP `xmux.maxConnections: 3`** |
| `scripts/reapply-sub.sh` | Восстановление после `kit update` (hook в `kit-update.service`) |
| `scripts/kit-ip-cert-sync.sh` | Синхронизация IP-сертификата acme → `/root/cert/custom` |
| `templates/nginx-selfsteal.conf.template` | Локальный HTTPS для REALITY self-steal |
| `scripts/upgrade-xray.sh` | Опционально Xray 26.7+ |

## Настройка

```bash
cp /opt/3x-ui-antitspu/config/antitspu.env.example /etc/3x-ui-antitspu.env
nano /etc/3x-ui-antitspu.env
bash /opt/3x-ui-antitspu/scripts/apply.sh
```

Пример:

```bash
LINK_DOMAIN=stats.example.com
LINK_DOMAIN_SUBS=*
SELFSTEAL_DOMAIN=stats.example.com
XRAY_VERSION=26.7.28
```

Перед self-steal: выпустите сертификат на домен (`acme.sh`), пропишите пути в шаблоне nginx при необходимости.

## Ручная донастройка панели (не в репозитории)

Рекомендуется после установки (см. ваш runbook):

- отпечаток **firefox** в REALITY / TLS / Hysteria;
- inbound self-steal REALITY → `127.0.0.1:10448`;
- AmneziaWG 1.x / 3.1 и twin `*-awg` для Mihomo;
- `worker_connections` nginx ≥ 16384.

## Проверка подписки

```bash
curl -sk "https://<IP>/<sub-path>/<subId>" | base64 -d | grep -E 'xmux|sni='
```

В xHTTP-ссылке в `extra` должно быть `"xmux":{"maxConnections":3}`; у WS/gRPC TLS — `sni=<IP>`.

## Лицензия

`overlay/kit_sub.py` производен от kit-sub 3X-UI KIT; остальные файлы — по вашему усмотрению.

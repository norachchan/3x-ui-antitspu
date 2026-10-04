# Донастройка панели (вручную)

Скрипты репозитория **не** меняют все inbound'ы в SQLite — это чеклист после `apply.sh`.

1. **Fingerprint** — `firefox` на REALITY, внешнем TLS (WS/gRPC), Hysteria2.
2. **xHTTP** — в inbound `sockopt.acceptProxyProtocol`, в подписке xmux ≤ 3 (даёт overlay).
3. **Self-steal** — отдельный VLESS REALITY Vision, `dest` → `127.0.0.1:10448`, SNI = ваш домен.
   - A-запись домена на VPS, порт **80** открыт.
   - Сертификат: `bash /opt/3x-ui-antitspu/scripts/issue-domain-cert.sh image.example.com`
   - Затем overlay: `SKIP_BASE_INSTALL=1 ANTITSPU_SKIP_PROMPT=1 bash /opt/3x-ui-antitspu/install.sh`
   - В env `LINK_DOMAIN_SUBS` для «всем» пишите **`'*'`** (с кавычками), иначе bash раскроет `*` как glob.
4. **AmneziaWG** — порты 51821 / 51822, клиенты `*-awg` для Clash/Mihomo.
5. **nginx** — `worker_connections 16384`, `worker_rlimit_nofile 65535` (частично в `apply.sh`).

Проверка из РФ: probe / Happ, burst 8× TLS без заморозки IP.

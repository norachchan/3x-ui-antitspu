#!/usr/bin/env python3
"""Прокси подписки 3X-UI (3x-ui-antitspu overlay).

add_sni (gRPC/WS), link_domain, xHTTP xmux maxConnections=3.

Слушает публичный адрес подписки (HTTPS) и ходит в подписку 3X-UI на 127.0.0.1:
  * Clash / Mihomo (Clash Verge, FlClash, Mihomo Party…) – конфиг 3X-UI плюс AmneziaWG
    из подписки «<id>-awg»: Mihomo умеет AmneziaWG, а остальные приложения нет;
  * остальные приложения и браузер – ответ 3X-UI как есть (ссылки или страница);
  * заголовок Subscription-Userinfo: expire=0 («бессрочно») убирается – иначе
    приложения показывают срок «01.01.1970».

Настройки – /etc/kit-sub/config.json. Сертификат перечитывается сам после продления.
"""

import base64
import http.client
import http.server
import json
import os
import re
import socket
import ssl
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

import yaml

# Под systemd kit-sub работает без root (DynamicUser): конфиг и сертификат ему передаёт
# systemd через LoadCredential в $CREDENTIALS_DIRECTORY.
CREDS = os.environ.get("CREDENTIALS_DIRECTORY", "")
CONFIG = os.environ.get("KIT_SUB_CONFIG") or (
    os.path.join(CREDS, "config.json") if CREDS and os.path.exists(os.path.join(CREDS, "config.json")) else "/etc/kit-sub/config.json")
CLASH_UA = re.compile(r"clash|mihomo|flclash|stash|nyanpasu|meta", re.I)
# AmneziaWG добавляем только приложениям на ядре Mihomo. Karing, Hiddify и другие на sing-box
# тоже могут просить формат Clash (Karing так и делает), но AmneziaWG не умеют.
NO_AWG_UA = re.compile(r"karing|hiddify|nekobox|sing-?box|husi|stash|shadowrocket|v2box|streisand|happ|loon|surge|quantumult", re.I)
SUB_ID = re.compile(r"^[A-Za-z0-9_.@-]{1,64}$")
# Заголовки Happ, которые 3X-UI отдаёт в подписке (маршрутизация, баннеры, настройки клиента).
HAPP_HEADERS = ("routing", "routing-enable", "announce", "providerid", "new-url", "fallback-url",
                "hide-settings", "no-limit-enabled", "ping-type", "color-profile", "tun-mode", "tun-type",
                "exclude-routes", "exclude-apns-enable", "per-app-proxy-mode", "per-app-proxy-list",
                "notification-subs-expire", "sub-expire", "sub-expire-button-link", "sub-info-text",
                "sub-info-color", "sub-info-button-text", "sub-info-button-link",
                "subscription-autoconnect", "subscription-autoconnect-type", "subscription-always-hwid-enable")
PASS_HEADERS = ("content-type", "content-disposition", "profile-title", "profile-update-interval",
                "profile-web-page-url", "subscription-userinfo", "support-url", "cache-control") + HAPP_HEADERS

with open(CONFIG, encoding="utf-8") as f:
    CONF = json.load(f)
PATH = "/" + CONF["path"].strip("/") + "/"


def log(msg):
    print(msg, flush=True)


def upstream(sub_id, ua, host, accept):
    """GET к подписке 3X-UI. Возвращает (код, заголовки, тело) или (None, {}, b"")."""
    req = urllib.request.Request(CONF["upstream"].rstrip("/") + PATH + sub_id, headers={
        "User-Agent": ua, "Host": host, "Accept": accept or "*/*"})
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return r.status, {k.lower(): v for k, v in r.getheaders()}, r.read()
    except urllib.error.HTTPError as e:
        return e.code, {k.lower(): v for k, v in e.headers.items()}, e.read()
    except (urllib.error.URLError, http.client.HTTPException, OSError, socket.timeout) as e:
        log(f"upstream недоступен: {e}")
        return None, {}, b""


def fix_userinfo(value):
    # «expire=0» значит «бессрочно», но приложения рисуют 01.01.1970 – убираем.
    parts = [p.strip() for p in value.split(";") if p.strip() and p.strip() != "expire=0"]
    return "; ".join(parts)


def patch_xhttp_xmux(line):
    """XHTTP: не больше 3 параллельных TLS (anti-TSPU, Xray 26.7+)."""
    if not line.startswith("vless://"):
        return line
    u = urllib.parse.urlsplit(line)
    q = urllib.parse.parse_qs(u.query, keep_blank_values=True)
    if q.get("type", [""])[0] != "xhttp":
        return line
    raw = q.get("extra", ["{}"])[0] or "{}"
    try:
        extra = json.loads(urllib.parse.unquote(raw))
    except (json.JSONDecodeError, TypeError):
        extra = {}
    xmux = extra.setdefault("xmux", {})
    if isinstance(xmux, dict):
        xmux["maxConnections"] = 3
    q["extra"] = [json.dumps(extra, separators=(",", ":"))]
    query = urllib.parse.urlencode({k: v[0] for k, v in q.items()}, safe=":/")
    return urllib.parse.urlunsplit(u._replace(query=query))


def add_sni(line):
    """TLS через nginx по IP: 3X-UI не пишет sni в ссылку, а gRPC в Xray-core без ServerName
    не подключается («at least one of ServerName… must be specified»)."""
    if not line.startswith(("vless://", "trojan://")):
        return line
    u = urllib.parse.urlsplit(line)
    q = urllib.parse.parse_qs(u.query, keep_blank_values=True)
    if q.get("security", [""])[0] != "tls" or q.get("sni", [""])[0] or not u.hostname:
        return line
    query = (u.query + "&" if u.query else "") + "sni=" + urllib.parse.quote(u.hostname, safe=":")
    return urllib.parse.urlunsplit(u._replace(query=query))


def domain_for(sub_id):
    """Домен для TLS-ссылок через nginx (WS, gRPC) вместо IP: «link_domain» в конфиге,
    «link_domain_subs» – список подписок или «*» для всех."""
    domain, subs = CONF.get("link_domain", ""), CONF.get("link_domain_subs", [])
    return domain if domain and (subs == "*" or sub_id in subs) else ""


def use_domain(line, domain):
    if not domain or not line.startswith(("vless://", "trojan://")):
        return line
    u = urllib.parse.urlsplit(line)
    q = urllib.parse.parse_qs(u.query, keep_blank_values=True)
    if q.get("security", [""])[0] != "tls" or q.get("type", [""])[0] not in ("ws", "grpc") or q.get("sni", [""])[0]:
        return line
    netloc = u.netloc.rsplit("@", 1)
    hostport = domain + (f":{u.port}" if u.port else "")
    return urllib.parse.urlunsplit(u._replace(netloc=f"{netloc[0]}@{hostport}" if len(netloc) == 2 else hostport))


def domain_clash(clash_yaml, domain):
    if not domain:
        return clash_yaml
    cfg = yaml.safe_load(clash_yaml)
    if not isinstance(cfg, dict):
        return clash_yaml
    for p in cfg.get("proxies") or []:
        if (isinstance(p, dict) and p.get("type") in ("vless", "trojan") and p.get("tls")
                and p.get("network") in ("ws", "grpc") and "reality-opts" not in p):
            p["server"] = domain
            p["sni" if p["type"] == "trojan" else "servername"] = domain
    return yaml.safe_dump(cfg, allow_unicode=True, sort_keys=False).encode()


def strip_links(body, domain=""):
    """Список ссылок (base64 или текст) без vpn:// и tg:// – их не умеет ни одно VPN-приложение
    со ссылками: vpn:// – конфиг для AmneziaVPN, tg:// – прокси для Telegram."""
    text = body.decode("utf-8", "replace").strip()
    encoded = "://" not in text
    if encoded:
        try:
            text = base64.b64decode(text + "=" * (-len(text) % 4)).decode("utf-8", "replace")
        except ValueError:
            return body
    lines = [patch_xhttp_xmux(add_sni(use_domain(l, domain)))
             for l in text.splitlines() if l.strip() and not l.startswith(("vpn://", "tg://"))]
    out = "\n".join(lines)
    return base64.b64encode(out.encode()).decode().encode() if encoded else out.encode()


def strip_awg(clash_yaml):
    """Clash-конфиг без AmneziaWG – для приложений, которые его не умеют."""
    cfg = yaml.safe_load(clash_yaml)
    if not isinstance(cfg, dict):
        return clash_yaml
    awg = {p.get("name") for p in cfg.get("proxies") or [] if isinstance(p, dict) and "amnezia-wg-option" in p}
    if not awg:
        return clash_yaml
    cfg["proxies"] = [p for p in cfg["proxies"] if p.get("name") not in awg]
    for g in cfg.get("proxy-groups") or []:
        if isinstance(g.get("proxies"), list):
            g["proxies"] = [x for x in g["proxies"] if x not in awg]
    return yaml.safe_dump(cfg, allow_unicode=True, sort_keys=False).encode()


def merge_awg(main_yaml, awg_yaml):
    """Добавляет прокси AmneziaWG в Clash-конфиг и во все группы, где перечислены прокси."""
    main = yaml.safe_load(main_yaml)
    awg = yaml.safe_load(awg_yaml)
    if not isinstance(main, dict) or not isinstance(awg, dict):
        return main_yaml
    extra = [p for p in (awg.get("proxies") or []) if isinstance(p, dict) and p.get("name")]
    if not extra:
        return main_yaml
    names = {p.get("name") for p in main.get("proxies") or []}
    for p in extra:
        # 3X-UI дописывает к имени запись-«двойника» («AmneziaWG-3.1-sasha-awg») – убираем хвост.
        p["name"] = re.sub(r"-[^-\s]+-awg\d*$", "", p["name"]) or p["name"]
        base, n = p["name"], 2
        while p["name"] in names:
            p["name"] = f"{base} {n}"
            n += 1
        names.add(p["name"])
    main.setdefault("proxies", []).extend(extra)
    added = [p["name"] for p in extra]
    for g in main.get("proxy-groups") or []:
        lst = g.get("proxies")
        if isinstance(lst, list) and any(x in names for x in lst):
            pos = lst.index("DIRECT") if "DIRECT" in lst else len(lst)
            g["proxies"] = lst[:pos] + added + lst[pos:]
    return yaml.safe_dump(main, allow_unicode=True, sort_keys=False).encode()


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "nginx"
    sys_version = ""
    timeout = 20  # зависшие соединения не держим

    def setup(self):
        # TLS-рукопожатие – в потоке запроса, а не в общем цикле приёма соединений.
        # Без сертификата (за nginx, на 127.0.0.1) работаем по обычному HTTP.
        self.request.settimeout(self.timeout)
        if self.server.ssl_ctx is not None:
            self.request = self.server.ssl_ctx.wrap_socket(self.request, server_side=True)
        super().setup()

    def handle(self):
        try:
            super().handle()
        except (ssl.SSLError, ConnectionError, socket.timeout, OSError):
            pass

    def log_message(self, fmt, *args):  # без IP клиентов в логах
        pass

    def send_plain(self, code, text=""):
        body = text.encode()
        self.send_response(code)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def send_error(self, code, message=None, explain=None):
        # Свои короткие ответы вместо страницы ошибок Python: сканеру не видно, чем отвечает сервер.
        self.close_connection = True
        self.send_plain(code, f"{code} {self.responses.get(code, ('error',))[0].lower()}")

    def do_other(self):
        self.send_plain(404, "404 page not found")

    do_POST = do_PUT = do_DELETE = do_PATCH = do_OPTIONS = do_other

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if not path.startswith(PATH):
            return self.send_plain(404, "404 page not found")
        sub_id = path[len(PATH):]
        if not SUB_ID.match(sub_id):
            return self.send_plain(404, "404 page not found")
        ua = self.headers.get("User-Agent", "")
        host = self.headers.get("Host", CONF.get("host", ""))
        accept = self.headers.get("Accept", "")
        code, headers, body = upstream(sub_id, ua, host, accept)
        if code is None:
            return self.send_plain(502, "subscription backend is unavailable")

        clash = bool(CLASH_UA.search(ua)) and "yaml" in headers.get("content-type", "")
        awg = clash and not NO_AWG_UA.search(ua)
        # В журнал – только приложение и что ему отдали, без IP.
        log(f"{ua[:80]!r} → {'clash+awg' if awg else 'clash' if clash else headers.get('content-type', '?').split(';')[0]}")
        domain = domain_for(sub_id)
        try:
            if code == 200 and clash and not awg:
                body = domain_clash(strip_awg(body), domain)
            elif code == 200 and awg and not sub_id.endswith(("-awg", "-tg")):
                # Старые установки держали AmneziaWG в подписке «<id>-awg» – подмешиваем её.
                acode, _, abody = upstream(sub_id + "-awg", ua, host, accept)
                if acode == 200 and abody:
                    body = merge_awg(body, abody)
                body = domain_clash(body, domain)
            elif code == 200 and clash:
                body = domain_clash(body, domain)
            elif code == 200 and "text/plain" in headers.get("content-type", ""):
                body = strip_links(body, domain)
        except (yaml.YAMLError, UnicodeError) as e:
            log(f"не удалось обработать подписку: {e}")

        self.send_response(code)
        for k in PASS_HEADERS:
            if k in headers:
                v = fix_userinfo(headers[k]) if k == "subscription-userinfo" else headers[k]
                if v and "\r" not in v and "\n" not in v:
                    self.send_header(k.title(), v)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)


class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True
    ssl_ctx = None

    def handle_error(self, request, client_address):  # обрывы TLS от сканеров – не ошибка
        pass
    address_family = socket.AF_INET6 if ":" in CONF.get("listen", "") else socket.AF_INET


def main():
    cert, key = CONF.get("cert"), CONF.get("key")
    if cert and CREDS and os.path.exists(os.path.join(CREDS, "cert.pem")):
        cert, key = os.path.join(CREDS, "cert.pem"), os.path.join(CREDS, "key.pem")
    if not cert:
        srv = Server((CONF.get("listen", "127.0.0.1"), int(CONF["port"])), Handler)
        log(f"sub-proxy слушает http://{CONF.get('listen', '127.0.0.1')}:{CONF['port']}{PATH} (TLS снимает nginx)")
        srv.serve_forever()
        return
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.minimum_version = ssl.TLSVersion.TLSv1_2
    ctx.load_cert_chain(cert, key)
    stamp = [os.path.getmtime(cert)]

    def reload_cert():
        # Let's Encrypt на IP живёт 6 дней – после продления берём новый сертификат без перезапуска.
        while True:
            time.sleep(600)
            try:
                m = os.path.getmtime(cert)
                if m != stamp[0]:
                    ctx.load_cert_chain(cert, key)
                    stamp[0] = m
                    log("сертификат обновлён")
            except (OSError, ssl.SSLError) as e:
                log(f"не удалось перечитать сертификат: {e}")

    threading.Thread(target=reload_cert, daemon=True).start()
    srv = Server((CONF.get("listen", "0.0.0.0"), int(CONF["port"])), Handler)
    srv.ssl_ctx = ctx
    log(f"sub-proxy слушает {CONF.get('listen', '0.0.0.0')}:{CONF['port']}{PATH}")
    srv.serve_forever()


if __name__ == "__main__":
    main()

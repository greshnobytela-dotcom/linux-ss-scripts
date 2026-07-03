#!/usr/bin/env bash
# BrowserHistory — URL/IP читов в истории браузера (Linux)
# Python3 + sqlite — расширенная база RU/EU/INT клиентов и агрегаторов

set -uo pipefail

echo "=== BrowserHistory — читы / IP / inject (Linux) ==="
echo

if ! command -v python3 >/dev/null 2>&1; then
  echo "[ERR] Нужен python3."
  exit 1
fi

python3 - "$HOME" <<'PY'
import glob, os, re, shutil, sqlite3, sys, tempfile, urllib.parse
from datetime import datetime, timezone

HOME = sys.argv[1]

# ── Популярные чит-клиенты (имя в домене/URL/title) ──
CLIENT_NAMES = (
    "nursultan", "wexside", "wexide", "expensive", "minced", "delta", "deltaclient",
    "celestial", "celka", "zenith", "haruka", "rockstar", "catlavan", "wildclient",
    "doomsday", "vape", "vapev4", "vapelite", "meteor", "liquidbounce", "wurst",
    "aristois", "fdp", "fdpclient", "novoline", "onetap", "manthe", "thunderhack",
    "bleachhack", "impact", "phobos", "xulu", "astolfo", "exosware", "grim",
    "entropy", "dream", "drip", "sunset", "slinky", "karma", "sigma", "moon",
    "zeroday", "rise", "akrien", "atomic", "raven", "flux", "weedhack", "celka",
    "eclipse", "nixware", "interium", "spirt", "matix", "deadcode", "relake",
    "venus", "quickclient", "fluger", "winzor", "ponos", "nevermore", "koid",
    "fusion", "skid", "intent", "monot", "huzuni", "sigma5",
    "remix", "cortex", "slinky", "entrance", "nightmare",
    "nurik", "cataclysm", "wissend", "nuclear", "drogan", "spooky", "wildclient",
)

# ── Известные сайты-агрегаторы / магазины читов ──
CHEAT_SITES = (
    r"masterminecraft\.ru", r"cheat-empire\.(fun|ru|eu)", r"mineleak\.pro",
    r"cheatgate", r"ghostclient", r"chity-minecraft", r"minecraft-chity",
    r"chit-minecraft", r"mc-hack", r"minecraft-hack", r"hack-minecraft",
    r"cheat-master", r"cheatmaster", r"mcleak", r"leakmc", r"skidstore",
    r"skid\.cc", r"intent\.store", r"nursultan\.fun", r"vape\.gg", r"vape\.lt",
    r"meteorclient\.com", r"liquidbounce\.net", r"wurstclient\.net",
    r"aristois\.net", r"riseclient\.com", r"novoline\.wtf", r"fdpinfo",
    r"cheat\.(ru|eu|fun|xyz)", r"chit\.(ru|eu|fun)", r"client\.(ru|eu)",
    r"ghost\.(ru|eu|fun)", r"hack\.(ru|eu|fun)", r"\.su/",
    r"celka\.su", r"wexside\.(ru|eu|xyz|fun)", r"expensive.*\.(ru|eu|fun)",
    r"minced\.(ru|eu|fun)", r"delta.*client", r"masterminecraft",
)

CLIENT_RE = re.compile("|".join(re.escape(n) for n in CLIENT_NAMES), re.I)
SITE_RE = re.compile("|".join(CHEAT_SITES), re.I)

CHEAT_IP = re.compile(
    r"165\.22\.\d{1,3}\.\d{1,3}|167\.172\.\d{1,3}\.\d{1,3}|"
    r"144\.217\.\d{1,3}\.\d{1,3}|45\.142\.\d{1,3}\.\d{1,3}|"
    r"185\.234\.\d{1,3}\.\d{1,3}",
    re.I,
)

# Путь URL — типичные RU/EU страницы скачивания
CHEAT_PATH = re.compile(
    r"/chit|/cheat|/hack|/ghost|/kryak|/kryaknut|/кряк|/чит|"
    r"chit-|cheat-|hack-|ghost-|klient|client-cheat|cheat-client|"
    r"/resources/chit|/download.*cheat|/download.*chit",
    re.I,
)

# Title — явные фразы (не «бесплатно» / «кончить»)
def title_is_cheat(title, host=""):
    if not title:
        return False
    t = title.lower()
    if "hosting-minecraft" in host or "hosting-minecraft" in t:
        return False
    phrases = (
        "чит клиент", "чит-client", "чит minecraft", "minecraft чит",
        "чит-клиент", "чит мод", "hack client", "ghost client", "cheat client",
        "кряк", "крякнут", "скачать чит", "killaura",
        "лучший клиент для майн", "лучший клиент для комфортной",
        "клиент для комфортной игры", "pvp client", "hvh client",
        "чит client", "ghost client",
    )
    if any(p in t for p in phrases):
        return True
    if re.search(r"(?:^|[\s\W\-«\"'])чит(?:[\s\W\-»\"']|$)", t):
        return True
    # имя клиента + слово client/клиент/чит в title
    if CLIENT_RE.search(t) and re.search(r"client|клиент|чит|hack|ghost|кряк", t):
        return True
    return False


CHEAT_SEARCH = re.compile(
    r"(?:search.*?(?:q|query|text)=([^&]+)|ya\.ru/search/\?text=([^&]+))",
    re.I,
)
CHEAT_QUERY = re.compile(
    r"nursultan|wexside|expensive|minced|delta\s*client|celestial|zenith|"
    r"vape|doomsday|meteor|liquidbounce|wurst|aristois|fdp|novoline|"
    r"чит\s*клиент|клиент\s*чит|скачать\s*чит|minecraft\s*чит|ghost\s*client|"
    r"hack\s*client|killaura|инжект|javaagent|thunderhack|bleachhack",
    re.I,
)

# Не банить легит
WHITELIST_HOST = re.compile(
    r"google\.|youtube\.|yandex\.|ya\.ru|vk\.com|discord\.com|github\.com|"
    r"modrinth\.com|curseforge\.com|minecraft\.net|mojang\.|tlauncher\.|"
    r"gosuslugi|rambler\.|hosting-minecraft|hypixel\.|2x2\.|"
    r"brave\.com|cursor\.|workos\.|authenticator\.|"
    r"vanillatweaks|fabricmc\.|forge\.|labymod\.|lunarclient|feathermc|"
    r"youtube\.com|youtu\.be|pornhub\.|xvideos\.|googlevideo|24xxx\.|xxx\.",
    re.I,
)

hits = []


def chrome_ts(t):
    if not t:
        return 0, "?"
    ts = t / 1_000_000 - 11644473600
    try:
        dt = datetime.fromtimestamp(ts, tz=timezone.utc).astimezone()
        return ts, dt.strftime("%Y-%m-%d %H:%M")
    except Exception:
        return ts, "?"


def firefox_ts(t):
    if not t:
        return 0, "?"
    ts = t / 1_000_000
    try:
        dt = datetime.fromtimestamp(ts, tz=timezone.utc).astimezone()
        return ts, dt.strftime("%Y-%m-%d %H:%M")
    except Exception:
        return ts, "?"


def pretty_browser(raw):
    m = {"google-chrome": "Chrome", "Brave-Browser": "Brave", "chromium": "Chromium",
         "microsoft-edge": "Edge", "opera": "Opera", "vivaldi": "Vivaldi"}
    parts = raw.split("/", 1)
    name = m.get(parts[0], parts[0])
    if "Brave" in raw:
        name = "Brave"
    return f"{name}/{parts[1] if len(parts) > 1 else 'Default'}"


def match_url(url, title=""):
    if not url or url.startswith(("chrome://", "brave://", "about:", "blob:")):
        return None
    text = f"{url} {title}"
    if CHEAT_IP.search(text):
        return "IP чит-сервера"

    try:
        p = urllib.parse.urlparse(url)
        host = (p.netloc or "").lower()
        path = (p.path or "").lower()
        full = f"{host}{path}"
    except Exception:
        host, path, full = "", "", url.lower()

    if WHITELIST_HOST.search(host):
        # поисковики — только query в URL, не title
        if re.search(r"search\.|google\.|ya\.ru/search", host + path):
            for m in CHEAT_SEARCH.finditer(url):
                q = urllib.parse.unquote_plus((m.group(1) or m.group(2) or "").replace("+", " "))
                q = q.split("&")[0][:120]
                if CHEAT_QUERY.search(q):
                    return f"поиск: {q[:55]}"
            return None
        if not (CHEAT_PATH.search(path) or CLIENT_RE.search(full) or SITE_RE.search(full)):
            return None

    if SITE_RE.search(full):
        return "сайт читов (агрегатор)"
    if CLIENT_RE.search(full):
        m = CLIENT_RE.search(full)
        return f"клиент: {m.group(0)}"
    if CHEAT_PATH.search(path):
        return "RU/EU страница чита"
    if title_is_cheat(title or "", host):
        return "title: чит/клиент"

    # .ru .eu .fun — имя клиента в домене второго уровня
    tld = host.rsplit(".", 1)[-1] if "." in host else ""
    if tld in ("ru", "eu", "fun", "xyz", "site", "online", "pro", "gg", "lt", "cc", "su"):
        label = host.replace("www.", "").split(".")[0]
        if CLIENT_RE.search(label) or CLIENT_RE.search(host):
            m = CLIENT_RE.search(host) or CLIENT_RE.search(label)
            return f"RU/EU домен: {m.group(0) if m else label}"

    for m in CHEAT_SEARCH.finditer(url):
        q = urllib.parse.unquote_plus((m.group(1) or m.group(2) or "").replace("+", " "))
        q = q.split("&")[0][:120]
        if CHEAT_QUERY.search(q):
            return f"поиск: {q[:55]}"
    return None


def add_hit(sort_ts, when, browser, url, title, reason):
    hits.append((sort_ts, when, browser, url, title or "", reason))


def scan_chromium(db, label):
    tmp = tempfile.mktemp(suffix=".db")
    try:
        shutil.copy2(db, tmp)
    except OSError:
        return
    try:
        con = sqlite3.connect(f"file:{tmp}?mode=ro", uri=True)
        browser = pretty_browser(label)
        for url, title, lvt, _ in con.execute(
            "SELECT url, IFNULL(title,''), last_visit_time, IFNULL(visit_count,0) FROM urls"
        ):
            reason = match_url(url, title)
            if reason:
                ts, when = chrome_ts(lvt)
                add_hit(ts, when, browser, url, title, reason)
        con.close()
    except sqlite3.Error:
        pass
    finally:
        try:
            os.unlink(tmp)
        except OSError:
            pass


def scan_firefox(db):
    tmp = tempfile.mktemp(suffix=".db")
    try:
        shutil.copy2(db, tmp)
    except OSError:
        return
    try:
        con = sqlite3.connect(f"file:{tmp}?mode=ro", uri=True)
        for url, title, lvd in con.execute(
            "SELECT url, IFNULL(title,''), IFNULL(last_visit_date,0) FROM moz_places"
        ):
            reason = match_url(url, title)
            if reason:
                ts, when = firefox_ts(lvd)
                add_hit(ts, when, "Firefox", url, title, reason)
        con.close()
    except sqlite3.Error:
        pass
    finally:
        try:
            os.unlink(tmp)
        except OSError:
            pass


for pat in (
    ".config/google-chrome/*/History",
    ".config/chromium/*/History",
    ".config/BraveSoftware/Brave-Browser/*/History",
    ".config/microsoft-edge/*/History",
    ".config/opera/*/History",
    ".config/vivaldi/*/History",
):
    for db in glob.glob(os.path.join(HOME, pat)):
        prof = os.path.basename(os.path.dirname(db))
        browser = os.path.basename(os.path.dirname(os.path.dirname(db)))
        scan_chromium(db, f"{browser}/{prof}")

for db in glob.glob(os.path.join(HOME, ".mozilla/firefox/*/places.sqlite")):
    scan_firefox(db)

if not hits:
    print("[OK] Подозрительных URL/IP в истории браузера не найдено.")
    print("     (Incognito / очистка history / другой профиль — не видно.)")
    sys.exit(0)

seen = set()
uniq = []
for h in sorted(hits, key=lambda x: -x[0]):
    if h[3] in seen:
        continue
    seen.add(h[3])
    uniq.append(h)

print(f"{'КОГДА':<17} {'БРАУЗЕР':<16} {'ПРИЧИНА':<26} {'URL'}")
print("-" * 110)
for _, when, browser, url, title, reason in uniq[:150]:
    u = (url[:68] + "…") if len(url) > 69 else url
    print(f"{when:<17} {browser:<16} {reason:<26} {u}")
    if title and title != url:
        t = (title[:65] + "…") if len(title) > 66 else title
        print(f"{'':17} {'':16} title: {t}")

print()
print(f"[DETECT] Найдено: {len(uniq)} URL")
print(f"База: {len(CLIENT_NAMES)} клиентов · RU/EU .ru/.eu/.fun · агрегаторы (masterminecraft, cheat-empire…)")
for _, when, browser, url, _, reason in uniq[:25]:
    print(f"  → {when} | {reason} | {url[:90]}")
sys.exit(2)
PY

exit $?

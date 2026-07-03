#!/usr/bin/env bash
# BrowserHistory — URL/IP читов в истории браузера (Linux)
# Python3 + sqlite (не нужен sqlite3 CLI)

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

# --- домены / ключевые слова чит-клиентов (публичные PC-check базы) ---
CHEAT_DOMAINS = re.compile(
    r"nursultan\.fun|nursultan|"
    r"vape\.gg|vapev4|vapelite|vapeclient|"
    r"doomsday|"
    r"meteorclient|meteor-client|meteordevelopment|"
    r"liquidbounce|ccbluex|"
    r"wurstclient|wurstplus|"
    r"riseclient|rise\.client|"
    r"aristois\.net|aristois|"
    r"fdpclient|fdpinfo|"
    r"novoline\.wtf|novoline|"
    r"onetap|"
    r"manthe\.|mantheclient|"
    r"sigma5|sigmaclient|"
    r"moonclient|zeroday|"
    r"thunderhack|bleachhack|"
    r"impactclient|futureclient|"
    r"phobos|komatclient|"
    r"xulu|astolfo|exosware|grimclient|"
    r"entropyclient|dreamclient|dripclient|"
    r"sunsetclient|slinkyclient|karmaclient|"
    r"skidfest|skid\.cc|"
    r"intent\.store|"
    r"ghost.?client|hack.?client|cheat.?client|"
    r"inject.*minecraft|minecraft.*cheat|"
    r"cheat\.jar|client\.jar|\.vape",
    re.I,
)

CHEAT_IP = re.compile(
    r"165\.22\.\d{1,3}\.\d{1,3}|"
    r"167\.172\.\d{1,3}\.\d{1,3}|"
    r"144\.217\.\d{1,3}\.\d{1,3}|"
    r"45\.142\.\d{1,3}\.\d{1,3}|"
    r"185\.234\.\d{1,3}\.\d{1,3}",
    re.I,
)

# Поисковые запросы в URL (Brave/Google/Яндекс)
CHEAT_SEARCH = re.compile(
    r"search.*?(?:q|query|text)=([^&]+)|"
    r"ya\.ru/search/\?text=([^&]+)",
    re.I,
)
CHEAT_QUERY_WORDS = re.compile(
    r"nursultan|vape\s*lite|vape\s*v4|vape\s*client|doomsday|meteor\s*client|"
    r"liquidbounce|wurst\s*client|rise\s*client|aristois|fdp\s*client|novoline|"
    r"onetap|manthe|killaura|ghost\s*client|hack\s*client|"
    r"чит\s*клиент|клиент\s*чит|скачать\s*чит|minecraft\s*чит|чит\s*minecraft|"
    r"инжект\s*minecraft|javaagent",
    re.I,
)

hits = []  # (sort_ts, when, browser, url, title, reason)


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
    m = {
        "google-chrome": "Chrome",
        "Brave-Browser": "Brave",
        "chromium": "Chromium",
        "microsoft-edge": "Edge",
        "opera": "Opera",
        "vivaldi": "Vivaldi",
    }
    parts = raw.split("/", 1)
    name = m.get(parts[0], parts[0])
    prof = parts[1] if len(parts) > 1 else "Default"
    if "Brave" in raw:
        name = "Brave"
    return f"{name}/{prof}"


def match_url(url, title=""):
    if not url:
        return None
    text = f"{url} {title}"
    if CHEAT_IP.search(text):
        return "IP чит-сервера"
    if CHEAT_DOMAINS.search(text):
        return "сайт чита"
    for m in CHEAT_SEARCH.finditer(url):
        q = m.group(1) or m.group(2) or ""
        q = urllib.parse.unquote_plus(q.replace("+", " "))
        q = q.split("&")[0][:120]
        if CHEAT_QUERY_WORDS.search(q):
            return f"поиск: {q[:60]}"
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
        for url, title, lvt, vc in con.execute(
            "SELECT url, IFNULL(title,''), last_visit_time, IFNULL(visit_count,0) FROM urls"
        ):
            reason = match_url(url, title)
            if reason:
                ts, when = chrome_ts(lvt)
                add_hit(ts, when, browser, url, title, reason)
        for path, st in con.execute(
            "SELECT COALESCE(target_path,current_path,''), start_time FROM downloads"
        ):
            reason = match_url(path)
            if reason:
                ts, when = chrome_ts(st)
                add_hit(ts, when, browser, path, "", f"скачивание: {reason}")
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


def scan_history_files():
    for hist in (".bash_history", ".zsh_history"):
        path = os.path.join(HOME, hist)
        if not os.path.isfile(path):
            continue
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                for line in f:
                    line = line.strip()
                    reason = match_url(line)
                    if reason:
                        add_hit(0, "terminal", hist, line[:200], "", reason)
        except OSError:
            pass


profiles = []
for pat in (
    ".config/google-chrome/*/History",
    ".config/chromium/*/History",
    ".config/BraveSoftware/Brave-Browser/*/History",
    ".config/microsoft-edge/*/History",
    ".config/opera/*/History",
    ".config/vivaldi/*/History",
):
    profiles.extend(glob.glob(os.path.join(HOME, pat)))

found_dbs = 0
for db in profiles:
    found_dbs += 1
    prof = os.path.basename(os.path.dirname(db))
    browser = os.path.basename(os.path.dirname(os.path.dirname(db)))
    scan_chromium(db, f"{browser}/{prof}")

for db in glob.glob(os.path.join(HOME, ".mozilla/firefox/*/places.sqlite")):
    found_dbs += 1
    scan_firefox(db)

scan_history_files()

if found_dbs == 0:
    print("[WARN] Браузеры не найдены (~/.config/.../History)")

seen = set()
uniq = []
for h in sorted(hits, key=lambda x: -x[0]):
    key = (h[3], h[2])
    if key in seen:
        continue
    seen.add(key)
    uniq.append(h)

if not uniq:
    print("[OK] Подозрительных URL/IP в истории браузера не найдено.")
    print("     (Пусто ≠ чисто — могли чистить историю или incognito.)")
    sys.exit(0)

print(f"{'КОГДА':<17} {'БРАУЗЕР':<16} {'ПРИЧИНА':<22} {'URL'}")
print("-" * 100)
for _, when, browser, url, title, reason in uniq[:100]:
    u = (url[:70] + "…") if len(url) > 71 else url
    print(f"{when:<17} {browser:<16} {reason:<22} {u}")
    if title and title != url:
        t = (title[:60] + "…") if len(title) > 61 else title
        print(f"{'':17} {'':16} title: {t}")

print()
print(f"[DETECT] Найдено: {len(uniq)}")
for _, when, browser, url, _, reason in uniq[:20]:
    print(f"  → {when} | {browser} | {reason}")
    print(f"     {url}")
sys.exit(2)
PY

exit $?

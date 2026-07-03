#!/usr/bin/env bash
# AllDownloads — все скачивания из браузеров (+ wget/curl из history)
# Колонки: КОГДА | ФАЙЛ | БРАУЗЕР | ОТКУДА | ССЫЛКА

set -uo pipefail

LIMIT="${1:-150}"
[[ "$LIMIT" =~ ^[0-9]+$ ]] || LIMIT=150

CHEAT_RE='vape\.gg|vapev4|vapelite|doomsday|meteorclient|meteor-client|liquidbounce|wurstclient|riseclient|aristois|fdpclient|novoline|onetap|manthe|thunderhack|bleachhack|impactclient|cheat|hackclient|ghost-client|\.vape|165\.22\.|167\.172\.|144\.217\.|killaura|inject.*jar|client\.jar'

echo "=== AllDownloads — история скачиваний (Linux) ==="
echo

if ! command -v python3 >/dev/null 2>&1; then
  echo "[ERR] Нужен python3."
  exit 1
fi

python3 - "$LIMIT" "$HOME" "$CHEAT_RE" <<'PY'
import glob, os, re, shutil, sqlite3, sys, tempfile, urllib.parse
from datetime import datetime, timezone

LIMIT = int(sys.argv[1])
HOME = sys.argv[2]
CHEAT_RE = re.compile(sys.argv[3], re.I)

# sort_ts, when, file, browser, site, url, suspicious
rows = []

BROWSER_NAMES = {
    "google-chrome": "Chrome",
    "Brave-Browser": "Brave",
    "chromium": "Chromium",
    "microsoft-edge": "Edge",
    "opera": "Opera",
    "vivaldi": "Vivaldi",
}


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


def basename(path):
    if not path:
        return "(неизвестно)"
    path = path.replace("file://", "")
    path = urllib.parse.unquote(path)
    return os.path.basename(path) or path


def site_from_url(url):
    if not url or url.startswith("blob:"):
        return "—"
    try:
        return urllib.parse.urlparse(url).netloc or "—"
    except Exception:
        return "—"


def pretty_browser(raw):
    parts = raw.split("/", 1)
    key = parts[0]
    prof = parts[1] if len(parts) > 1 else "Default"
    name = BROWSER_NAMES.get(key, key)
    if "Brave" in raw:
        name = "Brave"
    return f"{name}/{prof}"


def add(when_ts, when, file, browser, url):
    url = url or ""
    site = site_from_url(url)
    sus = bool(CHEAT_RE.search(f"{file} {url} {browser} {site}"))
    rows.append((when_ts, when, file, browser, site, url, sus))


def query_chromium(db, source_label):
    tmp = tempfile.mktemp(suffix=".db")
    try:
        shutil.copy2(db, tmp)
    except OSError:
        return
    try:
        con = sqlite3.connect(tmp)
        q = """
        SELECT d.target_path, d.current_path, d.start_time,
               COALESCE(
                 (SELECT url FROM downloads_url_chains c
                  WHERE c.id = d.id AND c.chain_index = 0 LIMIT 1),
                 d.tab_url, d.referrer, d.site_url, ''
               )
        FROM downloads d
        ORDER BY d.start_time DESC
        """
        for target, current, st, url in con.execute(q):
            path = target or current or ""
            ts, when = chrome_ts(st)
            fname = basename(path) if path else basename(url) if url else "(без файла)"
            add(ts, when, fname, pretty_browser(source_label), url)
        con.close()
    except sqlite3.Error:
        pass
    finally:
        try:
            os.unlink(tmp)
        except OSError:
            pass


def query_firefox(db):
    tmp = tempfile.mktemp(suffix=".db")
    try:
        shutil.copy2(db, tmp)
    except OSError:
        return
    try:
        con = sqlite3.connect(tmp)
        q = """
        SELECT p.url, a.content, p.last_visit_date
        FROM moz_annos a
        JOIN moz_anno_attributes aa ON aa.id = a.anno_attribute_id
        JOIN moz_places p ON p.id = a.place_id
        WHERE aa.name = 'downloads/destinationFileURI'
        ORDER BY p.last_visit_date DESC
        """
        for url, dest, lv in con.execute(q):
            ts, when = firefox_ts(lv)
            add(ts, when, basename(dest), "Firefox", url or "")
        con.close()
    except sqlite3.Error:
        pass
    finally:
        try:
            os.unlink(tmp)
        except OSError:
            pass


def scan_terminal_history():
    for hist in (".bash_history", ".zsh_history"):
        path = os.path.join(HOME, hist)
        if not os.path.isfile(path):
            continue
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                lines = f.readlines()
        except OSError:
            continue
        for line in lines:
            line = line.strip()
            m = re.search(r'wget\s+(?:-[^\s]+\s+)*["\']?(https?://[^\s"\']+)', line, re.I)
            if not m:
                m = re.search(
                    r'curl\s+(?:-[^\s]+\s+)*(?:-O|--output\s+\S+\s+)?["\']?(https?://[^\s"\']+)',
                    line, re.I,
                )
            if not m:
                continue
            url = m.group(1)
            out = re.search(r'--output\s+(\S+)', line)
            fname = basename(out.group(1)) if out else basename(url)
            add(0, "terminal", fname, hist, url)


for pattern in (
    ".config/google-chrome/*/History",
    ".config/chromium/*/History",
    ".config/BraveSoftware/Brave-Browser/*/History",
    ".config/microsoft-edge/*/History",
    ".config/opera/*/History",
    ".config/vivaldi/*/History",
):
    for db in glob.glob(os.path.join(HOME, pattern)):
        prof = os.path.basename(os.path.dirname(db))
        browser = os.path.basename(os.path.dirname(os.path.dirname(db)))
        query_chromium(db, f"{browser}/{prof}")

for db in glob.glob(os.path.join(HOME, ".mozilla/firefox/*/places.sqlite")):
    query_firefox(db)

scan_terminal_history()

if not rows:
    print("[OK] Записей о скачиваниях не найдено.")
    print("     (Пусто ≠ чисто — могли чистить историю браузера.)")
    sys.exit(0)

seen = set()
uniq = []
for r in sorted(rows, key=lambda x: (-x[0], x[2])):
    key = (r[1], r[2], r[5])
    if key in seen:
        continue
    seen.add(key)
    uniq.append(r)

uniq = uniq[:LIMIT]
sus_count = sum(1 for r in uniq if r[6])

hdr = f"{'КОГДА':<17} {'ФАЙЛ':<32} {'БРАУЗЕР':<16} {'ОТКУДА':<28} {'ССЫЛКА'}"
print(hdr)
print("-" * len(hdr.encode("utf-8")))

for _, when, file, browser, site, url, sus in uniq:
    tag = " 🚨" if sus else ""
    f = (file[:30] + "…") if len(file) > 31 else file
    b = (browser[:14] + "…") if len(browser) > 15 else browser
    s = (site[:26] + "…") if len(site) > 27 else site
    link = url if url else "—"
    print(f"{when:<17} {f:<32} {b:<16} {s:<28} {link}{tag}")

print()
print(f"Всего записей: {len(uniq)}  |  Подозрительных: {sus_count}")

if sus_count:
    print()
    print("[DETECT] Подозрительные скачивания:")
    for _, when, file, browser, site, url, _ in uniq:
        if not CHEAT_RE.search(f"{file} {url} {browser} {site}"):
            continue
        print(f"  → {when} | {file} | {browser} | {site}")
        if url:
            print(f"     {url}")
    sys.exit(2)

print("[OK] Подозрительных скачиваний в списке нет.")
sys.exit(0)
PY

exit $?
